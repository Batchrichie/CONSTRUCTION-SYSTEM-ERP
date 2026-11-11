begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(19);

-- This test exercises the public accounting RPCs with a real authenticated
-- identity claim, while keeping all fixture records inside this transaction.
create temporary table _period_fixture (
  user_id uuid not null,
  company_id uuid not null,
  fiscal_year_id uuid,
  period_id uuid,
  blocked_journal_id uuid
) on commit drop;

insert into _period_fixture(user_id, company_id)
values (gen_random_uuid(), gen_random_uuid());

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select user_id, 'authenticated', 'authenticated',
       'period-test-' || user_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _period_fixture;

insert into public.companies (
  id, legal_name, display_name, base_currency, country_code, created_by
)
select company_id, 'Period Test Company', 'Period Test',
       'GHS', 'GH', user_id
from _period_fixture;

select private.seed_default_chart_of_accounts(company_id)
from _period_fixture;

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.user_id, r.id, 'active', now()
from _period_fixture f
cross join public.roles r
where r.code = 'owner';

select set_config(
  'request.jwt.claim.sub',
  (select user_id::text from _period_fixture),
  true
);

update _period_fixture
set fiscal_year_id = public.create_fiscal_year(
  company_id, 'TEST-' || left(company_id::text, 8),
  date '2026-01-01', date '2026-12-31'
);

select extensions.is(
  (select status from public.fiscal_years
   where id=(select fiscal_year_id from _period_fixture)),
  'draft'::text,
  'A fiscal year is created in draft status'
);

select extensions.is(
  public.transition_fiscal_year_status(
    (select fiscal_year_id from _period_fixture), 'open'
  ),
  'open'::text,
  'A draft fiscal year can be opened'
);

update _period_fixture
set period_id = public.create_accounting_period(
  company_id, fiscal_year_id, 1::smallint, 'January',
  date '2026-01-01', date '2026-01-31'
);

select extensions.is(
  (select status from public.accounting_periods
   where id=(select period_id from _period_fixture)),
  'draft'::text,
  'An accounting period is created in draft status'
);

select extensions.is(
  public.transition_accounting_period_status(
    (select period_id from _period_fixture), 'open'
  ),
  'open'::text,
  'A draft accounting period can be opened after its fiscal year'
);

select extensions.throws_ok(
  format(
    'select public.create_accounting_period(%L::uuid,%L::uuid,2::smallint,%L,%L::date,%L::date)',
    (select company_id from _period_fixture),
    (select fiscal_year_id from _period_fixture),
    'Overlapping period',
    '2026-01-15',
    '2026-02-15'
  ),
  'P0001',
  'Accounting periods cannot overlap within a fiscal year',
  'Overlapping accounting periods are rejected'
);

select extensions.throws_ok(
  format(
    'select public.create_accounting_period(%L::uuid,%L::uuid,2::smallint,%L,%L::date,%L::date)',
    (select company_id from _period_fixture),
    (select fiscal_year_id from _period_fixture),
    'Out of year period',
    '2025-12-01',
    '2025-12-31'
  ),
  'P0001',
  'Accounting period must fall within its fiscal year',
  'An accounting period outside its fiscal year is rejected'
);

select extensions.is(
  public.transition_accounting_period_status(
    (select period_id from _period_fixture), 'closed'
  ),
  'closed'::text,
  'An open accounting period can be closed'
);

select extensions.is(
  public.transition_accounting_period_status(
    (select period_id from _period_fixture), 'locked'
  ),
  'locked'::text,
  'A closed accounting period can be locked'
);

update _period_fixture set blocked_journal_id = gen_random_uuid();

-- Insert a draft directly as a privileged test fixture to simulate a journal
-- that existed before a period was closed; the posting RPC must still recheck.
insert into public.journal_entries (
  id, company_id, fiscal_period_id, journal_date, description,
  currency_code, status, created_by
)
select blocked_journal_id, company_id, period_id, date '2026-01-26',
       'Closed-period posting guard', 'GHS', 'draft', user_id
