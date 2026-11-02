# Construction System ERP

A modular construction, architecture/engineering, and real-estate ERP designed initially for single-company deployments in Ghana.

## Product direction

Build one maintainable product for construction contractors, architectural and engineering practices, and real-estate developers. Each customer installation has its own application deployment and database. Operational and financial records retain `company_id` for future branch and group readiness.

## Confirmed foundations

- Accrual accounting; GHS is the initial default functional currency.
- IFRS-aligned design, with statutory and tax rules configurable by effective date.
- Modular monolith architecture.
- React, TypeScript, Vite frontend.
- Supabase PostgreSQL, Auth, RLS, database functions, Edge Functions and Storage.
- GitHub source control; database schema changes are versioned as migrations.
- Free-tier-first development, with production limits and costs reviewed before launch.

## Core product areas

1. Organisation, branches, departments, users and permissions
2. Customers, suppliers and CRM
3. Projects, contracts, milestones and variations
4. Estimation, BOQ and project budgets
5. Accounting, journals, general ledger and financial statements
6. Quotations, sales invoices, receipts and credit notes
7. Purchases, supplier bills and payables
8. Procurement and approvals
9. Inventory, warehouses and project material issues
10. Site operations, labour and equipment
11. Payroll and HR
12. Ghana tax configuration and statutory reporting
13. Architectural/engineering stages, deliverables and revisions
14. Real-estate properties, units, sales and leases
15. Management reporting and analytics

## Non-negotiable accounting controls

- Posted journals balance and post atomically.
- General-ledger balances are derived from posted journal lines.
- Posted entries are not deleted; corrections use linked reversals or credit notes.
- Posting is idempotent and protected against duplicate submissions.
- Closed periods reject postings; period transitions are controlled and audited.
- Subledgers reconcile to the general ledger.
- Revenue recognition is separate from invoicing and cash collection.
- Construction over-time revenue recognition is not assumed for every contract.
- Monetary values use fixed-precision decimal types, never floating-point types.
- Privileged posting is validated server-side and leaves an audit trail.

## Repository layout (target)

```text
apps/web/                 React application
packages/shared/          Shared types and utilities
packages/accounting-core/ Accounting domain rules
packages/construction-core/ Construction domain rules
packages/tax-engine/      Effective-dated tax rules
supabase/migrations/      Versioned database migrations
supabase/functions/       Edge Functions
supabase/tests/           Database tests
docs/                     Architecture, accounting, database and tax guidance
```

## Delivery sequence

1. Repository and frontend foundation
2. Database foundation, identity and permissions
3. Chart of accounts, fiscal periods, journals and general ledger
4. Projects, contracts, BOQ and budgets
5. Sales, purchases, payments and reconciliation
6. Procurement, inventory and site operations
7. Construction progress, retention, advances and revenue recognition
8. Ghana tax and payroll
9. Architecture/engineering and real-estate workflows
10. Reporting, hardening and deployment

## Current status

- Repository and frontend shell established; automated build, test and lint workflows are configured but have not yet been independently verified in this environment.
- Dedicated development Supabase project is connected.
- Organisation, identity and access foundation applied.
- Accounting database foundation applied: fiscal years, periods, construction-oriented chart of accounts, journal entries and lines, controlled posting and reversals, general ledger, account balances and trial balance.
- No company, users, or sample accounting transactions have been inserted.
- Frontend authentication, company setup, accounting screens and operational source modules remain pending.
