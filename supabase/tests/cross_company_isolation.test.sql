-- Phase 7.5: verify that an authenticated outsider cannot access the single company's data.
-- The ERP deployment is single-company; this uses one member and one non-member user.
-- Runs only in the disposable CI database; no hosted data is touched.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(6);
CREATE TEMP TABLE _membership_fixture (
  company_id uuid NOT NULL, owner_id uuid NOT NULL, outsider_id uuid NOT NULL
) ON COMMIT DROP;
INSERT INTO _membership_fixture VALUES (gen_random_uuid(),gen_random_uuid(),gen_random_uuid());
GRANT SELECT ON _membership_fixture TO authenticated;
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
SELECT owner_id,'authenticated','authenticated','member-'||owner_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb FROM _membership_fixture
UNION ALL
SELECT outsider_id,'authenticated','authenticated','outsider-'||outsider_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb FROM _membership_fixture;
INSERT INTO public.companies(id,legal_name,display_name,base_currency,country_code,created_by)
SELECT company_id,'Single Company Boundary Test Limited','Single Company Boundary Test','GHS','GH',owner_id FROM _membership_fixture;
SELECT private.seed_default_chart_of_accounts(company_id) FROM _membership_fixture;
INSERT INTO public.company_memberships(company_id,user_id,role_id,status,joined_at)
SELECT company_id,owner_id,r.id,'active',now()
FROM _membership_fixture CROSS JOIN public.roles r WHERE r.code='owner';

-- The authorized member can access the company.
SELECT set_config('request.jwt.claim.sub',(SELECT owner_id::text FROM _membership_fixture),true);
SET LOCAL ROLE authenticated;
SELECT extensions.ok(
  (SELECT count(*) > 0 FROM public.chart_of_accounts WHERE company_id=(SELECT company_id FROM _membership_fixture)),
  'Company member can read the company chart'
);
SELECT extensions.ok(
  private.has_company_permission((SELECT company_id FROM _membership_fixture),'accounting.read'),
  'Company member has accounting.read permission'
);

-- A second authenticated user with no membership must see no company data.
SELECT set_config('request.jwt.claim.sub',(SELECT outsider_id::text FROM _membership_fixture),true);
SELECT extensions.is(
  (SELECT count(*)::integer FROM public.chart_of_accounts WHERE company_id=(SELECT company_id FROM _membership_fixture)),
  0,'Non-member cannot read chart-of-accounts records'
);
SELECT extensions.is(
  (SELECT count(*)::integer FROM public.companies WHERE id=(SELECT company_id FROM _membership_fixture)),
  0,'Non-member cannot read company record'
);
SELECT extensions.ok(
  NOT private.has_company_permission((SELECT company_id FROM _membership_fixture),'accounting.read'),
  'Non-member has no accounting permission'
);
UPDATE public.chart_of_accounts SET is_active=false
WHERE company_id=(SELECT company_id FROM _membership_fixture) AND account_code='1110';

-- Return to the member identity to prove the outsider's update was blocked.
SELECT set_config('request.jwt.claim.sub',(SELECT owner_id::text FROM _membership_fixture),true);
SELECT extensions.ok(
  (SELECT is_active FROM public.chart_of_accounts
   WHERE company_id=(SELECT company_id FROM _membership_fixture) AND account_code='1110'),
  'Non-member cannot update the company chart'
);
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
