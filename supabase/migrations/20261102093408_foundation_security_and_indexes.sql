-- Phase 2 / Migration 002: keep privileged onboarding code out of the exposed API schema
-- and cover foreign-key lookup paths identified by the database advisors.

drop function public.create_company_for_current_user(text, text);

create or replace function private.create_company_for_current_user(
  p_legal_name text,
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_owner_role_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  if p_legal_name is null or length(btrim(p_legal_name)) < 2
     or p_display_name is null or length(btrim(p_display_name)) < 2 then
    raise exception 'A valid legal name and display name are required' using errcode = '22023';
  end if;

  select id into v_owner_role_id from public.roles where code = 'owner';
  if v_owner_role_id is null then
    raise exception 'Owner role is not configured';
  end if;

  insert into public.companies (legal_name, display_name, created_by)
  values (btrim(p_legal_name), btrim(p_display_name), v_user_id)
  returning id into v_company_id;

  insert into public.company_memberships (company_id, user_id, role_id, status, joined_at)
  values (v_company_id, v_user_id, v_owner_role_id, 'active', now());

  insert into public.user_profiles (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;

  return v_company_id;
end;
$$;

revoke all on function private.create_company_for_current_user(text, text) from public, anon;
grant execute on function private.create_company_for_current_user(text, text) to authenticated;

-- The exposed RPC is SECURITY INVOKER; its privileged implementation remains private.
create function public.create_company_for_current_user(
  p_legal_name text,
  p_display_name text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.create_company_for_current_user(p_legal_name, p_display_name);
$$;

revoke all on function public.create_company_for_current_user(text, text) from public, anon;
grant execute on function public.create_company_for_current_user(text, text) to authenticated;

create index audit_logs_actor_user_idx on public.audit_logs(actor_user_id);
create index companies_created_by_idx on public.companies(created_by);
create index company_memberships_invited_by_idx on public.company_memberships(invited_by);
create index company_memberships_role_id_idx on public.company_memberships(role_id);
create index role_permissions_permission_id_idx on public.role_permissions(permission_id);
