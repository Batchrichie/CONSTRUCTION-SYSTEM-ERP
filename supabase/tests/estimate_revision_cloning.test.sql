begin;

select plan(15);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('91000000-0000-4000-8000-000000000001','authenticated','authenticated','phase745-manager@example.test','test-password',now(),now(),now()),
  ('91000000-0000-4000-8000-000000000002','authenticated','authenticated','phase745-viewer@example.test','test-password',now(),now(),now());

insert into public.companies (id, legal_name, display_name, created_by)
values ('92000000-0000-4000-8000-000000000001','Phase 7.4.5 Revision Test Ltd','Phase 7.4.5 Revision Test','91000000-0000-4000-8000-000000000001');

insert into public.company_memberships (company_id,user_id,role_id,status,joined_at)
select '92000000-0000-4000-8000-000000000001', u.user_id, r.id, 'active', now()
from (values
  ('91000000-0000-4000-8000-000000000001'::uuid,'accountant'),
  ('91000000-0000-4000-8000-000000000002'::uuid,'viewer')
) u(user_id,role_code)
join public.roles r on r.code=u.role_code;

insert into public.business_parties (
  id,company_id,party_code,legal_name,is_customer,is_supplier,status,created_by
) values (
  '93000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000001',
  'P745-CUST','Phase 7.4.5 Customer',true,false,'active',
  '91000000-0000-4000-8000-000000000001'
);

insert into public.estimates (
  id,company_id,estimate_number,revision_number,customer_party_id,title,
  issue_date,valid_until,currency_code,discount_amount,tax_amount,status,
  approved_by,approved_at,created_by
) values
  ('94000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001',
   'P745-EXPIRED',1,'93000000-0000-4000-8000-000000000001','Expired approved estimate',
   current_date-30,current_date-1,'GHS',10,2,'approved',
   '91000000-0000-4000-8000-000000000001',now(),'91000000-0000-4000-8000-000000000001'),
  ('94000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000001',
   'P745-FUTURE',1,'93000000-0000-4000-8000-000000000001','Rejected estimate with future validity',
   current_date-5,current_date+30,'GHS',0,0,'rejected',
   null,null,'91000000-0000-4000-8000-000000000001'),
  ('94000000-0000-4000-8000-000000000003','92000000-0000-4000-8000-000000000001',
   'P745-DRAFT',1,'93000000-0000-4000-8000-000000000001','Draft estimate',
   current_date,null,'GHS',0,0,'draft',null,null,
   '91000000-0000-4000-8000-000000000001');

insert into public.estimate_sections (
  id,company_id,estimate_id,section_number,title,description,sort_order
) values
  ('95000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001',
   '94000000-0000-4000-8000-000000000001',1,'Preliminaries','Site setup',10),
  ('95000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000001',
   '94000000-0000-4000-8000-000000000001',2,'Substructure','Foundation works',20);

insert into public.estimate_items (
  company_id,estimate_id,section_id,item_number,item_type,description,unit,quantity,unit_rate,sort_order
) values
  ('92000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001',
   '95000000-0000-4000-8000-000000000001','1.1','work','Site establishment','item',1,1250,1),
  ('92000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001',
   '95000000-0000-4000-8000-000000000002','2.1','material','Concrete','m3',12.5,850,1);

select ok(
  to_regprocedure('public.clone_estimate_revision(uuid,uuid)') is not null,
  'revision cloning RPC is installed'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$ select public.clone_estimate_revision('92000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001') $$,
  '42501','You do not have permission to create estimate revisions',
  'read-only users cannot clone estimates'
);

select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select throws_ok(
  $$ select public.clone_estimate_revision('92000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000003') $$,
  '22023','Only approved or rejected estimates can be revised',
  'draft estimates cannot be cloned'
);

select set_config(
  'phase745.approved_clone_id',
  public.clone_estimate_revision('92000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001')::text,
  true
);
select set_config(
  'phase745.rejected_clone_id',
  public.clone_estimate_revision('92000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000002')::text,
  true
);
reset role;

select is(
  (select revision_number from public.estimates where id=current_setting('phase745.approved_clone_id')::uuid),
  2,'approved estimate cloning creates the next revision number'
);
select is(
  (select status from public.estimates where id=current_setting('phase745.approved_clone_id')::uuid),
  'draft','a cloned revision always starts as draft'
);
select is(
  (select valid_until from public.estimates where id=current_setting('phase745.approved_clone_id')::uuid),
  null::date,'an expired validity date is cleared so the new revision can be issued today'
);
select is(
  (select issue_date from public.estimates where id=current_setting('phase745.approved_clone_id')::uuid),
  current_date,'the new revision receives today as its issue date'
);
select is(
  (select valid_until from public.estimates where id=current_setting('phase745.rejected_clone_id')::uuid),
  current_date+30,'a still-valid expiry date is preserved'
);
select is(
  (select count(*)::integer from public.estimate_sections where estimate_id=current_setting('phase745.approved_clone_id')::uuid),
  2,'all BOQ sections are copied'
);
select is(
  (select count(*)::integer from public.estimate_items where estimate_id=current_setting('phase745.approved_clone_id')::uuid),
  2,'all BOQ items are copied'
);
select ok(
  exists (
    select 1 from public.estimate_items i
    join public.estimate_sections s on s.id=i.section_id
      and s.company_id=i.company_id and s.estimate_id=i.estimate_id
    where i.estimate_id=current_setting('phase745.approved_clone_id')::uuid
      and s.section_number=2 and i.item_number='2.1'
      and i.description='Concrete' and i.quantity=12.5 and i.unit_rate=850
  ),
  'BOQ item values and their remapped section relationship are preserved'
);
select is(
  (select status from public.estimates where id='94000000-0000-4000-8000-000000000001'),
  'approved','the source approved estimate remains unchanged'
);
select is(
  (select valid_until from public.estimates where id='94000000-0000-4000-8000-000000000001'),
  current_date-1,'the source validity date remains unchanged'
);
select is(
  (select count(*)::integer from public.estimates
   where company_id='92000000-0000-4000-8000-000000000001' and estimate_number='P745-EXPIRED'),
  2,'the source estimate and its new revision coexist'
);
select is(
  (select count(*)::integer from public.estimate_items
   where estimate_id='94000000-0000-4000-8000-000000000001'),
  2,'source BOQ items remain intact after cloning'
);

select * from finish();
rollback;
