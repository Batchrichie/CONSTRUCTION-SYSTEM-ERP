# Construction System ERP

A modular construction, architecture/engineering, and real-estate ERP designed initially for single-company deployments in Ghana.

## Product direction

Build one maintainable product for:
- Construction contractors
- Architectural and engineering practices
- Real-estate developers

Each customer installation has its own application deployment and database. The schema retains `company_id` on financial and operational records to support future branches and group structures without adopting shared multi-tenant hosting now.

## Confirmed foundations

- **Accounting:** accrual basis; GHS is the initial default currency.
- **Accounting standards:** IFRS-aligned design, with statutory and tax rules configurable by effective date.
- **Architecture:** modular monolith; shared project and accounting foundations.
- **Frontend:** React, TypeScript, Vite, Tailwind CSS.
- **Backend:** Supabase PostgreSQL, Auth, Row Level Security, database functions, Edge Functions and Storage.
- **Source control:** GitHub; database changes are versioned as migrations.
- **Deployment approach:** free-tier-first for development, with production limits and costs reviewed before launch.

## Core product areas

1. Organisation, branches and departments
2. Users, roles and permissions
3. Customers, suppliers and CRM
4. Projects, contracts and variations
5. Estimation, BOQ and project budgets
6. Accounting, journals, general ledger and financial statements
7. Quotations, sales invoices, receipts and credit notes
8. Purchases, supplier bills and payables
9. Procurement and approvals
10. Inventory, warehouses and project material issues
11. Site operations, labour and equipment
12. Payroll and HR
13. Ghana tax configuration and statutory reporting
14. Architectural/engineering project stages, deliverables and revisions
15. Real-estate properties, units, sales and leases
16. Management reporting and analytics

## Non-negotiable accounting controls

- Posted journals must balance and post atomically.
- General-ledger balances are derived from posted journal lines.
- Posted entries are immutable; corrections use linked reversals or credit notes.
- Posting is idempotent and protected against duplicate submissions.
- Closed accounting periods reject unauthorised postings.
- Subledgers reconcile to the general ledger.
- Revenue recognition is separate from invoicing and cash collection.
- Construction revenue recognition follows the applicable contract/accounting criteria; over-time recognition is not assumed for every contract.
- Monetary values use fixed-precision decimal types, never floating-point types.
- Every privileged posting operation is validated server-side and leaves an audit trail.

## Development principles

- Inspect before extending; avoid duplicate modules and premature abstractions.
- Keep business rules out of presentation components.
- Use database migrations as the source of truth for schema changes.
- Enforce permissions in the database, not only in the UI.
- Never expose Supabase service-role credentials in browser code.
- Add automated tests for accounting invariants and critical workflows.
- Do not hardcode Ghana tax rates. Tax rules must be effective-dated, configurable and verified against current official guidance before release.

## Repository layout (target)

```text
apps/
  web/                 React application
packages/
  shared/              Shared types and utilities
  accounting-core/     Accounting domain rules
  construction-core/   Construction domain rules
  tax-engine/          Effective-dated tax rules
supabase/
  migrations/          Versioned database migrations
  functions/           Edge Functions
  seed/                Development seed data
  tests/               Database tests
docs/
  architecture/
  accounting/
  database/
  tax/
```

## Delivery sequence

1. Repository and frontend foundation
2. Database foundation, identity and permissions
3. Chart of accounts, periods, journals and general ledger
4. Projects, contracts, BOQ and budgets
5. Sales, purchases, payments and reconciliation
6. Procurement, inventory and site operations
7. Construction progress, retention, advances and revenue recognition
8. Ghana tax and payroll
9. Architecture/engineering and real-estate workflows
10. Reporting, hardening and deployment

## Current status

The repository is being bootstrapped in phases. The dedicated development Supabase project is connected. The organisation/identity/access foundation is applied and versioned under `supabase/migrations`. The accounting schema and operational modules are still pending.
