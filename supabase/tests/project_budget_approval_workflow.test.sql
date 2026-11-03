begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(13);

create temporary table _budget_fixture (
  company_id uuid not null,
  owner_id uuid not null,
  accountant_id uuid not null,
  project_id uuid not null,
  cost_code_id uuid not null,
  budget_id uuid,
  revision_id uuid
) on commit drop;

insert into _budget_fixture
values (gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),null,null);

insert into auth.users (
  id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data
)
select owner_id,'authenticated','authenticated','budget-owner-'||owner_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb
from _budget_fixture
union all
select accountant_id,'authenticated','authenticated','budget-accountant-'||accountant_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb
from _budget_fixture;

insert into public.companies (id,legal_name,display_name,base_currency,country_code,created_by)
select company_id,'Budget Workflow Test Company','Budget Test','GHS','GH',owner_id
from _budget_fixture;

insert into public.company_memberships (company_id,user_id,role_id,status,joined_at)
select f.company_id,f.owner_id,r.id,'active',now()
from _budget_fixture f cross join public.roles r where r.code='owner';

insert into public.company_memberships (company_id,user_id,role_id,status,joined_at)
select f.company_id,f.accountant_id,r.id,'active',now()
from _budget_fixture f cross join public.roles r where r.code='accountant';

insert into public.projects (id,company_id,project_code,name,currency_code,created_by)
select project_id,company_id,'BUDGET-001','Budget Workflow Project','GHS',owner_id
from _budget_fixture;

insert into public.cost_codes (id,company_id,code,name,category)
select cost_code_id,company_id,'MAT-001','Construction Materials','materials'
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

select extensions.is(
  (select count(*)::integer from public.project_budgets where budget_version_id=(select budget_id from _budget_fixture)),
  1,
  'Budget lines are saved against the revision'
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

select * from extensions.finish();
rollback;
