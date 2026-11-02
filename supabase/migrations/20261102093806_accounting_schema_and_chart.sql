-- Accounting foundation: periods, chart of accounts and journal ledger.
-- All public tables are RLS protected and explicitly granted.

create table public.fiscal_years (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  year_code text not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'draft' check (status in ('draft','open','closed')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date),
  unique (company_id, year_code),
  unique (company_id, id)
);

create table public.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  fiscal_year_id uuid not null,
  period_number smallint not null check (period_number between 1 and 13),
  period_name text not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'draft' check (status in ('draft','open','closed','locked')),
  closed_by uuid references auth.users(id) on delete restrict,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date),
  foreign key (company_id, fiscal_year_id)
    references public.fiscal_years(company_id, id) on delete restrict,
  unique (company_id, fiscal_year_id, period_number),
  unique (company_id, id)
);

create table public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  account_code text not null check (length(btrim(account_code)) between 1 and 30),
  account_name text not null check (length(btrim(account_name)) between 2 and 160),
  account_type text not null check (account_type in ('asset','liability','equity','revenue','expense')),
  account_subtype text not null,
  normal_balance text not null check (normal_balance in ('debit','credit')),
  parent_account_id uuid,
  is_postable boolean not null default true,
  is_control_account boolean not null default false,
  allow_manual_journal boolean not null default true,
  is_system_account boolean not null default false,
  is_active boolean not null default true,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, account_code),
  unique (company_id, id),
  foreign key (company_id, parent_account_id)
    references public.chart_of_accounts(company_id, id) on delete restrict,
  check (parent_account_id is null or parent_account_id <> id)
);

create index chart_of_accounts_company_type_idx
  on public.chart_of_accounts(company_id, account_type, is_active);
create index chart_of_accounts_parent_idx
  on public.chart_of_accounts(company_id, parent_account_id);
create index fiscal_years_company_dates_idx
  on public.fiscal_years(company_id, start_date, end_date);
create index accounting_periods_company_dates_idx
  on public.accounting_periods(company_id, start_date, end_date, status);
create index accounting_periods_fiscal_year_idx
  on public.accounting_periods(company_id, fiscal_year_id, period_number);

-- Validate that a period is inside its financial year and does not overlap
-- another period in that same year. Locking the year serializes concurrent edits.
create or replace function private.validate_accounting_period()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year public.fiscal_years%rowtype;
begin
  select * into v_year
  from public.fiscal_years
  where company_id = new.company_id and id = new.fiscal_year_id
  for update;

  if not found then
    raise exception 'Fiscal year not found for this company';
  end if;

  if new.start_date < v_year.start_date or new.end_date > v_year.end_date then
    raise exception 'Accounting period must fall within its fiscal year';
  end if;

  if exists (
    select 1 from public.accounting_periods p
    where p.company_id = new.company_id
      and p.fiscal_year_id = new.fiscal_year_id
      and p.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and daterange(p.start_date, p.end_date, '[]') && daterange(new.start_date, new.end_date, '[]')
  ) then
    raise exception 'Accounting periods cannot overlap within a fiscal year';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_accounting_period() from public, anon, authenticated;

