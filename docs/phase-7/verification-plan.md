# Phase 7 — Verification and hardening

## Objective

Prove that the Phase 1–6 foundations work together under authenticated use before expanding into sales, purchasing, procurement, inventory, site operations or statutory workflows.

This phase is a control and reliability gate, not a feature-count milestone. A visible page or an applied migration is not proof that the workflow is operational.

## Workstreams and acceptance criteria

### 7.1 Authentication and company workspace

- [x] Keep initial sign-in rendering deterministic when Supabase configuration is missing.
- [x] Distinguish a missing company membership from a failed membership/company lookup.
- [x] Provide a retry path for a transient company workspace lookup failure.
- [x] Ignore stale company lookup responses after sign-out or a newer request.
- [ ] Verify email confirmation and password recovery using a real development user (automated reset-flow tests merged in PR #40; hosted delivery and redirect allow-list still require manual verification).
- [x] Verify first-company onboarding and duplicate-company protection with authenticated tests (PR #41; six pgTAP assertions).
- [x] Verify role changes and suspended membership behaviour (PR #42; six pgTAP assertions).

### 7.2 Accounting controls

- [x] Verify chart-of-account seed and account activation rules (PR #44; seed hierarchy, activation, postability, manual-journal restrictions and role enforcement covered by pgTAP).
- [x] Verify fiscal year and period creation, opening, closing and locking (PR #35 and PR #46; creation defaults, authorized opening/closing/locking, overlap and containment rejection, draft-journal close guard, open/empty-year close guards, locked-period posting rejection, no-reopen transitions, audit trail and direct-write restrictions covered by pgTAP).
- [x] Verify balanced draft journal creation and reject unbalanced/invalid lines (PR #48; six additional pgTAP assertions cover one-line journals, zero/negative amounts, malformed and unavailable account IDs, and absence of partial headers; existing assertions cover balanced totals, unbalanced lines and debit/credit exclusivity).
- [x] Verify atomic posting, idempotency and duplicate submission handling (PR #33 and current CI evidence: audit-write failure rolls back journal status, number, ledger and audit; repeated post returns the existing number; concurrent draft requests with the same key return one draft; concurrent posts return one journal number and produce exactly one ledger posting, audit row and counter increment).
- [x] Verify closed-period posting rejection with no side effects (PR #51; rejected posting leaves the journal in draft, assigns no number, creates no general-ledger rows or posting audit, and does not increment the journal-number counter).
- [x] Verify reversal linkage, opposite debit/credit lines and preservation of original posted journals (PR #36 and existing journal integrity coverage; original remains present as reversed, one linked posted reversal mirrors every account and amount in the opposite direction, duplicate reversal is rejected, and audit failure rolls back atomically).
- [x] Reconcile trial balance to posted journal lines after the actual reversal RPC (PR #52; cash and bank closing balances return to zero, total debits equal credits, and every trial-balance account reconciles to its general-ledger debit/credit totals).

### 7.3 Project cost controls — COMPLETE (PR #38)

- [x] Verify project/contract/customer links and company boundaries.
- [x] Verify budget setup and cost-code validity.
- [x] Verify split project/overhead allocations equal the expense debit line.
- [x] Verify incomplete or over-allocated expense lines cannot post.
- [x] Verify project cost reports reconcile to attributed posted journal lines.
- [x] Verify project cost ledger reconciliation to posted expenses.
- [x] Verify reversal of project costs returns project and overhead ledgers to net zero.

### 7.4 Commercial workflows — COMPLETE (PRs #23–#27, #54–#55)

- [x] Verify customer/supplier creation and contacts under role permissions (PR #55; authenticated accountant/read-only fixtures verify create/read boundaries, primary-contact replacement and one-active-primary invariant).
- [x] Verify estimate/BOQ calculations against PostgreSQL totals (PR #23; generated four-decimal line totals, subtotal/discount/tax composition, invoker-security totals view and frontend decimal tests).
- [x] Verify invalid customer, project and contract links are rejected (PR #24; active customer designation, project/contract/estimate customer consistency, company boundaries and linked-party role protection).
- [x] Verify submit/approve/reject/cancel permissions and immutable status history (PR #25; 27 pgTAP assertions cover priced submission, separate manage/approve permissions, required rejection reasons, allowed transitions, audit attribution and direct-write denial; PR #26 adds a two-session stale-transition race test).
- [x] Verify revision cloning preserves source estimate and BOQ without duplicating or losing sections/items (PR #27; permission and eligible-source checks, draft status, validity-date handling, section/item copy, remapped BOQ relationships and source immutability).
- [x] Verify concurrent revision creation cannot generate duplicate revision numbers (PR #54; two independent PostgreSQL sessions serialize on the company/estimate-number advisory lock and create unique revisions with copied BOQ content).

**Phase 7.4 final verification evidence (2026-11-27):** PR #55 merge commit `4f3048a86e21d356495ebfe4c2b1315db9582764` was verified with frontend type check/build/tests/lint; isolated Supabase migrations and pgTAP; estimate transition, estimate revision, duplicate journal-draft and duplicate journal-posting concurrency tests; and Vercel preview. No live database changes were made. Earlier dedicated PRs #23–#27 and #54 also merged; their database and frontend checks passed.

### 7.5 Security, quality and release readiness

- [x] Test cross-company isolation and role-specific access with at least two authenticated users (PR #61; one authorized member and one authenticated non-member in the single-company installation model; member accounting access succeeds, outsider reads and writes are denied).
- [x] Review grants, RLS policies, SECURITY DEFINER functions and exposed views (hosted read-only review on 2026-11-27: all public tables have RLS and policies; all public views use security_invoker; no public SECURITY DEFINER functions; private SECURITY DEFINER functions have empty search_path; no public tables granted directly to anon; no public functions executable by anon. Eight private trigger functions had API-role EXECUTE grants; migration `20261127214753_revoke_private_trigger_function_execute` was applied and verified on hosted DB on 2026-11-27: anon/authenticated execution is false for all private trigger functions).
- [ ] Enable leaked-password protection in Supabase Auth settings (security advisor still reports disabled; enable in Supabase Dashboard → Authentication → Settings → Password Security).
- [x] Add deterministic automated database tests (existing isolated migration, pgTAP and concurrency suites).
- [ ] Authenticated browser integration tests — deferred by product decision on 2026-11-27; PR #64 was closed without merging and can be reopened when a dedicated test account and non-production target are available.
- [ ] Keep CI green and document the exact checks run.
- [x] Document backup, recovery, monitoring and deployment procedures (runbook added; operational configuration and restore rehearsal remain open).

**Phase 7.5 PR #61 evidence (2026-11-27):** Merge commit `8f3f29bb8d24799f16e55399c750d916bd8307a1`. CI, isolated database migration/pgTAP tests, all four concurrency checks and Vercel preview passed. Test fixtures roll back; no hosted database or production data changes were made.

**Hosted security migration evidence (2026-11-27):** Applied migration `20261127214753_revoke_private_trigger_function_execute` to Supabase project `tpqpdunwniezmvrvyzxv` after explicit user approval. Post-migration verification confirmed all 12 private trigger functions deny EXECUTE to anon and authenticated while postgres retains EXECUTE. The only remaining security-advisor finding is leaked-password protection disabled.

## Execution order

1. Frontend auth/workspace reliability and deterministic tests.
2. Database-level tests for accounting invariants and permissions.
3. Fix findings in isolated migrations/PRs; do not bypass RLS or weaken accounting controls.
4. Re-run CI, database advisors and automated database regression tests.
5. Complete the backup, restore, monitoring and deployment readiness checklist in `backup-recovery-monitoring-deployment.md`.
6. Authenticated browser tests remain deferred until a dedicated test account and non-production target are available.
7. Only then plan the next feature phase.

## Current baseline (2026-11-02)

- Main branch includes Phases 1–6 and CI stabilisation PR #8.
- The dedicated development Supabase project has recorded migrations and all inspected public application tables have RLS enabled.
- One company and one membership existed at the initial baseline; no fiscal years, journals, projects, business parties or estimates were then recorded.
- CI covers TypeScript/production build, Vitest, ESLint, isolated Supabase migrations, pgTAP and concurrency checks.
- Security advisor warning: leaked-password protection is disabled. Performance advisor unused-index notices should not be acted on without workload evidence.
