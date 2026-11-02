
-- Keep customer links valid: only active parties flagged as customers may be
-- newly linked to projects, contracts or estimates.
create or replace function private.validate_customer_party_link()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_active_customer boolean;
  v_project_customer uuid;
begin
  if new.customer_party_id is null then
    return new;
  end if;

  select (bp.is_customer and bp.status = 'active')
    into v_is_active_customer
  from public.business_parties bp
  where bp.company_id = new.company_id and bp.id = new.customer_party_id;

  if coalesce(v_is_active_customer, false) is not true then
    raise exception 'The linked business party must be an active customer'
      using errcode = '23514';
  end if;

  if tg_table_name = 'project_contracts' then
    select p.customer_party_id into v_project_customer
    from public.projects p
    where p.company_id = new.company_id and p.id = new.project_id;

    if v_project_customer is not null and v_project_customer <> new.customer_party_id then
      raise exception 'The contract customer must match the project customer'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create or replace function private.validate_estimate_party_links()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_active_customer boolean;
  v_project_customer uuid;
  v_contract_project uuid;
  v_contract_customer uuid;
begin
  select (bp.is_customer and bp.status = 'active')
    into v_is_active_customer
  from public.business_parties bp
  where bp.company_id = new.company_id and bp.id = new.customer_party_id;

  if coalesce(v_is_active_customer, false) is not true then
    raise exception 'An estimate must reference an active business party marked as a customer'
      using errcode = '23514';
  end if;

  if new.project_id is not null then
    select p.customer_party_id into v_project_customer
    from public.projects p
    where p.company_id = new.company_id and p.id = new.project_id;

    if v_project_customer is not null and v_project_customer <> new.customer_party_id then
      raise exception 'Estimate customer must match the linked project customer'
        using errcode = '23514';
    end if;
  end if;

  if new.project_contract_id is not null then
    select pc.project_id, pc.customer_party_id
      into v_contract_project, v_contract_customer
    from public.project_contracts pc
    where pc.company_id = new.company_id and pc.id = new.project_contract_id;

    if v_contract_project is null then
      raise exception 'The selected contract does not exist for this company'
        using errcode = '23503';
    end if;
    if new.project_id is distinct from v_contract_project then
      raise exception 'The selected contract must belong to the estimate project'
        using errcode = '23514';
    end if;
    if v_contract_customer is not null and v_contract_customer <> new.customer_party_id then
      raise exception 'Estimate customer must match the linked contract customer'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create or replace function private.prevent_customer_role_removal_when_linked()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.is_customer and not new.is_customer and (
    exists (select 1 from public.projects p
      where p.company_id = old.company_id and p.customer_party_id = old.id)
    or exists (select 1 from public.project_contracts pc
      where pc.company_id = old.company_id and pc.customer_party_id = old.id)
    or exists (select 1 from public.estimates e
      where e.company_id = old.company_id and e.customer_party_id = old.id)
  ) then
    raise exception 'A party linked to projects, contracts or estimates cannot lose its customer designation'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger business_parties_guard_customer_role
before update of is_customer on public.business_parties
for each row execute function private.prevent_customer_role_removal_when_linked();
