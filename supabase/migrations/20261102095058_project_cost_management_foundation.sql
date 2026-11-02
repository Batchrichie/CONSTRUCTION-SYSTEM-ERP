-- Phase 4: project, contract, cost-code, cost-centre, budget and journal cost attribution foundation.
-- Applied to Supabase project tpqpdunwniezmvrvyzxv as migration 20261102095058.

create table public.projects (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete restrict,
 branch_id uuid, project_code text not null check(length(btrim(project_code)) between 1 and 40),
 name text not null check(length(btrim(name)) between 2 and 200), description text,
 project_type text not null default 'construction' check(project_type in ('construction','architectural_design','engineering','real_estate_development','renovation','other')),
 status text not null default 'planning' check(status in ('planning','active','on_hold','completed','cancelled')),
 location text, client_name text, project_manager_user_id uuid, planned_start_date date, planned_end_date date,
 actual_start_date date, actual_end_date date, currency_code char(3) not null default 'GHS',
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(planned_end_date is null or planned_start_date is null or planned_end_date>=planned_start_date),
 check(actual_end_date is null or actual_start_date is null or actual_end_date>=actual_start_date),
 unique(company_id,project_code), unique(company_id,id),
 foreign key(company_id,branch_id) references public.branches(company_id,id) on delete restrict,
 foreign key(company_id,project_manager_user_id) references public.company_memberships(company_id,user_id) on delete restrict
);

create table public.project_contracts (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, project_id uuid not null,
 contract_ref text not null, title text not null,
 contract_type text not null default 'fixed_price' check(contract_type in ('fixed_price','remeasurement','cost_plus','time_and_materials','design_fee','other')),
 client_name text, contract_value numeric(20,4) not null default 0 check(contract_value>=0), currency_code char(3) not null default 'GHS',
 retention_rate numeric(7,4) not null default 0 check(retention_rate between 0 and 100),
 mobilisation_amount numeric(20,4) not null default 0 check(mobilisation_amount>=0),
 start_date date, end_date date, status text not null default 'draft' check(status in ('draft','active','completed','terminated')),
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(end_date is null or start_date is null or end_date>=start_date),
 unique(company_id,project_id,contract_ref), unique(company_id,id),
 foreign key(company_id,project_id) references public.projects(company_id,id) on delete restrict
);

create table public.cost_codes (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete restrict,
 code text not null, name text not null,
 category text not null check(category in ('materials','labour','subcontractors','equipment','professional_fees','transport','permits_and_fees','site_overheads','other')),
 parent_cost_code_id uuid, is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(company_id,code), unique(company_id,id),
 foreign key(company_id,parent_cost_code_id) references public.cost_codes(company_id,id) on delete restrict,
 check(parent_cost_code_id is null or parent_cost_code_id<>id)
);

create table public.cost_centres (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete restrict,
 branch_id uuid, code text not null, name text not null,
 centre_type text not null default 'overhead' check(centre_type in ('overhead','department','site','shared')),
 is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(company_id,code), unique(company_id,id),
 foreign key(company_id,branch_id) references public.branches(company_id,id) on delete restrict
);

create table public.project_budgets (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, project_id uuid not null, cost_code_id uuid not null,
 budget_amount numeric(20,4) not null default 0 check(budget_amount>=0), approved_amount numeric(20,4) not null default 0 check(approved_amount>=0),
 currency_code char(3) not null default 'GHS', notes text, created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(company_id,project_id,cost_code_id),
 foreign key(company_id,project_id) references public.projects(company_id,id) on delete restrict,
 foreign key(company_id,cost_code_id) references public.cost_codes(company_id,id) on delete restrict
);

alter table public.journal_lines add constraint journal_lines_company_id_id_key unique(company_id,id);

create table public.journal_line_cost_allocations (
 id uuid primary key default gen_random_uuid(), company_id uuid not null, journal_line_id uuid not null,
 attribution_scope text not null check(attribution_scope in ('project','overhead')), project_id uuid, cost_code_id uuid, cost_centre_id uuid,
 allocation_side text not null check(allocation_side in ('debit','credit')), amount numeric(20,4) not null check(amount>0),
 description text, created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 check((attribution_scope='project' and project_id is not null and cost_centre_id is null) or
       (attribution_scope='overhead' and project_id is null and cost_centre_id is not null)),
 foreign key(company_id,journal_line_id) references public.journal_lines(company_id,id) on delete restrict,
 foreign key(company_id,project_id) references public.projects(company_id,id) on delete restrict,
 foreign key(company_id,cost_code_id) references public.cost_codes(company_id,id) on delete restrict,
 foreign key(company_id,cost_centre_id) references public.cost_centres(company_id,id) on delete restrict
);

