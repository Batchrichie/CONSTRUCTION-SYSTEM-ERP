# Database Foundation

## Environment

- Supabase project: `CONSTRUCTION SYSTEM ERP`
- Project reference: `tpqpdunwniezmvrvyzxv`
- Region: `eu-west-1`
- PostgreSQL: 17
- Intended use: dedicated development environment for this repository

Do not commit Supabase secrets. The browser application must use only the project URL and publishable key. A service-role or secret key must remain server-side.

## Applied migrations

1. `20261102090000_organisation_identity_access.sql`
   - Company workspace and user profile records
   - System roles and permissions catalogue
   - Company memberships
   - Branches and departments
   - Audit-log storage
   - RLS policies and explicit Data API grants
2. `20261102094500_foundation_security_and_indexes.sql`
   - Moves privileged company onboarding implementation into the non-exposed `private` schema
   - Exposes only a SECURITY INVOKER RPC wrapper
   - Adds indexes for foreign-key lookup paths

## Access model

- Supabase Auth is the identity provider.
- Company access is represented by an active row in `company_memberships`.
- The initial company creator receives the `owner` role.
- `owner` and `admin` are the only roles currently allowed to administer company structure and memberships.
- Every public application table has RLS enabled.
- Data API grants are explicit; grants do not replace RLS.
- Membership helper functions live in the non-exposed `private` schema.
- The company-onboarding RPC validates `auth.uid()`; its privileged implementation is not exposed directly.

## Initial onboarding

After a user signs in, call:

```ts
const { data: companyId, error } = await supabase.rpc(
  'create_company_for_current_user',
  {
    p_legal_name: legalName,
    p_display_name: displayName,
  },
);
```

The function creates the company, the caller's active owner membership and a profile row. It returns the new company UUID.

## Deliberate omissions

- No sample company, user or financial data has been inserted.
- No real user has been invited or assigned a role.
- Role-permission mappings are not yet seeded or enforced as fine-grained module permissions.
- Audit-log writes are not yet wired to business-table triggers or posting functions.
- Branch and department management UI is not yet implemented.
- Accounting periods, chart of accounts, journals and journal-posting functions are the next database stage.

## Verification status

The two migrations are recorded in Supabase migration history. A catalog query confirmed all nine foundation tables have RLS enabled and policies present. Security and performance advisors were run; the initial onboarding security warning was addressed by moving the SECURITY DEFINER implementation into the private schema, and missing foreign-key indexes were added. Advisors should be rerun after the next migration.
