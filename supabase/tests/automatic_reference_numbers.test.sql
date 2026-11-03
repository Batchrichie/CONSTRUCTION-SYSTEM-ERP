begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(7);

insert into auth.users (
  id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data
) values (
  'd2a65e38-87f2-4f44-9b89-a0a88f61a1a1','authenticated','authenticated',
  'reference-number-test@example.test','',now(),'{}'::jsonb,'{}'::jsonb
);

insert into public.companies (id,legal_name,display_name,base_currency,country_code,created_by)
values (
  'd2a65e38-87f2-4f44-9b89-a0a88f61a1a2',
  'Reference Number Test Company','Reference Test','GHS','GH',
  'd2a65e38-87f2-4f44-9b89-a0a88f61a1a1'
);

insert into public.business_parties (
  company_id,legal_name,is_customer,created_by
) values (
  'd2a65e38-87f2-4f44-9b89-a0a88f61a1a2','Reference Test Customer',true,
  'd2a65e38-87f2-4f44-9b89-a0a88f61a1a1'
);

insert into public.projects (company_id,name,created_by)
values
  ('d2a65e38-87f2-4f44-9b89-a0a88f61a1a2','First Reference Project','d2a65e38-87f2-4f44-9b89-a0a88f61a1a1'),
  ('d2a65e38-87f2-4f44-9b89-a0a88f61a1a2','Second Reference Project','d2a65e38-87f2-4f44-9b89-a0a88f61a1a1');

insert into public.cost_codes (company_id,name,category)
values ('d2a65e38-87f2-4f44-9b89-a0a88f61a1a2','Test Materials','materials');

insert into public.cost_centres (company_id,name,centre_type)
values ('d2a65e38-87f2-4f44-9b89-a0a88f61a1a2','Head Office','overhead');

insert into public.estimates (
  company_id,customer_party_id,title
) values (
  'd2a65e38-87f2-4f44-9b89-a0a88f61a1a2',
  (select id from public.business_parties where legal_name='Reference Test Customer'),
  'Reference Number Estimate'
);

select extensions.is(
  (select project_code from public.projects where name='First Reference Project'),
  'PRJ-0001',
  'Project codes are generated automatically'
);
select extensions.is(
  (select project_code from public.projects where name='Second Reference Project'),
  'PRJ-0002',
  'Project references increment without form input'
);
select extensions.is(
  (select code from public.cost_codes where name='Test Materials'),
  'CST-0001',
  'Cost codes are generated automatically'
);
select extensions.is(
  (select code from public.cost_centres where name='Head Office'),
  'CTR-0001',
  'Cost centre codes are generated automatically'
);
select extensions.is(
  (select party_code from public.business_parties where legal_name='Reference Test Customer'),
  'PTY-0001',
  'Customer and supplier party references are generated automatically'
);
select extensions.is(
  (select estimate_number from public.estimates where title='Reference Number Estimate'),
  'EST-0001',
  'Estimate numbers are generated automatically'
);
select extensions.is(
  (select count(distinct project_code)::integer from public.projects
   where company_id='d2a65e38-87f2-4f44-9b89-a0a88f61a1a2'),
  2,
  'Generated project references remain unique'
);

select * from extensions.finish();
rollback;