create index projects_company_status_idx on public.projects(company_id,status,project_code);
create index projects_company_dates_idx on public.projects(company_id,planned_start_date,planned_end_date);
create index project_contracts_project_status_idx on public.project_contracts(company_id,project_id,status);
create index cost_codes_company_category_idx on public.cost_codes(company_id,category,is_active);
create index cost_centres_company_type_idx on public.cost_centres(company_id,centre_type,is_active);
create index project_budgets_project_idx on public.project_budgets(company_id,project_id,cost_code_id);
create index journal_cost_allocations_line_idx on public.journal_line_cost_allocations(company_id,journal_line_id);
create index journal_cost_allocations_project_idx on public.journal_line_cost_allocations(company_id,project_id,cost_code_id);
create index journal_cost_allocations_overhead_idx on public.journal_line_cost_allocations(company_id,cost_centre_id) where attribution_scope='overhead';

insert into public.permissions(code,module,description) values
 ('project_costs.read','project_costs','View project budgets, cost allocations and overhead attribution'),
 ('project_costs.manage','project_costs','Manage project budgets, cost codes, cost centres and cost allocations')
on conflict(code) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on
 (r.code in ('owner','admin') and p.code in ('projects.read','projects.manage','project_costs.read','project_costs.manage'))
 or (r.code='project_manager' and p.code in ('projects.read','projects.manage','project_costs.read','project_costs.manage'))
 or (r.code='site_supervisor' and p.code in ('projects.read','project_costs.read'))
 or (r.code='accountant' and p.code in ('projects.read','project_costs.read','project_costs.manage'))
 or (r.code='procurement_officer' and p.code in ('projects.read','project_costs.read'))
on conflict do nothing;

alter table public.projects enable row level security;
alter table public.project_contracts enable row level security;
alter table public.cost_codes enable row level security;
alter table public.cost_centres enable row level security;
alter table public.project_budgets enable row level security;
alter table public.journal_line_cost_allocations enable row level security;

create policy projects_read on public.projects for select to authenticated using((select private.has_company_permission(company_id,'projects.read')));
create policy projects_insert on public.projects for insert to authenticated with check((select private.has_company_permission(company_id,'projects.manage')));
create policy projects_update on public.projects for update to authenticated using((select private.has_company_permission(company_id,'projects.manage'))) with check((select private.has_company_permission(company_id,'projects.manage')));
create policy project_contracts_read on public.project_contracts for select to authenticated using((select private.has_company_permission(company_id,'projects.read')));
create policy project_contracts_insert on public.project_contracts for insert to authenticated with check((select private.has_company_permission(company_id,'projects.manage')));
create policy project_contracts_update on public.project_contracts for update to authenticated using((select private.has_company_permission(company_id,'projects.manage'))) with check((select private.has_company_permission(company_id,'projects.manage')));
create policy cost_codes_read on public.cost_codes for select to authenticated using((select private.has_company_permission(company_id,'project_costs.read')));
create policy cost_codes_insert on public.cost_codes for insert to authenticated with check((select private.has_company_permission(company_id,'project_costs.manage')));
create policy cost_codes_update on public.cost_codes for update to authenticated using((select private.has_company_permission(company_id,'project_costs.manage'))) with check((select private.has_company_permission(company_id,'project_costs.manage')));
create policy cost_centres_read on public.cost_centres for select to authenticated using((select private.has_company_permission(company_id,'project_costs.read')));
create policy cost_centres_insert on public.cost_centres for insert to authenticated with check((select private.has_company_permission(company_id,'project_costs.manage')));
create policy cost_centres_update on public.cost_centres for update to authenticated using((select private.has_company_permission(company_id,'project_costs.manage'))) with check((select private.has_company_permission(company_id,'project_costs.manage')));
create policy project_budgets_read on public.project_budgets for select to authenticated using((select private.has_company_permission(company_id,'project_costs.read')));
create policy project_budgets_insert on public.project_budgets for insert to authenticated with check((select private.has_company_permission(company_id,'project_costs.manage')));
create policy project_budgets_update on public.project_budgets for update to authenticated using((select private.has_company_permission(company_id,'project_costs.manage'))) with check((select private.has_company_permission(company_id,'project_costs.manage')));
create policy journal_cost_allocations_read on public.journal_line_cost_allocations for select to authenticated using((select private.has_company_permission(company_id,'project_costs.read')));

revoke all on public.projects,public.project_contracts,public.cost_codes,public.cost_centres,public.project_budgets,public.journal_line_cost_allocations from anon,authenticated;
grant select,insert,update on public.projects,public.project_contracts to authenticated;
grant select,insert,update on public.cost_codes,public.cost_centres,public.project_budgets to authenticated;
grant select on public.journal_line_cost_allocations to authenticated;

