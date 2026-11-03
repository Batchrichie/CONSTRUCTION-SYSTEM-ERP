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

## Delivery sequence

1. Repository and frontend foundation
2. Database foundation, identity and permissions
3. Chart of accounts, fiscal periods, journals and general ledger
4. Projects, contracts, cost codes and budgets
5. Customers, suppliers, estimates and BOQ
6. Sales, purchases, payments and reconciliation
7. Procurement, inventory and site operations
8. Construction progress, retention, advances and revenue recognition
9. Ghana tax and payroll
10. Architecture/engineering and real-estate workflows
11. Reporting, hardening and deployment

## Current implementation status

- Phases 1–6 and their integration are merged into `main`.
- The development Supabase project is connected and all 16 versioned migrations are recorded as applied.
- Organisation, identity, role/permission foundations, accounting, project costing, customers/suppliers, estimates and BOQ are present in the database.
- Authentication, company onboarding, customer/supplier management and estimate/BOQ workflows are implemented in the frontend.
- CI runs TypeScript/production build, Vitest tests and ESLint.
- Phase 7 is the verification and hardening phase. Authenticated end-to-end coverage, accounting/project-cost control tests, operational sample workflows and production readiness remain outstanding.
- The development database currently contains one company membership and no fiscal years, journals, projects, parties or estimates. Do not treat the empty operational tables as tested workflows.
- Supabase Auth leaked-password protection is currently reported disabled by the security advisor and must be enabled in the project Auth settings before production use. Follow the dashboard-only release gate in [`docs/security/auth-hardening.md`](docs/security/auth-hardening.md).

See `docs/phase-7/verification-plan.md` for the staged acceptance plan.
