# Architecture Decision Log

## ADR-001: Modular monolith

**Decision:** Start with a modular monolith rather than microservices.

**Reason:** The initial product is built and deployed per customer. A modular codebase reduces operational overhead while preserving clear domain boundaries.

## ADR-002: Separate customer installations

**Decision:** Each customer receives a separate deployment and database.

**Reason:** This matches the initial single-company installation requirement and reduces cross-customer data isolation complexity. Keep company identifiers in relevant records for future branch/group needs.

## ADR-003: PostgreSQL as accounting source of truth

**Decision:** Use PostgreSQL constraints and controlled database operations for critical accounting integrity.

**Reason:** Double-entry posting, atomicity, permissions and auditability must not depend on browser behavior.

## ADR-004: Versioned database changes

**Decision:** All schema changes are committed as ordered Supabase migrations.

**Reason:** Environments must be reproducible and reviewable. Do not make undocumented manual production schema changes.

## ADR-005: Free-tier-first development

**Decision:** Prefer free tiers while developing and validating the product.

**Reason:** Keep early costs low, but review storage, compute, backups, availability, support and usage limits before production deployment.
