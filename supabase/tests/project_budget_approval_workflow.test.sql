begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(21);

-- The application currently enforces one company per installation. Temporarily
-- relax that installation constraint inside this rollback-only test transaction
-- so tenant RLS can be exercised against two company-owned fixtures.
drop index public.companies_single_workspace_per_database;

create temporary table _budget_fixture (
  company_id uuid not null,
  owner_id uuid not null,
  other_company_id uuid not null,
  other_owner_id uuid not null,
  accountant_id uuid not null,
  project_id uuid not null,
  cost_code_id uuid not null,
  budget_id uuid,
  revision_id uuid,
  other_project_id uuid not null,
  other_cost_code_id uuid not null,
  other_budget_id uuid
) on commit drop;

insert into _budget_fixture
values (gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),null,null,gen_random_uuid(),gen_random_uuid(),null);

insert into auth.users (
  id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data
)
select owner_id,'authenticated','authenticated','budget-owner-'||owner_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb
from _budget_fixture
union all
select accountant_id,'authenticated','authenticated','budget-accountant-'||accountant_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb
from _budget_fixture
union all
select other_owner_id,'authenticated','authenticated','budget-other-owner-'||other_owner_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb
from _budget_fixture;

insert into public.companies (id,legal_name,display_name,base_currency,country_code,created_by)
select company_id,'Budget Workflow Test Company','Budget Test','GHS','GH',owner_id
from _budget_fixture
union all
select other_company_id,'Other Budget Test Company','Other Budget Test','GHS','GH',other_owner_id
from _budget_fixture;

insert into public.company_memberships (company_id,user_id,role_id,status,joined_at)
select f.company_id,f.owner_id,r.id,'active',now()
from _budget_fixture f cross join public.roles r where r.code='owner'
union all
select f.other_company_id,f.other_owner_id,r.id,'active',now()
from _budget_fixture f cross join public.roles r where r.code='owner';

insert into public.company_memberships (company_id,user_id,role_id,status,joined_at)
select f.company_id,f.accountant_id,r.id,'active',now()
from _budget_fixture f cross join public.roles r where r.code='accountant';

insert into public.projects (id,company_id,project_code,name,currency_code,created_by)
select project_id,company_id,'BUDGET-001','Budget Workflow Project','GHS',owner_id
from _budget_fixture
union all
select other_project_id,other_company_id,'OTHER-BUDGET-001','Other Tenant Project','GHS',other_owner_id
from _budget_fixture;

insert into public.cost_codes (id,company_id,code,name,category)
select cost_code_id,company_id,'MAT-001','Construction Materials','materials'
from _budget_fixture
union all
select other_cost_code_id,other_company_id,'OTHER-MAT-001','Other Tenant Materials','materials'
from _budget_fixture;

select set_config('request.jwt.claim.sub',(select accountant_id::text from _budget_fixture),true);

update _budget_fixture f
set budget_id = public.save_project_budget_draft(
  f.company_id,
  f.project_id,
  null,
  'Initial project budget',
  jsonb_build_array(jsonb_build_object(
    'cost_code_id',f.cost_code_id,
    'budget_amount',125000,
    'notes','Materials allowance'
  ))
);

select extensions.is(
  (select status from public.project_budget_versions where id=(select budget_id from _budget_fixture)),
  'draft',
  'Saving a budget creates a draft revision'
);

select set_config('request.jwt.claim.sub',(select other_owner_id::text from _budget_fixture),true);

update _budget_fixture f
set other_budget_id = public.save_project_budget_draft(
  f.other_company_id, f.other_project_id, null, 'Other tenant budget',
  jsonb_build_array(jsonb_build_object(
    'cost_code_id',f.other_cost_code_id,
    'budget_amount','98765.4321',
    'notes','Other tenant allowance'
  ))
);

select set_config('request.jwt.claim.sub',(select owner_id::text from _budget_fixture),true);

select extensions.is(
  (select count(*)::integer from public.project_budget_versions
   where company_id=(select other_company_id from _budget_fixture)),
  0,
  'A company owner cannot read another company budget revisions through RLS'
);

select extensions.is(
  (select count(*)::integer from public.project_budget_history
   where company_id=(select other_company_id from _budget_fixture)),
  0,
  'A company owner cannot read another company budget history through RLS'
);

select extensions.throws_ok(
  format(
    'select public.transition_project_budget(%L::uuid,%L::uuid,%L,%L)',
    (select other_company_id from _budget_fixture),
    (select other_budget_id from _budget_fixture),
    'submitted', null
  ),
  '42501',
  'You do not have permission to submit project budgets',
  'A company owner cannot transition another company budget'
);

select extensions.is(
  (select count(*)::integer from public.project_budgets where budget_version_id=(select budget_id from _budget_fixture)),
  1,
  'Budget lines are saved against the revision'
);

select extensions.has_column(
  'public',
  'project_budgets',
  'legacy_approved_amount',
  'The migration retains the pre-workflow approved amount for audit'
);

