# Phase 7.2 — Accounting controls

## First verified defect and correction

The original `account_balances` view determined the sign of a balance from
`account_type`. That is incorrect for contra accounts. For example,
Accumulated Depreciation is an asset account with a credit normal balance.

The follow-up migration exposes `normal_balance` in the general ledger and
calculates each account balance using that value, matching the existing
trial-balance convention.

## Regression coverage

`supabase/tests/accounting_views.test.sql` creates isolated fixture data inside
a transaction and verifies:

- General-ledger normal-balance metadata.
- Correct debit/credit sign for Accumulated Depreciation.
- Agreement between account balances and the trial balance.
- Retention of both original and reversing journal lines.
- Net-zero balances after a reversal.

The test rolls back its fixture data.

## Running the database tests

The test uses pgTAP and is intended for a local Supabase database after all
migrations have been applied:

```sh
supabase test db supabase/tests/accounting_views.test.sql
```

Do not run this fixture against the live development database. The current
development database is intentionally empty of fiscal periods and journals.
