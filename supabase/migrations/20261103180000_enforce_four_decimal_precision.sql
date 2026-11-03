-- Enforce four-decimal precision at database boundaries for budget,
-- project-cost allocation and commercial estimate inputs. This is a forward
-- migration; previously released migration files remain unchanged.

create or replace function private.save_project_budget_draft(
  p_company_id uuid,
  p_project_id uuid,
  p_budget_version_id uuid,
  p_notes text,
  p_lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_budget public.project_budget_versions%rowtype;
  v_line jsonb;
  v_cost_code_id uuid;
  v_amount numeric(20,4);
  v_notes text;
  v_version_id uuid;
  v_revision integer;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if not private.has_company_permission(p_company_id, 'project_costs.manage') then
    raise exception 'You do not have permission to manage project budgets' using errcode = '42501';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Budget lines must be supplied as a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_lines) < 1 or jsonb_array_length(p_lines) > 200 then
    raise exception 'A budget must contain between 1 and 200 cost-code lines' using errcode = '22023';
  end if;

  select * into v_project
  from public.projects
  where company_id = p_company_id and id = p_project_id
  for update;
  if not found or v_project.status = 'cancelled' then
    raise exception 'Project not found or cancelled' using errcode = 'P0002';
  end if;

  if p_budget_version_id is null then
    if exists (
      select 1 from public.project_budget_versions
      where company_id = p_company_id and project_id = p_project_id
        and status in ('draft','submitted')
    ) then
      raise exception 'A draft or submitted budget already exists for this project' using errcode = '23505';
    end if;
    select coalesce(max(revision_number), 0) + 1 into v_revision
    from public.project_budget_versions
    where company_id = p_company_id and project_id = p_project_id;
    insert into public.project_budget_versions (
      company_id, project_id, revision_number, status, currency_code,
      notes, created_by
    ) values (
      p_company_id, p_project_id, v_revision, 'draft', v_project.currency_code,
      nullif(btrim(coalesce(p_notes, '')), ''), v_user_id
    ) returning id into v_version_id;
  else
    select * into v_budget
    from public.project_budget_versions
    where company_id = p_company_id
      and project_id = p_project_id
      and id = p_budget_version_id
    for update;
    if not found then
      raise exception 'Budget revision not found for this project' using errcode = 'P0002';
    end if;
    if v_budget.status <> 'draft' then
      raise exception 'Only draft budget revisions can be edited' using errcode = '22023';
    end if;
    v_version_id := v_budget.id;
    update public.project_budget_versions
    set notes = nullif(btrim(coalesce(p_notes, '')), '')
    where company_id = p_company_id and id = v_version_id;
    delete from public.project_budgets
    where company_id = p_company_id and budget_version_id = v_version_id;
  end if;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    if nullif(v_line->>'budget_amount', '') is null
       or (v_line->>'budget_amount') !~ '^[+]?[0-9]+([.][0-9]{1,4})?
      v_cost_code_id := nullif(v_line->>'cost_code_id', '')::uuid;
      v_amount := (v_line->>'budget_amount')::numeric;
      v_notes := nullif(btrim(coalesce(v_line->>'notes', '')), '');
    exception when others then
      raise exception 'Invalid budget line data' using errcode = '22023';
    end;

    if v_cost_code_id is null or v_amount is null or v_amount <= 0 then
      raise exception 'Each budget line requires an active cost code and a positive amount' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.cost_codes
      where company_id = p_company_id and id = v_cost_code_id and is_active
    ) then
      raise exception 'A selected cost code is invalid or inactive' using errcode = '23503';
    end if;

    insert into public.project_budgets (
      company_id, project_id, budget_version_id, cost_code_id,
      budget_amount, approved_amount, currency_code, notes, created_by
    ) values (
      p_company_id, p_project_id, v_version_id, v_cost_code_id,
      v_amount, 0, v_project.currency_code, v_notes, v_user_id
    );
    v_count := v_count + 1;
  end loop;

  insert into public.project_budget_history (
    company_id, budget_version_id, from_status, to_status, note, changed_by
  ) values (
    p_company_id, v_version_id, case when p_budget_version_id is null then null else 'draft' end,
    'draft', 'Draft budget saved.', v_user_id
  );

  return v_version_id;