from _period_fixture;

insert into public.journal_lines (
  company_id, journal_entry_id, account_id, line_number, debit, credit
)
select f.company_id, f.blocked_journal_id, a.id, 1, 10, 0
from _period_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_id and a.account_code='1110';

insert into public.journal_lines (
  company_id, journal_entry_id, account_id, line_number, debit, credit
)
select f.company_id, f.blocked_journal_id, a.id, 2, 0, 10
from _period_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_id and a.account_code='1120';

select extensions.throws_ok(
  format(
    'select public.post_journal_entry(%L::uuid)',
    (select blocked_journal_id from _period_fixture)
  ),
  'P0001',
  'The journal accounting period is not open for posting',
  'Posting revalidates and rejects a draft assigned to a locked period'
);

select extensions.is(
  public.transition_fiscal_year_status(
    (select fiscal_year_id from _period_fixture), 'closed'
  ),
  'closed'::text,
  'A fiscal year can close after all its periods are closed or locked'
);


-- Reject invalid lifecycle transitions rather than silently reopening periods.
select extensions.throws_ok(
  format(
    'select public.transition_fiscal_year_status(%L::uuid,%L)',
    (select fiscal_year_id from _period_fixture),
    'open'
  ),
  'P0001',
  'Invalid fiscal-year status transition: open to open',
  'A fiscal year cannot be opened twice'
);

select extensions.throws_ok(
  format(
    'select public.transition_accounting_period_status(%L::uuid,%L)',
    (select period_id from _period_fixture),
    'open'
  ),
  'P0001',
  'Invalid accounting-period status transition: locked to open',
  'A locked accounting period cannot be reopened'
);

select extensions.throws_ok(
  format(
    'select public.create_fiscal_year(%L::uuid,%L,%L::date,%L::date)',
    (select company_id from _period_fixture),
    'OVERLAP-' || left((select company_id::text from _period_fixture),8),
    '2026-06-01',
    '2027-05-31'
  ),
  'P0001',
  'Fiscal years cannot overlap within a company',
  'Overlapping fiscal years are rejected'
);

-- Lifecycle data is read-only through direct authenticated table writes;
-- callers must use the permission-checked RPCs.
select extensions.ok(
  not has_table_privilege('authenticated','public.fiscal_years','INSERT')
  and not has_table_privilege('authenticated','public.fiscal_years','UPDATE'),
  'Authenticated users cannot directly insert or update fiscal years'
);

select extensions.ok(
  not has_table_privilege('authenticated','public.accounting_periods','INSERT')
  and not has_table_privilege('authenticated','public.accounting_periods','UPDATE'),
  'Authenticated users cannot directly insert or update accounting periods'
);

select extensions.is(
  (select count(*)::integer from public.audit_logs
   where company_id=(select company_id from _period_fixture)
     and actor_user_id=(select user_id from _period_fixture)
     and action in ('fiscal_year.created','fiscal_year.status_changed',
                    'accounting_period.created','accounting_period.status_changed')),
  7,
  'Fiscal-year and accounting-period creation and status changes are audited'
);

select extensions.ok(
  exists (
    select 1 from public.audit_logs
    where company_id=(select company_id from _period_fixture)
      and actor_user_id=(select user_id from _period_fixture)
      and action='accounting_period.status_changed'
      and entity_id=(select period_id::text from _period_fixture)
      and old_values->>'status'='closed'
      and new_values->>'status'='locked'
  ),
  'The period-lock audit records the actor and previous and new statuses'
);

select extensions.ok(
  exists (
    select 1 from public.audit_logs
    where company_id=(select company_id from _period_fixture)
      and actor_user_id=(select user_id from _period_fixture)
      and action='fiscal_year.status_changed'
      and entity_id=(select fiscal_year_id::text from _period_fixture)
      and old_values->>'status'='open'
      and new_values->>'status'='closed'
  ),
  'The fiscal-year close audit records the actor and previous and new statuses'
);

select * from extensions.finish();
rollback;