create trigger accounting_period_validate_dates
before insert or update of company_id, fiscal_year_id, start_date, end_date
on public.accounting_periods
for each row execute function private.validate_accounting_period();

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  branch_id uuid,
  fiscal_period_id uuid not null,
  journal_number text,
  journal_date date not null,
  description text not null check (length(btrim(description)) between 2 and 500),
  reference text,
  source_module text not null default 'manual',
  source_type text,
  source_id uuid,
  currency_code char(3) not null,
  exchange_rate numeric(20,10) not null default 1 check (exchange_rate > 0),
  total_debit numeric(20,4) not null default 0 check (total_debit >= 0),
  total_credit numeric(20,4) not null default 0 check (total_credit >= 0),
  status text not null default 'draft' check (status in ('draft','posted','reversed')),
  idempotency_key text,
  request_hash text,
  reversal_of_journal_id uuid,
  created_by uuid not null references auth.users(id) on delete restrict,
  posted_by uuid references auth.users(id) on delete restrict,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (company_id, branch_id)
    references public.branches(company_id, id) on delete restrict,
  foreign key (company_id, fiscal_period_id)
    references public.accounting_periods(company_id, id) on delete restrict,
  foreign key (company_id, reversal_of_journal_id)
    references public.journal_entries(company_id, id) on delete restrict,
  unique (company_id, id),
  unique (company_id, journal_number),
  unique (company_id, reversal_of_journal_id),
  check (reversal_of_journal_id is null or reversal_of_journal_id <> id),
  check (
    (status = 'draft' and posted_at is null and posted_by is null)
    or (status in ('posted','reversed') and posted_at is not null and posted_by is not null)
  )
);

create unique index journal_entries_idempotency_idx
  on public.journal_entries(company_id, idempotency_key)
  where idempotency_key is not null;
create index journal_entries_company_date_idx
  on public.journal_entries(company_id, journal_date desc);
create index journal_entries_company_period_status_idx
  on public.journal_entries(company_id, fiscal_period_id, status);
create index journal_entries_source_idx
  on public.journal_entries(company_id, source_module, source_type, source_id)
  where source_id is not null;
create index journal_entries_reversal_idx
  on public.journal_entries(company_id, reversal_of_journal_id)
  where reversal_of_journal_id is not null;

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  journal_entry_id uuid not null,
  account_id uuid not null,
  line_number integer not null check (line_number > 0),
  description text,
  debit numeric(20,4) not null default 0 check (debit >= 0),
  credit numeric(20,4) not null default 0 check (credit >= 0),
  created_at timestamptz not null default now(),
  foreign key (company_id, journal_entry_id)
    references public.journal_entries(company_id, id) on delete restrict,
  foreign key (company_id, account_id)
    references public.chart_of_accounts(company_id, id) on delete restrict,
  unique (company_id, journal_entry_id, line_number),
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create index journal_lines_company_account_idx
  on public.journal_lines(company_id, account_id);
create index journal_lines_entry_idx
  on public.journal_lines(company_id, journal_entry_id, line_number);

-- Private sequence table: no Data API exposure.
create table private.journal_number_counters (
  company_id uuid not null,
  fiscal_year_id uuid not null,
  next_number bigint not null check (next_number > 0),
  primary key (company_id, fiscal_year_id),
  foreign key (company_id, fiscal_year_id)
    references public.fiscal_years(company_id, id) on delete restrict
);
revoke all on private.journal_number_counters from public, anon, authenticated;

-- Fine-grained permission evaluation; owner/admin are company-wide administrators.
create or replace function private.has_company_permission(
  p_company_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.roles r on r.id = m.role_id
    where m.company_id = p_company_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and (
        r.code in ('owner','admin')
        or exists (
          select 1
          from public.role_permissions rp
          join public.permissions p on p.id = rp.permission_id
          where rp.role_id = r.id and p.code = p_permission_code
        )
      )
  );
$$;

revoke all on function private.has_company_permission(uuid,text) from public, anon;
grant execute on function private.has_company_permission(uuid,text) to authenticated;

-- Seed the permission catalogue and default role mappings.
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r cross join public.permissions p
where r.code = 'owner'
on conflict do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r cross join public.permissions p
where r.code = 'admin' and p.code <> 'company.manage'
on conflict do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('accounting.read','accounting.manage','accounting.post')
where r.code = 'accountant'
on conflict do nothing;

