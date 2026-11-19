begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(6);

create temporary table _membership_access_fixture (
  company_id uuid not null,
  owner_id uuid not null,
  member_id uuid not null
) on commit drop;

insert into _membership_access_fixture
values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid());

grant select on _membership_access_fixture to authenticated;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select owner_id, 'authenticated', 'authenticated',
       'role-owner-' || owner_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _membership_access_fixture
union all
select member_id, 'authenticated', 'authenticated',
       'role-member-' || member_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _membership_access_fixture;

insert into public.companies (
  id, legal_name, display_name, base_currency, country_code, created_by
)
select company_id, 'Membership Access Test Limited', 'Membership Access Test',
       'GHS', 'GH', owner_id
from _membership_access_fixture;

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.owner_id, r.id, 'active', now()
from _membership_access_fixture f
cross join public.roles r
where r.code = 'owner';

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.member_id, r.id, 'active', now()
from _membership_access_fixture f
cross join public.roles r
where r.code = 'accountant';

-- An owner may change an ordinary member's role without granting admin rights.
select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _membership_access_fixture),
  true
);
set local role authenticated;

update public.company_memberships
set role_id = (select id from public.roles where code = 'project_manager')
where company_id = (select company_id from _membership_access_fixture)
  and user_id = (select member_id from _membership_access_fixture);

select extensions.is(
  (select count(*)::integer
   from public.company_memberships m
   join public.roles r on r.id = m.role_id
   where m.company_id = (select company_id from _membership_access_fixture)
     and m.user_id = (select member_id from _membership_access_fixture)
     and m.status = 'active'
     and r.code = 'project_manager'),
  1,
  'An owner can change an ordinary member role and the change is persisted'
);

-- Active membership grants access to the company workspace.
select set_config(
  'request.jwt.claim.sub',
  (select member_id::text from _membership_access_fixture),
  true
);

select extensions.is(
  (select count(*)::integer
   from public.companies
   where id = (select company_id from _membership_access_fixture)),
  1,
  'An active member can read the company workspace'
);

select extensions.ok(
  private.is_company_member((select company_id from _membership_access_fixture)),
  'The membership helper recognises an active member'
);

-- The owner suspends the member. Suspension must immediately revoke access
-- without deleting the membership record or changing its assigned role.
select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _membership_access_fixture),
  true
);

update public.company_memberships
set status = 'suspended'
where company_id = (select company_id from _membership_access_fixture)
  and user_id = (select member_id from _membership_access_fixture);

select set_config(
  'request.jwt.claim.sub',
  (select member_id::text from _membership_access_fixture),
  true
);

select extensions.is(
  (select count(*)::integer
   from public.company_memberships m
   join public.roles r on r.id = m.role_id
   where m.company_id = (select company_id from _membership_access_fixture)
     and m.user_id = (select member_id from _membership_access_fixture)
     and m.status = 'suspended'
     and r.code = 'project_manager'),
  1,
  'Suspension preserves the membership and assigned role for auditability'
);

select extensions.is(
  (select count(*)::integer
   from public.companies
   where id = (select company_id from _membership_access_fixture)),
  0,
  'A suspended member can no longer read the company workspace'
);

select extensions.ok(
  not private.is_company_member((select company_id from _membership_access_fixture)),
  'The membership helper denies a suspended member'
);

reset role;
select * from extensions.finish();
rollback;
