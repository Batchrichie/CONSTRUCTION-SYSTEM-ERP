begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(9);

-- Isolated fixture: this test runs on a freshly migrated local Supabase database.
create temporary table _accounting_fixture (
  company_id uuid not null,
  user_id uuid not null,
  fiscal_year_id uuid not null,
  period_id uuid not null,
  journal_id uuid not null,
  reversal_id uuid not null
) on commit drop;

insert into _accounting_fixture
values (gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),
        gen_random_uuid(),gen_random_uuid(),gen_random_uuid());

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select user_id, 'authenticated', 'authenticated',
       'accounting-test-' || user_id::text || '@example.test', '',
       now(), '{}'::jsonb, '{}'::jsonb
from _accounting_fixture;

insert into public.companies (
  id, legal_name, display_name, base_currency, country_code, created_by
)
select company_id, 'Accounting Test Company', 'Accounting Test',
       'GHS', 'GH', user_id
from _accounting_fixture;

select private.seed_default_chart_of_accounts(company_id)
from _accounting_fixture;

select extensions.is(
  (select count(*)::integer from public.chart_of_accounts
   where company_id=(select company_id from _accounting_fixture)
     and account_code='1110'),
  1,
  'Default chart seeding creates leaf accounts beneath newly created grouping accounts'
);

insert into public.fiscal_years (
  id, company_id, year_code, start_date, end_date, status, created_by
)
select fiscal_year_id, company_id, 'TAP-' || left(company_id::text,8),
       date '2026-01-01', date '2026-12-31', 'open', user_id
from _accounting_fixture;

insert into public.accounting_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, status
)
select period_id, company_id, fiscal_year_id, 1, 'January',
       date '2026-01-01', date '2026-01-31', 'open'
from _accounting_fixture;

-- Debit the credit-normal accumulated depreciation account and credit cash.
insert into public.journal_entries (
  id, company_id, fiscal_period_id, journal_number, journal_date,
  description, currency_code, total_debit, total_credit, status,
  created_by, posted_by, posted_at
)
select journal_id, company_id, period_id, 'TAP-ORIGINAL-' || left(journal_id::text,8),
       date '2026-01-15', 'Normal-balance regression fixture', 'GHS',
       100, 100, 'posted', user_id, user_id, now()
from _accounting_fixture;

insert into public.journal_lines (
  company_id, journal_entry_id, account_id, line_number, description, debit, credit
)
select f.company_id, f.journal_id, a.id, 1, 'Accumulated depreciation debit', 100, 0
from _accounting_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_id and a.account_code='1590';

insert into public.journal_lines (
  company_id, journal_entry_id, account_id, line_number, description, debit, credit
)
select f.company_id, f.journal_id, a.id, 2, 'Cash credit', 0, 100
from _accounting_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_id and a.account_code='1110';

select extensions.has_column('public','general_ledger','normal_balance',
  'General ledger exposes each account normal balance');

select extensions.is(
  (select normal_balance from public.account_balances
   where company_id=(select company_id from _accounting_fixture)
     and account_code='1590'),
  'credit'::text,
  'Accumulated depreciation is treated as a credit-normal account'
);

select extensions.is(
  (select balance from public.account_balances
   where company_id=(select company_id from _accounting_fixture)
     and account_code='1590'),
  (-100)::numeric,
  'A debit to accumulated depreciation reduces its credit-normal balance'
);

select extensions.is(
  (select closing_balance from public.trial_balance
   where company_id=(select company_id from _accounting_fixture)
     and account_code='1590'),
  (-100)::numeric,
  'Trial balance agrees with the contra-account ledger balance'
);

-- Add the linked opposite entry and mark the original as reversed. Both remain
-- in the immutable general ledger and net to zero.
insert into public.journal_entries (
  id, company_id, fiscal_period_id, journal_number, journal_date,
  description, currency_code, total_debit, total_credit, status,
  reversal_of_journal_id, created_by, posted_by, posted_at
)
select reversal_id, company_id, period_id, 'TAP-REVERSAL-' || left(reversal_id::text,8),
       date '2026-01-20', 'Reversal fixture', 'GHS',
       100, 100, 'posted', journal_id, user_id, user_id, now()
from _accounting_fixture;

insert into public.journal_lines (
  company_id, journal_entry_id, account_id, line_number, description, debit, credit
)
select f.company_id, f.reversal_id, a.id, 1, 'Reverse accumulated depreciation', 0, 100
from _accounting_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_id and a.account_code='1590';

insert into public.journal_lines (
  company_id, journal_entry_id, account_id, line_number, description, debit, credit
)
select f.company_id, f.reversal_id, a.id, 2, 'Reverse cash', 100, 0
from _accounting_fixture f
join public.chart_of_accounts a
  on a.company_id=f.company_id and a.account_code='1110';

update public.journal_entries
set status='reversed'
where id=(select journal_id from _accounting_fixture);

select extensions.is(
  (select count(*)::integer from public.general_ledger
   where company_id=(select company_id from _accounting_fixture)),
  4,
  'Original and reversing journal lines both remain in the general ledger'
);

select extensions.is(
  (select reversal_of_journal_id from public.journal_entries
   where id=(select reversal_id from _accounting_fixture)),
  (select journal_id from _accounting_fixture),
  'Reversal retains its link to the original journal'
);

select extensions.is(
  (select balance from public.account_balances
   where company_id=(select company_id from _accounting_fixture)
     and account_code='1590'),
  0::numeric,
  'Original and reversing entries net the contra-account balance to zero'
);

select extensions.is(
  (select closing_balance from public.trial_balance
   where company_id=(select company_id from _accounting_fixture)
     and account_code='1590'),
  0::numeric,
  'Trial balance reflects the net-zero reversal'
);

select * from extensions.finish();
rollback;
