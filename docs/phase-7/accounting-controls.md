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
supabase start
supabase test db
```

The committed `supabase/config.toml` pins the local database major version to
PostgreSQL 17, matching the development project's major version. The database
is created locally from the versioned migrations. The test runner wraps each
SQL test in a transaction and rolls it back; no remote project credentials are
needed or used.

GitHub Actions runs the same database test suite against a fresh local
Supabase stack on pull requests targeting `main` and pushes to `main` or
`phase-*` branches.

Do not run this fixture against the live development database. The current
development database is intentionally empty of fiscal periods and journals.
