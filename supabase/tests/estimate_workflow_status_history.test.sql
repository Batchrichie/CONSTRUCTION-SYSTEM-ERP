-- Phase 7.4.4: estimate workflow, authorization and immutable status history.
-- Runs only in the disposable Supabase database started by GitHub Actions.
BEGIN;

SELECT plan(27);

-- Fixtures: one installation/company, with separate manage, approve and read-only users.
INSERT INTO auth.users (
  id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) VALUES
  ('81000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'phase744-manager@example.test', 'test-password', now(), now(), now()),
  ('81000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'phase744-approver@example.test', 'test-password', now(), now(), now()),
  ('81000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'phase744-viewer@example.test', 'test-password', now(), now(), now());

INSERT INTO public.companies (id, legal_name, display_name, created_by)
VALUES (
  '82000000-0000-4000-8000-000000000001',
  'Phase 7.4.4 Test Company Ltd', 'Phase 7.4.4 Test Company',
  '81000000-0000-4000-8000-000000000001'
);

INSERT INTO public.company_memberships (company_id, user_id, role_id, status, joined_at)
SELECT '82000000-0000-4000-8000-000000000001', users.user_id, roles.id, 'active', now()
FROM (VALUES
  ('81000000-0000-4000-8000-000000000001'::uuid, 'accountant'),
  ('81000000-0000-4000-8000-000000000002'::uuid, 'project_manager'),
  ('81000000-0000-4000-8000-000000000003'::uuid, 'viewer')
) AS users(user_id, role_code)
JOIN public.roles roles ON roles.code = users.role_code;

INSERT INTO public.business_parties (
  id, company_id, party_code, legal_name, is_customer, is_supplier, status, created_by
) VALUES (
  '83000000-0000-4000-8000-000000000001',
  '82000000-0000-4000-8000-000000000001',
  'T744-CUST', 'Phase 7.4.4 Test Customer', true, false, 'active',
  '81000000-0000-4000-8000-000000000001'
);

INSERT INTO public.estimates (
  id, company_id, estimate_number, customer_party_id, title, created_by
) VALUES
  ('84000000-0000-4000-8000-000000000001',
   '82000000-0000-4000-8000-000000000001', 'T744-EMPTY',
   '83000000-0000-4000-8000-000000000001', 'Unpriced estimate',
   '81000000-0000-4000-8000-000000000001'),
  ('84000000-0000-4000-8000-000000000002',
   '82000000-0000-4000-8000-000000000001', 'T744-REJECT',
   '83000000-0000-4000-8000-000000000001', 'Estimate for rejection',
   '81000000-0000-4000-8000-000000000001'),
  ('84000000-0000-4000-8000-000000000003',
   '82000000-0000-4000-8000-000000000001', 'T744-APPROVE',
   '83000000-0000-4000-8000-000000000001', 'Estimate for approval',
   '81000000-0000-4000-8000-000000000001');

INSERT INTO public.estimate_items (
  company_id, estimate_id, item_number, description, unit, quantity, unit_rate
) VALUES
  ('82000000-0000-4000-8000-000000000001',
   '84000000-0000-4000-8000-000000000001', '1', 'Unpriced BOQ item', 'item', 1, 0),
  ('82000000-0000-4000-8000-000000000001',
   '84000000-0000-4000-8000-000000000002', '1', 'Priced BOQ item', 'item', 10, 25),
  ('82000000-0000-4000-8000-000000000001',
   '84000000-0000-4000-8000-000000000003', '1', 'Priced BOQ item', 'item', 4, 125);

SET LOCAL ROLE authenticated;

-- Authentication is mandatory even when the caller has the authenticated database role.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'submitted', null
     ) $$,
  '42501',
  'Authentication is required',
  'an authenticated database role without a user identity cannot transition an estimate'
);

-- Viewer has estimating.read only, not estimating.manage.
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000003', true);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'submitted', null
     ) $$,
  '42501',
  'You do not have permission to manage estimates',
  'a read-only user cannot submit an estimate'
);

-- Accountant has estimating.manage, but submission still requires a priced BOQ.
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000001', 'submitted', null
     ) $$,
  '23514',
  'An estimate must contain at least one priced BOQ item before submission',
  'an estimate with zero priced BOQ value cannot be submitted'
);
SELECT is(
  (SELECT status FROM public.estimates
   WHERE id = '84000000-0000-4000-8000-000000000001'),
  'draft',
  'a rejected submission attempt leaves the estimate in draft'
);

SELECT lives_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'submitted', '  Sent for review  '
     ) $$,
  'a user with estimating.manage can submit a priced estimate'
);
RESET ROLE;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.estimate_status_history
    WHERE estimate_id = '84000000-0000-4000-8000-000000000002'
      AND company_id = '82000000-0000-4000-8000-000000000001'
      AND from_status = 'draft' AND to_status = 'submitted'
      AND note = 'Sent for review'
      AND changed_by = '81000000-0000-4000-8000-000000000001'
  ),
  'submission history records company, estimate, old/new status, trimmed note and acting user'
);

