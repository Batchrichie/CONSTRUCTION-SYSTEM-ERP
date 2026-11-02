-- A reversal never erases the original posted journal from the ledger.
-- Both the original and its linked opposite entry remain visible, netting to zero.

create or replace view public.general_ledger
with (security_invoker = true)
as
select
  j.company_id,
  j.branch_id,
  j.id as journal_entry_id,
  j.journal_number,
  j.journal_date,
  j.fiscal_period_id,
  l.id as journal_line_id,
  l.line_number,
  a.id as account_id,
  a.account_code,
  a.account_name,
  a.account_type,
  a.account_subtype,
  l.description as line_description,
  j.description as journal_description,
  j.reference,
  j.source_module,
  j.source_type,
  j.source_id,
  l.debit,
  l.credit,
  j.currency_code,
  j.posted_at,
  j.status as journal_status,
  j.reversal_of_journal_id
from public.journal_entries j
join public.journal_lines l
  on l.company_id=j.company_id and l.journal_entry_id=j.id
join public.chart_of_accounts a
  on a.company_id=l.company_id and a.id=l.account_id
where j.status in ('posted','reversed');

comment on view public.general_ledger is
  'Immutable posted history. Original journals remain visible after reversal alongside the linked reversing journal.';
