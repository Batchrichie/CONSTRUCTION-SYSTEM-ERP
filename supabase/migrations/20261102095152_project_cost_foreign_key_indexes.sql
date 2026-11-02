-- Supporting indexes for the Phase 4 composite and actor foreign keys.
create index projects_company_branch_fk_idx on public.projects(company_id,branch_id);
create index projects_company_manager_fk_idx on public.projects(company_id,project_manager_user_id);
create index projects_created_by_fk_idx on public.projects(created_by);
create index project_contracts_created_by_fk_idx on public.project_contracts(created_by);
create index cost_codes_parent_fk_idx on public.cost_codes(company_id,parent_cost_code_id);
create index cost_centres_branch_fk_idx on public.cost_centres(company_id,branch_id);
create index project_budgets_cost_code_fk_idx on public.project_budgets(company_id,cost_code_id);
create index project_budgets_created_by_fk_idx on public.project_budgets(created_by);
create index journal_cost_allocations_cost_code_fk_idx on public.journal_line_cost_allocations(company_id,cost_code_id);
create index journal_cost_allocations_created_by_fk_idx on public.journal_line_cost_allocations(created_by);
