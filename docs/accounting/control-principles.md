# Accounting Control Principles

These are product requirements, not a claim of completed implementation.

## Basis and currency

- Accrual accounting is the default basis.
- GHS is the initial default functional and presentation currency; support ISO currency codes for additional currencies.
- Store monetary amounts in fixed-precision PostgreSQL `NUMERIC` columns, never floating-point types.
- Store transaction currency, functional currency and exchange-rate context where foreign currency is supported.

## Journal and ledger integrity

- A journal must contain at least two lines and total debits must equal total credits before posting.
- Posting is atomic: either the journal and all related ledger effects commit, or none do.
- Posting operations are idempotent and protected against duplicate source-document submissions.
- Posted journals and lines are immutable. Correct errors through controlled reversal and replacement workflows.
- Preserve source-document references, actor, timestamps and audit history.
- Prevent posting to locked or closed accounting periods unless an authorised reopen process is completed and recorded.

## Reporting

- Trial balance, profit or loss, statement of financial position and cash-flow reporting derive from posted ledger data.
- Receivables, payables, inventory and fixed-asset subledgers must reconcile to the general ledger.
- Project is a reporting dimension, not a separate ledger.

## Construction-specific accounting

Support contract variations, progress certificates, mobilisation advances, advance applications, retention, contract assets and contract liabilities. Keep billing, cash collection and revenue recognition as separate events.

Revenue recognition must be based on the applicable accounting requirements and contract facts. The system must not assume every construction contract qualifies for recognition over time. Where permitted, support appropriate input or output methods and retain the calculation evidence and approval history.

## Tax and payroll

Tax rules must be effective-dated, configurable and traceable to an official source. Do not hardcode tax rates in frontend components or database triggers. Verify Ghana tax and payroll rules against current official guidance before enabling a statutory calculation in production.