select extensions.is(
  (select approved_amount from public.project_budgets where budget_version_id=(select budget_id from _budget_fixture)),
  0::numeric,
  'A newly saved draft has no approved amount before the new approval workflow'
);

select extensions.throws_ok(
  format(
    'select public.save_project_budget_draft(%L::uuid,%L::uuid,NULL,%L,%L::jsonb)',
    (select company_id from _budget_fixture),
    (select project_id from _budget_fixture),
    'Duplicate draft attempt',
    jsonb_build_array(jsonb_build_object(
      'cost_code_id',(select cost_code_id from _budget_fixture),
      'budget_amount',5000
    ))::text
  ),
  '23505',
  'A draft or submitted budget already exists for this project',
  'A project cannot have two open budget revisions'
);

select public.transition_project_budget(
  (select company_id from _budget_fixture),
  (select budget_id from _budget_fixture),
  'submitted',
  null
);

select extensions.is(
  (select status from public.project_budget_versions where id=(select budget_id from _budget_fixture)),
  'submitted',
  'A draft budget can be submitted'
);

select extensions.throws_ok(
  format(
    'select public.transition_project_budget(%L::uuid,%L::uuid,%L,%L)',
    (select company_id from _budget_fixture),
    (select budget_id from _budget_fixture),
    'approved',
    null
  ),
  '42501',
  'You do not have permission to approve or reject project budgets',
  'An accountant cannot approve a submitted budget'
);

select extensions.is(
  (select status from public.project_budget_versions where id=(select budget_id from _budget_fixture)),
  'submitted',
  'A denied approval leaves the budget submitted'
);

select set_config('request.jwt.claim.sub',(select owner_id::text from _budget_fixture),true);

select public.transition_project_budget(
  (select company_id from _budget_fixture),
  (select budget_id from _budget_fixture),
  'approved',
  'Approved by company owner'
);

select extensions.is(
  (select status from public.project_budget_versions where id=(select budget_id from _budget_fixture)),
  'approved',
  'An owner can approve a submitted budget'
);

select extensions.is(
  (select approved_amount from public.project_budgets where budget_version_id=(select budget_id from _budget_fixture)),
  125000::numeric,
  'Approval records the approved amount on each budget line'
);

update _budget_fixture f
set revision_id = public.create_project_budget_revision(f.company_id,f.project_id,null);

select extensions.is(
  (select revision_number from public.project_budget_versions where id=(select revision_id from _budget_fixture)),
  2,
  'A new revision increments the project budget revision number'
);

select extensions.is(
  (select status from public.project_budget_versions where id=(select revision_id from _budget_fixture)),
  'draft',
  'A copied revision starts as a draft'
);

select extensions.is(
  (select budget_amount from public.project_budgets where budget_version_id=(select revision_id from _budget_fixture)),
  125000::numeric,
  'A new revision copies the previous approved budget lines'
);

select extensions.is(
  (select approved_amount from public.project_budgets where budget_version_id=(select revision_id from _budget_fixture)),
  0::numeric,
  'Copied revision lines require fresh approval'
);

select public.transition_project_budget(
  (select company_id from _budget_fixture),
  (select revision_id from _budget_fixture),
  'submitted',
  null
);

select extensions.throws_ok(
  format(
    'select public.transition_project_budget(%L::uuid,%L::uuid,%L,%L)',
    (select company_id from _budget_fixture),
    (select revision_id from _budget_fixture),
    'rejected',
    null
  ),
  '22023',
  'A rejection reason is required',
  'A budget cannot be rejected without a reason'
);

select public.transition_project_budget(
  (select company_id from _budget_fixture),
  (select revision_id from _budget_fixture),
  'rejected',
  'Update the labour allowance and supporting assumptions'
);

select extensions.is(
  (select status from public.project_budget_versions where id=(select revision_id from _budget_fixture)),
  'rejected',
  'An owner can reject a submitted revision with a reason'
);

select extensions.throws_ok(
  format(
    'select public.save_project_budget_draft(%L::uuid,%L::uuid,%L::uuid,%L,%L::jsonb)',
    (select company_id from _budget_fixture),
    (select project_id from _budget_fixture),
    (select budget_id from _budget_fixture),
    'Attempt to edit approved revision',
    jsonb_build_array(jsonb_build_object(
      'cost_code_id',(select cost_code_id from _budget_fixture),
      'budget_amount',130000
    ))::text
  ),
  '22023',
  'Only draft budget revisions can be edited',
  'An approved budget revision is immutable'
);

update _budget_fixture f
set budget_id = public.create_project_budget_revision(
  f.company_id,
  f.project_id,
  f.revision_id
);

select extensions.is(
  (select revision_number from public.project_budget_versions
   where id = (select budget_id from _budget_fixture)),
  3,
  'A rejected budget can be copied into the next revision'
);

select * from extensions.finish();
rollback;
