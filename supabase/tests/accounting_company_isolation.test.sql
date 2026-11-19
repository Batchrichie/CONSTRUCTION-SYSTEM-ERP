begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(11);

-- Two companies and two owners prove that accounting reads are scoped to the
-- authenticated member's company, including security-invoker ledger views.
create temporary table _company_isolation_fixture (
  company_a uuid not null,
  company_b uuid not null,
  user_a uuid not null,
  user_b uuid not null,
  fiscal_year_a uuid not null,
  fiscal_year_b uuid not null,
  period_a uuid not null,
  period_b uuid not null,
  journal_a uuid not null,
  journal_b uuid not null
) on commit drop;

insert into _company_isolation_fixture
values (
  gen_random_uuid(), gen_random_uuid(),
  gen_random_uuid(), gen_random_uuid(),
  gen_random_uuid(), gen_random_uuid(),
  gen_random_uuid(), gen_random_uuid(),
  gen_random_uuid(), gen_random_uuid()
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select user_a, 'authenticated', 'authenticated',
       'isolation-a-' || user_a::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _company_isolation_fixture
union all
select user_b, 'authenticated', 'authenticated',
       'isolation-b-' || user_b::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _company_isolation_fixture;

insert into public.companies (
  id, legal_name, display_name, base_currency, country_code, created_by
)
select company_a, 'Isolation Company A', 'Isolation A', 'GHS', 'GH', user_a
from _company_isolation_fixture
union all
select company_b, 'Isolation Company B', 'Isolation B', 'GHS', 'GH', user_b
from _company_isolation_fixture;

select private.seed_default_chart_of_accounts(company_a)
from _company_isolation_fixture;
select private.seed_default_chart_of_accounts(company_b)
from _company_isolation_fixture;

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_a, f.user_a, r.id, 'active', now()
from _company_isolation_fixture f
cross join public.roles r
where r.code = 'owner'
union all
select f.company_b, f.user_b, r.id, 'active', now()
from _company_isolation_fixture f
cross join public.roles r
where r.code = 'owner';

insert into public.fiscal_years (
  id, company_id, year_code, start_date, end_date, status, created_by
)
select fiscal_year_a, company_a, 'ISO-A-' || left(company_a::text,8),
       date '2026-01-01', date '2026-12-31', 'open', user_a
from _company_isolation_fixture
union all
select fiscal_year_b, company_b, 'ISO-B-' || left(company_b::text,8),
       date '2026-01-01', date '2026-12-31', 'open', user_b
from _company_isolation_fixture;

insert into public.accounting_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, status
)
select period_a, company_a, fiscal_year_a, 1, 'January',
       date '2026-01-01', date '2026-01-31', 'open'
from _company_isolation_fixture
union all
select period_b, company_b, fiscal_year_b, 1, 'January',
       date '2026-01-01', date '2026-01-31', 'open'
from _company_isolation_fixture;

insert into public.journal_entries (
  id, company_id, fiscal_period_id, journal_number, journal_date,
  description, currency_code, total_debit, total_credit, status,
  created_by, posted_by, posted_at
)
select journal_a, company_a, period_a, 'ISO-A-' || left(journal_a::text,8),
       date '2026-01-15', 'Company A isolation fixture', 'GHS',
       125, 125, 'posted', user_a, user_a, now()
from _company_isolation_fixture
union all
select journal_b, company_b, period_b, 'ISO-B-' || left(journal_b::text,8),
       date '2026-01-15', 'Company B isolation fixture', 'GHS',
       250, 250, 'posted', user_b, user_b, now()
from _company_isolation_fixture;

insert into public.journal_lines (
  company_id, journal_entry_id, account_id, line_number,
  description, debit, credit
)
select f.company_a, f.journal_a, a.id, 1, 'Company A cash debit', 125, 0
from _company_isolation_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_a and a.account_code='1110'
union all
select f.company_a, f.journal_a, a.id, 2, 'Company A bank credit', 0, 125
from _company_isolation_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_a and a.account_code='1120'
union all
select f.company_b, f.journal_b, a.id, 1, 'Company B cash debit', 250, 0
from _company_isolation_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_b and a.account_code='1110'
union all
select f.company_b, f.journal_b, a.id, 2, 'Company B bank credit', 0, 250
from _company_isolation_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_b and a.account_code='1120';

-- Keep fixture identifiers available after switching to the Data API role.
select set_config('request.jwt.claim.sub',
  (select user_a::text from _company_isolation_fixture), true);
select set_config('test.company_a',
  (select company_a::text from _company_isolation_fixture), true);
select set_config('test.company_b',
  (select company_b::text from _company_isolation_fixture), true);

set local role authenticated;

select extensions.ok(
  exists (
    select 1 from public.chart_of_accounts
    where company_id=current_setting('test.company_a')::uuid
      and account_code='1110'
  ),
  'A company member can read their own chart of accounts'
);

select extensions.is(
  (select count(*)::integer from public.chart_of_accounts
   where company_id=current_setting('test.company_b')::uuid),
  0,
  'A company member cannot read another company chart of accounts'
);

select extensions.is(
  (select count(*)::integer from public.fiscal_years
   where company_id=current_setting('test.company_b')::uuid),
  0,
  'Fiscal-year rows are isolated by company membership'
);

select extensions.is(
  (select count(*)::integer from public.accounting_periods
   where company_id=current_setting('test.company_b')::uuid),
  0,
  'Accounting-period rows are isolated by company membership'
);

select extensions.is(
  (select count(*)::integer from public.journal_entries
   where company_id=current_setting('test.company_b')::uuid),
  0,
  'Journal headers from another company are not visible'
);

select extensions.is(
  (select count(*)::integer from public.journal_lines
   where company_id=current_setting('test.company_b')::uuid),
  0,
  'Journal lines from another company are not visible'
);

select extensions.is(
  (select count(*)::integer from public.general_ledger
   where company_id=current_setting('test.company_a')::uuid),
  2,
  'The general-ledger view exposes the member company posted lines'
);

select extensions.is(
  (select count(*)::integer from public.general_ledger
   where company_id=current_setting('test.company_b')::uuid),
  0,
  'The security-invoker general-ledger view hides another company'
);

select extensions.is(
  (select count(*)::integer from public.account_balances
   where company_id=current_setting('test.company_a')::uuid),
  2,
  'The account-balances view exposes the member company balances'
);

select extensions.is(
  (select count(*)::integer from public.account_balances
   where company_id=current_setting('test.company_b')::uuid),
  0,
  'The security-invoker account-balances view hides another company'
);

select extensions.is(
  private.has_company_permission(
    current_setting('test.company_b')::uuid,
    'accounting.read'
  ),
  false,
  'Company permission checks deny access outside the member company'
);

reset role;

select * from extensions.finish();
rollback;
