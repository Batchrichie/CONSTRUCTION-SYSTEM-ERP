begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(6);

create temporary table _estimate_precision_fixture (
  owner_id uuid not null,
  company_id uuid,
  party_id uuid,
  estimate_id uuid
) on commit drop;

insert into _estimate_precision_fixture(owner_id)
values (gen_random_uuid());

grant select, update on _estimate_precision_fixture to authenticated;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select owner_id, 'authenticated', 'authenticated',
       'estimate-precision-' || owner_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _estimate_precision_fixture;

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _estimate_precision_fixture),
  true
);
set local role authenticated;

update _estimate_precision_fixture
set company_id = public.create_company_for_current_user(
  'Estimate Precision Test Company',
  'Estimate Precision Test'
);

insert into public.business_parties (
  company_id, party_code, legal_name, is_customer
)
select company_id, 'CUST-001', 'Estimate Precision Customer', true
from _estimate_precision_fixture;

update _estimate_precision_fixture f
set party_id = p.id
from public.business_parties p
where p.company_id = f.company_id
  and p.party_code = 'CUST-001';

select extensions.throws_ok(
  format(
    'insert into public.estimates(company_id,estimate_number,customer_party_id,title,discount_amount,tax_amount) values (%L::uuid,%L,%L::uuid,%L,%L::numeric,0)',
    (select company_id from _estimate_precision_fixture),
    'EST-INVALID-DISCOUNT',
    (select party_id from _estimate_precision_fixture),
    'Invalid precision estimate',
    '0.00001'
  ),
  '23514',
  'new row for relation "estimates" violates check constraint "estimates_discount_amount_max_4dp"',
  'Estimate discounts with more than four decimal places are rejected without rounding'
);

select extensions.throws_ok(
  format(
    'insert into public.estimates(company_id,estimate_number,customer_party_id,title,discount_amount,tax_amount) values (%L::uuid,%L,%L::uuid,%L,0,%L::numeric)',
    (select company_id from _estimate_precision_fixture),
    'EST-INVALID-TAX',
    (select party_id from _estimate_precision_fixture),
    'Invalid tax precision estimate',
    '0.00001'
  ),
  '23514',
  'new row for relation "estimates" violates check constraint "estimates_tax_amount_max_4dp"',
  'Estimate tax amounts with more than four decimal places are rejected without rounding'
);

with inserted as (
  insert into public.estimates (
    company_id, estimate_number, customer_party_id, title
  )
  select company_id, 'EST-VALID', party_id, 'Valid precision estimate'
  from _estimate_precision_fixture
  returning id
)
update _estimate_precision_fixture
set estimate_id = (select id from inserted);

select extensions.throws_ok(
  format(
    'insert into public.estimate_items(company_id,estimate_id,item_number,description,unit,quantity,unit_rate) values (%L::uuid,%L::uuid,%L,%L,%L,%L::numeric,%L::numeric)',
    (select company_id from _estimate_precision_fixture),
    (select estimate_id from _estimate_precision_fixture),
    'ITEM-INVALID-QUANTITY',
    'Invalid quantity',
    'item',
    '1.00001',
    '1'
  ),
  '23514',
  'new row for relation "estimate_items" violates check constraint "estimate_items_quantity_max_4dp"',
  'BOQ quantities with more than four decimal places are rejected without rounding'
);

select extensions.throws_ok(
  format(
    'insert into public.estimate_items(company_id,estimate_id,item_number,description,unit,quantity,unit_rate) values (%L::uuid,%L::uuid,%L,%L,%L,%L::numeric,%L::numeric)',
    (select company_id from _estimate_precision_fixture),
    (select estimate_id from _estimate_precision_fixture),
    'ITEM-INVALID',
    'Invalid unit rate',
    'item',
    '1',
    '1.00001'
  ),
  '23514',
  'new row for relation "estimate_items" violates check constraint "estimate_items_unit_rate_max_4dp"',
  'BOQ unit rates with more than four decimal places are rejected without rounding'
);

insert into public.estimate_items (
  company_id, estimate_id, item_number, description, unit, quantity, unit_rate
)
select company_id, estimate_id, 'ITEM-VALID', 'Valid BOQ amount', 'item', '0.1', '0.2'
from _estimate_precision_fixture;

select extensions.is(
  (select line_total from public.estimate_items
   where company_id = (select company_id from _estimate_precision_fixture)
     and estimate_id = (select estimate_id from _estimate_precision_fixture)
     and item_number = 'ITEM-VALID'),
  0.0200::numeric,
  'The generated BOQ line total is stored at exactly four decimal places'
);

reset role;
select * from extensions.finish();
rollback;
