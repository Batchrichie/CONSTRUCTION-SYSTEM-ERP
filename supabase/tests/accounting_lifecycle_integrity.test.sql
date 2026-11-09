begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(12);

-- Lifecycle regression coverage for fiscal-year and accounting-period controls.
-- All identities and business records are isolated in this transaction.
create temporary table _lifecycle_fixture (
  company_id uuid not null,
  owner_id uuid not null,
  viewer_id uuid not null,
  fiscal_year_id uuid,
  period_id uuid,
  cash_account_id uuid,
  bank_account_id uuid,
  journal_id uuid
) on commit drop;

insert into _lifecycle_fixture(company_id, owner_id, viewer_id)
values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid());

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select owner_id, 'authenticated', 'authenticated',
       'lifecycle-owner-' || owner_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _lifecycle_fixture;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select viewer_id, 'authenticated', 'authenticated',
       'lifecycle-viewer-' || viewer_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _lifecycle_fixture;

insert into public.companies (
  id, legal_name, display_name, base_currency, country_code, created_by
)
select company_id, 'Accounting Lifecycle Test', 'Lifecycle Test',
       'GHS', 'GH', owner_id
from _lifecycle_fixture;

select private.seed_default_chart_of_accounts(company_id)
from _lifecycle_fixture;

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.owner_id, r.id, 'active', now()
from _lifecycle_fixture f
cross join public.roles r
where r.code = 'owner';

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.viewer_id, r.id, 'active', now()
from _lifecycle_fixture f
cross join public.roles r
where r.code = 'viewer';

update _lifecycle_fixture f
set cash_account_id = a.id
from public.chart_of_accounts a
where a.company_id = f.company_id and a.account_code = '1110';

update _lifecycle_fixture f
set bank_account_id = a.id
from public.chart_of_accounts a
where a.company_id = f.company_id and a.account_code = '1120';

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _lifecycle_fixture),
  true
);

update _lifecycle_fixture
set fiscal_year_id = public.create_fiscal_year(
  company_id, 'LIFE-' || left(company_id::text, 8),
  date '2026-01-01', date '2026-12-31'
);

select extensions.throws_ok(
  format(
    'select public.create_fiscal_year(%L::uuid,%L,%L::date,%L::date)',
    (select company_id from _lifecycle_fixture),
    'OVERLAP-' || left((select company_id::text from _lifecycle_fixture), 8),
    '2026-06-01',
    '2027-05-31'
  ),
  'P0001',
  'Fiscal years cannot overlap within a company',
  'Overlapping fiscal years are rejected'
);

select set_config(
  'request.jwt.claim.sub',
  (select viewer_id::text from _lifecycle_fixture),
  true
);

select extensions.throws_ok(
  format(
    'select public.transition_fiscal_year_status(%L::uuid,%L)',
    (select fiscal_year_id from _lifecycle_fixture),
    'open'
  ),
  '42501',
  'You do not have permission to manage fiscal years',
  'A read-only member cannot open a fiscal year'
);

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _lifecycle_fixture),
  true
);

select extensions.is(
  public.transition_fiscal_year_status(
    (select fiscal_year_id from _lifecycle_fixture), 'open'
  ),
  'open'::text,
  'An authorised owner can open the fiscal year'
);

select set_config(
  'request.jwt.claim.sub',
  (select viewer_id::text from _lifecycle_fixture),
  true
);

select extensions.throws_ok(
  format(
    'select public.create_accounting_period(%L::uuid,%L::uuid,1::smallint,%L,%L::date,%L::date)',
    (select company_id from _lifecycle_fixture),
    (select fiscal_year_id from _lifecycle_fixture),
    'January',
    '2026-01-01',
    '2026-01-31'
  ),
  '42501',
  'You do not have permission to manage accounting periods',
  'A read-only member cannot create an accounting period'
);

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _lifecycle_fixture),
  true
);

update _lifecycle_fixture
set period_id = public.create_accounting_period(
  company_id, fiscal_year_id, 1::smallint, 'January',
  date '2026-01-01', date '2026-01-31'
);

select extensions.is(
  public.transition_accounting_period_status(
    (select period_id from _lifecycle_fixture), 'open'
  ),
  'open'::text,
  'An authorised owner can open an accounting period'
);

update _lifecycle_fixture
set journal_id = public.create_journal_draft(
  company_id,
  date '2026-01-15',
  'Draft journal blocks period close',
  jsonb_build_array(
    jsonb_build_object('account_id', cash_account_id, 'debit', 125, 'credit', 0),
    jsonb_build_object('account_id', bank_account_id, 'debit', 0, 'credit', 125)
  ),
  'LIFECYCLE-REFERENCE',
  'lifecycle-draft-key'
);

select extensions.throws_ok(
  format(
    'select public.transition_accounting_period_status(%L::uuid,%L)',
    (select period_id from _lifecycle_fixture),
    'closed'
  ),
  'P0001',
  'The period cannot close while draft journals remain',
  'A period cannot close while an unposted draft journal remains'
);

select public.post_journal_entry((select journal_id from _lifecycle_fixture));

select extensions.is(
  public.transition_accounting_period_status(
    (select period_id from _lifecycle_fixture), 'closed'
  ),
  'closed'::text,
  'The period can close after all draft journals have been posted'
);

select set_config(
  'request.jwt.claim.sub',
  (select viewer_id::text from _lifecycle_fixture),
  true
);

select extensions.throws_ok(
  format(
    'select public.transition_accounting_period_status(%L::uuid,%L)',
    (select period_id from _lifecycle_fixture),
    'locked'
  ),
  '42501',
  'You do not have permission to manage accounting periods',
  'A read-only member cannot lock a closed accounting period'
);

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _lifecycle_fixture),
  true
);

select extensions.is(
  public.transition_accounting_period_status(
    (select period_id from _lifecycle_fixture), 'locked'
  ),
  'locked'::text,
  'An authorised owner can lock a closed accounting period'
);

select extensions.throws_ok(
  format(
    'select public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb)',
    (select company_id from _lifecycle_fixture),
    '2026-01-20',
    'Posting into a locked period',
    jsonb_build_array(
      jsonb_build_object('account_id', (select cash_account_id from _lifecycle_fixture), 'debit', 10, 'credit', 0),
      jsonb_build_object('account_id', (select bank_account_id from _lifecycle_fixture), 'debit', 0, 'credit', 10)
    )::text
  ),
  'P0001',
  'No open accounting period covers the journal date',
  'A journal draft cannot be created for a locked period'
);

select * from extensions.finish();
rollback;
