-- Keep the original overhead allocation visible after its journal is reversed.
-- The reversing journal carries the opposite allocation; both rows are required
-- for overhead actuals to net to zero, matching project_cost_ledger semantics.

create or replace view public.overhead_cost_ledger
with (security_invoker = true)
as
select
  a.company_id,
  a.cost_centre_id,
  c.code as cost_centre_code,
  c.name as cost_centre_name,
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
join public.cost_centres c
  on c.company_id = a.company_id
 and c.id = a.cost_centre_id
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
where a.attribution_scope = 'overhead'
  and j.status in ('posted', 'reversed');

grant select on public.overhead_cost_ledger to authenticated;
revoke all on public.overhead_cost_ledger from anon;

comment on view public.overhead_cost_ledger is
  'Posted and reversed overhead allocations; debit allocations increase overhead cost and credit allocations reduce it, preserving reversal history.';
