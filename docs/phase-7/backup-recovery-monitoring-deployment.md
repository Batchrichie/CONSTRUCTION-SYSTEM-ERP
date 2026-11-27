# Phase 7.5 — Backup, recovery, monitoring and deployment runbook

## Status and scope

This runbook defines the minimum operational procedures for the Construction System ERP before production use. It is a documented operating plan, not evidence that backups, alerts or restore automation have already been configured. No hosted settings, production data or database objects are changed by this document.

The application uses Supabase for PostgreSQL/authentication and Vercel for deployment. Confirm the actual Supabase plan, Vercel plan, retention limits and available recovery features in the project dashboards before relying on any provider capability.

## 1. Backup policy

### Required layers

1. **Provider-managed database backups:** Confirm that automated backups are enabled for the Supabase project, record the retention period and backup schedule, and identify whether point-in-time recovery (PITR) is available on the current plan. Do not assume PITR is included.
2. **Independent logical backups:** Maintain encrypted PostgreSQL exports outside the Supabase project. Include the application schema, data, functions, policies and required database metadata. Keep backup credentials in an approved secret store; never commit them to GitHub or place them in logs.
3. **Source and configuration:** GitHub is the source of truth for migrations and application code. Keep a secure inventory of Supabase Auth redirect URLs, authentication settings, Storage configuration (if used), Vercel environment-variable names, domains and deployment settings. Do not put secret values in the inventory.
4. **Evidence:** Record backup timestamp, project/environment, method, result, size, retention expiry and operator. Alert on failed or missing backups.

### Suggested minimum retention

- Daily logical backup: retain 14 days.
- Weekly backup: retain 8 weeks.
- Monthly backup: retain 12 months.

These are proposed starting values, not current provider settings. Adjust them to legal, contractual, cost and recovery requirements. Store backups encrypted and separately from the production project; restrict restore and download access.

## 2. Recovery objectives

Agree and record business-approved targets before launch:

- **RPO (maximum acceptable data loss):** proposed target 24 hours when only daily independent backups are available. A shorter RPO requires a verified PITR or more frequent backup arrangement.
- **RTO (maximum acceptable outage):** proposed initial target one business day, subject to a successful restore rehearsal.

A target is not achieved merely because a provider advertises a feature. Measure it during restore drills.

## 3. Restore procedure

1. Declare an incident, identify the affected environment and appoint an incident lead.
2. Stop or restrict writes where safe; communicate the incident and preserve relevant logs.
3. Select the recovery point based on the incident timeline and approved RPO. Record why it was selected.
4. Restore to a **separate recovery project/environment first**. Never test a restore by overwriting production.
5. Apply the repository's migrations in the documented order if the selected recovery method does not already include the required schema.
6. Verify schema/migration version, user access, company membership, RLS, grants, accounting periods, journals, ledger totals and key project/estimate records. Reconcile trial balance totals and inspect audit history.
7. Run frontend smoke tests against the recovery environment and verify authentication redirect URLs and environment variables.
8. Obtain business-owner approval before switching traffic or reopening writes.
9. Record recovery start/end times, selected backup, data-loss window, validation results and follow-up actions.

Run a restore rehearsal at least quarterly and after material changes to backup configuration. A backup is not considered proven until it has been restored and validated.

## 4. Monitoring and alerting

### Supabase
Monitor:
- Database availability, connection/resource pressure and storage growth.
- Failed migrations and database errors.
- Authentication failures and unusual sign-in patterns.
- API errors, elevated latency and RLS/permission failures.
- Backup completion and retention status.

### Vercel
Monitor:
- Production and preview deployment status.
- Build failures and deployment rollbacks.
- Function/runtime errors, request failures and latency.
- Domain, TLS and environment-variable configuration changes.

### Application-level controls
- Log important operational failures with request/correlation identifiers, but never log passwords, access tokens, service-role keys or full sensitive financial payloads.
- Alert on repeated posting failures, duplicate/idempotency conflicts beyond expected retries, and unexpected inability to access accounting periods or reports.
- Keep audit records for sensitive business actions and privileged access.
- Assign an owner and escalation contact for each alert. Review alerts on working days and test alert delivery quarterly.

## 5. Deployment and rollback

1. All changes enter through a pull request. Require relevant frontend CI, database migration/pgTAP and concurrency checks to pass.
2. Review migration safety: prefer additive changes, preserve RLS and grants, and identify any backfill, lock or downtime risk.
3. Deploy to a Vercel preview first. Smoke-test sign-in, company workspace, role permissions, projects, customers/suppliers, estimates/BOQ and accounting reports relevant to the change.
4. Apply database migrations using the approved migration process. Do not rely on a frontend rollback to reverse a database migration.
5. Promote the verified deployment to production and record commit SHA, migration version, deployment URL, operator and timestamp.
6. If the frontend release fails, roll back to the last known-good Vercel deployment. If a migration is involved, use a forward fix or a separately reviewed database recovery plan; do not blindly reverse destructive migrations.
7. Verify authentication, core reads, journal posting controls and financial reports after rollback/recovery.

Keep development, preview and production Supabase projects and credentials separate. Never point preview deployments at production data by default.

## 6. Operational ownership and records

Before production, name:
- Primary technical operator and backup operator.
- Person authorized to approve production deployments.
- Person authorized to approve database restores.
- Incident communications contact.

Maintain a release log, backup log, restore-drill report, incident log and list of current provider settings. Review this runbook quarterly and whenever the hosting architecture or data sensitivity changes.

## 7. Readiness checklist

- [ ] Confirm Supabase automated backup schedule and retention in the dashboard.
- [ ] Confirm whether PITR is available and enabled; document its actual retention.
- [ ] Establish encrypted independent logical backups and failure alerts.
- [ ] Perform a restore into a separate recovery project.
- [ ] Measure and approve RPO/RTO based on the restore drill.
- [ ] Configure Supabase and Vercel monitoring/alerts and test notification delivery.
- [ ] Document environment separation and secret ownership.
- [ ] Complete a preview-to-production release and rollback rehearsal.
- [ ] Assign operational owners and schedule quarterly restore drills.

## References

Use the current official provider documentation and the actual project dashboard as the source of truth because plan features and retention limits can change:

- Supabase backups: https://supabase.com/docs/guides/platform/backups
- Supabase point-in-time recovery: https://supabase.com/docs/guides/platform/backups#point-in-time-recovery
- Supabase database management: https://supabase.com/docs/guides/database
- Vercel deployments: https://vercel.com/docs/deployments
- Vercel rollback: https://vercel.com/docs/deployments/instant-rollback
- Vercel monitoring: https://vercel.com/docs/observability
