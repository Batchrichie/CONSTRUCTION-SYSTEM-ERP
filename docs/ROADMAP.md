# Construction System ERP — Delivery Roadmap

Last updated: 2026-11-19  
Baseline: `main` at `904cceaa969b4a0628ef2d586351e7fb82c196f6`

This is the working delivery plan. Work through one phase at a time, in order. A phase is complete only when its acceptance criteria are implemented, automated checks pass, the reviewed PR is merged, and any required manual release checks are explicitly recorded.

## Working rules

- Inspect the current code and tests before changing anything; do not rebuild working features.
- Prefer regression tests and isolated CI/local databases before production changes.
- Database changes require versioned migrations. Never apply a migration to the live Supabase project without explicit approval.
- Never weaken RLS, grants, permission checks, accounting invariants, or audit history to make tests pass.
- Verify the exact PR head and all relevant GitHub Actions jobs before merging.
- Keep this roadmap and the detailed [Phase 7 verification plan](phase-7/verification-plan.md) updated as work is completed.
- For external/manual checks (email delivery, Auth dashboard settings, backups), record evidence and owner; do not mark complete based on assumptions.

## Part A — Phase 7: integration verification and hardening

Phase 7 is the release gate proving the foundations work together under authenticated use. It is not a feature-count milestone.

### 7.1 Authentication and company workspace — IN PROGRESS

