-- Keep ledger balances consistent with each account's configured normal balance.
-- This is essential for contra accounts such as accumulated depreciation.

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
  j.reversal_of_journal_id,
  a.normal_balance
from public.journal_entries j
join public.journal_lines l
  on l.company_id = j.company_id and l.journal_entry_id = j.id
join public.chart_of_accounts a
  on a.company_id = l.company_id and a.id = l.account_id
where j.status in ('posted','reversed');

create or replace view public.account_balances
with (security_invoker = true)
as
select
  company_id,
  account_id,
  account_code,
  account_name,
  account_type,
  account_subtype,
  sum(debit) as total_debits,
  sum(credit) as total_credits,
  case when normal_balance = 'debit'
       then sum(debit) - sum(credit)
       else sum(credit) - sum(debit)
  end as balance,
  normal_balance
from public.general_ledger
group by
  company_id,
  account_id,
  account_code,
  account_name,
  account_type,
  account_subtype,
  normal_balance;

revoke all on public.general_ledger, public.account_balances from anon;
grant select on public.general_ledger, public.account_balances to authenticated;

comment on view public.account_balances is
  'Posted general-ledger balances calculated using each account normal_balance, including contra accounts.';
