
-- Phase 5: business partners, customer links, estimates and BOQ.
-- Commercial documents remain non-posting; accounting is only affected by later
-- controlled sales/purchase workflows.

create table public.business_parties (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  party_code text not null check (length(btrim(party_code)) between 1 and 40),
  legal_name text not null check (length(btrim(legal_name)) between 2 and 200),
  trading_name text,
  is_customer boolean not null default false,
  is_supplier boolean not null default false,
  tax_identifier text,
  registration_number text,
  email text,
  phone text,
  website text,
  address_line_1 text,
  address_line_2 text,
  city text,
  region text,
  postal_code text,
  country_code char(2) not null default 'GH' check (country_code ~ '^[A-Z]{2}$'),
  credit_terms_days integer not null default 0 check (credit_terms_days between 0 and 365),
  payment_terms_days integer not null default 0 check (payment_terms_days between 0 and 365),
  status text not null default 'active' check (status in ('active','inactive')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, id),
  unique (company_id, party_code),
  check (is_customer or is_supplier)
);

create table public.party_contacts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  party_id uuid not null,
  contact_name text not null check (length(btrim(contact_name)) between 2 and 160),
  job_title text,
  email text,
  phone text,
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (company_id, id),
  foreign key (company_id, party_id)
    references public.business_parties(company_id, id) on delete restrict
);

create unique index party_contacts_one_primary_per_party
  on public.party_contacts(company_id, party_id) where is_primary and is_active;

alter table public.projects add column customer_party_id uuid;
alter table public.projects
  add constraint projects_customer_party_fk
  foreign key (company_id, customer_party_id)
  references public.business_parties(company_id, id) on delete restrict;

alter table public.project_contracts add column customer_party_id uuid;
alter table public.project_contracts
  add constraint project_contracts_customer_party_fk
  foreign key (company_id, customer_party_id)
  references public.business_parties(company_id, id) on delete restrict;

create table public.estimates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  estimate_number text not null check (length(btrim(estimate_number)) between 1 and 40),
  revision_number integer not null default 1 check (revision_number > 0),
  project_id uuid,
  customer_party_id uuid not null,
  project_contract_id uuid,
  title text not null check (length(btrim(title)) between 2 and 200),
  scope_notes text,
  issue_date date not null default current_date,
  valid_until date,
  currency_code char(3) not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  discount_amount numeric(20,4) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(20,4) not null default 0 check (tax_amount >= 0),
  status text not null default 'draft'
    check (status in ('draft','submitted','approved','rejected','cancelled')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, id),
  unique (company_id, estimate_number, revision_number),
  foreign key (company_id, project_id)
    references public.projects(company_id, id) on delete restrict,
  foreign key (company_id, customer_party_id)
    references public.business_parties(company_id, id) on delete restrict,
  foreign key (company_id, project_contract_id)
    references public.project_contracts(company_id, id) on delete restrict,
  check (valid_until is null or valid_until >= issue_date),
  check ((status = 'approved' and approved_by is not null and approved_at is not null)
      or (status <> 'approved' and approved_by is null and approved_at is null))
);

create table public.estimate_sections (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  estimate_id uuid not null,
  section_number integer not null check (section_number > 0),
  title text not null check (length(btrim(title)) between 1 and 200),
  description text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (company_id, id),
  unique (company_id, estimate_id, id),
  unique (company_id, estimate_id, section_number),
  foreign key (company_id, estimate_id)
    references public.estimates(company_id, id) on delete restrict
);

create table public.estimate_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  estimate_id uuid not null,
  section_id uuid,
  item_number text not null check (length(btrim(item_number)) between 1 and 40),
  item_type text not null default 'work'
    check (item_type in ('work','material','labour','equipment','subcontract','provisional_sum','prime_cost','other')),
  description text not null check (length(btrim(description)) between 1 and 1000),
  unit text not null check (length(btrim(unit)) between 1 and 24),
  quantity numeric(20,4) not null check (quantity > 0),
  unit_rate numeric(20,4) not null default 0 check (unit_rate >= 0),
  line_total numeric(20,4) generated always as (round(quantity * unit_rate, 4)) stored,
  cost_code_id uuid,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (company_id, id),
  unique (company_id, estimate_id, item_number),
  foreign key (company_id, estimate_id)
    references public.estimates(company_id, id) on delete restrict,
  foreign key (company_id, estimate_id, section_id)
    references public.estimate_sections(company_id, estimate_id, id) on delete restrict,
  foreign key (company_id, cost_code_id)
    references public.cost_codes(company_id, id) on delete restrict
);

