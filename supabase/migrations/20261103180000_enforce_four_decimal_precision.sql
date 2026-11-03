-- Enforce four-decimal precision at the public database boundaries for
-- project budgets, project-cost allocations and commercial estimate inputs.
-- Previously released migrations remain immutable.

create or replace function public.save_project_budget_draft(
  p_company_id uuid,
  p_project_id uuid,
  p_budget_version_id uuid,
  p_notes text,
  p_lines jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_line jsonb;
begin
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Budget lines must be supplied as a JSON array' using errcode = '22023';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    if nullif(v_line->>'budget_amount', '') is null
       or ((v_line->>'budget_amount') !~ '^[+]?[0-9]+([.][0-9]{1,4})?$'
           and (v_line->>'budget_amount') !~ '^[+]?([.][0-9]{1,4})$') then
      raise exception 'Budget amounts must not exceed 4 decimal places'
        using errcode = '22023';
    end if;
  end loop;

  return private.save_project_budget_draft(
    p_company_id, p_project_id, p_budget_version_id, p_notes, p_lines
  );
end;
$$;

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
declare
  v_item jsonb;
begin
  if p_allocations is null or jsonb_typeof(p_allocations) is distinct from 'array' then
    raise exception 'Allocations must be supplied as a JSON array' using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    if nullif(v_item->>'amount', '') is null
       or ((v_item->>'amount') !~ '^[+]?[0-9]+([.][0-9]{1,4})?$'
           and (v_item->>'amount') !~ '^[+]?([.][0-9]{1,4})$') then
      raise exception 'Allocation amounts must not exceed 4 decimal places'
        using errcode = '22023';
    end if;
  end loop;

  perform private.replace_journal_line_cost_allocations(
    p_company_id, p_journal_line_id, p_allocations
  );
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
