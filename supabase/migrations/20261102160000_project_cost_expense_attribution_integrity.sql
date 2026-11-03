-- Phase 7.4: enforce expense-only project attribution and exact debit/credit allocation.
-- This migration tightens the existing journal-to-project cost controls without
-- changing the general-ledger posting model or existing posted journal data.

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
    begin
      v_scope := v_item->>'attribution_scope';
      v_project_id := nullif(v_item->>'project_id', '')::uuid;
      v_cost_code_id := nullif(v_item->>'cost_code_id', '')::uuid;
      v_cost_centre_id := nullif(v_item->>'cost_centre_id', '')::uuid;
      v_side := v_item->>'allocation_side';
      if nullif(v_item->>'amount', '') is null
         or (v_item->>'amount') !~ '^[+]?(?:[0-9]+(?:[.][0-9]{1,4})?|[.][0-9]{1,4})
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

revoke all on function private.replace_journal_line_cost_allocations(uuid, uuid, jsonb)
  from public, anon;
grant execute on function private.replace_journal_line_cost_allocations(uuid, uuid, jsonb)
  to authenticated;

-- Keep the public API as the permission-checked entry point and reject null
-- or malformed payloads before invoking the private implementation.
create or replace function public.replace_journal_line_cost_allocations(
  p_company_id uuid,
  p_journal_line_id uuid,
  p_allocations jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_allocations is null
     or jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'Allocations must be supplied as a JSON array'
      using errcode = '22023';
  end if;

  perform private.replace_journal_line_cost_allocations(
    p_company_id, p_journal_line_id, p_allocations
  );
end;
$$;

revoke all on function public.replace_journal_line_cost_allocations(uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.replace_journal_line_cost_allocations(uuid, uuid, jsonb)
  to authenticated;

-- Both debit and credit sides of expense lines must be completely attributed.
-- This includes expense credits and reversal entries, so project costs reverse
-- in step with the immutable general ledger.
create or replace function private.enforce_expense_cost_attribution()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'posted' and old.status = 'draft' and exists (
    select 1
    from public.journal_lines l
    join public.chart_of_accounts a
      on a.company_id = l.company_id
     and a.id = l.account_id
    left join lateral (
      select
        coalesce(sum(x.amount) filter (where x.allocation_side = 'debit'), 0) as debit_allocated,
        coalesce(sum(x.amount) filter (where x.allocation_side = 'credit'), 0) as credit_allocated
      from public.journal_line_cost_allocations x
      where x.company_id = l.company_id
        and x.journal_line_id = l.id
    ) allocation_totals on true
    where l.company_id = new.company_id
      and l.journal_entry_id = new.id
      and a.account_type = 'expense'
      and (
        allocation_totals.debit_allocated <> l.debit
        or allocation_totals.credit_allocated <> l.credit
      )
  ) then
    raise exception 'Every debit and credit on an expense account must be fully allocated to a project or overhead cost centre'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

-- Replace the existing trigger function in place; retain its existing trigger.
create or replace view public.project_cost_ledger
with (security_invoker = true)
as
select
  a.company_id,
  a.project_id,
  p.project_code,
  p.name as project_name,
  a.cost_code_id,
  cc.code as cost_code,
  cc.name as cost_code_name,
  j.id as journal_entry_id,
  j.journal_number,
  j.journal_date,
  l.id as journal_line_id,
  l.account_id,
  coa.account_code,
  coa.account_name,
  a.amount,
  a.allocation_side,
  case when a.allocation_side = 'debit' then a.amount else -a.amount end as signed_cost,
  a.description
from public.journal_line_cost_allocations a
join public.projects p
  on p.company_id = a.company_id
 and p.id = a.project_id
join public.journal_lines l
  on l.company_id = a.company_id
 and l.id = a.journal_line_id
join public.journal_entries j
  on j.company_id = l.company_id
 and j.id = l.journal_entry_id
join public.chart_of_accounts coa
  on coa.company_id = l.company_id
 and coa.id = l.account_id
left join public.cost_codes cc
  on cc.company_id = a.company_id
 and cc.id = a.cost_code_id
where a.attribution_scope = 'project'
  and j.status in ('posted', 'reversed')
  and coa.account_type = 'expense';

grant select on public.project_cost_ledger to authenticated;
revoke all on public.project_cost_ledger from anon;

comment on view public.project_cost_ledger is
  'Posted expense-account allocations only; debit allocations increase project cost and credit allocations reduce it.';
 then
        raise exception 'Allocation amounts must not exceed 4 decimal places'
          using errcode = '22023';
      end if;
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
$$;

revoke all on function private.replace_journal_line_cost_allocations(uuid, uuid, jsonb)
  from public, anon;
grant execute on function private.replace_journal_line_cost_allocations(uuid, uuid, jsonb)
  to authenticated;

-- Keep the public API as the permission-checked entry point and reject null
-- or malformed payloads before invoking the private implementation.
create or replace function public.replace_journal_line_cost_allocations(
  p_company_id uuid,
  p_journal_line_id uuid,
  p_allocations jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_allocations is null
     or jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'Allocations must be supplied as a JSON array'
      using errcode = '22023';
  end if;

  perform private.replace_journal_line_cost_allocations(
    p_company_id, p_journal_line_id, p_allocations
  );
end;
$$;

revoke all on function public.replace_journal_line_cost_allocations(uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.replace_journal_line_cost_allocations(uuid, uuid, jsonb)
  to authenticated;

-- Both debit and credit sides of expense lines must be completely attributed.
-- This includes expense credits and reversal entries, so project costs reverse
-- in step with the immutable general ledger.
create or replace function private.enforce_expense_cost_attribution()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'posted' and old.status = 'draft' and exists (
    select 1
    from public.journal_lines l
    join public.chart_of_accounts a
      on a.company_id = l.company_id
     and a.id = l.account_id
    left join lateral (
      select
        coalesce(sum(x.amount) filter (where x.allocation_side = 'debit'), 0) as debit_allocated,
        coalesce(sum(x.amount) filter (where x.allocation_side = 'credit'), 0) as credit_allocated
      from public.journal_line_cost_allocations x
      where x.company_id = l.company_id
        and x.journal_line_id = l.id
    ) allocation_totals on true
    where l.company_id = new.company_id
      and l.journal_entry_id = new.id
      and a.account_type = 'expense'
      and (
        allocation_totals.debit_allocated <> l.debit
        or allocation_totals.credit_allocated <> l.credit
      )
  ) then
    raise exception 'Every debit and credit on an expense account must be fully allocated to a project or overhead cost centre'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

-- Replace the existing trigger function in place; retain its existing trigger.
create or replace view public.project_cost_ledger
with (security_invoker = true)
as
select
  a.company_id,
  a.project_id,
  p.project_code,
  p.name as project_name,
  a.cost_code_id,
  cc.code as cost_code,
  cc.name as cost_code_name,
  j.id as journal_entry_id,
  j.journal_number,
  j.journal_date,
  l.id as journal_line_id,
  l.account_id,
  coa.account_code,
  coa.account_name,
  a.amount,
  a.allocation_side,
  case when a.allocation_side = 'debit' then a.amount else -a.amount end as signed_cost,
  a.description
from public.journal_line_cost_allocations a
join public.projects p
  on p.company_id = a.company_id
 and p.id = a.project_id
join public.journal_lines l
  on l.company_id = a.company_id
 and l.id = a.journal_line_id
join public.journal_entries j
  on j.company_id = l.company_id
 and j.id = l.journal_entry_id
join public.chart_of_accounts coa
  on coa.company_id = l.company_id
 and coa.id = l.account_id
left join public.cost_codes cc
  on cc.company_id = a.company_id
 and cc.id = a.cost_code_id
where a.attribution_scope = 'project'
  and j.status in ('posted', 'reversed')
  and coa.account_type = 'expense';

grant select on public.project_cost_ledger to authenticated;
revoke all on public.project_cost_ledger from anon;

comment on view public.project_cost_ledger is
  'Posted expense-account allocations only; debit allocations increase project cost and credit allocations reduce it.';