-- A starter chart is created for every new company. Customers can later edit
-- descriptions and add accounts; system accounts cannot be deleted casually.
create or replace function private.seed_default_chart_of_accounts(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.chart_of_accounts
    (company_id, account_code, account_name, account_type, account_subtype,
     normal_balance, is_postable, is_control_account, allow_manual_journal,
     is_system_account, description)
  values
    (p_company_id,'1000','Assets','asset','assets','debit',false,false,false,true,'Asset accounts'),
    (p_company_id,'2000','Liabilities','liability','liabilities','credit',false,false,false,true,'Liability accounts'),
    (p_company_id,'3000','Equity','equity','equity','credit',false,false,false,true,'Equity accounts'),
    (p_company_id,'4000','Revenue','revenue','revenue','credit',false,false,false,true,'Revenue accounts'),
    (p_company_id,'5000','Direct Costs','expense','direct_costs','debit',false,false,false,true,'Direct project and contract costs'),
    (p_company_id,'6000','Operating Expenses','expense','operating_expenses','debit',false,false,false,true,'Operating and administrative expenses'),
    (p_company_id,'7000','Other Income','revenue','other_income','credit',false,false,false,true,'Non-core income'),
    (p_company_id,'8000','Finance Costs','expense','finance_costs','debit',false,false,false,true,'Finance and borrowing costs');

  insert into public.chart_of_accounts
    (company_id, account_code, account_name, account_type, account_subtype,
     normal_balance, parent_account_id, is_postable, is_control_account,
     allow_manual_journal, is_system_account, description)
  select p_company_id, x.account_code, x.account_name, x.account_type,
         x.account_subtype, x.normal_balance, parent.id, x.is_postable,
         x.is_control_account, x.allow_manual_journal, true, x.description
  from (values
    ('1100','Current Assets','asset','current_asset','debit','1000',false,false,false,'Current asset grouping'),
    ('1110','Cash on Hand','asset','cash','debit','1100',true,false,true,'Cash held by the company'),
    ('1120','Bank Accounts','asset','bank','debit','1100',true,false,true,'Company bank balances'),
    ('1130','Mobile Money','asset','mobile_money','debit','1100',true,false,true,'Company mobile money balances'),
    ('1140','Trade Receivables','asset','trade_receivables','debit','1100',true,true,false,'Customer balances due'),
    ('1150','Contract Assets','asset','contract_assets','debit','1100',true,true,false,'Unconditional right to consideration not yet billed'),
    ('1160','Retention Receivable','asset','retention_receivable','debit','1100',true,true,false,'Contract retention receivable'),
    ('1200','Inventory','asset','inventory','debit','1000',false,false,false,'Inventory grouping'),
    ('1210','Construction Materials','asset','inventory_materials','debit','1200',true,true,false,'Construction materials held in stores'),
    ('1300','Work in Progress','asset','work_in_progress','debit','1000',true,true,false,'Eligible unrecognised contract costs'),
    ('1500','Property Plant and Equipment','asset','fixed_assets','debit','1000',true,false,true,'Property plant and equipment at cost'),
    ('1590','Accumulated Depreciation','asset','accumulated_depreciation','credit','1000',true,false,true,'Accumulated depreciation contra-asset'),
    ('2100','Current Liabilities','liability','current_liability','credit','2000',false,false,false,'Current liability grouping'),
    ('2110','Trade Payables','liability','trade_payables','credit','2100',true,true,false,'Supplier balances due'),
    ('2120','Accrued Expenses','liability','accruals','credit','2100',true,false,true,'Accrued expenses'),
    ('2130','VAT Payable','liability','vat_payable','credit','2100',true,true,false,'Output VAT payable'),
    ('2140','PAYE Payable','liability','paye_payable','credit','2100',true,true,false,'PAYE deductions payable'),
    ('2150','SSNIT and Pension Payable','liability','pension_payable','credit','2100',true,true,false,'Statutory pension deductions payable'),
    ('2160','Contract Liabilities and Customer Advances','liability','contract_liabilities','credit','2100',true,true,false,'Advance consideration and amounts billed ahead of performance'),
    ('2170','Retention Payable','liability','retention_payable','credit','2100',true,true,false,'Retention held from subcontractors'),
    ('2200','Long-term Liabilities','liability','long_term_liability','credit','2000',false,false,false,'Long-term liability grouping'),
    ('2210','Loans and Borrowings','liability','borrowings','credit','2200',true,false,true,'Borrowings and loans'),
    ('3100','Share Capital','equity','share_capital','credit','3000',true,false,true,'Issued share capital'),
    ('3200','Retained Earnings','equity','retained_earnings','credit','3000',true,false,false,'Accumulated retained earnings'),
    ('3300','Current Year Earnings','equity','current_year_earnings','credit','3000',true,false,false,'Current year result clearing account'),
    ('4100','Construction Contract Revenue','revenue','construction_revenue','credit','4000',true,false,true,'Recognised construction contract revenue'),
    ('4110','Architectural and Engineering Revenue','revenue','design_revenue','credit','4000',true,false,true,'Architectural and engineering design services'),
    ('4120','Real Estate Sales Revenue','revenue','real_estate_revenue','credit','4000',true,false,true,'Revenue from real estate unit sales'),
    ('4130','Other Operating Revenue','revenue','other_operating_revenue','credit','4000',true,false,true,'Other operating revenue'),
    ('5100','Construction Materials Consumed','expense','materials_cost','debit','5000',true,false,true,'Materials charged to projects'),
    ('5200','Direct Labour','expense','direct_labour','debit','5000',true,false,true,'Direct project labour'),
    ('5300','Subcontractor Costs','expense','subcontractor_cost','debit','5000',true,false,true,'Subcontractor and specialist works'),
    ('5400','Plant and Equipment Hire','expense','equipment_hire','debit','5000',true,false,true,'Plant and equipment hire for projects'),
    ('5500','Site Expenses','expense','site_expenses','debit','5000',true,false,true,'Site running costs'),
    ('5600','Project Professional Fees','expense','project_professional_fees','debit','5000',true,false,true,'Project-related technical and professional costs'),
    ('6100','Administrative Salaries','expense','administrative_payroll','debit','6000',true,false,true,'Administrative staff costs'),
    ('6200','Rent and Utilities','expense','occupancy','debit','6000',true,false,true,'Office rent and utilities'),
    ('6300','Repairs and Maintenance','expense','repairs_maintenance','debit','6000',true,false,true,'Repairs and maintenance'),
    ('6400','Professional and Legal Fees','expense','professional_fees','debit','6000',true,false,true,'Legal, audit and advisory fees'),
    ('6500','Transport and Travel','expense','travel','debit','6000',true,false,true,'Transport and travel costs'),
    ('6600','Depreciation Expense','expense','depreciation','debit','6000',true,false,true,'Depreciation charge'),
    ('6700','Insurance Expense','expense','insurance','debit','6000',true,false,true,'Insurance premiums'),
    ('6800','Marketing and Business Development','expense','marketing','debit','6000',true,false,true,'Marketing and business development'),
    ('6900','General Office Expenses','expense','general_admin','debit','6000',true,false,true,'General office and administration'),
    ('7100','Interest and Investment Income','revenue','finance_income','credit','7000',true,false,true,'Interest and investment income'),
    ('8100','Interest Expense','expense','interest_expense','debit','8000',true,false,true,'Interest and finance charges'),
    ('8200','Bank and Payment Charges','expense','bank_charges','debit','8000',true,false,true,'Bank and payment service charges')
  ) as x(account_code,account_name,account_type,account_subtype,normal_balance,parent_code,is_postable,is_control_account,allow_manual_journal,description)
  join public.chart_of_accounts parent
    on parent.company_id = p_company_id and parent.account_code = x.parent_code
  on conflict (company_id, account_code) do nothing;
end;
$$;

revoke all on function private.seed_default_chart_of_accounts(uuid) from public, anon, authenticated;

-- Extend onboarding so every new company receives a usable starter chart.
create or replace function private.create_company_for_current_user(
  p_legal_name text,
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_owner_role_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  if p_legal_name is null or length(btrim(p_legal_name)) < 2
     or p_display_name is null or length(btrim(p_display_name)) < 2 then
    raise exception 'A valid legal name and display name are required' using errcode = '22023';
  end if;

  select id into v_owner_role_id from public.roles where code = 'owner';
  if v_owner_role_id is null then
    raise exception 'Owner role is not configured';
  end if;

  insert into public.companies (legal_name, display_name, created_by)
  values (btrim(p_legal_name), btrim(p_display_name), v_user_id)
  returning id into v_company_id;

  insert into public.company_memberships (company_id, user_id, role_id, status, joined_at)
  values (v_company_id, v_user_id, v_owner_role_id, 'active', now());

  insert into public.user_profiles (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;

  perform private.seed_default_chart_of_accounts(v_company_id);
  return v_company_id;
end;
$$;

-- All accounting tables are protected by company permission checks.
alter table public.fiscal_years enable row level security;
alter table public.accounting_periods enable row level security;
alter table public.chart_of_accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;

create policy fiscal_years_read
  on public.fiscal_years for select to authenticated
  using ((select private.has_company_permission(company_id,'accounting.read')));
create policy fiscal_years_insert
  on public.fiscal_years for insert to authenticated
  with check ((select private.has_company_permission(company_id,'accounting.manage')));
create policy fiscal_years_update
  on public.fiscal_years for update to authenticated
  using ((select private.has_company_permission(company_id,'accounting.manage')))
  with check ((select private.has_company_permission(company_id,'accounting.manage')));

create policy accounting_periods_read
  on public.accounting_periods for select to authenticated
  using ((select private.has_company_permission(company_id,'accounting.read')));
create policy accounting_periods_insert
  on public.accounting_periods for insert to authenticated
  with check ((select private.has_company_permission(company_id,'accounting.manage')));
create policy accounting_periods_update
  on public.accounting_periods for update to authenticated
  using ((select private.has_company_permission(company_id,'accounting.manage')))
  with check ((select private.has_company_permission(company_id,'accounting.manage')));

create policy chart_of_accounts_read
  on public.chart_of_accounts for select to authenticated
  using ((select private.has_company_permission(company_id,'accounting.read')));
create policy chart_of_accounts_insert
  on public.chart_of_accounts for insert to authenticated
  with check ((select private.has_company_permission(company_id,'accounting.manage')));
create policy chart_of_accounts_update
  on public.chart_of_accounts for update to authenticated
  using ((select private.has_company_permission(company_id,'accounting.manage')))
  with check ((select private.has_company_permission(company_id,'accounting.manage')));

create policy journal_entries_read
  on public.journal_entries for select to authenticated
  using ((select private.has_company_permission(company_id,'accounting.read')));
create policy journal_lines_read
  on public.journal_lines for select to authenticated
  using ((select private.has_company_permission(company_id,'accounting.read')));

-- Explicit API exposure grants; write access to journals is RPC-only.
revoke all on public.fiscal_years, public.accounting_periods, public.chart_of_accounts,
  public.journal_entries, public.journal_lines from anon;
grant select, insert, update on public.fiscal_years, public.accounting_periods to authenticated;
grant select, insert, update on public.chart_of_accounts to authenticated;
grant select on public.journal_entries, public.journal_lines to authenticated;

comment on table public.fiscal_years is 'Company-specific financial year definitions; no calendar-year assumption.';
comment on table public.accounting_periods is 'Non-overlapping accounting periods bounded by their fiscal year.';
comment on table public.chart_of_accounts is 'Company chart of accounts with account hierarchy and posting controls.';
comment on table public.journal_entries is 'Journal headers; all posting is performed through controlled database functions.';
comment on table public.journal_lines is 'Balanced double-entry journal lines in the company functional currency.';