create table public.estimate_status_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  estimate_id uuid not null,
  from_status text,
  to_status text not null check (to_status in ('draft','submitted','approved','rejected','cancelled')),
  note text,
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  foreign key (company_id, estimate_id)
    references public.estimates(company_id, id) on delete restrict
);

create index business_parties_company_status_idx
  on public.business_parties(company_id, status, legal_name);
create index party_contacts_company_party_idx
  on public.party_contacts(company_id, party_id);
create index projects_customer_party_idx
  on public.projects(company_id, customer_party_id) where customer_party_id is not null;
create index project_contracts_customer_party_idx
  on public.project_contracts(company_id, customer_party_id) where customer_party_id is not null;
create index estimates_company_customer_idx
  on public.estimates(company_id, customer_party_id, issue_date desc);
create index estimates_company_project_idx
  on public.estimates(company_id, project_id) where project_id is not null;
create index estimates_company_contract_idx
  on public.estimates(company_id, project_contract_id) where project_contract_id is not null;
create index estimates_company_status_idx
  on public.estimates(company_id, status, issue_date desc);
create index estimate_sections_company_estimate_idx
  on public.estimate_sections(company_id, estimate_id, sort_order);
create index estimate_items_company_estimate_idx
  on public.estimate_items(company_id, estimate_id, sort_order);
create index estimate_items_company_section_idx
  on public.estimate_items(company_id, section_id) where section_id is not null;
create index estimate_items_company_cost_code_idx
  on public.estimate_items(company_id, cost_code_id) where cost_code_id is not null;
create index estimate_status_history_company_estimate_idx
  on public.estimate_status_history(company_id, estimate_id, changed_at desc);

insert into public.permissions(code, module, description) values
  ('parties.read','commercial','Read customer and supplier records'),
  ('parties.manage','commercial','Create and maintain customer and supplier records'),
  ('estimating.read','estimating','Read estimates and bills of quantities'),
  ('estimating.manage','estimating','Create and maintain draft estimates and bills of quantities'),
  ('estimating.approve','estimating','Approve or reject submitted estimates')
on conflict (code) do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('parties.read','estimating.read')
where r.code in ('owner','admin','accountant','project_manager','procurement_officer','site_supervisor','viewer')
on conflict do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('parties.manage')
where r.code in ('owner','admin','accountant','procurement_officer')
on conflict do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('estimating.manage')
where r.code in ('owner','admin','accountant','project_manager')
on conflict do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('estimating.approve')
where r.code in ('owner','admin','project_manager')
on conflict do nothing;

create or replace function private.touch_commercial_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger business_parties_touch_updated_at
before update on public.business_parties
for each row execute function private.touch_commercial_updated_at();

create trigger estimates_touch_updated_at
before update on public.estimates
for each row execute function private.touch_commercial_updated_at();

create or replace function private.validate_customer_party_link()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_customer boolean;
  v_project_customer uuid;
begin
  if new.customer_party_id is null then
    return new;
  end if;

  select bp.is_customer into v_is_customer
  from public.business_parties bp
  where bp.company_id = new.company_id and bp.id = new.customer_party_id;

  if coalesce(v_is_customer, false) is not true then
    raise exception 'The linked business party is not an active customer record'
      using errcode = '23514';
  end if;

  if tg_table_name = 'project_contracts' then
    select p.customer_party_id into v_project_customer
    from public.projects p
    where p.company_id = new.company_id and p.id = new.project_id;

    if v_project_customer is not null and v_project_customer <> new.customer_party_id then
      raise exception 'The contract customer must match the project customer'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger projects_validate_customer_party
before insert or update of customer_party_id on public.projects
for each row execute function private.validate_customer_party_link();

create trigger project_contracts_validate_customer_party
before insert or update of customer_party_id on public.project_contracts
for each row execute function private.validate_customer_party_link();

create or replace function private.validate_estimate_party_links()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_customer boolean;
  v_project_customer uuid;
  v_contract_project uuid;
  v_contract_customer uuid;
