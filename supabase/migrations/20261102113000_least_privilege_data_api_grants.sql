-- Least-privilege Data API grants across all currently defined public objects.
-- Supabase projects may have permissive default grants; revoke first, then opt in.

revoke all on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;

-- Organisation and identity access.
grant select, update on public.companies to authenticated;
grant select, update on public.user_profiles to authenticated;
grant select on public.roles, public.permissions, public.role_permissions to authenticated;
grant select, insert, update, delete on public.company_memberships to authenticated;
grant select, insert, update, delete on public.branches, public.departments to authenticated;
grant select on public.audit_logs to authenticated;

-- Accounting access.
grant select on public.fiscal_years, public.accounting_periods to authenticated;
grant select, insert, update on public.chart_of_accounts to authenticated;
grant select on public.journal_entries, public.journal_lines to authenticated;
grant select on public.general_ledger, public.account_balances, public.trial_balance to authenticated;

-- Explicitly document that no unauthenticated Data API access is intended.
revoke all on all tables in schema public from anon;

