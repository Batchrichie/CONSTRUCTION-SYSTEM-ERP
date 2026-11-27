# Authenticated browser verification

The authenticated browser suite lives in `e2e/authenticated-workspace.spec.cjs` and runs against a deployed application using Chromium.

## Configure the test account

Create a dedicated, non-production Supabase user with an active membership in the test company. The account should have read access to Projects, Customers & Suppliers and Estimates & BOQ. Do not use an administrator or production user's personal credentials.

Add these GitHub Actions repository secrets:

- `E2E_EMAIL`: email address of the dedicated test user.
- `E2E_PASSWORD`: password for that test user.

The test account must already have a company workspace. The suite deliberately does not create a company or write business records.

## Run the suite

1. Open Actions → Authenticated Browser Tests.
2. Select Run workflow.
3. Enter the deployed Vercel preview or test-environment URL.
4. Run the workflow and inspect the uploaded Playwright report.

The workflow uses the URL supplied at dispatch time and the two repository secrets. It does not connect to or mutate the hosted production database directly.

## Current coverage

- Sign in and reach the authenticated company dashboard.
- Navigate Projects, Customers & Suppliers, and Estimates & BOQ.
- Sign out and return to the unauthenticated sign-in screen.

## Next coverage to add

- Role-specific navigation and write permissions using separate least-privilege test accounts.
- Project and estimate create/edit/submit/approve flows using disposable test fixtures.
- Recovery of browser state after token expiry and network interruption.