end;
$$; then
      raise exception 'Budget amounts must not exceed 4 decimal places (line %)', v_count + 1
        using errcode = '22023';
    end if;

    begin
      v_cost_code_id := nullif(v_line->>'cost_code_id', '')::uuid;
      v_amount := (v_line->>'budget_amount')::numeric(20,4);
      v_notes := nullif(btrim(coalesce(v_line->>'notes', '')), '');
    exception when others then
      raise exception 'Invalid budget line data' using errcode = '22023';
    end;

    if v_cost_code_id is null or v_amount is null or v_amount <= 0 then
      raise exception 'Each budget line requires an active cost code and a positive amount' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.cost_codes
      where company_id = p_company_id and id = v_cost_code_id and is_active
    ) then
      raise exception 'A selected cost code is invalid or inactive' using errcode = '23503';
    end if;

    insert into public.project_budgets (
      company_id, project_id, budget_version_id, cost_code_id,
      budget_amount, approved_amount, currency_code, notes, created_by
    ) values (
      p_company_id, p_project_id, v_version_id, v_cost_code_id,
      v_amount, 0, v_project.currency_code, v_notes, v_user_id
    );
    v_count := v_count + 1;
  end loop;

  insert into public.project_budget_history (
    company_id, budget_version_id, from_status, to_status, note, changed_by
  ) values (
    p_company_id, v_version_id, case when p_budget_version_id is null then null else 'draft' end,
    'draft', 'Draft budget saved.', v_user_id
  );

  return v_version_id;
end;
$$;

