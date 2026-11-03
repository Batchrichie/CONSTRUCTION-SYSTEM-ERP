begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(7);

create temporary table _membership_fixture (
  company_id uuid not null,
  owner_id uuid not null,
  admin_id uuid not null,
  successor_id uuid not null
) on commit drop;

insert into _membership_fixture
values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid());

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select owner_id, 'authenticated', 'authenticated',
       'membership-owner-' || owner_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _membership_fixture
union all
select admin_id, 'authenticated', 'authenticated',
       'membership-admin-' || admin_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _membership_fixture
union all
select successor_id, 'authenticated', 'authenticated',
       'membership-successor-' || successor_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _membership_fixture;

-- Exercise the real first-owner onboarding path. The membership trigger
-- must allow the creator's initial owner row but no later privilege escalation.
select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _membership_fixture),
  true
);

update _membership_fixture
set company_id = public.create_company_for_current_user(
  'Membership Guard Test',
  'Membership Test'
);

select extensions.is(
  (select count(*)::integer
   from public.company_memberships m
   join public.roles r on r.id = m.role_id
   where m.company_id = (select company_id from _membership_fixture)
     and m.user_id = (select owner_id from _membership_fixture)
     and r.code = 'owner'
     and m.status = 'active'),
  1,
  'Company onboarding creates the first active owner membership'
);

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.admin_id, r.id, 'active', now()
from _membership_fixture f
cross join public.roles r
where r.code = 'admin';

-- An administrator cannot promote their own membership.
select set_config(
  'request.jwt.claim.sub',
  (select admin_id::text from _membership_fixture),
  true
);
set local role authenticated;

select extensions.throws_ok(
  format(
    'update public.company_memberships set role_id=(select id from public.roles where code=''owner'') where company_id=%L::uuid and user_id=%L::uuid',
    (select company_id from _membership_fixture),
    (select admin_id from _membership_fixture)
  ),
  '42501',
  'Only a company owner can grant or change owner or administrator roles',
  'An administrator cannot promote themselves to owner'
);

select extensions.throws_ok(
  format(
    'update public.company_memberships set role_id=(select id from public.roles where code=''admin'') where company_id=%L::uuid and user_id=%L::uuid',
    (select company_id from _membership_fixture),
    (select owner_id from _membership_fixture)
  ),
  '42501',
  'Only a company owner can grant or change owner or administrator roles',
  'An administrator cannot change the owner role'
);

select extensions.throws_ok(
  format(
    'delete from public.company_memberships where company_id=%L::uuid and user_id=%L::uuid',
    (select company_id from _membership_fixture),
    (select owner_id from _membership_fixture)
  ),
  '42501',
  'Only a company owner can remove an owner or administrator',
  'An administrator cannot delete the owner membership'
);

reset role;

-- The sole active owner cannot demote or deactivate themselves.
select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _membership_fixture),
  true
);
set local role authenticated;

select extensions.throws_ok(
  format(
    'update public.company_memberships set role_id=(select id from public.roles where code=''admin'') where company_id=%L::uuid and user_id=%L::uuid',
    (select company_id from _membership_fixture),
    (select owner_id from _membership_fixture)
  ),
  '23514',
  'The last active company owner cannot be removed or deactivated',
  'The last active owner cannot demote themselves'
);

-- The owner can transfer ownership first, then safely change their own role.
insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.successor_id, r.id, 'active', now()
from _membership_fixture f
cross join public.roles r
where r.code = 'owner';

select extensions.is(
  (select count(*)::integer
   from public.company_memberships m
   join public.roles r on r.id = m.role_id
   where m.company_id = (select company_id from _membership_fixture)
     and m.status = 'active'
     and r.code = 'owner'),
  2,
  'An owner can appoint a successor owner'
);

update public.company_memberships
set role_id = (select id from public.roles where code = 'admin')
where company_id = (select company_id from _membership_fixture)
  and user_id = (select owner_id from _membership_fixture);

select extensions.is(
  (select count(*)::integer
   from public.company_memberships m
   join public.roles r on r.id = m.role_id
   where m.company_id = (select company_id from _membership_fixture)
     and m.status = 'active'
     and r.code = 'owner'),
  1,
  'The former owner can change roles after a successor becomes active'
);

select * from extensions.finish();
rollback;