begin
  select bp.is_customer into v_is_customer
  from public.business_parties bp
  where bp.company_id = new.company_id and bp.id = new.customer_party_id;

  if coalesce(v_is_customer, false) is not true then
    raise exception 'An estimate must reference a business party marked as a customer'
      using errcode = '23514';
  end if;

  if new.project_id is not null then
    select p.customer_party_id into v_project_customer
    from public.projects p
    where p.company_id = new.company_id and p.id = new.project_id;

    if v_project_customer is not null and v_project_customer <> new.customer_party_id then
      raise exception 'Estimate customer must match the linked project customer'
        using errcode = '23514';
    end if;
  end if;

  if new.project_contract_id is not null then
    select pc.project_id, pc.customer_party_id
      into v_contract_project, v_contract_customer
    from public.project_contracts pc
    where pc.company_id = new.company_id and pc.id = new.project_contract_id;

    if v_contract_project is null then
      raise exception 'The selected contract does not exist for this company'
        using errcode = '23503';
    end if;
    if new.project_id is distinct from v_contract_project then
      raise exception 'The selected contract must belong to the estimate project'
        using errcode = '23514';
    end if;
    if v_contract_customer is not null and v_contract_customer <> new.customer_party_id then
      raise exception 'Estimate customer must match the linked contract customer'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger estimates_validate_party_links
before insert or update of company_id, project_id, customer_party_id, project_contract_id
on public.estimates
for each row execute function private.validate_estimate_party_links();

