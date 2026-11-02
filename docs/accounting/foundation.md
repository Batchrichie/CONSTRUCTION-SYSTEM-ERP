# Accounting Database Foundation

## Delivered

The accounting database foundation includes fiscal years, accounting periods, a company chart of accounts, journal headers and lines, controlled posting and reversal functions, a general-ledger view, account balances and a trial-balance view.

The deployment model allows one company workspace per database. Branches are represented separately, while financial and operational records retain company scope.

All monetary amounts use PostgreSQL NUMERIC(20,4). The initial functional currency is the company base currency, defaulting to GHS. Foreign-currency remeasurement and FX gains/losses are not yet implemented.

## Starter chart of accounts

New companies created through the company onboarding RPC receive a construction-focused starter chart. It covers cash, bank, mobile money, receivables, contract assets, retention receivable, inventory, work in progress, fixed assets, supplier payables, VAT, PAYE, pensions, contract liabilities, retention payable, equity, construction revenue, design revenue, real-estate revenue, direct project costs, operating expenses and finance costs.

System accounts are protected from ordinary Data API editing. Company administrators can add additional accounts. Control accounts and accounts marked as not manually journalable are reserved for future source-module workflows.

## Period controls

Fiscal years cannot overlap within a company. Periods must fall within their fiscal year and cannot overlap. Fiscal years and periods are created in draft state and opened through validated RPCs. An open period can close only when no draft journals remain; closed periods can be locked. A fiscal year closes only after all its periods are closed or locked. Lifecycle changes are audited.

## Journal controls

A journal draft is created through the database RPC. The database validates company permissions, open period, company-owned active/postable accounts, manual-journal eligibility, positive one-sided debit/credit lines, and equality of total debits and credits. An idempotency key prevents duplicate submissions and rejects reuse with a different payload.

Posting is atomic. It revalidates the journal, assigns a sequential journal number for the company and fiscal year, records the posting user and timestamp, and writes an audit event. Authenticated clients have read-only access to journal headers and lines; writes occur through controlled RPCs.

Reversals create a new opposite journal in an open period and link it to the original. The original is marked reversed but remains visible in the general ledger alongside the reversing journal. No posted entry is deleted or silently removed from history.

## Security

All accounting tables in the exposed public schema have RLS enabled. Data API grants are explicit and least-privilege. Company access is checked against active membership and role permissions. Public RPC wrappers use SECURITY INVOKER; privileged implementations are held in the non-exposed private schema, use an empty search path, and validate the authenticated user and permissions. General-ledger, account-balance and trial-balance views use security_invoker=true.

## Not yet implemented

- Frontend company setup, fiscal-year setup, chart-of-accounts screens and journal UI.
- Full authenticated end-to-end posting/reversal test; no test Auth user was provisioned in the live project.
- Foreign currency journals, remeasurement and realised/unrealised FX accounting.
- Project, cost-code and cost-centre dimensions; these will be connected with the project/cost-management schema.
- Sales, procurement, inventory, payroll and tax source-module integrations.
- Advanced year-end closing, retained-earnings roll-forward and reconciliation workflows.
- Construction contract revenue-recognition calculations, which remain separate from invoicing and cash collection.

The database catalog, migration history, RLS, grants, RPC security posture and Supabase advisors have been checked.
