-- Accounting controls: fiscal-year/period lifecycle, immutable system accounts,
-- trial balance reporting, posting revalidation and advisor-identified FK indexes.

create or replace function private.validate_fiscal_year()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1 from public.companies c where c.id = new.company_id for update;
  if not found then
    raise exception 'Company not found';
  end if;

  if exists (
    select 1 from public.fiscal_years fy
    where fy.company_id = new.company_id
      and fy.id <> coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
      and daterange(fy.start_date,fy.end_date,'[]') && daterange(new.start_date,new.end_date,'[]')
  ) then
    raise exception 'Fiscal years cannot overlap within a company';
  end if;

  if exists (
    select 1 from public.accounting_periods p
    where p.company_id = new.company_id
      and p.fiscal_year_id = new.id
      and (p.start_date < new.start_date or p.end_date > new.end_date)
  ) then
    raise exception 'Fiscal year dates cannot exclude existing accounting periods';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_fiscal_year() from public, anon, authenticated;

create trigger fiscal_year_validate_dates
before insert or update of company_id,start_date,end_date
on public.fiscal_years
for each row execute function private.validate_fiscal_year();

-- Only user-created accounts can be edited through the Data API.
drop policy chart_of_accounts_insert on public.chart_of_accounts;
create policy chart_of_accounts_insert
  on public.chart_of_accounts for insert to authenticated
  with check (
    not is_system_account
    and (select private.has_company_permission(company_id,'accounting.manage'))
  );

drop policy chart_of_accounts_update on public.chart_of_accounts;
create policy chart_of_accounts_update
  on public.chart_of_accounts for update to authenticated
  using (
    not is_system_account
    and (select private.has_company_permission(company_id,'accounting.manage'))
  )
  with check (
    not is_system_account
    and (select private.has_company_permission(company_id,'accounting.manage'))
  );

-- Fiscal year and period lifecycle changes must use the validated RPCs below.
drop policy fiscal_years_insert on public.fiscal_years;
drop policy fiscal_years_update on public.fiscal_years;
drop policy accounting_periods_insert on public.accounting_periods;
drop policy accounting_periods_update on public.accounting_periods;
revoke insert, update on public.fiscal_years, public.accounting_periods from authenticated;
grant select on public.fiscal_years, public.accounting_periods to authenticated;