create or replace function private.replace_journal_line_cost_allocations(p_company_id uuid,p_journal_line_id uuid,p_allocations jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare
 v_user_id uuid:=auth.uid(); v_line public.journal_lines%rowtype; v_journal public.journal_entries%rowtype;
 v_item jsonb; v_scope text; v_project_id uuid; v_cost_code_id uuid; v_cost_centre_id uuid; v_side text; v_amount numeric(20,4);
begin
 if v_user_id is null then raise exception 'Authentication is required' using errcode='28000'; end if;
 if not private.has_company_permission(p_company_id,'project_costs.manage') then raise exception 'You do not have permission to manage project cost allocations' using errcode='42501'; end if;
 if jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations)>100 then raise exception 'Allocations must be an array containing no more than 100 rows' using errcode='22023'; end if;
 select * into v_line from public.journal_lines where company_id=p_company_id and id=p_journal_line_id for update;
 if not found then raise exception 'Journal line not found'; end if;
 select * into v_journal from public.journal_entries where company_id=p_company_id and id=v_line.journal_entry_id for update;
 if v_journal.status<>'draft' then raise exception 'Cost allocations can only be changed on draft journals'; end if;
 delete from public.journal_line_cost_allocations where company_id=p_company_id and journal_line_id=p_journal_line_id;
 for v_item in select value from jsonb_array_elements(p_allocations) loop
  begin
   v_scope:=v_item->>'attribution_scope'; v_project_id:=nullif(v_item->>'project_id','')::uuid;
   v_cost_code_id:=nullif(v_item->>'cost_code_id','')::uuid; v_cost_centre_id:=nullif(v_item->>'cost_centre_id','')::uuid;
   v_side:=v_item->>'allocation_side'; v_amount:=(v_item->>'amount')::numeric(20,4);
  exception when others then raise exception 'Invalid allocation data' using errcode='22023'; end;
  if v_scope='project' then
   if v_project_id is null or v_cost_centre_id is not null then raise exception 'Project allocations require a project and cannot use an overhead cost centre'; end if;
   if not exists(select 1 from public.projects where company_id=p_company_id and id=v_project_id and status<>'cancelled') then raise exception 'Project is invalid or cancelled'; end if;
  elsif v_scope='overhead' then
   if v_project_id is not null or v_cost_centre_id is null then raise exception 'Overhead allocations require a cost centre and cannot use a project'; end if;
   if not exists(select 1 from public.cost_centres where company_id=p_company_id and id=v_cost_centre_id and is_active and centre_type in ('overhead','department','shared')) then raise exception 'Overhead cost centre is invalid or inactive'; end if;
  else raise exception 'Attribution scope must be project or overhead'; end if;
  if v_cost_code_id is not null and not exists(select 1 from public.cost_codes where company_id=p_company_id and id=v_cost_code_id and is_active) then raise exception 'Cost code is invalid or inactive'; end if;
  if v_side not in ('debit','credit') or v_amount<=0 then raise exception 'Allocation side and positive amount are required'; end if;
  insert into public.journal_line_cost_allocations(company_id,journal_line_id,attribution_scope,project_id,cost_code_id,cost_centre_id,allocation_side,amount,description,created_by)
  values(p_company_id,p_journal_line_id,v_scope,v_project_id,v_cost_code_id,v_cost_centre_id,v_side,v_amount,nullif(btrim(v_item->>'description'),''),v_user_id);
 end loop;
 if exists(select 1 from public.journal_line_cost_allocations a where a.company_id=p_company_id and a.journal_line_id=p_journal_line_id
   group by a.allocation_side having sum(a.amount)>case when a.allocation_side='debit' then v_line.debit else v_line.credit end) then
  raise exception 'Allocated amount cannot exceed the journal line amount';
 end if;
end; $$;

revoke all on function private.replace_journal_line_cost_allocations(uuid,uuid,jsonb) from public,anon;
grant execute on function private.replace_journal_line_cost_allocations(uuid,uuid,jsonb) to authenticated;
create or replace function public.replace_journal_line_cost_allocations(p_company_id uuid,p_journal_line_id uuid,p_allocations jsonb)
returns void language sql security invoker set search_path='' as $$
 select private.replace_journal_line_cost_allocations(p_company_id,p_journal_line_id,p_allocations);
$$;
revoke all on function public.replace_journal_line_cost_allocations(uuid,uuid,jsonb) from public,anon;
grant execute on function public.replace_journal_line_cost_allocations(uuid,uuid,jsonb) to authenticated;

