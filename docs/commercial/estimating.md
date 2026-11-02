# Commercial parties, estimates and BOQ

## Business parties

The `business_parties` table is the shared customer/supplier register. A record can be a customer, supplier, or both. It stores the company-scoped party code, legal and trading names, tax/registration identifiers, primary contact details, postal address, country, credit/payment terms and active status.

Contact persons are stored in `party_contacts`; one active primary contact is allowed per party. Customer references on projects and contracts use `customer_party_id`. The legacy `client_name` text fields remain for compatibility during migration of existing project records.

## Estimates and revisions

An estimate belongs to a company and a customer, and can optionally reference a project and project contract. `estimate_number` plus `revision_number` uniquely identifies a revision within a company. Revision creation/numbering is supplied by the application; automatic document numbering and revision cloning are future work.

Supported statuses:
- `draft`: editable BOQ and header.
- `submitted`: locked pending review.
- `approved`: approved commercial estimate; approval user and timestamp are retained.
- `rejected`: rejected with a required reason; can be returned to draft for amendment.
- `cancelled`: withdrawn from use.

The `transition_estimate` RPC is the only granted route for status changes. Submission requires at least one priced BOQ item and prevents a discount greater than the BOQ subtotal. Approval/rejection requires the `estimating.approve` permission. Every transition is written to `estimate_status_history`.

## Bill of Quantities

Each estimate can contain ordered `estimate_sections` and `estimate_items`. Items capture item number, category, description, unit, quantity, rate, optional cost code and display order. Quantity must be positive; rate cannot be negative. The database calculates `line_total` using fixed-precision numeric arithmetic. `estimate_totals` aggregates BOQ line totals and applies estimate-level discount and tax inputs.

## Access control

- `parties.read` / `parties.manage` control party and contact access.
- `estimating.read` / `estimating.manage` control estimate and BOQ access.
- `estimating.approve` controls approval and rejection.
- All new public tables have RLS enabled and explicit authenticated grants; no anonymous access is granted.
- BOQ sections and items can only be changed while the parent estimate is a draft.
- Status history is read-only to authenticated users; changes are written by the controlled transition function.

## Accounting and tax boundary

Estimates are not invoices, customer balances, contract assets, revenue, or cash receipts. They do not create journal entries or update the general ledger. Estimate tax and discount values are commercial inputs only and are not a Ghana VAT calculation or statutory tax filing. Approved estimates do not automatically create contracts or update project budgets. Sales invoicing, receipts, credit notes, VAT treatment, revenue recognition and project budget baselines are separate subsequent workflows.

## Verification limitations

The migrations are applied to the dedicated development Supabase project. Schema/RLS/grants/views and advisor checks have been verified. There are no company records or authenticated test users yet, so live user journeys for party creation, BOQ editing, submission, approval and rejection remain to be tested after test-user provisioning.
