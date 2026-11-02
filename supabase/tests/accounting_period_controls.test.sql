begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(9);

-- This test exercises the public accounting RPCs with a real authenticated
-- identity claim, while keeping all fixture records inside this transaction.
create temporary table _period_fixture (
  user_id uuid not null,
  company_id uuid not null,
  fiscal_year_id uuid,
  period_id uuid
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
  company_id, fiscal_year_id, 1, 'January',
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
    'select public.create_accounting_period(%L::uuid,%L::uuid,2,%L,%L::date,%L::date)',
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
    'select public.create_accounting_period(%L::uuid,%L::uuid,2,%L,%L::date,%L::date)',
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

select extensions.is(
  public.transition_fiscal_year_status(
    (select fiscal_year_id from _period_fixture), 'closed'
  ),
  'closed'::text,
  'A fiscal year can close after all its periods are closed or locked'
);

select * from extensions.finish();
rollback;
