begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(3);

create temporary table _precision_fixture (
  user_id uuid not null,
  company_id uuid not null,
  debit_account_id uuid not null,
  credit_account_id uuid not null,
  fiscal_year_id uuid not null,
  period_id uuid not null
) on commit drop;

insert into _precision_fixture
values (gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid());

insert into auth.users (
  id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data
)
select user_id,'authenticated','authenticated',
       'precision-test-'||user_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb
from _precision_fixture;

insert into public.companies (
  id,legal_name,display_name,base_currency,country_code,created_by
)
select company_id,'Journal Precision Test','Precision Test','GHS','GH',user_id
from _precision_fixture;

insert into public.company_memberships(company_id,user_id,role_id,status,joined_at)
select f.company_id,f.user_id,r.id,'active',now()
from _precision_fixture f cross join public.roles r
where r.code='owner';

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
cross join public.permissions p
where r.code='owner' and p.code='accounting.manage'
on conflict do nothing;

insert into public.fiscal_years (
  id,company_id,year_code,start_date,end_date,status,created_by
)
select fiscal_year_id,company_id,'FY-2026',date '2026-01-01',date '2026-12-31','open',user_id
from _precision_fixture;

insert into public.accounting_periods (
  id,company_id,fiscal_year_id,period_number,period_name,start_date,end_date,status
)
select period_id,company_id,fiscal_year_id,1,'January',date '2026-01-01',date '2026-01-31','open'
from _precision_fixture;

insert into public.chart_of_accounts (
  id,company_id,account_code,account_name,account_type,account_subtype,normal_balance
)
select debit_account_id,company_id,'EXP-TEST','Test Expense','expense','operating_expense','debit'
from _precision_fixture
union all
select credit_account_id,company_id,'PAY-TEST','Test Payable','liability','current_liability','credit'
from _precision_fixture;

select set_config('request.jwt.claim.sub',(select user_id::text from _precision_fixture),true);

select extensions.throws_ok(
  format(
    'select private.create_journal_draft(%L::uuid,%L::date,%L,jsonb_build_array(jsonb_build_object(''account_id'',%L,''debit'',''1.00001'',''credit'',''0''),jsonb_build_object(''account_id'',%L,''debit'',''0'',''credit'',''1.00001'')))',
    (select company_id from _precision_fixture),
    '2026-01-15',
    'Reject excess debit precision',
    (select debit_account_id from _precision_fixture),
    (select credit_account_id from _precision_fixture)
  ),
  '22023',
  'Debit amounts must not exceed 4 decimal places (line 1)',
  'A debit with more than four decimal places is rejected before numeric casting'
);

select extensions.throws_ok(
  format(
    'select private.create_journal_draft(%L::uuid,%L::date,%L,jsonb_build_array(jsonb_build_object(''account_id'',%L,''debit'',''0'',''credit'',''1.00001''),jsonb_build_object(''account_id'',%L,''debit'',''1.00001'',''credit'',''0'')))',
    (select company_id from _precision_fixture),
    '2026-01-15',
    'Reject excess credit precision',
    (select credit_account_id from _precision_fixture),
    (select debit_account_id from _precision_fixture)
  ),
  '22023',
  'Credit amounts must not exceed 4 decimal places (line 1)',
  'A credit with more than four decimal places is rejected before numeric casting'
);

select extensions.ok(
  private.create_journal_draft(
    (select company_id from _precision_fixture),
    date '2026-01-15',
    'Accept four decimal places',
    jsonb_build_array(
      jsonb_build_object('account_id',(select debit_account_id from _precision_fixture),'debit','1.2345','credit','0'),
      jsonb_build_object('account_id',(select credit_account_id from _precision_fixture),'debit','0','credit','1.2345')
    )
  ) is not null,
  'Amounts with exactly four decimal places remain valid'
);

select * from extensions.finish();
rollback;