create or replace function private.replace_journal_line_cost_allocations(
  p_company_id uuid,
  p_journal_line_id uuid,
  p_allocations jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_line public.journal_lines%rowtype;
  v_journal public.journal_entries%rowtype;
  v_account_type text;
  v_item jsonb;
  v_scope text;
  v_project_id uuid;
  v_cost_code_id uuid;
  v_cost_centre_id uuid;
  v_side text;
  v_amount numeric(20,4);
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  if not private.has_company_permission(p_company_id, 'project_costs.manage') then
    raise exception 'You do not have permission to manage project cost allocations'
      using errcode = '42501';
  end if;

  if p_allocations is null
     or jsonb_typeof(p_allocations) <> 'array'
     or jsonb_array_length(p_allocations) > 100 then
    raise exception 'Allocations must be an array containing no more than 100 rows'
      using errcode = '22023';
  end if;

  select *
  into v_line
  from public.journal_lines
  where company_id = p_company_id
    and id = p_journal_line_id
  for update;

  if not found then
    raise exception 'Journal line not found' using errcode = 'P0002';
  end if;

  select account_type
  into v_account_type
  from public.chart_of_accounts
  where company_id = p_company_id
    and id = v_line.account_id;

  if v_account_type is distinct from 'expense' then
    raise exception 'Only expense-account journal lines can receive project cost allocations'
      using errcode = '22023';
  end if;

  select *
  into v_journal
  from public.journal_entries
  where company_id = p_company_id
    and id = v_line.journal_entry_id
  for update;

  if not found then
    raise exception 'Journal entry not found' using errcode = 'P0002';
  end if;

  if v_journal.status <> 'draft' then
    raise exception 'Cost allocations can only be changed on draft journals';
  end if;

  -- Replace is atomic: any invalid row or total mismatch rolls back this deletion.
  delete from public.journal_line_cost_allocations
  where company_id = p_company_id
    and journal_line_id = p_journal_line_id;

  for v_item in
    select value from jsonb_array_elements(p_allocations)
  loop
    if nullif(v_item->>'amount', '') is null
       or (v_item->>'amount') !~ '^[+]?[0-9]+([.][0-9]{1,4})?
      v_project_id := nullif(v_item->>'project_id', '')::uuid;
      v_cost_code_id := nullif(v_item->>'cost_code_id', '')::uuid;
      v_cost_centre_id := nullif(v_item->>'cost_centre_id', '')::uuid;
      v_side := v_item->>'allocation_side';
      v_amount := (v_item->>'amount')::numeric;
    exception when others then
      raise exception 'Invalid allocation data' using errcode = '22023';
    end;

    if v_scope = 'project' then
      if v_project_id is null or v_cost_centre_id is not null then
        raise exception 'Project allocations require a project and cannot use an overhead cost centre'
          using errcode = '22023';
      end if;

      if not exists (
        select 1
        from public.projects
        where company_id = p_company_id
          and id = v_project_id
          and status <> 'cancelled'
      ) then
        raise exception 'Project is invalid or cancelled' using errcode = '22023';
      end if;
    elsif v_scope = 'overhead' then
      if v_project_id is not null or v_cost_centre_id is null then
        raise exception 'Overhead allocations require a cost centre and cannot use a project'
          using errcode = '22023';
      end if;

      if not exists (
        select 1
        from public.cost_centres
        where company_id = p_company_id
          and id = v_cost_centre_id
          and is_active
          and centre_type in ('overhead', 'department', 'shared')
      ) then
        raise exception 'Overhead cost centre is invalid or inactive'
          using errcode = '22023';
      end if;
    else
      raise exception 'Attribution scope must be project or overhead'
        using errcode = '22023';
    end if;

    if v_cost_code_id is not null and not exists (
      select 1
      from public.cost_codes
      where company_id = p_company_id
        and id = v_cost_code_id
        and is_active
    ) then
      raise exception 'Cost code is invalid or inactive' using errcode = '22023';
    end if;

    if v_side is null or v_side not in ('debit', 'credit')
       or v_amount is null or v_amount <= 0 then
      raise exception 'Allocation side and positive amount are required'
        using errcode = '22023';
    end if;

    insert into public.journal_line_cost_allocations (
      company_id,
      journal_line_id,
      attribution_scope,
      project_id,
      cost_code_id,
      cost_centre_id,
      allocation_side,
      amount,
      description,
      created_by
    )
    values (
      p_company_id,
      p_journal_line_id,
      v_scope,
      v_project_id,
      v_cost_code_id,
      v_cost_centre_id,
      v_side,
      v_amount,
      nullif(btrim(v_item->>'description'), ''),
      v_user_id
    );
  end loop;

  if exists (
    select 1
    from public.journal_line_cost_allocations a
    where a.company_id = p_company_id
      and a.journal_line_id = p_journal_line_id
    group by a.allocation_side
    having sum(a.amount) >
      case when a.allocation_side = 'debit' then v_line.debit else v_line.credit end
  ) then
    raise exception 'Allocated amount cannot exceed the journal line amount'
      using errcode = '22023';
  end if;
end;
$$; then
      raise exception 'Allocation amounts must not exceed 4 decimal places'
        using errcode = '22023';
    end if;

    begin
      v_scope := v_item->>'attribution_scope';
      v_project_id := nullif(v_item->>'project_id', '')::uuid;
      v_cost_code_id := nullif(v_item->>'cost_code_id', '')::uuid;
      v_cost_centre_id := nullif(v_item->>'cost_centre_id', '')::uuid;
      v_side := v_item->>'allocation_side';
      v_amount := (v_item->>'amount')::numeric(20,4);
    exception when others then
      raise exception 'Invalid allocation data' using errcode = '22023';
    end;

    if v_scope = 'project' then
      if v_project_id is null or v_cost_centre_id is not null then
        raise exception 'Project allocations require a project and cannot use an overhead cost centre'
          using errcode = '22023';
      end if;

      if not exists (
        select 1
        from public.projects
        where company_id = p_company_id
          and id = v_project_id
          and status <> 'cancelled'
      ) then
        raise exception 'Project is invalid or cancelled' using errcode = '22023';
      end if;
    elsif v_scope = 'overhead' then
      if v_project_id is not null or v_cost_centre_id is null then
        raise exception 'Overhead allocations require a cost centre and cannot use a project'
          using errcode = '22023';
      end if;

      if not exists (
        select 1
        from public.cost_centres
        where company_id = p_company_id
          and id = v_cost_centre_id
          and is_active
          and centre_type in ('overhead', 'department', 'shared')
      ) then
        raise exception 'Overhead cost centre is invalid or inactive'
          using errcode = '22023';
      end if;
    else
      raise exception 'Attribution scope must be project or overhead'
        using errcode = '22023';
    end if;

    if v_cost_code_id is not null and not exists (
      select 1
      from public.cost_codes
      where company_id = p_company_id
        and id = v_cost_code_id
        and is_active
    ) then
      raise exception 'Cost code is invalid or inactive' using errcode = '22023';
    end if;

    if v_side is null or v_side not in ('debit', 'credit')
       or v_amount is null or v_amount <= 0 then
      raise exception 'Allocation side and positive amount are required'
        using errcode = '22023';
    end if;

    insert into public.journal_line_cost_allocations (
      company_id,
      journal_line_id,
      attribution_scope,
      project_id,
      cost_code_id,
      cost_centre_id,
      allocation_side,
      amount,
      description,
      created_by
    )
    values (
      p_company_id,
      p_journal_line_id,
      v_scope,
      v_project_id,
      v_cost_code_id,
      v_cost_centre_id,
      v_side,
      v_amount,
      nullif(btrim(v_item->>'description'), ''),
      v_user_id
    );
  end loop;

  if exists (
    select 1
    from public.journal_line_cost_allocations a
    where a.company_id = p_company_id
      and a.journal_line_id = p_journal_line_id
    group by a.allocation_side
    having sum(a.amount) >
      case when a.allocation_side = 'debit' then v_line.debit else v_line.credit end
  ) then
    raise exception 'Allocated amount cannot exceed the journal line amount'
      using errcode = '22023';
  end if;
end;
$$;


-- Widen source numeric columns so scale checks reject excess precision before
-- PostgreSQL can silently round values into numeric(20,4).
drop view public.estimate_totals;

alter table public.estimates
  alter column discount_amount type numeric using discount_amount::numeric,
  alter column tax_amount type numeric using tax_amount::numeric;

alter table public.estimates
  add constraint estimates_discount_amount_max_4dp
    check (discount_amount >= 0 and scale(discount_amount) <= 4),
  add constraint estimates_tax_amount_max_4dp
    check (tax_amount >= 0 and scale(tax_amount) <= 4);

alter table public.estimate_items
  drop column line_total;

alter table public.estimate_items
  alter column quantity type numeric using quantity::numeric,
  alter column unit_rate type numeric using unit_rate::numeric;

alter table public.estimate_items
  add column line_total numeric(20,4)
    generated always as (round(quantity * unit_rate, 4)) stored,
  add constraint estimate_items_quantity_max_4dp
    check (quantity > 0 and scale(quantity) <= 4),
  add constraint estimate_items_unit_rate_max_4dp
    check (unit_rate >= 0 and scale(unit_rate) <= 4);

create view public.estimate_totals
with (security_invoker = true)
as
select
  e.company_id,
  e.id as estimate_id,
  e.estimate_number,
  e.revision_number,
  e.project_id,
  e.customer_party_id,
  e.project_contract_id,
  e.title,
  e.currency_code,
  e.status,
  coalesce(sum(i.line_total), 0)::numeric(20,4) as subtotal,
  e.discount_amount,
  e.tax_amount,
  (coalesce(sum(i.line_total), 0) - e.discount_amount + e.tax_amount)::numeric(20,4) as total_amount
from public.estimates e
left join public.estimate_items i
  on i.company_id = e.company_id and i.estimate_id = e.id
group by e.company_id, e.id;

grant select on public.estimate_totals to authenticated;
