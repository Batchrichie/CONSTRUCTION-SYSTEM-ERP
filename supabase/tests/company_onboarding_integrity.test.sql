begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(6);

create temporary table _onboarding_users (
  first_user_id uuid not null,
  second_user_id uuid not null
) on commit drop;

insert into _onboarding_users
values (gen_random_uuid(), gen_random_uuid());

grant select on _onboarding_users to authenticated;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select first_user_id, 'authenticated', 'authenticated',
       'onboarding-first-' || first_user_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _onboarding_users
union all
select second_user_id, 'authenticated', 'authenticated',
       'onboarding-second-' || second_user_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _onboarding_users;

-- First authenticated user completes the normal first-company onboarding path.
select set_config(
  'request.jwt.claim.sub',
  (select first_user_id::text from _onboarding_users),
  true
);
set local role authenticated;

select public.create_company_for_current_user(
  'Onboarding Integrity Limited',
  'Onboarding Integrity'
);

select extensions.is(
  (select count(*)::integer from public.companies),
  1,
  'The first authenticated onboarding request creates exactly one company'
);

select extensions.is(
  (select count(*)::integer
   from public.company_memberships m
   join public.roles r on r.id = m.role_id
   where m.user_id = (select first_user_id from _onboarding_users)
     and m.status = 'active'
     and r.code = 'owner'),
  1,
  'The first company creator receives one active owner membership'
);

-- A second authenticated user must not create a second workspace in this
-- single-company installation. The controlled onboarding function rejects
-- an already-configured installation before any second-user records are made.
select set_config(
  'request.jwt.claim.sub',
  (select second_user_id::text from _onboarding_users),
  true
);

select extensions.throws_ok(
  format(
    'select public.create_company_for_current_user(%L, %L)',
    'Duplicate Onboarding Limited',
    'Duplicate Onboarding'
  ),
  'P0001',
  'This installation is already configured with a company',
  'A second authenticated user cannot create another company workspace'
);

-- Inspect resulting rows as the database test role, not as the second user,
-- whose RLS view correctly excludes the first user's company and membership.
reset role;

select extensions.is(
  (select count(*)::integer from public.companies),
  1,
  'A rejected duplicate onboarding request leaves the original company unchanged'
);

select extensions.is(
  (select count(*)::integer
   from public.company_memberships m
   where m.user_id = (select second_user_id from _onboarding_users)),
  0,
  'A rejected duplicate onboarding request creates no membership'
);

select extensions.is(
  (select count(*)::integer
   from public.user_profiles p
   where p.user_id = (select second_user_id from _onboarding_users)),
  0,
  'A rejected duplicate onboarding request creates no user profile'
);

select * from extensions.finish();
rollback;
