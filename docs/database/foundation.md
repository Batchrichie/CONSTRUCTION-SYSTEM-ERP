# Database Foundation

## Environment

- Supabase project: `CONSTRUCTION SYSTEM ERP`
- Project reference: `tpqpdunwniezmvrvyzxv`
- Region: `eu-west-1`
- PostgreSQL: 17
- Intended use: dedicated development environment for this repository

Never commit Supabase secrets. Browser code may use the project URL and publishable key only. A service-role or secret key must remain server-side.

## Applied migration history

The SQL migration filenames in this repository use the exact versions recorded by Supabase.

1. `20261102093318_organisation_identity_access.sql` — companies, profiles, roles, permissions, memberships, branches, departments, audit-log storage and RLS.
2. `20261102093408_foundation_security_and_indexes.sql` — private company-onboarding implementation and supporting indexes.
3. `20261102093806_accounting_schema_and_chart.sql` — fiscal years, accounting periods, chart of accounts, journal headers/lines, permission evaluation and starter chart seeding.
4. `20261102093809_accounting_posting_engine.sql` — journal draft, posting and reversal RPCs, general-ledger and balance views.
5. `20261102093920_accounting_period_controls_and_indexes.sql` — fiscal-year/period lifecycle controls, trial balance and additional indexes.
6. `20261102093949_least_privilege_data_api_grants.sql` — explicit least-privilege grants and default privilege tightening.
7. `20261102094017_preserve_reversed_journals_in_ledger.sql` — preserves original posted entries alongside their reversing entries in ledger history.

## Organisation and access

- Supabase Auth is the identity provider.
- Active company membership controls access to company records.
- The first user creating a company becomes its owner.
- Owner and administrator roles have company-wide access; the accountant role has accounting read/manage/post permissions.
- Permission evaluation is enforced in PostgreSQL.
- All exposed public tables have RLS enabled.
- Data API grants are explicit and separate from RLS policies.
- Privileged implementations are kept in the non-exposed `private` schema; public RPC wrappers use SECURITY INVOKER.

## Company onboarding

After a user signs in, call the `create_company_for_current_user` RPC with the legal name and display name. It creates the company, active owner membership, profile row and construction-oriented starter chart of accounts.

## Accounting foundation

See [Accounting Database Foundation](../accounting/foundation.md) for the chart of accounts, fiscal-year/period lifecycle, journal posting, reversals, ledger views, security model and current limitations.

## Verification status

Supabase migration history confirms all seven migrations. Catalog queries confirmed RLS and policies on the accounting tables, explicit authenticated privileges, security-invoker views, and public RPC wrappers that are not executable by anon. The Supabase security advisor returned no findings. Performance advisor notices are limited to unused-index informational findings while the new database is still empty.

No company or sample accounting records have been inserted. Full authenticated end-to-end testing remains outstanding because no test Auth user has been provisioned in the project.
