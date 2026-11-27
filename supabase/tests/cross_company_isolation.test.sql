-- Phase 7.5: prove tenant isolation with two authenticated users in separate companies.
-- Runs only in the disposable CI database; no hosted data is touched.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(10);
CREATE TEMP TABLE _cross_company_fixture (
  company_a uuid NOT NULL, company_b uuid NOT NULL, user_a uuid NOT NULL, user_b uuid NOT NULL
) ON COMMIT DROP;
INSERT INTO _cross_company_fixture VALUES (gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid());
GRANT SELECT ON _cross_company_fixture TO authenticated;
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
SELECT user_a,'authenticated','authenticated','tenant-a-'||user_a::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb FROM _cross_company_fixture
UNION ALL
SELECT user_b,'authenticated','authenticated','tenant-b-'||user_b::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb FROM _cross_company_fixture;
INSERT INTO public.companies(id,legal_name,display_name,base_currency,country_code,created_by)
SELECT company_a,'Tenant A Test Limited','Tenant A Test','GHS','GH',user_a FROM _cross_company_fixture
UNION ALL
SELECT company_b,'Tenant B Test Limited','Tenant B Test','GHS','GH',user_b FROM _cross_company_fixture;
SELECT private.seed_default_chart_of_accounts(company_a) FROM _cross_company_fixture;
SELECT private.seed_default_chart_of_accounts(company_b) FROM _cross_company_fixture;
INSERT INTO public.company_memberships(company_id,user_id,role_id,status,joined_at)
SELECT company_a,user_a,r.id,'active',now() FROM _cross_company_fixture CROSS JOIN public.roles r WHERE r.code='owner'
UNION ALL
SELECT company_b,user_b,r.id,'active',now() FROM _cross_company_fixture CROSS JOIN public.roles r WHERE r.code='owner';
SELECT set_config('request.jwt.claim.sub',(SELECT user_a::text FROM _cross_company_fixture),true);
SET LOCAL ROLE authenticated;
SELECT extensions.ok((SELECT count(*) > 0 FROM public.chart_of_accounts WHERE company_id=(SELECT company_a FROM _cross_company_fixture)),'User A can read their own company chart');
SELECT extensions.is((SELECT count(*)::integer FROM public.chart_of_accounts WHERE company_id=(SELECT company_b FROM _cross_company_fixture)),0,'User A cannot read company B chart');
SELECT extensions.is((SELECT count(*)::integer FROM public.companies WHERE id=(SELECT company_b FROM _cross_company_fixture)),0,'User A cannot read company B record');
SELECT extensions.ok(private.has_company_permission((SELECT company_a FROM _cross_company_fixture),'accounting.read'),'User A has accounting permission in company A');
SELECT extensions.ok(NOT private.has_company_permission((SELECT company_b FROM _cross_company_fixture),'accounting.read'),'User A has no accounting permission in company B');
UPDATE public.chart_of_accounts SET is_active=false WHERE company_id=(SELECT company_b FROM _cross_company_fixture) AND account_code='1110';
SELECT set_config('request.jwt.claim.sub',(SELECT user_b::text FROM _cross_company_fixture),true);
SELECT extensions.ok((SELECT count(*) > 0 FROM public.chart_of_accounts WHERE company_id=(SELECT company_b FROM _cross_company_fixture)),'User B can read their own company chart');
SELECT extensions.is((SELECT count(*)::integer FROM public.chart_of_accounts WHERE company_id=(SELECT company_a FROM _cross_company_fixture)),0,'User B cannot read company A chart');
SELECT extensions.ok((SELECT is_active FROM public.chart_of_accounts WHERE company_id=(SELECT company_b FROM _cross_company_fixture) AND account_code='1110'),'User A could not update company B chart');
SELECT extensions.ok(private.has_company_permission((SELECT company_b FROM _cross_company_fixture),'accounting.read'),'User B has accounting permission in company B');
SELECT extensions.ok(NOT private.has_company_permission((SELECT company_a FROM _cross_company_fixture),'accounting.read'),'User B has no accounting permission in company A');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
