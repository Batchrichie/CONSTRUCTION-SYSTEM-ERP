-- Phase 7.4.5: make expired estimate validity dates safe when cloning a new revision.
-- A revision receives today's issue date. An already-expired validity date must not
-- prevent creation of the new draft; retain only a validity date that is still current.
create or replace function public.clone_estimate_revision(p_company_id uuid,p_estimate_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_source public.estimates%rowtype;
  v_new_estimate_id uuid;
  v_next_revision integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  if not private.has_company_permission(p_company_id, 'estimating.manage') then
    raise exception 'You do not have permission to create estimate revisions' using errcode = '42501';
  end if;

  select *
    into v_source
  from public.estimates
  where id = p_estimate_id
    and company_id = p_company_id;

  if not found then
    raise exception 'Estimate not found' using errcode = 'P0002';
  end if;

  if v_source.status not in ('approved', 'rejected') then
    raise exception 'Only approved or rejected estimates can be revised' using errcode = '22023';
  end if;

  -- Serialize all revisions sharing this company/estimate number, including
  -- requests made from different prior revisions.
  perform pg_advisory_xact_lock(
    hashtextextended(p_company_id::text || ':' || v_source.estimate_number, 0)
  );

  select coalesce(max(revision_number), 0) + 1
    into v_next_revision
  from public.estimates
  where company_id = p_company_id
    and estimate_number = v_source.estimate_number;

  insert into public.estimates (
    company_id, estimate_number, revision_number, project_id,
    customer_party_id, project_contract_id, title, scope_notes,
    issue_date, valid_until, currency_code, discount_amount, tax_amount
  )
  values (
    v_source.company_id, v_source.estimate_number, v_next_revision,
    v_source.project_id, v_source.customer_party_id, v_source.project_contract_id,
    v_source.title, v_source.scope_notes, current_date,
    case
      when v_source.valid_until is null or v_source.valid_until >= current_date
        then v_source.valid_until
      else null
    end,
    v_source.currency_code, v_source.discount_amount, v_source.tax_amount
  )
  returning id into v_new_estimate_id;

  with section_map as (
    insert into public.estimate_sections (
      company_id, estimate_id, section_number, title, description, sort_order
    )
    select
      s.company_id, v_new_estimate_id, s.section_number,
      s.title, s.description, s.sort_order
    from public.estimate_sections s
    where s.company_id = p_company_id
      and s.estimate_id = p_estimate_id
    returning id, section_number
  )
  insert into public.estimate_items (
    company_id, estimate_id, section_id, item_number, item_type,
    description, unit, quantity, unit_rate, cost_code_id, sort_order
  )
  select
    i.company_id, v_new_estimate_id, sm.id, i.item_number, i.item_type,
    i.description, i.unit, i.quantity, i.unit_rate, i.cost_code_id, i.sort_order
  from public.estimate_items i
  left join public.estimate_sections old_section
    on old_section.id = i.section_id
   and old_section.company_id = i.company_id
   and old_section.estimate_id = i.estimate_id
  left join section_map sm
    on sm.section_number = old_section.section_number
  where i.company_id = p_company_id
    and i.estimate_id = p_estimate_id;

  return v_new_estimate_id;
end;
$$;

revoke all on function public.clone_estimate_revision(uuid,uuid) from public, anon;
grant execute on function public.clone_estimate_revision(uuid,uuid) to authenticated;
comment on function public.clone_estimate_revision(uuid,uuid) is
  'Creates the next draft estimate revision, copies its BOQ atomically, preserves a still-valid expiry date and clears an expired one; source estimate remains unchanged.';
