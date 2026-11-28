-- Phase 8.1: customer invoice draft foundation.
-- Invoices remain non-posting until the dedicated issue/GL integration step.
create table public.sales_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  invoice_number text not null check (length(btrim(invoice_number)) between 1 and 40),
  customer_party_id uuid not null,
  project_id uuid,
  project_contract_id uuid,
  estimate_id uuid,
  title text not null check (length(btrim(title)) between 2 and 200),
  invoice_date date not null default current_date,
  due_date date,
  currency_code char(3) not null default 'GHS',
  discount_amount numeric not null default 0 check (discount_amount >= 0 and discount_amount = round(discount_amount,4)),
  tax_amount numeric not null default 0 check (tax_amount >= 0 and tax_amount = round(tax_amount,4)),
  status text not null default 'draft' check (status in ('draft','issued','cancelled')),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id,id),
  unique (company_id,invoice_number),
  foreign key (company_id,customer_party_id)
    references public.business_parties(company_id,id) on delete restrict,
  check (due_date is null or due_date >= invoice_date),
  check (discount_amount <= 9999999999999999.9999),
  check (tax_amount <= 9999999999999999.9999)
);

create table public.sales_invoice_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  invoice_id uuid not null,
  line_number integer not null check (line_number > 0),
  description text not null check (length(btrim(description)) between 1 and 500),
  unit text not null default 'item' check (length(btrim(unit)) between 1 and 30),
  quantity numeric not null check (quantity > 0 and quantity = round(quantity,4)),
  unit_rate numeric not null check (unit_rate >= 0 and unit_rate = round(unit_rate,4)),
  line_total numeric generated always as (round(quantity * unit_rate,4)) stored,
  created_at timestamptz not null default now(),
  unique (company_id,id),
  unique (company_id,invoice_id,line_number),
  foreign key (company_id,invoice_id)
    references public.sales_invoices(company_id,id) on delete restrict
);

create table public.sales_invoice_status_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  invoice_id uuid not null,
  from_status text,
  to_status text not null check (to_status in ('draft','issued','cancelled')),
  note text,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  foreign key (company_id,invoice_id)
    references public.sales_invoices(company_id,id) on delete restrict
);

-- Reuse the transaction-safe, company-scoped document numbering service.
insert into private.company_reference_sequences(company_id,sequence_key,next_value)
select company_id,'sales_invoices',
       coalesce(max((regexp_match(invoice_number,'^INV-([0-9]+)$'))[1]::bigint),0)+1
from public.sales_invoices
group by company_id
on conflict (company_id,sequence_key)
do update set next_value = greatest(
  private.company_reference_sequences.next_value, excluded.next_value
);

create trigger sales_invoices_assign_reference
before insert on public.sales_invoices
for each row execute function private.assign_company_reference('invoice_number','INV');

create or replace function private.validate_sales_invoice_links()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.business_parties p
    where p.company_id = new.company_id
      and p.id = new.customer_party_id
      and p.is_customer and p.status = 'active'
  ) then
    raise exception 'Invoice customer must be an active customer in this company'
      using errcode = '23514';
  end if;

  if new.project_id is not null and not exists (
    select 1 from public.projects p
    where p.company_id = new.company_id and p.id = new.project_id
      and (p.customer_party_id is null or p.customer_party_id = new.customer_party_id)
  ) then
    raise exception 'Invoice project must belong to this company and customer'
      using errcode = '23514';
  end if;

  if new.project_contract_id is not null and not exists (
    select 1 from public.project_contracts c
    where c.company_id = new.company_id and c.id = new.project_contract_id
      and c.project_id = new.project_id
      and (c.customer_party_id is null or c.customer_party_id = new.customer_party_id)
  ) then
    raise exception 'Invoice contract must belong to the selected project and customer'
      using errcode = '23514';
  end if;

  if new.estimate_id is not null and not exists (
    select 1 from public.estimates e
    where e.company_id = new.company_id and e.id = new.estimate_id
      and e.customer_party_id = new.customer_party_id
      and e.status = 'approved'
      and (new.project_id is null or e.project_id = new.project_id)
      and (new.project_contract_id is null or e.project_contract_id = new.project_contract_id)
  ) then
    raise exception 'Linked estimate must be approved and match the invoice customer, project and contract'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_sales_invoice_links() from public,anon,authenticated;
create trigger sales_invoices_validate_links
before insert or update of company_id,customer_party_id,project_id,project_contract_id,estimate_id
on public.sales_invoices
for each row execute function private.validate_sales_invoice_links();

create or replace function private.record_sales_invoice_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.sales_invoice_status_history(
    company_id,invoice_id,from_status,to_status,changed_by
  ) values (
    new.company_id,new.id,null,new.status,auth.uid()
  );
  return new;
end;
$$;
revoke all on function private.record_sales_invoice_status() from public,anon,authenticated;
create trigger sales_invoices_record_initial_status
after insert on public.sales_invoices
for each row execute function private.record_sales_invoice_status();

create or replace function private.guard_sales_invoice_item_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company_id uuid;
  v_invoice_id uuid;
begin
  v_company_id := case when tg_op = 'DELETE' then old.company_id else new.company_id end;
  v_invoice_id := case when tg_op = 'DELETE' then old.invoice_id else new.invoice_id end;
  if not exists (
    select 1 from public.sales_invoices i
    where i.company_id = v_company_id and i.id = v_invoice_id and i.status = 'draft'
  ) then
    raise exception 'Invoice lines can only be changed while the invoice is a draft'
      using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.guard_sales_invoice_item_write() from public,anon,authenticated;
