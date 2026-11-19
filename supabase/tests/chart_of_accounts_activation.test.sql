begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(10);

-- Account activation and manual-journal controls. All fixtures are isolated
-- and rolled back; this test never touches the hosted development database.
create temporary table _coa_fixture (
  company_id uuid not null,
  owner_id uuid not null,
  viewer_id uuid not null,
  draft_id uuid,
  cash_id uuid,
  bank_id uuid
) on commit drop;

insert into _coa_fixture(company_id, owner_id, viewer_id)
values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid());

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select owner_id, 'authenticated', 'authenticated',
       'coa-owner-' || owner_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _coa_fixture
union all
select viewer_id, 'authenticated', 'authenticated',
       'coa-viewer-' || viewer_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _coa_fixture;

insert into public.companies (
  id, legal_name, display_name, base_currency, country_code, created_by
)
select company_id, 'Chart Activation Test', 'Chart Activation Test',
       'GHS', 'GH', owner_id
from _coa_fixture;

select private.seed_default_chart_of_accounts(company_id)
from _coa_fixture;

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.owner_id, r.id, 'active', now()
from _coa_fixture f
cross join public.roles r
where r.code = 'owner';

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.viewer_id, r.id, 'active', now()
from _coa_fixture f
cross join public.roles r
where r.code = 'viewer';

insert into public.chart_of_accounts (
  company_id, account_code, account_name, account_type, account_subtype,
  normal_balance, parent_account_id, is_postable, is_control_account,
  allow_manual_journal, is_system_account, is_active
)
select f.company_id, x.account_code, x.account_name, 'expense', 'other_expense',
       'debit', parent.id, true, false, true, false, true
from _coa_fixture f
join public.chart_of_accounts parent
  on parent.company_id = f.company_id and parent.account_code = '6000'
cross join (values
  ('6911', 'Inactive account at draft creation'),
  ('6912', 'Account deactivated after draft creation'),
  ('6913', 'Viewer activation permission test')
) as x(account_code, account_name);

update _coa_fixture f
set cash_id = a.id
from public.chart_of_accounts a
where a.company_id = f.company_id and a.account_code = '1110';

update _coa_fixture f
set bank_id = a.id
from public.chart_of_accounts a
where a.company_id = f.company_id and a.account_code = '1120';

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _coa_fixture),
  true
);
set local role authenticated;

select extensions.ok(
  exists (
    select 1 from public.chart_of_accounts
    where company_id = (select company_id from _coa_fixture)
      and account_code = '1000'
      and not is_postable
  ),
  'A seeded grouping account is not postable'
);

select extensions.ok(
  exists (
    select 1 from public.chart_of_accounts
    where company_id = (select company_id from _coa_fixture)
      and account_code = '1110'
      and is_active and is_postable and allow_manual_journal
  ),
  'A seeded cash account is active, postable and available for manual journals'
);

select extensions.ok(
  exists (
    select 1 from public.chart_of_accounts
    where company_id = (select company_id from _coa_fixture)
      and account_code = '1140'
      and is_active and is_postable and not allow_manual_journal
  ),
  'A seeded control account disallows manual journal entry'
);

select extensions.throws_ok(
  format(
    'select public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb)',
    (select company_id from _coa_fixture),
    '2026-01-15',
    'Grouping account must not be posted',
    jsonb_build_array(
      jsonb_build_object('account_id', (select id from public.chart_of_accounts where company_id=(select company_id from _coa_fixture) and account_code='1000'), 'debit', 25, 'credit', 0),
      jsonb_build_object('account_id', (select cash_id from _coa_fixture), 'debit', 0, 'credit', 25)
    )::text
  ),
  '22023',
  'Account on line 1 is unavailable for manual journal posting',
  'A non-postable grouping account is rejected during draft creation'
);

select extensions.throws_ok(
  format(
    'select public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb)',
    (select company_id from _coa_fixture),
    '2026-01-15',
    'Control account must not be manually posted',
    jsonb_build_array(
      jsonb_build_object('account_id', (select id from public.chart_of_accounts where company_id=(select company_id from _coa_fixture) and account_code='1140'), 'debit', 25, 'credit', 0),
      jsonb_build_object('account_id', (select cash_id from _coa_fixture), 'debit', 0, 'credit', 25)
    )::text
  ),
  '22023',
  'Account on line 1 is unavailable for manual journal posting',
  'A control account that disallows manual journals is rejected'
);

update public.chart_of_accounts
set is_active = false
where company_id = (select company_id from _coa_fixture)
  and account_code = '6911';

select extensions.ok(
  exists (
    select 1 from public.chart_of_accounts
    where company_id = (select company_id from _coa_fixture)
      and account_code = '6911' and not is_active
  ),
  'An authorised owner can deactivate an ordinary chart account'
);

select extensions.throws_ok(
  format(
    'select public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb)',
    (select company_id from _coa_fixture),
    '2026-01-15',
    'Inactive account must not be used',
    jsonb_build_array(
      jsonb_build_object('account_id', (select id from public.chart_of_accounts where company_id=(select company_id from _coa_fixture) and account_code='6911'), 'debit', 25, 'credit', 0),
      jsonb_build_object('account_id', (select cash_id from _coa_fixture), 'debit', 0, 'credit', 25)
    )::text
  ),
  '22023',
  'Account on line 1 is unavailable for manual journal posting',
  'An inactive account is rejected during draft creation'
);

update _coa_fixture
set draft_id = public.create_journal_draft(
  company_id,
  date '2026-01-15',
  'Deactivate account after draft creation',
  jsonb_build_array(
    jsonb_build_object('account_id', (select id from public.chart_of_accounts where company_id=_coa_fixture.company_id and account_code='6912'), 'debit', 40, 'credit', 0),
    jsonb_build_object('account_id', cash_id, 'debit', 0, 'credit', 40)
  )
);

update public.chart_of_accounts
set is_active = false
where company_id = (select company_id from _coa_fixture)
  and account_code = '6912';

select extensions.throws_ok(
  format(
    'select public.post_journal_entry(%L::uuid)',
    (select draft_id from _coa_fixture)
  ),
  'P0001',
  'A journal line uses an inactive or non-postable account',
  'Posting rechecks account activation after the draft was created'
);

select extensions.is(
  (select status from public.journal_entries
   where id = (select draft_id from _coa_fixture)),
  'draft'::text,
  'A failed activation recheck leaves the journal unposted'
);

select set_config(
  'request.jwt.claim.sub',
  (select viewer_id::text from _coa_fixture),
  true
);

update public.chart_of_accounts
set is_active = false
where company_id = (select company_id from _coa_fixture)
  and account_code = '6913';

select extensions.is(
  (select count(*)::integer from public.chart_of_accounts
   where company_id = (select company_id from _coa_fixture)
     and account_code = '6913' and is_active),
  1,
  'A read-only member cannot deactivate a chart-of-accounts record'
);

reset role;
select * from extensions.finish();
rollback;