create or replace function private.create_fiscal_year(
  p_company_id uuid,
  p_year_code text,
  p_start_date date,
  p_end_date date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication is required' using errcode='28000'; end if;
  if not private.has_company_permission(p_company_id,'accounting.manage') then
    raise exception 'You do not have permission to manage fiscal years' using errcode='42501';
  end if;
  if p_year_code is null or length(btrim(p_year_code)) < 2
     or p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'A valid fiscal-year code and date range are required' using errcode='22023';
  end if;

  insert into public.fiscal_years(company_id,year_code,start_date,end_date,status,created_by)
  values(p_company_id,btrim(p_year_code),p_start_date,p_end_date,'draft',v_user_id)
  returning id into v_id;

  insert into public.audit_logs(company_id,actor_user_id,action,entity_table,entity_id,new_values)
  values(p_company_id,v_user_id,'fiscal_year.created','fiscal_years',v_id::text,
    jsonb_build_object('year_code',btrim(p_year_code),'start_date',p_start_date,'end_date',p_end_date));
  return v_id;
end;
$$;

create or replace function private.create_accounting_period(
  p_company_id uuid,
  p_fiscal_year_id uuid,
  p_period_number smallint,
  p_period_name text,
  p_start_date date,
  p_end_date date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication is required' using errcode='28000'; end if;
  if not private.has_company_permission(p_company_id,'accounting.manage') then
    raise exception 'You do not have permission to manage accounting periods' using errcode='42501';
  end if;
  if p_period_name is null or length(btrim(p_period_name)) < 2
     or p_period_number not between 1 and 13
     or p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'A valid period number, name and date range are required' using errcode='22023';
  end if;

  insert into public.accounting_periods(
    company_id,fiscal_year_id,period_number,period_name,start_date,end_date,status
  ) values (
    p_company_id,p_fiscal_year_id,p_period_number,btrim(p_period_name),p_start_date,p_end_date,'draft'
  ) returning id into v_id;

  insert into public.audit_logs(company_id,actor_user_id,action,entity_table,entity_id,new_values)
  values(p_company_id,v_user_id,'accounting_period.created','accounting_periods',v_id::text,
    jsonb_build_object('period_number',p_period_number,'period_name',btrim(p_period_name),
      'start_date',p_start_date,'end_date',p_end_date));
  return v_id;
end;
$$;

create or replace function private.transition_fiscal_year_status(
  p_fiscal_year_id uuid,
  p_new_status text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year public.fiscal_years%rowtype;
  v_user_id uuid := auth.uid();
  v_period_count integer;
begin
  if v_user_id is null then raise exception 'Authentication is required' using errcode='28000'; end if;

  select * into v_year from public.fiscal_years where id=p_fiscal_year_id for update;
  if not found then raise exception 'Fiscal year not found'; end if;
  if not private.has_company_permission(v_year.company_id,'accounting.manage') then
    raise exception 'You do not have permission to manage fiscal years' using errcode='42501';
  end if;

  if v_year.status='draft' and p_new_status='open' then
    update public.fiscal_years set status='open',updated_at=now()
    where id=v_year.id and company_id=v_year.company_id;
  elsif v_year.status='open' and p_new_status='closed' then
    select count(*) into v_period_count from public.accounting_periods
    where company_id=v_year.company_id and fiscal_year_id=v_year.id;
    if v_period_count=0 or exists (
      select 1 from public.accounting_periods
      where company_id=v_year.company_id and fiscal_year_id=v_year.id
        and status in ('draft','open')
    ) then
      raise exception 'A fiscal year can close only after all its periods are closed or locked';
    end if;
    update public.fiscal_years set status='closed',updated_at=now()
    where id=v_year.id and company_id=v_year.company_id;
  else
    raise exception 'Invalid fiscal-year status transition: % to %',v_year.status,p_new_status;
  end if;

  insert into public.audit_logs(company_id,actor_user_id,action,entity_table,entity_id,old_values,new_values)
  values(v_year.company_id,v_user_id,'fiscal_year.status_changed','fiscal_years',v_year.id::text,
    jsonb_build_object('status',v_year.status),jsonb_build_object('status',p_new_status));
  return p_new_status;
end;
$$;

create or replace function private.transition_accounting_period_status(
  p_accounting_period_id uuid,
  p_new_status text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period public.accounting_periods%rowtype;
  v_year_status text;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication is required' using errcode='28000'; end if;

  select * into v_period from public.accounting_periods where id=p_accounting_period_id for update;
  if not found then raise exception 'Accounting period not found'; end if;
  if not private.has_company_permission(v_period.company_id,'accounting.manage') then
    raise exception 'You do not have permission to manage accounting periods' using errcode='42501';
  end if;

  select status into v_year_status from public.fiscal_years
  where company_id=v_period.company_id and id=v_period.fiscal_year_id;

  if v_period.status='draft' and p_new_status='open' and v_year_status='open' then
    update public.accounting_periods
    set status='open',closed_by=null,closed_at=null,updated_at=now()
    where id=v_period.id and company_id=v_period.company_id;
  elsif v_period.status='open' and p_new_status='closed' then
    if exists (
      select 1 from public.journal_entries
      where company_id=v_period.company_id and fiscal_period_id=v_period.id and status='draft'
    ) then
      raise exception 'The period cannot close while draft journals remain';
    end if;
    update public.accounting_periods
    set status='closed',closed_by=v_user_id,closed_at=now(),updated_at=now()
    where id=v_period.id and company_id=v_period.company_id;
  elsif v_period.status='closed' and p_new_status='locked' then
    update public.accounting_periods
    set status='locked',closed_by=v_user_id,closed_at=now(),updated_at=now()
    where id=v_period.id and company_id=v_period.company_id;
  else
    raise exception 'Invalid accounting-period status transition: % to %',v_period.status,p_new_status;
  end if;

  insert into public.audit_logs(company_id,actor_user_id,action,entity_table,entity_id,old_values,new_values)
  values(v_period.company_id,v_user_id,'accounting_period.status_changed','accounting_periods',v_period.id::text,
    jsonb_build_object('status',v_period.status),jsonb_build_object('status',p_new_status));
  return p_new_status;
end;
$$;

revoke all on function private.create_fiscal_year(uuid,text,date,date) from public,anon;
revoke all on function private.create_accounting_period(uuid,uuid,smallint,text,date,date) from public,anon;
revoke all on function private.transition_fiscal_year_status(uuid,text) from public,anon;
revoke all on function private.transition_accounting_period_status(uuid,text) from public,anon;
grant execute on function private.create_fiscal_year(uuid,text,date,date) to authenticated;
grant execute on function private.create_accounting_period(uuid,uuid,smallint,text,date,date) to authenticated;
grant execute on function private.transition_fiscal_year_status(uuid,text) to authenticated;
grant execute on function private.transition_accounting_period_status(uuid,text) to authenticated;

create or replace function public.create_fiscal_year(
  p_company_id uuid,p_year_code text,p_start_date date,p_end_date date
) returns uuid language sql security invoker set search_path=''
as $$ select private.create_fiscal_year(p_company_id,p_year_code,p_start_date,p_end_date); $$;

create or replace function public.create_accounting_period(
  p_company_id uuid,p_fiscal_year_id uuid,p_period_number smallint,
  p_period_name text,p_start_date date,p_end_date date
) returns uuid language sql security invoker set search_path=''
as $$ select private.create_accounting_period(p_company_id,p_fiscal_year_id,p_period_number,p_period_name,p_start_date,p_end_date); $$;

create or replace function public.transition_fiscal_year_status(
  p_fiscal_year_id uuid,p_new_status text
) returns text language sql security invoker set search_path=''
as $$ select private.transition_fiscal_year_status(p_fiscal_year_id,p_new_status); $$;

create or replace function public.transition_accounting_period_status(
  p_accounting_period_id uuid,p_new_status text
) returns text language sql security invoker set search_path=''
as $$ select private.transition_accounting_period_status(p_accounting_period_id,p_new_status); $$;

revoke all on function public.create_fiscal_year(uuid,text,date,date) from public,anon;
revoke all on function public.create_accounting_period(uuid,uuid,smallint,text,date,date) from public,anon;
revoke all on function public.transition_fiscal_year_status(uuid,text) from public,anon;
revoke all on function public.transition_accounting_period_status(uuid,text) from public,anon;
grant execute on function public.create_fiscal_year(uuid,text,date,date) to authenticated;
grant execute on function public.create_accounting_period(uuid,uuid,smallint,text,date,date) to authenticated;
grant execute on function public.transition_fiscal_year_status(uuid,text) to authenticated;
grant execute on function public.transition_accounting_period_status(uuid,text) to authenticated;

-- Revalidate manual-posting eligibility when a draft is posted.
create or replace function private.post_journal_entry(p_journal_entry_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_entry public.journal_entries%rowtype;
  v_period public.accounting_periods%rowtype;
  v_year public.fiscal_years%rowtype;
  v_debit numeric(20,4);
  v_credit numeric(20,4);
  v_line_count integer;
  v_next_number bigint;
  v_journal_number text;
begin
  if v_user_id is null then raise exception 'Authentication is required' using errcode='28000'; end if;

  select * into v_entry from public.journal_entries where id=p_journal_entry_id for update;
  if not found then raise exception 'Journal entry not found'; end if;
  if not private.has_company_permission(v_entry.company_id,'accounting.post') then
    raise exception 'You do not have permission to post journals for this company' using errcode='42501';
  end if;
  if v_entry.status='posted' then return v_entry.journal_number; end if;
  if v_entry.status<>'draft' then raise exception 'Only draft journal entries can be posted'; end if;

  select * into v_period from public.accounting_periods
  where company_id=v_entry.company_id and id=v_entry.fiscal_period_id for update;
  select * into v_year from public.fiscal_years
  where company_id=v_period.company_id and id=v_period.fiscal_year_id;

  if v_period.status<>'open' or v_year.status<>'open'
     or v_entry.journal_date not between v_period.start_date and v_period.end_date then
    raise exception 'The journal accounting period is not open for posting';
  end if;

  select count(*),coalesce(sum(debit),0),coalesce(sum(credit),0)
  into v_line_count,v_debit,v_credit
  from public.journal_lines
  where company_id=v_entry.company_id and journal_entry_id=v_entry.id;

  if v_line_count<2 or v_debit<=0 or v_debit<>v_credit then
    raise exception 'Journal failed the double-entry balance check';
  end if;

  if exists (
    select 1 from public.journal_lines l
    join public.chart_of_accounts a on a.company_id=l.company_id and a.id=l.account_id
    where l.company_id=v_entry.company_id and l.journal_entry_id=v_entry.id
      and (
        not a.is_active or not a.is_postable
        or (v_entry.source_module='manual' and not a.allow_manual_journal)
      )
  ) then
    raise exception 'A journal line uses an inactive, non-postable or restricted account';
  end if;

  insert into private.journal_number_counters(company_id,fiscal_year_id,next_number)
  values(v_entry.company_id,v_period.fiscal_year_id,2)
  on conflict(company_id,fiscal_year_id)
  do update set next_number=private.journal_number_counters.next_number+1
  returning next_number-1 into v_next_number;

  v_journal_number:='JRN-'||to_char(v_period.start_date,'YYYY')||'-'||lpad(v_next_number::text,6,'0');

  update public.journal_entries
  set journal_number=v_journal_number,total_debit=v_debit,total_credit=v_credit,
      status='posted',posted_by=v_user_id,posted_at=now(),updated_at=now()
  where id=v_entry.id and company_id=v_entry.company_id;

  insert into public.audit_logs(company_id,actor_user_id,action,entity_table,entity_id,new_values)
  values(v_entry.company_id,v_user_id,'journal.posted','journal_entries',v_entry.id::text,
    jsonb_build_object('journal_number',v_journal_number,'total_debit',v_debit,'total_credit',v_credit));
  return v_journal_number;
end;
$$;

-- Advisor-identified foreign-key indexes.
create index accounting_periods_closed_by_idx on public.accounting_periods(closed_by);
create index fiscal_years_created_by_idx on public.fiscal_years(created_by);
create index journal_entries_company_branch_idx on public.journal_entries(company_id,branch_id);
create index journal_entries_created_by_idx on public.journal_entries(created_by);
create index journal_entries_posted_by_idx on public.journal_entries(posted_by);

-- A trial balance includes every account, including accounts with no activity.
create or replace view public.trial_balance
with (security_invoker = true)
as
select
  a.company_id,
  a.id as account_id,
  a.account_code,
  a.account_name,
  a.account_type,
  a.normal_balance,
  coalesce(sum(l.debit),0)::numeric(20,4) as total_debits,
  coalesce(sum(l.credit),0)::numeric(20,4) as total_credits,
  case when a.normal_balance='debit'
       then coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0)
       else coalesce(sum(l.credit),0)-coalesce(sum(l.debit),0)
  end::numeric(20,4) as closing_balance
from public.chart_of_accounts a
left join public.general_ledger l
  on l.company_id=a.company_id and l.account_id=a.id
group by a.company_id,a.id,a.account_code,a.account_name,a.account_type,a.normal_balance;

revoke all on public.trial_balance from anon;
grant select on public.trial_balance to authenticated;

comment on view public.trial_balance is 'All-account trial balance from posted general-ledger lines; includes zero-activity accounts.';
