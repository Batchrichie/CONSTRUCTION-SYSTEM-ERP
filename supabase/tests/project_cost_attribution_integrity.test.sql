begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(14);

-- Test-only fixture. Every row is rolled back at the end of this test.
create temporary table _project_cost_fixture (
  company_id uuid not null,
  owner_id uuid not null,
  fiscal_year_id uuid not null,
  period_id uuid not null,
  project_one_id uuid not null,
  project_two_id uuid not null,
  cost_code_id uuid not null,
  expense_account_id uuid,
  cash_account_id uuid,
  journal_id uuid,
  expense_line_id uuid,
  cash_line_id uuid,
  budget_version_id uuid
) on commit drop;

insert into _project_cost_fixture (
  company_id, owner_id, fiscal_year_id, period_id,
  project_one_id, project_two_id, cost_code_id
)
values (
  gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
  gen_random_uuid(), gen_random_uuid(), gen_random_uuid()
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select owner_id, 'authenticated', 'authenticated',
       'project-cost-' || owner_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _project_cost_fixture;

grant select, update on _project_cost_fixture to authenticated;

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _project_cost_fixture),
  true
);
set local role authenticated;

-- Create the company and first owner through the authenticated onboarding RPC.
update _project_cost_fixture
set company_id = public.create_company_for_current_user(
  'Project Cost Test Company',
  'Project Cost Test'
);

reset role;
select private.seed_default_chart_of_accounts(company_id)
from _project_cost_fixture;
set local role authenticated;

-- Open the fiscal year and accounting period through their public workflows.
update _project_cost_fixture
set fiscal_year_id = public.create_fiscal_year(
  company_id,
  'PC-' || left(company_id::text, 8),
  date '2026-01-01',
  date '2026-12-31'
);

select public.transition_fiscal_year_status(
  (select fiscal_year_id from _project_cost_fixture),
  'open'
);

update _project_cost_fixture
set period_id = public.create_accounting_period(
  company_id,
  fiscal_year_id,
  1::smallint,
  'January',
  date '2026-01-01',
  date '2026-01-31'
);

select public.transition_accounting_period_status(
  (select period_id from _project_cost_fixture),
  'open'
);

insert into public.projects (
  id, company_id, project_code, name, created_by
)
select project_one_id, company_id, 'PC-PROJ-001', 'Project Cost Test One', owner_id
from _project_cost_fixture;

insert into public.projects (
  id, company_id, project_code, name, created_by
)
select project_two_id, company_id, 'PC-PROJ-002', 'Project Cost Test Two', owner_id
from _project_cost_fixture;

insert into public.cost_codes (
  id, company_id, code, name, category
)
select cost_code_id, company_id, 'MAT-001', 'Construction Materials', 'materials'
from _project_cost_fixture;

update _project_cost_fixture f
set expense_account_id = a.id
from public.chart_of_accounts a
where a.company_id = f.company_id and a.account_code = '5100';

update _project_cost_fixture f
set cash_account_id = a.id
from public.chart_of_accounts a
where a.company_id = f.company_id and a.account_code = '1110';

update _project_cost_fixture f
set journal_id = public.create_journal_draft(
  f.company_id,
  date '2026-01-15',
  'Project cost allocation integrity test',
  jsonb_build_array(
    jsonb_build_object('account_id', f.expense_account_id, 'debit', 100, 'credit', 0),
    jsonb_build_object('account_id', f.cash_account_id, 'debit', 0, 'credit', 100)
  ),
  'PROJECT-COST-TEST',
  'project-cost-integrity-' || f.company_id::text
);

update _project_cost_fixture f
set expense_line_id = l.id
from public.journal_lines l
where l.company_id = f.company_id
  and l.journal_entry_id = f.journal_id
  and l.line_number = 1;

update _project_cost_fixture f
set cash_line_id = l.id
from public.journal_lines l
where l.company_id = f.company_id
  and l.journal_entry_id = f.journal_id
  and l.line_number = 2;

select extensions.throws_ok(
  format(
    'select public.replace_journal_line_cost_allocations(%L::uuid,%L::uuid,%L::jsonb)',
    (select company_id from _project_cost_fixture),
    (select cash_line_id from _project_cost_fixture),
    jsonb_build_array(jsonb_build_object(
      'attribution_scope', 'project',
      'project_id', (select project_one_id from _project_cost_fixture),
      'cost_code_id', (select cost_code_id from _project_cost_fixture),
      'allocation_side', 'credit',
      'amount', 100
    ))::text
  ),
  '22023',
  'Only expense-account journal lines can receive project cost allocations',
  'A balance-sheet account cannot be attributed as a project cost'
);

select extensions.throws_ok(
  format(
    'select public.post_journal_entry(%L::uuid)',
    (select journal_id from _project_cost_fixture)
  ),
  '23514',
  'Every debit and credit on an expense account must be fully allocated to a project or overhead cost centre',
  'An expense journal cannot post before its expense amount is fully allocated'
);

