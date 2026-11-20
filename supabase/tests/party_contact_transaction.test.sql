-- Phase 7.4.1: authenticated customer/supplier and contact permission regression tests.
-- Runs only in the disposable Supabase database used by CI.
BEGIN;
SELECT plan(12);
INSERT INTO auth.users (id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) VALUES
('76000000-0000-4000-8000-000000000001','authenticated','authenticated','phase741-manager@example.test','test-password',now(),now(),now()),
('76000000-0000-4000-8000-000000000002','authenticated','authenticated','phase741-viewer@example.test','test-password',now(),now(),now());
INSERT INTO public.companies (id,legal_name,display_name,created_by) VALUES
('77000000-0000-4000-8000-000000000001','Phase 7.4.1 Parties Test Ltd','Phase 7.4.1 Parties Test','76000000-0000-4000-8000-000000000001');
INSERT INTO public.company_memberships (company_id,user_id,role_id,status,joined_at)
SELECT '77000000-0000-4000-8000-000000000001',u.user_id,r.id,'active',now()
FROM (VALUES ('76000000-0000-4000-8000-000000000001'::uuid,'accountant'),
('76000000-0000-4000-8000-000000000002'::uuid,'viewer')) u(user_id,role_code)
JOIN public.roles r ON r.code=u.role_code;
INSERT INTO public.business_parties (id,company_id,party_code,legal_name,is_customer,is_supplier,created_by) VALUES
('78000000-0000-4000-8000-000000000001','77000000-0000-4000-8000-000000000001',
'P741-EXISTING','Existing Customer and Supplier',true,true,'76000000-0000-4000-8000-000000000001');

SELECT ok(to_regprocedure('public.create_party_contact(uuid,uuid,text,text,text,text,boolean)') IS NOT NULL,'party-contact RPC is installed');
SELECT ok((SELECT NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.create_party_contact(uuid,uuid,text,text,text,text,boolean)')),'party-contact RPC uses invoker privileges');
SELECT ok(has_function_privilege('authenticated','public.create_party_contact(uuid,uuid,text,text,text,text,boolean)','EXECUTE')
 AND NOT has_function_privilege('anon','public.create_party_contact(uuid,uuid,text,text,text,text,boolean)','EXECUTE'),'only authenticated users can execute party-contact RPC');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','76000000-0000-4000-8000-000000000001',true);
SELECT lives_ok($$ INSERT INTO public.business_parties(company_id,party_code,legal_name,is_customer,is_supplier)
 VALUES ('77000000-0000-4000-8000-000000000001','P741-NEW','New Customer',true,false) $$,'parties.manage member can create a business party');
SELECT lives_ok($$ SELECT public.create_party_contact('77000000-0000-4000-8000-000000000001','78000000-0000-4000-8000-000000000001','Primary Contact One','Director','one@example.test','0200000001',true) $$,'parties.manage member can create a primary contact');
SELECT lives_ok($$ SELECT public.create_party_contact('77000000-0000-4000-8000-000000000001','78000000-0000-4000-8000-000000000001','Primary Contact Two','Manager','two@example.test','0200000002',true) $$,'creating a replacement primary contact succeeds');
RESET ROLE;

SELECT is((SELECT count(*)::integer FROM public.party_contacts WHERE company_id='77000000-0000-4000-8000-000000000001'
 AND party_id='78000000-0000-4000-8000-000000000001' AND is_primary AND is_active),1,'replacement leaves exactly one active primary contact');
SELECT ok(EXISTS(SELECT 1 FROM public.party_contacts WHERE party_id='78000000-0000-4000-8000-000000000001' AND contact_name='Primary Contact Two' AND is_primary)
 AND EXISTS(SELECT 1 FROM public.party_contacts WHERE party_id='78000000-0000-4000-8000-000000000001' AND contact_name='Primary Contact One' AND NOT is_primary),
 'new primary replaces the previous primary');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','76000000-0000-4000-8000-000000000002',true);
SELECT ok((SELECT count(*) FROM public.business_parties WHERE company_id='77000000-0000-4000-8000-000000000001')=2,'read-only member can read company business parties');
SELECT throws_ok($$ INSERT INTO public.business_parties(company_id,party_code,legal_name,is_customer,is_supplier)
 VALUES ('77000000-0000-4000-8000-000000000001','P741-DENIED','Denied Customer',true,false) $$,
 '42501',NULL,'read-only member cannot create a business party');
SELECT throws_ok($$ SELECT public.create_party_contact('77000000-0000-4000-8000-000000000001','78000000-0000-4000-8000-000000000001','Unauthorised Contact',null,null,null,false) $$,
 '42501','You do not have permission to manage business parties','read-only member cannot create or replace party contacts');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
