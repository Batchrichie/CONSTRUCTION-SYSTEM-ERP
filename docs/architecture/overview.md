# System Architecture

## Architectural style

Start as a modular monolith. Each customer receives an independent application deployment and Supabase database. Modules share domain services and database foundations; they are not separate microservices.

## Deployment boundary

- One customer installation has one Supabase project/database.
- Keep `company_id` on operational and financial records for branch and group readiness.
- Do not implement shared cross-customer tenancy or cross-database queries in the initial release.
- Keep environment-specific credentials outside source control.

## Application layers

1. **Presentation:** React pages, reusable UI components and navigation.
2. **Application services:** use cases, validation, orchestration and permission-aware requests.
3. **Domain packages:** accounting, construction and tax rules without React dependencies.
4. **Persistence:** Supabase client for safe reads and controlled writes; PostgreSQL functions for privileged and atomic operations.
5. **Database security:** constraints, indexes, Row Level Security, explicit grants and audit records.

## Domain boundaries

- **Projects:** project identity, contracts, scope, milestones, variations and status.
- **Commercial:** estimates, BOQ, budgets, quotations, invoices and certificates.
- **Accounting:** chart of accounts, fiscal years, periods, journals, general ledger, receivables, payables and financial reports.
- **Procurement and inventory:** requisitions, purchase orders, receipts, stores, stock movements and valuation.
- **Site operations:** labour, equipment, daily site reports and progress evidence.
- **People:** employees, payroll and statutory deductions.
- **Architecture/engineering:** design engagements, stages, deliverables, revisions and approvals.
- **Real estate:** developments, properties, units, sales and leases.
- **Tax:** effective-dated rules and calculations, separated from presentation and statutory filing adapters.

## Accounting integration rule

Operational modules do not write directly to general-ledger balances. They submit validated source transactions to controlled accounting operations. Those operations create balanced journal entries and journal lines in one database transaction. Reports read posted ledger lines and reconcile to their subledgers.

The accounting database foundation provides fiscal-year and period controls, a construction-oriented chart of accounts, controlled journal draft/post/reversal operations, a general-ledger view, account balances and trial balance. Journal lines are initially in the company's functional currency; multi-currency remeasurement is future work.

Phase 4 adds project and contract records, standard cost codes, cost centres, project budgets and project/overhead attribution of journal-line amounts. Project and overhead allocations are separate from the general ledger and are exposed through dedicated security-invoker views. Expense debit lines cannot post until their amounts are fully attributed.

## Security baseline

- Supabase Auth identifies users.
- Role and permission checks are enforced in PostgreSQL, not only in the UI.
- RLS is enabled on exposed tables, with explicit least-privilege grants.
- Public RPC wrappers use SECURITY INVOKER.
- Privileged posting implementations are narrowly scoped in the non-exposed private schema.
- The Supabase service-role key must never be placed in browser environment variables or committed to Git.
- Audit sensitive changes and all posting/reversal operations.

## Build sequence

The frontend shell and CI workflow are established. The dedicated Supabase development project is connected and verified. Organisation/identity, accounting, and project/cost database foundations are applied through versioned migrations. Frontend authentication, company setup, project management and accounting workflows are the next application-layer tasks.