create trigger sales_invoice_items_draft_only
before insert or update or delete on public.sales_invoice_items
for each row execute function private.guard_sales_invoice_item_write();

create view public.sales_invoice_totals
with (security_invoker = true)
as
select
  i.company_id,i.id as invoice_id,i.invoice_number,i.customer_party_id,
  i.project_id,i.project_contract_id,i.estimate_id,i.title,i.invoice_date,
  i.due_date,i.currency_code,i.status,
  coalesce(sum(li.line_total),0)::numeric(20,4) as subtotal,
  i.discount_amount,i.tax_amount,
  (coalesce(sum(li.line_total),0)-i.discount_amount+i.tax_amount)::numeric(20,4) as total_amount
from public.sales_invoices i
left join public.sales_invoice_items li
  on li.company_id=i.company_id and li.invoice_id=i.id
group by i.company_id,i.id;

alter table public.sales_invoices enable row level security;
alter table public.sales_invoice_items enable row level security;
alter table public.sales_invoice_status_history enable row level security;

insert into public.permissions(code,module,description) values
 ('sales_invoices.read','sales_invoices','View customer invoices and invoice history'),
 ('sales_invoices.manage','sales_invoices','Create and maintain draft customer invoices')
on conflict (code) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on
  (p.code='sales_invoices.read' and r.code in ('owner','admin','accountant','project_manager','procurement_officer','site_supervisor','viewer'))
  or
  (p.code='sales_invoices.manage' and r.code in ('owner','admin','accountant'))
on conflict do nothing;

create policy sales_invoices_read on public.sales_invoices
for select to authenticated
using ((select private.has_company_permission(company_id,'sales_invoices.read')));
create policy sales_invoices_insert_draft on public.sales_invoices
for insert to authenticated
with check (
  status='draft'
  and created_by=auth.uid()
  and (select private.has_company_permission(company_id,'sales_invoices.manage'))
);
create policy sales_invoices_update_draft on public.sales_invoices
for update to authenticated
using (
  status='draft'
  and (select private.has_company_permission(company_id,'sales_invoices.manage'))
)
with check (
  status='draft'
  and (select private.has_company_permission(company_id,'sales_invoices.manage'))
);

create policy sales_invoice_items_read on public.sales_invoice_items
for select to authenticated
using ((select private.has_company_permission(company_id,'sales_invoices.read')));
create policy sales_invoice_items_insert_draft on public.sales_invoice_items
for insert to authenticated
with check (
  (select private.has_company_permission(company_id,'sales_invoices.manage'))
  and exists (
    select 1 from public.sales_invoices i
    where i.company_id=sales_invoice_items.company_id
      and i.id=sales_invoice_items.invoice_id and i.status='draft'
  )
);
create policy sales_invoice_items_update_draft on public.sales_invoice_items
for update to authenticated
using (
  (select private.has_company_permission(company_id,'sales_invoices.manage'))
  and exists (
    select 1 from public.sales_invoices i
    where i.company_id=sales_invoice_items.company_id
      and i.id=sales_invoice_items.invoice_id and i.status='draft'
  )
)
with check (
  (select private.has_company_permission(company_id,'sales_invoices.manage'))
  and exists (
    select 1 from public.sales_invoices i
    where i.company_id=sales_invoice_items.company_id
      and i.id=sales_invoice_items.invoice_id and i.status='draft'
  )
);
create policy sales_invoice_items_delete_draft on public.sales_invoice_items
for delete to authenticated
using (
  (select private.has_company_permission(company_id,'sales_invoices.manage'))
  and exists (
    select 1 from public.sales_invoices i
    where i.company_id=sales_invoice_items.company_id
      and i.id=sales_invoice_items.invoice_id and i.status='draft'
  )
);

create policy sales_invoice_history_read on public.sales_invoice_status_history
for select to authenticated
using ((select private.has_company_permission(company_id,'sales_invoices.read')));

revoke all on public.sales_invoices,public.sales_invoice_items,
  public.sales_invoice_status_history,public.sales_invoice_totals from anon,authenticated;
grant select on public.sales_invoices,public.sales_invoice_items,
  public.sales_invoice_status_history,public.sales_invoice_totals to authenticated;
grant insert (
  company_id,customer_party_id,project_id,project_contract_id,estimate_id,
  title,invoice_date,due_date,currency_code,discount_amount,tax_amount,notes
) on public.sales_invoices to authenticated;
grant update (
  customer_party_id,project_id,project_contract_id,estimate_id,title,
  invoice_date,due_date,currency_code,discount_amount,tax_amount,notes
) on public.sales_invoices to authenticated;
grant insert (
  company_id,invoice_id,line_number,description,unit,quantity,unit_rate
) on public.sales_invoice_items to authenticated;
grant update (
  line_number,description,unit,quantity,unit_rate
) on public.sales_invoice_items to authenticated;
grant delete on public.sales_invoice_items to authenticated;

revoke all on public.sales_invoices,public.sales_invoice_items,
  public.sales_invoice_status_history,public.sales_invoice_totals from anon;

comment on table public.sales_invoices is
  'Customer invoice drafts and future controlled issue lifecycle; invoice creation does not post revenue or receivables.';
comment on table public.sales_invoice_items is
  'Customer invoice lines with database-generated four-decimal line totals.';
