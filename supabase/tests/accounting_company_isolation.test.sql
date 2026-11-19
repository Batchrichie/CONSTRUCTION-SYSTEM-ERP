begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(15);

-- This database enforces one company per installation. Test membership isolation
-- between its owner and an authenticated user who has no membership.
create temporary table _iso (
 company_id uuid not null, owner_id uuid not null, outsider_id uuid not null,
 fy_id uuid not null, period_id uuid not null, journal_id uuid not null
) on commit drop;
insert into _iso values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid());

insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select owner_id,'authenticated','authenticated','iso-owner-'||owner_id::text||'@example.test','',now(),'{}','{}' from _iso
union all
select outsider_id,'authenticated','authenticated','iso-outsider-'||outsider_id::text||'@example.test','',now(),'{}','{}' from _iso;

insert into public.companies(id,legal_name,display_name,base_currency,country_code,created_by)
select company_id,'Isolation Test Company','Isolation Test','GHS','GH',owner_id from _iso;
select private.seed_default_chart_of_accounts(company_id) from _iso;

insert into public.company_memberships(company_id,user_id,role_id,status,joined_at)
select i.company_id,i.owner_id,r.id,'active',now() from _iso i cross join public.roles r where r.code='owner';

insert into public.fiscal_years(id,company_id,year_code,start_date,end_date,status,created_by)
select fy_id,company_id,'ISO-'||left(company_id::text,8),date '2026-01-01',date '2026-12-31','open',owner_id from _iso;
insert into public.accounting_periods(id,company_id,fiscal_year_id,period_number,period_name,start_date,end_date,status)
select period_id,company_id,fy_id,1,'January',date '2026-01-01',date '2026-01-31','open' from _iso;
insert into public.journal_entries(id,company_id,fiscal_period_id,journal_number,journal_date,description,currency_code,total_debit,total_credit,status,created_by,posted_by,posted_at)
select journal_id,company_id,period_id,'ISO-'||left(journal_id::text,8),date '2026-01-15','Isolation fixture','GHS',125,125,'posted',owner_id,owner_id,now() from _iso;
insert into public.journal_lines(company_id,journal_entry_id,account_id,line_number,description,debit,credit)
select i.company_id,i.journal_id,a.id,1,'Cash debit',125,0 from _iso i join public.chart_of_accounts a on a.company_id=i.company_id and a.account_code='1110'
union all
select i.company_id,i.journal_id,a.id,2,'Bank credit',0,125 from _iso i join public.chart_of_accounts a on a.company_id=i.company_id and a.account_code='1120';

select set_config('test.company_id',(select company_id::text from _iso),true);
select set_config('test.owner_id',(select owner_id::text from _iso),true);
select set_config('test.outsider_id',(select outsider_id::text from _iso),true);
set local role authenticated;

select set_config('request.jwt.claim.sub',current_setting('test.owner_id'),true);
select extensions.ok((select count(*) > 0 from public.chart_of_accounts where company_id=current_setting('test.company_id')::uuid),'Owner can read the company chart of accounts');
select extensions.is((select count(*)::integer from public.fiscal_years where company_id=current_setting('test.company_id')::uuid),1,'Owner can read the fiscal year');
select extensions.is((select count(*)::integer from public.accounting_periods where company_id=current_setting('test.company_id')::uuid),1,'Owner can read the accounting period');
select extensions.is((select count(*)::integer from public.journal_entries where company_id=current_setting('test.company_id')::uuid),1,'Owner can read the journal header');
select extensions.is((select count(*)::integer from public.journal_lines where company_id=current_setting('test.company_id')::uuid),2,'Owner can read journal lines');
select extensions.is((select count(*)::integer from public.general_ledger where company_id=current_setting('test.company_id')::uuid),2,'Owner can read the general ledger');
select extensions.is((select count(*)::integer from public.account_balances where company_id=current_setting('test.company_id')::uuid),2,'Owner can read account balances');

select set_config('request.jwt.claim.sub',current_setting('test.outsider_id'),true);
select extensions.is((select count(*)::integer from public.chart_of_accounts where company_id=current_setting('test.company_id')::uuid),0,'Non-member cannot read chart of accounts');
select extensions.is((select count(*)::integer from public.fiscal_years where company_id=current_setting('test.company_id')::uuid),0,'Non-member cannot read fiscal years');
select extensions.is((select count(*)::integer from public.accounting_periods where company_id=current_setting('test.company_id')::uuid),0,'Non-member cannot read accounting periods');
select extensions.is((select count(*)::integer from public.journal_entries where company_id=current_setting('test.company_id')::uuid),0,'Non-member cannot read journal headers');
select extensions.is((select count(*)::integer from public.journal_lines where company_id=current_setting('test.company_id')::uuid),0,'Non-member cannot read journal lines');
select extensions.is((select count(*)::integer from public.general_ledger where company_id=current_setting('test.company_id')::uuid),0,'Non-member cannot read general ledger view');
select extensions.is((select count(*)::integer from public.account_balances where company_id=current_setting('test.company_id')::uuid),0,'Non-member cannot read account balances view');
select extensions.is(private.has_company_permission(current_setting('test.company_id')::uuid,'accounting.read'),false,'Permission helper denies accounting access to non-members');

reset role;
select * from extensions.finish();
rollback;
