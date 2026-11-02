# Database Foundation

## Environment

- Supabase project: `CONSTRUCTION SYSTEM ERP`
- Project reference: `tpqpdunwniezmvrvyzxv`
- Region: `eu-west-1`
- PostgreSQL: 17
- Intended use: dedicated development environment for this repository

Never commit Supabase secrets. Browser code may use the project URL and publishable key only. A service-role or secret key must remain server-side.

## Deployment model

Each customer has a separate application deployment and Supabase database. One company workspace is permitted per database. `company_id` remains on records to support branches and future group reporting dimensions without shared cross-customer tenancy.

## Applied migration history

The SQL migration filenames in this repository use the exact versions recorded by Supabase.

1. `20261102093318_organisation_identity_access.sql` — companies, profiles, roles, permissions, memberships, branches, departments, audit-log storage and RLS.
2. `20261102093408_foundation_security_and_indexes.sql` — private company-onboarding implementation and supporting indexes.
3. `20261102093806_accounting_schema_and_chart.sql` — fiscal years, accounting periods, chart of accounts, journal headers/lines, permission evaluation and starter chart seeding.
4. `20261102093809_accounting_posting_engine.sql` — journal draft, posting and reversal RPCs, general-ledger and balance views.
5. `20261102093920_accounting_period_controls_and_indexes.sql` — fiscal-year/period lifecycle controls, trial balance and additional indexes.
6. `20261102093949_least_privilege_data_api_grants.sql` — explicit least-privilege grants and default privilege tightening.
7. `20261102094017_preserve_reversed_journals_in_ledger.sql` — preserves original posted entries alongside their reversing entries in ledger history.
8. `20261102094403_single_company_installation.sql` — enforces one company workspace per database and records company creation in the audit log.
9. `20261102095058_project_cost_management_foundation.sql` — projects, contracts, cost codes, cost centres, project budgets, project/overhead journal-line allocations, allocation RPC, posting control and attributed-cost views.
10. `20261102095152_project_cost_foreign_key_indexes.sql` — supporting indexes for project/cost foreign keys.
11. `20261102095624_project_cost_allocation_input_hardening.sql` — rejects null or non-array allocation payloads at the public RPC boundary.
12. `20261102104638_commercial_estimating_foundation.sql` — business parties, contacts, customer links, estimates, BOQ sections/items, status workflow, RLS, grants and estimate totals.
13. `20261102104653_commercial_estimating_foreign_key_indexes.sql` — supporting indexes for Phase 5 foreign keys.
14. `20261102104846_commercial_active_customer_validation.sql` — requires active customer parties on new project, contract and estimate links; protects customer designation while linked.

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

After a user signs in, call the `create_company_for_current_user` RPC with the legal name and display name. It creates the single company workspace, active owner membership, profile row and construction-oriented starter chart of accounts. A unique database index prevents a second company from being created in the same installation.

## Project and cost foundation

Projects are company-scoped and support construction, architectural design, engineering, real-estate development, renovation and other project types. Contracts are linked to projects and capture contract value, currency, retention percentage, mobilisation amount, dates and status.

Cost codes standardise project cost categories. Cost centres distinguish overhead, department, site and shared costs. Project budgets are recorded by project and cost code.

Journal-line cost allocations support multiple allocations per line. A line can be split between multiple projects or between project and overhead cost centres. Expense debit lines must be fully attributed before journal posting. The allocation RPC only permits changes while the journal is a draft. Reversal lines inherit the original allocations with debit/credit sides inverted.

The general ledger is not joined directly to allocation rows, avoiding duplicated ledger amounts. Separate `project_cost_ledger` and `overhead_cost_ledger` security-invoker views expose attributed costs.

## Commercial and estimating foundation

The `business_parties` register supports customer-only, supplier-only, and combined customer/supplier records. Party contacts are maintained separately. Projects and project contracts can link to a customer record while retaining the existing free-text client field for compatibility. New customer links require an active party marked as a customer; a party linked to project, contract or estimate records cannot have its customer designation removed.

Estimates are revision-aware commercial documents linked to a customer and optionally to a project and contract. BOQs contain ordered sections and measurable items with positive quantities, non-negative rates, fixed-precision generated line totals, optional cost-code mapping, and an estimate totals view. Draft BOQs remain editable; submitted estimates are locked. Submission requires at least one priced BOQ line and a discount no greater than the BOQ subtotal. Approval and rejection are permission-controlled and status changes are retained in an append-only estimate status history. Rejection requires a reason.

Estimate tax and discount amounts are estimate-level inputs only. They are not a Ghana VAT calculation, tax filing value, sales invoice, receivable, or general-ledger posting. Approval does not automatically create a contract or change the project budget. Those integrations belong to subsequent commercial and accounting phases.

## Verification status

- Supabase migration history confirms fourteen migrations.
- The six new Phase 5 tables have RLS enabled and nineteen RLS policies are present.
- No anonymous table grants were found for Phase 5 tables.
- The `estimate_totals` view exists and uses `security_invoker=true`.
- Direct authenticated UPDATE privilege on the estimate status column is not granted; status changes use the controlled RPC.
- The security advisor returned no findings after Phase 5.
- The first Phase 5 performance pass identified six unindexed foreign keys; migration 13 adds the required indexes. Remaining notices are unused-index information while the database is empty.

No company or sample accounting records have been inserted. Full authenticated end-to-end testing remains outstanding because no test Auth user has been provisioned in the project.