1. Deterministic initial sign-in rendering when Supabase configuration is missing — complete.
2. Distinguish missing membership from failed membership/company lookup — complete.
3. Retry transient workspace lookup failures — complete.
4. Ignore stale lookup responses after sign-out or a newer request — complete.
5. Verify email confirmation and password recovery with a real development user — pending manual verification.
6. Verify first-company onboarding with authenticated tests — complete (PR #41).
7. Verify duplicate-company protection with authenticated tests — complete (PR #41; duplicate requests leave no extra company, membership or profile).
8. Verify role changes and suspended membership behaviour — complete (PR #42; owners can change ordinary member roles, and suspension immediately revokes workspace access).

**Next work:** complete the real-user email confirmation and password recovery check. The reset UI and recovery event have automated coverage in PR #40, but hosted email delivery and the configured redirect allow-list still require a real development account and inbox verification.

### 7.2 Accounting controls — IN PROGRESS

1. Chart-of-account seed integrity and account activation/deactivation rules — complete (PR #44; 10 pgTAP assertions cover seeded flags, inactive/non-postable/manual-restricted accounts, posting-time revalidation and viewer permissions).
2. Fiscal-year and period creation, opening, closing and locking — complete (PR #35 and PR #46; 20 lifecycle assertions cover creation, authorization, valid/invalid transitions, overlap/containment, draft-journal and empty/open-period close guards, locked-period posting, audit trail and direct-write restrictions).
3. Balanced journal draft creation; reject unbalanced and invalid lines — audit and test coverage.
4. Atomic posting, idempotency and duplicate submission handling — regression/concurrency coverage added in PR #33; verify acceptance coverage.
5. Closed-period posting rejection — audit and test coverage.
6. Reversal linkage, opposite debit/credit lines, preservation of original posted journals and atomic failure — regression coverage added in PR #36; verify acceptance coverage.
7. Trial balance reconciliation to posted journal lines — documented regression coverage in `docs/phase-7/accounting-controls.md`; verify against current test suite.

Do not repeat controls already proven. First map each acceptance criterion to a current test and close only genuine gaps.

**Next 7.2 task:** Step 3 — balanced journal draft creation and rejection of unbalanced or invalid journal lines.

### 7.3 Project cost controls — COMPLETE

The user-defined seven-step workstream is complete and merged in PR #38 (merge commit `94246238dae0595d901bde2252c58d2d15bbddfd`).

1. Project/contract/customer links and company boundaries.
2. Budget setup and cost-code validity.
3. Split project/overhead allocations reconcile to the source expense debit.
4. Incomplete and over-allocated expense lines are rejected atomically.
5. Project cost reports reconcile to attributed posted journal lines.
6. Project cost ledger reconciles to posted expenses.
7. Reversals return project and overhead cost ledgers to net zero.

PR #38 includes the overhead ledger correction migration and regression tests. CI applied migrations only to its isolated test database; the live development database was not migrated by that PR.

### 7.4 Commercial workflows — IN PROGRESS

1. Customer/supplier creation and contact access under role permissions — audit and verify.
2. Estimate/BOQ calculations agree with PostgreSQL totals — covered by merged estimate/BOQ verification work; retain regression coverage.
3. Invalid customer, project and contract links are rejected — covered by prior validation work; verify coverage remains in main.
4. Submit/approve/reject/cancel permissions and immutable status history — workflow/status-history work and concurrency coverage exist; verify full acceptance criteria.
5. Revision cloning preserves source estimate and BOQ sections/items without duplication or loss — pending final verification.
6. Concurrent revision creation cannot generate duplicate revision numbers — pending final verification.

### 7.5 Security, quality and production readiness — NOT STARTED / PARTIALLY COVERED

1. Cross-company isolation and role-specific access using at least two authenticated users — accounting membership isolation regression coverage exists (PR #37); broaden to all relevant data surfaces and roles.
2. Review grants, RLS policies, SECURITY DEFINER functions and exposed views.
3. Enable Supabase Auth leaked-password protection — dashboard action pending; do not change without explicit authorization.
4. Add deterministic database tests and authenticated browser integration tests.
5. Keep CI green and document exact checks and evidence.
6. Define backup, recovery, monitoring and deployment procedures before production use.
7. Run realistic end-to-end sample workflows and complete a production-readiness review.

### Phase 7 exit gate

Do not begin the next feature phase until 7.1–7.5 have been reviewed against evidence, required automated tests pass, manual/dashboard actions are recorded, and the production-readiness risks are understood. The next immediate workstream is **7.1**, starting with the email confirmation/password recovery verification and then authenticated onboarding tests.

## Part B — Product delivery after Phase 7

These are the planned feature phases. Their detailed scope and acceptance criteria will be refined before each phase begins.

### Phase 8 — Sales, invoicing and accounts receivable
- Quotations and sales orders where appropriate.
- Customer invoices, credit notes, receipts and allocations.
- Receivables ageing, customer statements and invoice numbering.
- Posting to the general ledger with period, tax, permission and idempotency controls.

### Phase 9 — Purchases and accounts payable
- Supplier bills, debit notes/credit notes and supplier payments.
- Bill approvals, payment allocations and payable ageing.
- Supplier statements and AP-to-GL reconciliation.

### Phase 10 — Procurement and approvals
- Purchase requisitions, RFQs, quotation comparison and purchase orders.
- Approval limits, delegated authority and audit trail.
- Goods/service receipt and links to projects, budgets and supplier bills.

### Phase 11 — Inventory and warehouse management
- Items, units of measure, warehouses and stock locations.
- Receipts, issues, transfers, adjustments and stock counts.
- Valuation, inventory-to-GL reconciliation and project material issues/returns.

### Phase 12 — Construction site operations
- Site diaries, daily reports, labour, equipment and subcontractor records.
- Material usage, progress quantities, site instructions and evidence attachments.
- Project/site permissions and operational dashboards.

### Phase 13 — Construction financial management
- Work in progress and cost-to-complete.
- Progress claims/certificates, advances, retention and variations.
- Contract assets/liabilities and construction revenue recognition based on contract facts and applicable accounting policy.
- Project margin, forecast and earned-value reporting.

### Phase 14 — Ghana tax and payroll
- Effective-dated Ghana tax configuration and statutory calculations.
- PAYE, SSNIT Tier 1, Tier 2/QLAC and configured Tier 3 contributions.
- Payroll, payslips, statutory reports and accounting postings.
- Validate requirements against current Ghana law before release.

### Phase 15 — Architecture, engineering and real estate
- Design stages, deliverables, drawing/document revisions and approvals.
- Professional time/cost tracking and client deliverables.
- Properties, units, sales, leases, deposits and property-related accounting.

### Phase 16 — Management reporting and analytics
- Management dashboards and configurable reports.
- Project profitability, cash flow, budgets, commitments and forecasts.
- Consolidated operational reporting with drill-down to source transactions.

### Phase 17 — Production release
- Performance, security and accessibility review.
- Backup/restore rehearsal, monitoring, incident response and deployment runbooks.
- Data migration and opening-balance procedures.
- User acceptance testing, training material and final release approval.

## Standard workflow for every phase

1. Inspect existing implementation, schema, permissions and tests.
2. Write scoped acceptance criteria and identify dependencies.
3. Implement the smallest coherent change on a feature branch.
4. Add/update automated tests, including database and concurrency tests where relevant.
5. Run CI and inspect underlying job/step results and logs.
6. Fix failures and review the final diff for security/accounting regressions.
7. Merge only when required checks pass.
8. Update this roadmap and phase-specific documentation with evidence.
9. Keep production migrations and dashboard changes separate; obtain approval before applying them.
