-- Phase 7.5: role-specific accounting access and organisation boundary tests.
-- Exercises authenticated RLS and RPC behaviour in the disposable CI database.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(15);
CREATE TEMP TABLE _role_fixture (
  company_id uuid NOT NULL, owner_id uuid NOT NULL, accountant_id uuid NOT NULL,
  viewer_id uuid NOT NULL, cash_id uuid, bank_id uuid, journal_id uuid
) ON COMMIT DROP;
INSERT INTO _role_fixture(company_id,owner_id,accountant_id,viewer_id)
VALUES(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid());
GRANT SELECT, UPDATE ON _role_fixture TO authenticated;
INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
SELECT owner_id,'authenticated','authenticated','role-owner-'||owner_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb FROM _role_fixture
UNION ALL SELECT accountant_id,'authenticated','authenticated','role-accountant-'||accountant_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb FROM _role_fixture
UNION ALL SELECT viewer_id,'authenticated','authenticated','role-viewer-'||viewer_id::text||'@example.test','',now(),'{}'::jsonb,'{}'::jsonb FROM _role_fixture;
INSERT INTO public.companies(id,legal_name,display_name,base_currency,country_code,created_by)
SELECT company_id,'Role Boundary Test Limited','Role Boundary Test','GHS','GH',owner_id FROM _role_fixture;
SELECT private.seed_default_chart_of_accounts(company_id) FROM _role_fixture;
INSERT INTO public.company_memberships(company_id,user_id,role_id,status,joined_at)
SELECT f.company_id,u.user_id,r.id,'active',now()
FROM _role_fixture f
CROSS JOIN LATERAL (VALUES (f.owner_id,'owner'),(f.accountant_id,'accountant'),(f.viewer_id,'viewer')) AS u(user_id,role_code)
JOIN public.roles r ON r.code=u.role_code;
INSERT INTO public.fiscal_years(company_id,year_code,start_date,end_date,status,created_by)
SELECT company_id,'ROLE-'||left(company_id::text,8),date '2026-01-01',date '2026-12-31','open',owner_id FROM _role_fixture;
INSERT INTO public.accounting_periods(company_id,fiscal_year_id,period_number,period_name,start_date,end_date,status)
SELECT f.company_id,fy.id,1,'January',date '2026-01-01',date '2026-01-31','open'
FROM _role_fixture f JOIN public.fiscal_years fy ON fy.company_id=f.company_id;
UPDATE _role_fixture f SET cash_id=a.id FROM public.chart_of_accounts a WHERE a.company_id=f.company_id AND a.account_code='1110';
UPDATE _role_fixture f SET bank_id=a.id FROM public.chart_of_accounts a WHERE a.company_id=f.company_id AND a.account_code='1120';

SELECT set_config('request.jwt.claim.sub',(SELECT accountant_id::text FROM _role_fixture),true);
SET LOCAL ROLE authenticated;
SELECT extensions.ok(private.has_company_permission((SELECT company_id FROM _role_fixture),'accounting.read'),'Accountant has accounting.read');
SELECT extensions.ok(private.has_company_permission((SELECT company_id FROM _role_fixture),'accounting.manage'),'Accountant has accounting.manage');
SELECT extensions.ok(private.has_company_permission((SELECT company_id FROM _role_fixture),'accounting.post'),'Accountant has accounting.post');
SELECT extensions.ok(NOT private.has_company_permission((SELECT company_id FROM _role_fixture),'company.manage'),'Accountant does not have company.manage');
SELECT extensions.ok(NOT private.has_company_permission((SELECT company_id FROM _role_fixture),'users.manage'),'Accountant does not have users.manage');
SELECT extensions.ok((SELECT count(*) > 0 FROM public.chart_of_accounts WHERE company_id=(SELECT company_id FROM _role_fixture)),'Accountant can read the company chart of accounts');
SELECT extensions.lives_ok(
  format('UPDATE _role_fixture SET journal_id=public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb)',
    (SELECT company_id FROM _role_fixture),date '2026-01-15','Accountant role posting permission',
    jsonb_build_array(
      jsonb_build_object('account_id',(SELECT cash_id FROM _role_fixture),'debit',125,'credit',0),
      jsonb_build_object('account_id',(SELECT bank_id FROM _role_fixture),'debit',0,'credit',125)
    )::text),
  'Accountant can create a balanced journal draft');
SELECT extensions.lives_ok(format('SELECT public.post_journal_entry(%L::uuid)',(SELECT journal_id FROM _role_fixture)),
  'Accountant can post a balanced journal');
SELECT extensions.is((SELECT status FROM public.journal_entries WHERE id=(SELECT journal_id FROM _role_fixture)),
  'posted'::text,'Accountant journal is posted through the controlled RPC');

SELECT set_config('request.jwt.claim.sub',(SELECT viewer_id::text FROM _role_fixture),true);
SELECT extensions.ok(NOT private.has_company_permission((SELECT company_id FROM _role_fixture),'accounting.read'),'Viewer does not have accounting.read');
SELECT extensions.ok(NOT private.has_company_permission((SELECT company_id FROM _role_fixture),'accounting.manage'),'Viewer does not have accounting.manage');
SELECT extensions.is((SELECT count(*)::integer FROM public.chart_of_accounts WHERE company_id=(SELECT company_id FROM _role_fixture)),0,
  'Viewer cannot read the company chart of accounts');
UPDATE public.chart_of_accounts SET is_active=false WHERE company_id=(SELECT company_id FROM _role_fixture) AND account_code='1110';
SELECT set_config('request.jwt.claim.sub',(SELECT owner_id::text FROM _role_fixture),true);
SELECT extensions.ok((SELECT is_active FROM public.chart_of_accounts WHERE company_id=(SELECT company_id FROM _role_fixture) AND account_code='1110'),
  'Viewer cannot deactivate a chart-of-accounts record');
SELECT set_config('request.jwt.claim.sub',(SELECT viewer_id::text FROM _role_fixture),true);
SELECT extensions.throws_ok(
  format('SELECT public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb)',
    (SELECT company_id FROM _role_fixture),date '2026-01-16','Viewer must not create journal',
    jsonb_build_array(
      jsonb_build_object('account_id',(SELECT cash_id FROM _role_fixture),'debit',10,'credit',0),
      jsonb_build_object('account_id',(SELECT bank_id FROM _role_fixture),'debit',0,'credit',10)
    )::text),
  '42501','You do not have permission to create journals for this company',
  'Viewer cannot create a journal through the RPC');

SELECT set_config('request.jwt.claim.sub',(SELECT accountant_id::text FROM _role_fixture),true);
UPDATE public.company_memberships SET role_id=(SELECT id FROM public.roles WHERE code='admin')
WHERE company_id=(SELECT company_id FROM _role_fixture) AND user_id=(SELECT viewer_id FROM _role_fixture);
SELECT set_config('request.jwt.claim.sub',(SELECT owner_id::text FROM _role_fixture),true);
SELECT extensions.is((SELECT r.code FROM public.company_memberships m JOIN public.roles r ON r.id=m.role_id
  WHERE m.company_id=(SELECT company_id FROM _role_fixture) AND m.user_id=(SELECT viewer_id FROM _role_fixture)),
  'viewer'::text,'Accountant cannot change another member role');

RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
