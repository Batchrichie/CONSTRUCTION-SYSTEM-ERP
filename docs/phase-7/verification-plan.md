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
- [ ] Verify email confirmation and password recovery using a real development user.
- [ ] Verify first-company onboarding and duplicate-company protection with authenticated tests.
- [ ] Verify role changes and suspended membership behaviour.

### 7.2 Accounting controls

- [ ] Verify chart-of-account seed and account activation rules.
- [ ] Verify fiscal year and period creation, opening, closing and locking.
- [ ] Verify balanced draft journal creation and reject unbalanced/invalid lines.
- [ ] Verify atomic posting, idempotency and duplicate submission handling.
- [ ] Verify closed-period posting rejection.
- [ ] Verify reversal linkage, opposite debit/credit lines and preservation of original posted journals.
- [ ] Reconcile trial balance to posted journal lines.

### 7.3 Project cost controls

- [ ] Verify project/contract/customer links and company boundaries.
- [ ] Verify budget setup and cost-code validity.
- [ ] Verify split project/overhead allocations equal the expense debit line.
- [ ] Verify incomplete or over-allocated expense lines cannot post.
- [ ] Verify project cost reports reconcile to attributed posted journal lines.

### 7.4 Commercial workflows

- [ ] Verify customer/supplier creation and contacts under role permissions.
- [ ] Verify estimate/BOQ calculations against PostgreSQL totals.
- [ ] Verify invalid customer, project and contract links are rejected.
- [ ] Verify submit/approve/reject/cancel permissions and immutable status history.
- [ ] Verify revision cloning preserves source estimate and BOQ without duplicating or losing sections/items.
- [ ] Verify concurrent revision creation cannot generate duplicate revision numbers.

### 7.5 Security, quality and release readiness

- [ ] Test cross-company isolation and role-specific access with at least two authenticated users.
- [ ] Review grants, RLS policies, SECURITY DEFINER functions and exposed views.
- [ ] Enable leaked-password protection in Supabase Auth settings.
- [ ] Add deterministic automated database tests and authenticated browser integration tests.
- [ ] Keep CI green and document the exact checks run.
- [ ] Define backup, recovery, monitoring and deployment procedures before production use.

## Execution order

1. Frontend auth/workspace reliability and deterministic tests.
2. Database-level tests for accounting invariants and permissions.
3. Authenticated end-to-end tests for onboarding, commercial and project workflows.
4. Fix findings in isolated migrations/PRs; do not bypass RLS or weaken accounting controls.
5. Re-run CI, database advisors and authenticated regression tests.
6. Only then plan the next feature phase.

## Current baseline (2026-11-02)

- Main branch includes Phases 1–6 and CI stabilisation PR #8.
- The dedicated development Supabase project has 16 recorded migrations and all inspected public application tables have RLS enabled.
- One company and one membership exist; no fiscal years, journals, projects, business parties or estimates are currently recorded.
- CI currently covers TypeScript/production build, Vitest and ESLint. The automated suite is still small and does not exercise authenticated database behaviour.
- Security advisor warning: leaked-password protection is disabled. Performance advisor unused-index notices are expected while the development database is nearly empty; do not remove indexes based only on this empty-database signal.