create or replace function private.transition_estimate(
  p_company_id uuid,
  p_estimate_id uuid,
  p_new_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_status text;
  v_subtotal numeric(20,4);
  v_discount numeric(20,4);
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if not private.has_company_permission(p_company_id, 'estimating.manage') then
    raise exception 'You do not have permission to manage estimates' using errcode = '42501';
  end if;

  select e.status, e.discount_amount
    into v_old_status, v_discount
  from public.estimates e
  where e.company_id = p_company_id and e.id = p_estimate_id
  for update;

  if not found then
    raise exception 'Estimate not found for this company' using errcode = 'P0002';
  end if;

  if p_new_status not in ('draft','submitted','approved','rejected','cancelled') then
    raise exception 'Unsupported estimate status' using errcode = '22023';
  end if;

  if v_old_status = 'draft' and p_new_status = 'submitted' then
    select coalesce(sum(i.line_total), 0) into v_subtotal
    from public.estimate_items i
    where i.company_id = p_company_id and i.estimate_id = p_estimate_id;

    if v_subtotal <= 0 then
      raise exception 'An estimate must contain at least one priced BOQ item before submission'
        using errcode = '23514';
    end if;
    if v_discount > v_subtotal then
      raise exception 'Estimate discount cannot exceed the BOQ subtotal'
        using errcode = '23514';
    end if;
  elsif v_old_status = 'submitted' and p_new_status in ('approved','rejected') then
    if not private.has_company_permission(p_company_id, 'estimating.approve') then
      raise exception 'You do not have permission to approve or reject estimates' using errcode = '42501';
    end if;
    if p_new_status = 'rejected' and nullif(btrim(coalesce(p_note,'')), '') is null then
      raise exception 'A rejection reason is required' using errcode = '22023';
    end if;
  elsif v_old_status in ('draft','rejected') and p_new_status = 'cancelled' then
    null;
  elsif v_old_status = 'rejected' and p_new_status = 'draft' then
    null;
  else
    raise exception 'Invalid estimate status transition: % to %', v_old_status, p_new_status
      using errcode = '22023';
  end if;

  update public.estimates
  set status = p_new_status,
      approved_by = case when p_new_status = 'approved' then auth.uid() else null end,
      approved_at = case when p_new_status = 'approved' then now() else null end
  where company_id = p_company_id and id = p_estimate_id;

  insert into public.estimate_status_history(
    company_id, estimate_id, from_status, to_status, note, changed_by
  ) values (
    p_company_id, p_estimate_id, v_old_status, p_new_status, nullif(btrim(p_note), ''), auth.uid()
  );
end;
$$;

revoke all on function private.transition_estimate(uuid,uuid,text,text) from public, anon;
grant execute on function private.transition_estimate(uuid,uuid,text,text) to authenticated;

create or replace function public.transition_estimate(
  p_company_id uuid,
  p_estimate_id uuid,
  p_new_status text,
  p_note text default null
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.transition_estimate(p_company_id, p_estimate_id, p_new_status, p_note);
$$;

revoke all on function public.transition_estimate(uuid,uuid,text,text) from public, anon;
grant execute on function public.transition_estimate(uuid,uuid,text,text) to authenticated;

create view public.estimate_totals
with (security_invoker = true)
as
select
  e.company_id,
  e.id as estimate_id,
  e.estimate_number,
  e.revision_number,
  e.project_id,
  e.customer_party_id,
  e.project_contract_id,
  e.title,
  e.currency_code,
  e.status,
  coalesce(sum(i.line_total), 0)::numeric(20,4) as subtotal,
  e.discount_amount,
  e.tax_amount,
  (coalesce(sum(i.line_total), 0) - e.discount_amount + e.tax_amount)::numeric(20,4) as total_amount
from public.estimates e
left join public.estimate_items i
  on i.company_id = e.company_id and i.estimate_id = e.id
group by e.company_id, e.id;

alter table public.business_parties enable row level security;
alter table public.party_contacts enable row level security;
alter table public.estimates enable row level security;
alter table public.estimate_sections enable row level security;
alter table public.estimate_items enable row level security;
alter table public.estimate_status_history enable row level security;

create policy business_parties_read on public.business_parties
for select to authenticated
using ((select private.has_company_permission(company_id,'parties.read')));
create policy business_parties_insert on public.business_parties
for insert to authenticated
with check ((select private.has_company_permission(company_id,'parties.manage')));
create policy business_parties_update on public.business_parties
for update to authenticated
using ((select private.has_company_permission(company_id,'parties.manage')))
with check ((select private.has_company_permission(company_id,'parties.manage')));

create policy party_contacts_read on public.party_contacts
for select to authenticated
using ((select private.has_company_permission(company_id,'parties.read')));
create policy party_contacts_insert on public.party_contacts
for insert to authenticated
with check ((select private.has_company_permission(company_id,'parties.manage')));
create policy party_contacts_update on public.party_contacts
for update to authenticated
using ((select private.has_company_permission(company_id,'parties.manage')))
with check ((select private.has_company_permission(company_id,'parties.manage')));
create policy party_contacts_delete on public.party_contacts
for delete to authenticated
using ((select private.has_company_permission(company_id,'parties.manage')));

create policy estimates_read on public.estimates
for select to authenticated
using ((select private.has_company_permission(company_id,'estimating.read')));
create policy estimates_insert on public.estimates
for insert to authenticated
with check (
  status = 'draft'
  and (select private.has_company_permission(company_id,'estimating.manage'))
);
create policy estimates_update_draft on public.estimates
for update to authenticated
using (
  status = 'draft'
  and (select private.has_company_permission(company_id,'estimating.manage'))
)
with check (
  status = 'draft'
  and (select private.has_company_permission(company_id,'estimating.manage'))
);

create policy estimate_sections_read on public.estimate_sections
for select to authenticated
using ((select private.has_company_permission(company_id,'estimating.read')));
create policy estimate_sections_insert_draft on public.estimate_sections
for insert to authenticated
with check (
  (select private.has_company_permission(company_id,'estimating.manage'))
  and exists (
    select 1 from public.estimates e
    where e.company_id = estimate_sections.company_id
      and e.id = estimate_sections.estimate_id and e.status = 'draft'
  )
);
create policy estimate_sections_update_draft on public.estimate_sections
for update to authenticated
using (
  (select private.has_company_permission(company_id,'estimating.manage'))
  and exists (
    select 1 from public.estimates e
    where e.company_id = estimate_sections.company_id
      and e.id = estimate_sections.estimate_id and e.status = 'draft'
  )
)
with check (
  (select private.has_company_permission(company_id,'estimating.manage'))
  and exists (
    select 1 from public.estimates e
    where e.company_id = estimate_sections.company_id
      and e.id = estimate_sections.estimate_id and e.status = 'draft'
  )
);
create policy estimate_sections_delete_draft on public.estimate_sections
for delete to authenticated
using (
  (select private.has_company_permission(company_id,'estimating.manage'))
  and exists (
    select 1 from public.estimates e
    where e.company_id = estimate_sections.company_id
      and e.id = estimate_sections.estimate_id and e.status = 'draft'
  )
);

create policy estimate_items_read on public.estimate_items
for select to authenticated
using ((select private.has_company_permission(company_id,'estimating.read')));
create policy estimate_items_insert_draft on public.estimate_items
for insert to authenticated
with check (
  (select private.has_company_permission(company_id,'estimating.manage'))
  and exists (
    select 1 from public.estimates e
    where e.company_id = estimate_items.company_id
      and e.id = estimate_items.estimate_id and e.status = 'draft'
  )
);
create policy estimate_items_update_draft on public.estimate_items
for update to authenticated
using (
  (select private.has_company_permission(company_id,'estimating.manage'))
  and exists (
    select 1 from public.estimates e
    where e.company_id = estimate_items.company_id
      and e.id = estimate_items.estimate_id and e.status = 'draft'
  )
)
with check (
  (select private.has_company_permission(company_id,'estimating.manage'))
  and exists (
    select 1 from public.estimates e
    where e.company_id = estimate_items.company_id
      and e.id = estimate_items.estimate_id and e.status = 'draft'
  )
);
create policy estimate_items_delete_draft on public.estimate_items
for delete to authenticated
using (
  (select private.has_company_permission(company_id,'estimating.manage'))
  and exists (
    select 1 from public.estimates e
    where e.company_id = estimate_items.company_id
      and e.id = estimate_items.estimate_id and e.status = 'draft'
  )
);

create policy estimate_status_history_read on public.estimate_status_history
for select to authenticated
using ((select private.has_company_permission(company_id,'estimating.read')));

-- Explicit Data API grants: newly created public tables are not automatically
-- exposed to the Data API on current Supabase projects.
revoke all on public.business_parties, public.party_contacts, public.estimates,
  public.estimate_sections, public.estimate_items, public.estimate_status_history,
  public.estimate_totals from anon, authenticated;

grant select on public.business_parties, public.party_contacts to authenticated;
grant insert (
  company_id, party_code, legal_name, trading_name, is_customer, is_supplier,
  tax_identifier, registration_number, email, phone, website, address_line_1,
  address_line_2, city, region, postal_code, country_code,
  credit_terms_days, payment_terms_days, status
) on public.business_parties to authenticated;
grant update (
  party_code, legal_name, trading_name, is_customer, is_supplier,
  tax_identifier, registration_number, email, phone, website, address_line_1,
  address_line_2, city, region, postal_code, country_code,
  credit_terms_days, payment_terms_days, status
) on public.business_parties to authenticated;

grant insert (company_id, party_id, contact_name, job_title, email, phone, is_primary, is_active)
  on public.party_contacts to authenticated;
grant update (contact_name, job_title, email, phone, is_primary, is_active)
  on public.party_contacts to authenticated;
grant delete on public.party_contacts to authenticated;

grant select on public.estimates, public.estimate_sections, public.estimate_items,
  public.estimate_status_history, public.estimate_totals to authenticated;
grant insert (
  company_id, estimate_number, revision_number, project_id, customer_party_id,
  project_contract_id, title, scope_notes, issue_date, valid_until, currency_code,
  discount_amount, tax_amount
) on public.estimates to authenticated;
grant update (
  estimate_number, revision_number, project_id, customer_party_id, project_contract_id,
  title, scope_notes, issue_date, valid_until, currency_code, discount_amount, tax_amount
) on public.estimates to authenticated;

grant insert (company_id, estimate_id, section_number, title, description, sort_order)
  on public.estimate_sections to authenticated;
grant update (section_number, title, description, sort_order)
  on public.estimate_sections to authenticated;
grant delete on public.estimate_sections to authenticated;

grant insert (
  company_id, estimate_id, section_id, item_number, item_type, description,
  unit, quantity, unit_rate, cost_code_id, sort_order
) on public.estimate_items to authenticated;
grant update (
  section_id, item_number, item_type, description, unit, quantity, unit_rate,
  cost_code_id, sort_order
) on public.estimate_items to authenticated;
grant delete on public.estimate_items to authenticated;

grant update (customer_party_id) on public.projects, public.project_contracts to authenticated;
grant select on public.estimate_totals to authenticated;

revoke all on public.business_parties, public.party_contacts, public.estimates,
  public.estimate_sections, public.estimate_items, public.estimate_status_history,
  public.estimate_totals from anon;


-- Preserve entered precision so PostgreSQL can reject (rather than silently
-- round) values carrying more than four decimal places at the Data API boundary.
alter table public.estimates
  alter column discount_amount type numeric using discount_amount::numeric,
  alter column tax_amount type numeric using tax_amount::numeric;

alter table public.estimates
  add constraint estimates_discount_amount_max_4dp
    check (discount_amount >= 0 and scale(discount_amount) <= 4),
  add constraint estimates_tax_amount_max_4dp
    check (tax_amount >= 0 and scale(tax_amount) <= 4);

alter table public.estimate_items
  alter column quantity type numeric using quantity::numeric,
  alter column unit_rate type numeric using unit_rate::numeric;

alter table public.estimate_items
  add constraint estimate_items_quantity_max_4dp
    check (quantity > 0 and scale(quantity) <= 4),
  add constraint estimate_items_unit_rate_max_4dp
    check (unit_rate >= 0 and scale(unit_rate) <= 4);
