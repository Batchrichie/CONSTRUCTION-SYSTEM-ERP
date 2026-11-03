-- Protect owner-level membership changes and prevent accidental company lockout.
-- Company admins may manage ordinary members, but only owners may grant,
-- revoke or change owner/administrator roles.

create or replace function private.is_company_owner(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.roles r on r.id = m.role_id
    where m.company_id = p_company_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and r.code = 'owner'
  );
$$;

revoke all on function private.is_company_owner(uuid) from public, anon;
grant execute on function private.is_company_owner(uuid) to authenticated;

create or replace function private.guard_company_membership_management()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_request_role text := coalesce(
    current_setting('request.jwt.claim.role', true),
    (select auth.jwt()->>'role')
  );
  v_is_service_role boolean := coalesce(v_request_role = 'service_role', false);
  v_old_role text;
  v_new_role text;
  v_active_other_owners integer;
begin
  -- Allow trusted SQL/migration execution with no request JWT. Reject an
  -- authenticated or anonymous API request that has no user identity.
  if v_actor_id is null then
    if coalesce(v_request_role, '') in ('authenticated', 'anon') then
      raise exception 'Authentication is required to manage company memberships'
        using errcode = '42501';
    end if;
    if not v_is_service_role then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;
  end if;

  if tg_op = 'INSERT' then
    select r.code into v_new_role
    from public.roles r
    where r.id = new.role_id;

    if v_new_role in ('owner', 'admin') then
      perform 1 from public.companies c where c.id = new.company_id for update;
    end if;

    if v_new_role in ('owner', 'admin')
       and not v_is_service_role
       and not private.is_company_owner(new.company_id) then
      -- The first owner is created by the controlled company-onboarding
      -- function before any membership exists.
      if not (
        v_new_role = 'owner'
        and new.status = 'active'
        and new.user_id = v_actor_id
        and exists (
          select 1 from public.companies c
          where c.id = new.company_id and c.created_by = v_actor_id
        )
        and not exists (
          select 1 from public.company_memberships m
          where m.company_id = new.company_id
        )
      ) then
        raise exception 'Only a company owner can grant owner or administrator roles'
          using errcode = '42501';
      end if;
    end if;

    return new;
  end if;

  if tg_op = 'UPDATE' and (
    old.company_id is distinct from new.company_id
    or old.user_id is distinct from new.user_id
  ) then
    raise exception 'A membership cannot be reassigned to another company or user'
      using errcode = '42501';
  end if;

  -- Serialize membership changes within a company so concurrent owner removals
  -- cannot both observe a different active owner and leave the workspace ownerless.
  perform 1 from public.companies c where c.id = old.company_id for update;

  select r.code into v_old_role
  from public.roles r
  where r.id = old.role_id;

  if tg_op = 'UPDATE' then
    select r.code into v_new_role
    from public.roles r
    where r.id = new.role_id;

    if (v_old_role in ('owner', 'admin') or v_new_role in ('owner', 'admin'))
       and not v_is_service_role
       and not private.is_company_owner(old.company_id) then
      raise exception 'Only a company owner can grant or change owner or administrator roles'
        using errcode = '42501';
    end if;

    if v_old_role = 'owner'
       and old.status = 'active'
       and (v_new_role <> 'owner' or new.status <> 'active') then
      select count(*) into v_active_other_owners
      from public.company_memberships m
      join public.roles r on r.id = m.role_id
      where m.company_id = old.company_id
        and m.id <> old.id
        and m.status = 'active'
        and r.code = 'owner';

      if v_active_other_owners = 0 then
        raise exception 'The last active company owner cannot be removed or deactivated'
          using errcode = '23514';
      end if;
    end if;

    return new;
  end if;

  if v_old_role in ('owner', 'admin')
     and not v_is_service_role
     and not private.is_company_owner(old.company_id) then
    raise exception 'Only a company owner can remove an owner or administrator'
      using errcode = '42501';
  end if;

  if v_old_role = 'owner' and old.status = 'active' then
    select count(*) into v_active_other_owners
    from public.company_memberships m
    join public.roles r on r.id = m.role_id
    where m.company_id = old.company_id
      and m.id <> old.id
      and m.status = 'active'
      and r.code = 'owner';

    if v_active_other_owners = 0 then
      raise exception 'The last active company owner cannot be removed or deactivated'
        using errcode = '23514';
    end if;
  end if;

  return old;
end;
$$;

revoke all on function private.guard_company_membership_management() from public, anon, authenticated;

drop trigger if exists company_memberships_guard_management on public.company_memberships;
create trigger company_memberships_guard_management
before insert or update or delete on public.company_memberships
for each row execute function private.guard_company_membership_management();

comment on function private.guard_company_membership_management() is
  'Restricts owner/admin membership changes to owners and prevents removal of the last active owner.';