-- Manage permission alone is insufficient for approval/rejection.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'approved', null
     ) $$,
  '42501',
  'You do not have permission to approve or reject estimates',
  'an estimating manager without estimating.approve cannot approve'
);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'rejected', 'Insufficient scope'
     ) $$,
  '42501',
  'You do not have permission to approve or reject estimates',
  'an estimating manager without estimating.approve cannot reject'
);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'cancelled', null
     ) $$,
  '22023',
  'Invalid estimate status transition: submitted to cancelled',
  'a submitted estimate cannot be cancelled directly'
);

-- Project manager has both manage and approve permissions.
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000002', true);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'rejected', null
     ) $$,
  '22023',
  'A rejection reason is required',
  'rejection without a reason is rejected'
);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'rejected', '   '
     ) $$,
  '22023',
  'A rejection reason is required',
  'a whitespace-only rejection reason is rejected'
);
SELECT lives_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'rejected', '  Revise the structural scope  '
     ) $$,
  'an authorised approver can reject with a non-empty reason'
);
RESET ROLE;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.estimate_status_history
    WHERE estimate_id = '84000000-0000-4000-8000-000000000002'
      AND from_status = 'submitted' AND to_status = 'rejected'
      AND note = 'Revise the structural scope'
      AND changed_by = '81000000-0000-4000-8000-000000000002'
  ),
  'rejection history records the approver and required reason'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
SELECT lives_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'draft', 'Returned for revision'
     ) $$,
  'a rejected estimate can return to draft for revision'
);
SELECT lives_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'cancelled', 'No longer required'
     ) $$,
  'a draft estimate can be cancelled'
);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000002', 'submitted', null
     ) $$,
  '22023',
  'Invalid estimate status transition: cancelled to submitted',
  'a cancelled estimate cannot be reopened or resubmitted'
);

-- Approval path: an authorised approver may submit and approve a priced estimate.
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000002', true);
SELECT lives_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000003', 'submitted', null
     ) $$,
  'a user with both permissions can submit a priced estimate'
);
SELECT lives_ok(
  $$ SELECT public.transition_estimate(
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000003', 'approved', null
     ) $$,
  'an authorised approver can approve a submitted estimate'
);
RESET ROLE;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.estimates
    WHERE id = '84000000-0000-4000-8000-000000000003'
      AND status = 'approved'
      AND approved_by = '81000000-0000-4000-8000-000000000002'
      AND approved_at IS NOT NULL
  ),
  'approval stores the correct approver and approval timestamp'
);
-- Ordinary authenticated users cannot bypass the RPC or alter its history.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
SELECT throws_ok(
  $$ UPDATE public.estimates SET status = 'approved'
     WHERE id = '84000000-0000-4000-8000-000000000001' $$,
  '42501',
  'a user cannot directly update estimate status'
);
SELECT throws_ok(
  $$ INSERT INTO public.estimate_status_history
       (company_id, estimate_id, from_status, to_status, changed_by)
     VALUES (
       '82000000-0000-4000-8000-000000000001',
       '84000000-0000-4000-8000-000000000001', 'draft', 'submitted',
       '81000000-0000-4000-8000-000000000001'
     ) $$,
  '42501',
  'a user cannot insert fabricated status history'
);
SELECT throws_ok(
  $$ UPDATE public.estimate_status_history SET note = 'tampered'
     WHERE estimate_id = '84000000-0000-4000-8000-000000000002' $$,
  '42501',
  'a user cannot modify status history'
);
SELECT throws_ok(
  $$ DELETE FROM public.estimate_status_history
     WHERE estimate_id = '84000000-0000-4000-8000-000000000002' $$,
  '42501',
  'a user cannot delete status history'
);

-- Read-only users may inspect history within their company.
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000003', true);
SELECT ok(
  (SELECT count(*) FROM public.estimate_status_history
   WHERE estimate_id = '84000000-0000-4000-8000-000000000002') = 4,
  'a read-only member can read the estimate status history'
);

-- A company identifier outside this installation cannot be used to transition its estimate.
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
SELECT throws_ok(
  $$ SELECT public.transition_estimate(
       '82999999-0000-4000-8000-000000000099',
       '84000000-0000-4000-8000-000000000001', 'submitted', null
     ) $$,
  '42501',
  'You do not have permission to manage estimates',
  'an estimate cannot be transitioned under another company identifier'
);
RESET ROLE;

SELECT is(
  (SELECT status FROM public.estimates
   WHERE id = '84000000-0000-4000-8000-000000000001'),
  'draft',
  'a cross-company transition attempt leaves the estimate unchanged'
);

-- The transition function must lock the estimate row before validating and changing state.
SELECT ok(
  position(
    'for update' IN lower(pg_get_functiondef(
      'private.transition_estimate(uuid,uuid,text,text)'::regprocedure
    ))
  ) > 0,
  'estimate transitions acquire a row lock to serialize concurrent attempts'
);

SELECT * FROM finish();
ROLLBACK;