select extensions.throws_ok(
  format(
    'select public.replace_journal_line_cost_allocations(%L::uuid,%L::uuid,%L::jsonb)',
    (select company_id from _project_cost_fixture),
    (select expense_line_id from _project_cost_fixture),
    jsonb_build_array(jsonb_build_object(
      'attribution_scope', 'project',
      'project_id', (select project_one_id from _project_cost_fixture),
      'cost_code_id', (select cost_code_id from _project_cost_fixture),
      'allocation_side', 'debit',
      'amount', '1.00001'
    ))::text
  ),
  '22023',
  'Allocation amounts must not exceed 4 decimal places',
  'Project cost allocations reject more than four decimal places without rounding'
);

select public.replace_journal_line_cost_allocations(
  (select company_id from _project_cost_fixture),
  (select expense_line_id from _project_cost_fixture),
  jsonb_build_array(
    jsonb_build_object(
      'attribution_scope', 'project',
      'project_id', (select project_one_id from _project_cost_fixture),
      'cost_code_id', (select cost_code_id from _project_cost_fixture),
      'allocation_side', 'debit',
      'amount', 60,
      'description', 'Materials allocation to project one'
    ),
    jsonb_build_object(
      'attribution_scope', 'project',
      'project_id', (select project_two_id from _project_cost_fixture),
      'cost_code_id', (select cost_code_id from _project_cost_fixture),
      'allocation_side', 'debit',
      'amount', 40,
      'description', 'Materials allocation to project two'
    )
  )
);

select extensions.is(
  (select count(*)::integer
   from public.journal_line_cost_allocations
   where company_id = (select company_id from _project_cost_fixture)
     and journal_line_id = (select expense_line_id from _project_cost_fixture)),
  2,
  'A single expense line can be split across multiple project allocations'
);

select public.post_journal_entry(
  (select journal_id from _project_cost_fixture)
);

select extensions.is(
  (select status
   from public.journal_entries
   where id = (select journal_id from _project_cost_fixture)),
  'posted'::text,
  'A fully allocated expense journal can be posted'
);

select extensions.is(
  (select count(*)::integer
   from public.project_cost_ledger
   where company_id = (select company_id from _project_cost_fixture)),
  2,
  'The project cost ledger exposes the two project allocations'
);

select extensions.is(
  (select sum(signed_cost)
   from public.project_cost_ledger
   where company_id = (select company_id from _project_cost_fixture)),
  100::numeric,
  'The project cost ledger reconciles to the full expense debit'
);

-- Complete the authenticated project-cost workflow with an approved budget
-- and compare the approved allowance against the posted project actual.
update _project_cost_fixture f
set budget_version_id = public.save_project_budget_draft(
  f.company_id,
  f.project_one_id,
  null,
  'Approved project baseline',
  jsonb_build_array(jsonb_build_object(
    'cost_code_id', f.cost_code_id,
    'budget_amount', '60.0000',
    'notes', 'Project one materials baseline'
  ))
);

select extensions.is(
  (select status from public.project_budget_versions
   where id = (select budget_version_id from _project_cost_fixture)),
  'draft',
  'The project budget is created as a draft'
);

select public.transition_project_budget(
  (select company_id from _project_cost_fixture),
  (select budget_version_id from _project_cost_fixture),
  'submitted',
  null
);

select extensions.is(
  (select status from public.project_budget_versions
   where id = (select budget_version_id from _project_cost_fixture)),
  'submitted',
  'The project budget can be submitted for approval'
);

select public.transition_project_budget(
  (select company_id from _project_cost_fixture),
  (select budget_version_id from _project_cost_fixture),
  'approved',
  null
);

select extensions.is(
  (select status from public.project_budget_versions
   where id = (select budget_version_id from _project_cost_fixture)),
  'approved',
  'The project budget can be approved by an owner'
);

select extensions.is(
  (select approved_amount
   from public.project_budgets
   where budget_version_id = (select budget_version_id from _project_cost_fixture)),
  60::numeric,
  'Approval releases the full approved budget amount'
);

select extensions.is(
  (
    select sum(b.approved_amount)
    from public.project_budgets b
    where b.company_id = (select company_id from _project_cost_fixture)
      and b.project_id = (select project_one_id from _project_cost_fixture)
  ) - (
    select sum(l.signed_cost)
    from public.project_cost_ledger l
    where l.company_id = (select company_id from _project_cost_fixture)
      and l.project_id = (select project_one_id from _project_cost_fixture)
      and l.cost_code_id = (select cost_code_id from _project_cost_fixture)
  ),
  0::numeric,
  'The approved project budget reconciles to posted project actuals'
);

select public.reverse_journal_entry(
  (select journal_id from _project_cost_fixture),
  date '2026-01-20',
  'Project cost attribution reversal test'
);

select extensions.is(
  (select count(*)::integer
   from public.project_cost_ledger
   where company_id = (select company_id from _project_cost_fixture)),
  4,
  'The reversal copies both original project allocations into the ledger'
);

select extensions.is(
  (select sum(signed_cost)
   from public.project_cost_ledger
   where company_id = (select company_id from _project_cost_fixture)),
  0::numeric,
  'The original expense and its reversal net project cost to zero'
);

reset role;
select * from extensions.finish();
rollback;
