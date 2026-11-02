-- Create a new draft revision from an approved or rejected estimate.
-- This operation is atomic and preserves the original estimate and BOQ.
create or replace function public.clone_estimate_revision(p_company_id uuid,p_estimate_id uuid)
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare v_source public.estimates%rowtype; v_new_estimate_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication is required' using errcode = '28000'; end if;
  if not private.has_company_permission(p_company_id, 'estimating.manage') then
    raise exception 'You do not have permission to create estimate revisions' using errcode = '42501';
  end if;
  select * into v_source from public.estimates where id=p_estimate_id and company_id=p_company_id for update;
  if not found then raise exception 'Estimate not found' using errcode = 'P0002'; end if;
  if v_source.status not in ('approved','rejected') then
    raise exception 'Only approved or rejected estimates can be revised' using errcode = '22023';
  end if;
  insert into public.estimates(company_id,estimate_number,revision_number,project_id,customer_party_id,project_contract_id,title,scope_notes,issue_date,valid_until,currency_code,discount_amount,tax_amount)
  values(v_source.company_id,v_source.estimate_number,v_source.revision_number+1,v_source.project_id,v_source.customer_party_id,v_source.project_contract_id,v_source.title,v_source.scope_notes,current_date,v_source.valid_until,v_source.currency_code,v_source.discount_amount,v_source.tax_amount)
  returning id into v_new_estimate_id;
  with section_map as (
    insert into public.estimate_sections(company_id,estimate_id,section_number,title,description,sort_order)
    select s.company_id,v_new_estimate_id,s.section_number,s.title,s.description,s.sort_order
    from public.estimate_sections s where s.company_id=p_company_id and s.estimate_id=p_estimate_id
    returning id,section_number
  )
  insert into public.estimate_items(company_id,estimate_id,section_id,item_number,item_type,description,unit,quantity,unit_rate,cost_code_id,sort_order)
  select i.company_id,v_new_estimate_id,sm.id,i.item_number,i.item_type,i.description,i.unit,i.quantity,i.unit_rate,i.cost_code_id,i.sort_order
  from public.estimate_items i
  left join public.estimate_sections old_section on old_section.id=i.section_id and old_section.company_id=i.company_id and old_section.estimate_id=i.estimate_id
  left join section_map sm on sm.section_number=old_section.section_number
  where i.company_id=p_company_id and i.estimate_id=p_estimate_id;
  return v_new_estimate_id;
end; $$;
revoke all on function public.clone_estimate_revision(uuid,uuid) from public,anon;
grant execute on function public.clone_estimate_revision(uuid,uuid) to authenticated;
comment on function public.clone_estimate_revision(uuid,uuid) is 'Creates the next draft estimate revision and copies its BOQ atomically; source estimate remains unchanged.';
