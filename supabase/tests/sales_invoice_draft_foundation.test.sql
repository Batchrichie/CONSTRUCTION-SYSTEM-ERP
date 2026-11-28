begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(16);

insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values ('91000000-0000-4000-8000-000000000001','authenticated','authenticated','phase81-accountant@example.test','',now(),'{}','{}');
insert into public.companies(id,legal_name,display_name,base_currency,country_code,created_by)
values ('92000000-0000-4000-8000-000000000001','Phase 8.1 Test Ltd','Phase 8.1 Test','GHS','GH','91000000-0000-4000-8000-000000000001');
insert into public.company_memberships(company_id,user_id,role_id,status,joined_at)
select '92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001',id,'active',now()
from public.roles where code='accountant';
insert into public.business_parties(id,company_id,party_code,legal_name,is_customer,created_by)
values ('93000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','T81-CUST','Phase 8.1 Customer',true,'91000000-0000-4000-8000-000000000001');
insert into public.business_parties(id,company_id,party_code,legal_name,is_supplier,created_by)
values ('93000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000001','T81-SUP','Phase 8.1 Supplier',true,'91000000-0000-4000-8000-000000000001');

select ok(to_regclass('public.sales_invoices') is not null,'customer invoice header table exists');
select ok(to_regclass('public.sales_invoice_items') is not null,'customer invoice line table exists');
select ok(to_regclass('public.sales_invoice_status_history') is not null,'invoice status history table exists');
select ok((select reloptions @> array['security_invoker=true'] from pg_class where oid='public.sales_invoice_totals'::regclass),'invoice totals view uses invoker security');
select ok((select relrowsecurity from pg_class where oid='public.sales_invoices'::regclass),'invoice headers have row-level security enabled');
select ok((select relrowsecurity from pg_class where oid='public.sales_invoice_items'::regclass),'invoice lines have row-level security enabled');
select ok((select relrowsecurity from pg_class where oid='public.sales_invoice_status_history'::regclass),'invoice history has row-level security enabled');

insert into public.sales_invoices(company_id,customer_party_id,title,invoice_date,due_date,created_by)
values ('92000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001','Test invoice',date '2026-11-28',date '2026-12-28','91000000-0000-4000-8000-000000000001');
select is((select invoice_number from public.sales_invoices where title='Test invoice'),'INV-0001','invoice numbers are generated per company');
insert into public.sales_invoice_items(company_id,invoice_id,line_number,description,unit,quantity,unit_rate)
select company_id,id,1,'Measured construction work','m2',2.5,125.3333
from public.sales_invoices where title='Test invoice';
select is((select line_total from public.sales_invoice_items li join public.sales_invoices i on i.id=li.invoice_id where i.title='Test invoice'),313.3333::numeric,'line total is calculated at four decimal places');
select is((select subtotal from public.sales_invoice_totals where invoice_id=(select id from public.sales_invoices where title='Test invoice')),313.3333::numeric,'invoice subtotal is calculated from stored line totals');
select is((select total_amount from public.sales_invoice_totals where invoice_id=(select id from public.sales_invoices where title='Test invoice')),313.3333::numeric,'invoice total is subtotal less discount plus tax');
select is((select count(*)::integer from public.sales_invoice_status_history where invoice_id=(select id from public.sales_invoices where title='Test invoice')),1,'invoice creation records its initial draft status');
select is((select to_status from public.sales_invoice_status_history where invoice_id=(select id from public.sales_invoices where title='Test invoice')),'draft','initial status history records draft');

select throws_ok(
 $$ insert into public.sales_invoices(company_id,customer_party_id,title,created_by)
    values ('92000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000002','Supplier cannot be billed','91000000-0000-4000-8000-000000000001') $$,
 '23514','Invoice customer must be an active customer in this company',
 'supplier-only parties cannot be used as invoice customers'
);
select throws_ok(
 $$ insert into public.sales_invoice_items(company_id,invoice_id,line_number,description,quantity,unit_rate)
    values ('92000000-0000-4000-8000-000000000001',(select id from public.sales_invoices where title='Test invoice'),2,'Excess precision',1.00001,1) $$,
 '23514',null,'invoice quantities reject more than four decimal places'
);
select throws_ok(
 $$ insert into public.sales_invoices(company_id,customer_party_id,title,invoice_date,due_date,created_by)
    values ('92000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001','Invalid dates',date '2026-12-01',date '2026-11-30','91000000-0000-4000-8000-000000000001') $$,
 '23514',null,'invoice due date cannot precede invoice date'
);

select * from extensions.finish();
rollback;
