-- Phase 7.4.3: customer, project and contract link validation.
-- Isolated pgTAP regression coverage only; no production records are changed.
BEGIN;

SELECT plan(16);

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) VALUES
  ('71000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'phase743-owner-a@example.test', 'test-password', now(), now(), now()),
  ('71000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'phase743-owner-b@example.test', 'test-password', now(), now(), now());

INSERT INTO public.companies (id, legal_name, display_name, created_by)
VALUES
  ('72000000-0000-4000-8000-000000000001', 'Phase 7.4.3 Company A Ltd', 'Company A',
   '71000000-0000-4000-8000-000000000001'),
  ('72000000-0000-4000-8000-000000000002', 'Phase 7.4.3 Company B Ltd', 'Company B',
   '71000000-0000-4000-8000-000000000002');

INSERT INTO public.business_parties (
  id, company_id, party_code, legal_name, is_customer, is_supplier, status, created_by
) VALUES
  ('73000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000001',
   'T743-CUST-A', 'Active Customer A', true, false, 'active',
   '71000000-0000-4000-8000-000000000001'),
  ('73000000-0000-4000-8000-000000000002', '72000000-0000-4000-8000-000000000001',
   'T743-CUST-B', 'Active Customer B', true, false, 'active',
   '71000000-0000-4000-8000-000000000001'),
  ('73000000-0000-4000-8000-000000000003', '72000000-0000-4000-8000-000000000001',
   'T743-INACT', 'Inactive Customer', true, false, 'inactive',
   '71000000-0000-4000-8000-000000000001'),
  ('73000000-0000-4000-8000-000000000004', '72000000-0000-4000-8000-000000000001',
   'T743-SUPP', 'Supplier Only', false, true, 'active',
   '71000000-0000-4000-8000-000000000001'),
  ('73000000-0000-4000-8000-000000000005', '72000000-0000-4000-8000-000000000002',
   'T743-CUST-X', 'Company B Customer', true, false, 'active',
   '71000000-0000-4000-8000-000000000002');

INSERT INTO public.projects (
  id, company_id, project_code, name, customer_party_id, created_by
) VALUES
  ('74000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000001',
   'T743-PROJ-A', 'Customer A Project', '73000000-0000-4000-8000-000000000001',
   '71000000-0000-4000-8000-000000000001'),
  ('74000000-0000-4000-8000-000000000002', '72000000-0000-4000-8000-000000000001',
   'T743-PROJ-OPEN', 'Project Without Customer', null,
   '71000000-0000-4000-8000-000000000001');

INSERT INTO public.project_contracts (
  id, company_id, project_id, contract_ref, title, contract_type,
  contract_value, customer_party_id, created_by
) VALUES (
  '75000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000001',
  '74000000-0000-4000-8000-000000000001', 'T743-CON-A', 'Matching Contract',
  'fixed_price', 100000, '73000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001'
);

SELECT ok(
  EXISTS (SELECT 1 FROM public.projects
    WHERE id = '74000000-0000-4000-8000-000000000001'
      AND customer_party_id = '73000000-0000-4000-8000-000000000001'),
  'a project accepts a same-company active customer'
);

SELECT throws_ok(
  $$ INSERT INTO public.projects (company_id, project_code, name, customer_party_id, created_by)
     VALUES ('72000000-0000-4000-8000-000000000001', 'T743-BAD-SUPP',
       'Supplier As Customer', '73000000-0000-4000-8000-000000000004',
       '71000000-0000-4000-8000-000000000001') $$,
  '23514',
  'a supplier-only party cannot be linked as a project customer'
);

SELECT throws_ok(
  $$ INSERT INTO public.projects (company_id, project_code, name, customer_party_id, created_by)
     VALUES ('72000000-0000-4000-8000-000000000001', 'T743-BAD-INACT',
       'Inactive Customer Project', '73000000-0000-4000-8000-000000000003',
       '71000000-0000-4000-8000-000000000001') $$,
  '23514',
  'an inactive customer cannot be linked to a project'
);

SELECT throws_ok(
  $$ INSERT INTO public.projects (company_id, project_code, name, customer_party_id, created_by)
     VALUES ('72000000-0000-4000-8000-000000000001', 'T743-BAD-COMPANY',
       'Cross Company Customer Project', '73000000-0000-4000-8000-000000000005',
       '71000000-0000-4000-8000-000000000001') $$,
  '23514',
  'a project cannot reference a customer from another company'
);

SELECT ok(
  EXISTS (SELECT 1 FROM public.project_contracts
    WHERE id = '75000000-0000-4000-8000-000000000001'),
  'a contract accepts the customer already linked to its project'
);

SELECT throws_ok(
  $$ INSERT INTO public.project_contracts (
       company_id, project_id, contract_ref, title, contract_type,
       contract_value, customer_party_id, created_by
     ) VALUES (
       '72000000-0000-4000-8000-000000000001',
       '74000000-0000-4000-8000-000000000001', 'T743-CON-MISMATCH',
       'Mismatched Contract', 'fixed_price', 50000,
       '73000000-0000-4000-8000-000000000002',
       '71000000-0000-4000-8000-000000000001'
     ) $$,
  '23514',
  'a contract customer must match its project customer'
);

SELECT ok(
  (SELECT customer_party_id IS NULL FROM public.projects
    WHERE id = '74000000-0000-4000-8000-000000000002'),
  'a project may remain unassigned to a customer'
);

SELECT ok(
  (SELECT customer_party_id IS NULL FROM public.project_contracts
    WHERE id = '75000000-0000-4000-8000-000000000001') IS FALSE,
  'the valid contract retains its explicit customer link'
);

SELECT throws_ok(
  $$ INSERT INTO public.estimates (
       company_id, estimate_number, project_id, customer_party_id,
       title, created_by
     ) VALUES (
       '72000000-0000-4000-8000-000000000001', 'T743-EST-SUPP',
       null, '73000000-0000-4000-8000-000000000004',
       'Supplier Estimate', '71000000-0000-4000-8000-000000000001'
     ) $$,
  '23514',
  'an estimate cannot be issued to a supplier-only party'
);

SELECT throws_ok(
  $$ INSERT INTO public.estimates (
       company_id, estimate_number, project_id, customer_party_id,
       title, created_by
     ) VALUES (
       '72000000-0000-4000-8000-000000000001', 'T743-EST-INACT',
       null, '73000000-0000-4000-8000-000000000003',
       'Inactive Customer Estimate', '71000000-0000-4000-8000-000000000001'
     ) $$,
  '23514',
  'an estimate cannot reference an inactive customer'
);

SELECT throws_ok(
  $$ INSERT INTO public.estimates (
       company_id, estimate_number, project_id, customer_party_id,
       title, created_by
     ) VALUES (
       '72000000-0000-4000-8000-000000000001', 'T743-EST-PROJ',
       '74000000-0000-4000-8000-000000000001',
       '73000000-0000-4000-8000-000000000002',
       'Mismatched Project Estimate', '71000000-0000-4000-8000-000000000001'
     ) $$,
  '23514',
  'an estimate customer must match the linked project customer'
);

SELECT throws_ok(
  $$ INSERT INTO public.estimates (
       company_id, estimate_number, project_id, project_contract_id,
       customer_party_id, title, created_by
     ) VALUES (
       '72000000-0000-4000-8000-000000000001', 'T743-EST-CON-CUST',
       '74000000-0000-4000-8000-000000000001',
       '75000000-0000-4000-8000-000000000001',
       '73000000-0000-4000-8000-000000000002',
       'Mismatched Contract Customer Estimate',
       '71000000-0000-4000-8000-000000000001'
     ) $$,
  '23514',
  'an estimate customer must match the linked contract customer'
);

SELECT throws_ok(
  $$ INSERT INTO public.estimates (
       company_id, estimate_number, project_id, project_contract_id,
       customer_party_id, title, created_by
     ) VALUES (
       '72000000-0000-4000-8000-000000000001', 'T743-EST-CON-PROJ',
       '74000000-0000-4000-8000-000000000002',
       '75000000-0000-4000-8000-000000000001',
       '73000000-0000-4000-8000-000000000001',
       'Wrong Contract Project Estimate',
       '71000000-0000-4000-8000-000000000001'
     ) $$,
  '23514',
  'an estimate contract must belong to the selected estimate project'
);

SELECT throws_ok(
  $$ INSERT INTO public.estimates (
       company_id, estimate_number, project_id, project_contract_id,
       customer_party_id, title, created_by
     ) VALUES (
       '72000000-0000-4000-8000-000000000001', 'T743-EST-CROSS',
       null, null, '73000000-0000-4000-8000-000000000005',
       'Cross Company Estimate', '71000000-0000-4000-8000-000000000001'
     ) $$,
  '23514',
  'an estimate cannot reference a customer from another company'
);

SELECT throws_ok(
  $$ UPDATE public.business_parties
     SET is_customer = false
     WHERE id = '73000000-0000-4000-8000-000000000001' $$,
  '23514',
  'a customer linked to a project or contract cannot lose its customer designation'
);

SELECT lives_ok(
  $$ UPDATE public.business_parties
     SET is_customer = false, is_supplier = true
     WHERE id = '73000000-0000-4000-8000-000000000002' $$,
  'an unlinked customer may be converted to a supplier'
);

SELECT ok(
  (SELECT is_customer = false AND is_supplier = true
   FROM public.business_parties
   WHERE id = '73000000-0000-4000-8000-000000000002'),
  'the unlinked party role change is persisted'
);

SELECT * FROM finish();
ROLLBACK;