create or replace function private.enforce_expense_cost_attribution()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='posted' and old.status='draft' and exists(
  select 1 from public.journal_lines l join public.chart_of_accounts a on a.company_id=l.company_id and a.id=l.account_id
  left join (select company_id,journal_line_id,sum(amount) allocated from public.journal_line_cost_allocations where allocation_side='debit' group by company_id,journal_line_id) x
   on x.company_id=l.company_id and x.journal_line_id=l.id
  where l.company_id=new.company_id and l.journal_entry_id=new.id and a.account_type='expense' and l.debit>0 and coalesce(x.allocated,0)<>l.debit
 ) then raise exception 'Every expense debit line must be fully allocated to a project or overhead cost centre before posting'; end if;
 return new;
end; $$;
create trigger journal_entries_require_expense_attribution before update of status on public.journal_entries
for each row execute function private.enforce_expense_cost_attribution();

create or replace function private.copy_reversal_cost_allocations()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_original_id uuid;
begin
 select reversal_of_journal_id into v_original_id from public.journal_entries where company_id=new.company_id and id=new.journal_entry_id;
 if v_original_id is not null then
  insert into public.journal_line_cost_allocations(company_id,journal_line_id,attribution_scope,project_id,cost_code_id,cost_centre_id,allocation_side,amount,description,created_by)
  select a.company_id,new.id,a.attribution_scope,a.project_id,a.cost_code_id,a.cost_centre_id,
   case when a.allocation_side='debit' then 'credit' else 'debit' end,a.amount,'Reversal: '||coalesce(a.description,'cost allocation'),a.created_by
  from public.journal_line_cost_allocations a join public.journal_lines ol on ol.company_id=a.company_id and ol.id=a.journal_line_id
  where a.company_id=new.company_id and ol.journal_entry_id=v_original_id and ol.line_number=new.line_number;
 end if; return new;
end; $$;
create trigger journal_lines_copy_reversal_cost_allocations after insert on public.journal_lines
for each row execute function private.copy_reversal_cost_allocations();

create or replace view public.project_cost_ledger with(security_invoker=true) as
select a.company_id,a.project_id,p.project_code,p.name project_name,a.cost_code_id,cc.code cost_code,cc.name cost_code_name,
 j.id journal_entry_id,j.journal_number,j.journal_date,l.id journal_line_id,l.account_id,coa.account_code,coa.account_name,
 a.amount,a.allocation_side,case when a.allocation_side='debit' then a.amount else -a.amount end signed_cost,a.description
from public.journal_line_cost_allocations a join public.projects p on p.company_id=a.company_id and p.id=a.project_id
join public.journal_lines l on l.company_id=a.company_id and l.id=a.journal_line_id
join public.journal_entries j on j.company_id=l.company_id and j.id=l.journal_entry_id
join public.chart_of_accounts coa on coa.company_id=l.company_id and coa.id=l.account_id
left join public.cost_codes cc on cc.company_id=a.company_id and cc.id=a.cost_code_id
where a.attribution_scope='project' and j.status='posted';

create or replace view public.overhead_cost_ledger with(security_invoker=true) as
select a.company_id,a.cost_centre_id,c.code cost_centre_code,c.name cost_centre_name,a.cost_code_id,cc.code cost_code,cc.name cost_code_name,
 j.id journal_entry_id,j.journal_number,j.journal_date,l.id journal_line_id,l.account_id,coa.account_code,coa.account_name,
 a.amount,a.allocation_side,case when a.allocation_side='debit' then a.amount else -a.amount end signed_cost,a.description
from public.journal_line_cost_allocations a join public.cost_centres c on c.company_id=a.company_id and c.id=a.cost_centre_id
join public.journal_lines l on l.company_id=a.company_id and l.id=a.journal_line_id
join public.journal_entries j on j.company_id=l.company_id and j.id=l.journal_entry_id
join public.chart_of_accounts coa on coa.company_id=l.company_id and coa.id=l.account_id
left join public.cost_codes cc on cc.company_id=a.company_id and cc.id=a.cost_code_id
where a.attribution_scope='overhead' and j.status='posted';

revoke all on public.project_cost_ledger,public.overhead_cost_ledger from anon;
grant select on public.project_cost_ledger,public.overhead_cost_ledger to authenticated;
comment on table public.projects is 'Company-scoped construction, design, engineering and real-estate projects.';
comment on table public.project_contracts is 'Commercial project contracts with retention and mobilisation terms.';
comment on table public.journal_line_cost_allocations is 'Project or overhead allocations of journal line amounts; supports split allocation without multiplying general-ledger rows.';
