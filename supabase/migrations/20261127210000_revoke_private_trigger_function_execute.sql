-- Phase 7.5: internal trigger functions are invoked by their table triggers only.
-- Remove PostgreSQL's default PUBLIC EXECUTE grant from these private functions.
-- Trigger execution continues to work; EXECUTE is required when creating a trigger,
-- not each time PostgreSQL fires an already-installed trigger.

revoke all on function private.copy_reversal_cost_allocations()
  from public, anon, authenticated;
revoke all on function private.enforce_expense_cost_attribution()
  from public, anon, authenticated;
revoke all on function private.prevent_customer_role_removal_when_linked()
  from public, anon, authenticated;
revoke all on function private.touch_commercial_updated_at()
  from public, anon, authenticated;
revoke all on function private.touch_project_budget_updated_at()
  from public, anon, authenticated;
revoke all on function private.touch_project_updated_at()
  from public, anon, authenticated;
revoke all on function private.validate_customer_party_link()
  from public, anon, authenticated;
revoke all on function private.validate_estimate_party_links()
  from public, anon, authenticated;
