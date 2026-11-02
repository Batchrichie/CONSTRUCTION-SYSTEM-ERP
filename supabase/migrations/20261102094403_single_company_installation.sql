-- Enforce the agreed single-company-per-installation deployment model.
-- company_id remains on records for future branch and group reporting dimensions.

create unique index companies_single_workspace_per_database
  on public.companies ((true));

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

  if exists (select 1 from public.companies) then
    raise exception 'This installation is already configured with a company';
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

  perform private.seed_default_chart_of_accounts(v_company_id);

  insert into public.audit_logs(company_id,actor_user_id,action,entity_table,entity_id,new_values)
  values(v_company_id,v_user_id,'company.created','companies',v_company_id::text,
    jsonb_build_object('legal_name',btrim(p_legal_name),'display_name',btrim(p_display_name)));

  return v_company_id;
end;
$$;

comment on index public.companies_single_workspace_per_database is
  'Enforces one company workspace per customer installation; branches remain separate records.';
