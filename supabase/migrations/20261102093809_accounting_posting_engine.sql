-- Accounting posting engine: validated drafts, atomic posting and linked reversals.
-- All privileged implementations remain in the non-exposed private schema.

create or replace function private.create_journal_draft(
  p_company_id uuid,
  p_journal_date date,
  p_description text,
  p_lines jsonb,
  p_reference text default null,
  p_idempotency_key text default null,
  p_branch_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_currency char(3);
  v_period_id uuid;
  v_entry_id uuid;
  v_existing_id uuid;
  v_existing_hash text;
  v_request_hash text;
  v_line jsonb;
  v_account_id uuid;
  v_debit numeric(20,4);
  v_credit numeric(20,4);
  v_total_debit numeric(20,4) := 0;
  v_total_credit numeric(20,4) := 0;
  v_line_number integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if not private.has_company_permission(p_company_id,'accounting.manage') then
    raise exception 'You do not have permission to create journals for this company' using errcode = '42501';
  end if;
  if p_journal_date is null or p_description is null
     or length(btrim(p_description)) < 2 then
    raise exception 'Journal date and description are required' using errcode = '22023';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2
     or jsonb_array_length(p_lines) > 500 then
    raise exception 'A journal must contain between 2 and 500 lines' using errcode = '22023';
  end if;

  select c.base_currency into v_currency
  from public.companies c
  where c.id = p_company_id;
  if not found then
    raise exception 'Company not found';
  end if;

  if p_branch_id is not null and not exists (
    select 1 from public.branches b
    where b.company_id = p_company_id and b.id = p_branch_id and b.is_active
  ) then
    raise exception 'Branch is not active or does not belong to this company';
  end if;

  select p.id into v_period_id
  from public.accounting_periods p
  join public.fiscal_years fy
    on fy.company_id = p.company_id and fy.id = p.fiscal_year_id
  where p.company_id = p_company_id
    and p_journal_date between p.start_date and p.end_date
    and p.status = 'open'
    and fy.status = 'open'
  order by p.start_date
  limit 1;

  if v_period_id is null then
    raise exception 'No open accounting period covers the journal date';
  end if;

  v_request_hash := md5(jsonb_build_object(
    'journal_date',p_journal_date,
    'description',btrim(p_description),
    'reference',p_reference,
    'branch_id',p_branch_id,
    'lines',p_lines
  )::text);

  if p_idempotency_key is not null then
    select j.id, j.request_hash into v_existing_id, v_existing_hash
    from public.journal_entries j
    where j.company_id = p_company_id
      and j.idempotency_key = p_idempotency_key;

    if v_existing_id is not null then
      if v_existing_hash is distinct from v_request_hash then
        raise exception 'Idempotency key has already been used with a different journal payload'
          using errcode = '23505';
      end if;
      return v_existing_id;
    end if;
  end if;

  insert into public.journal_entries (
    company_id, branch_id, fiscal_period_id, journal_date, description,
    reference, source_module, currency_code, exchange_rate, status,
    idempotency_key, request_hash, created_by
  ) values (
    p_company_id, p_branch_id, v_period_id, p_journal_date, btrim(p_description),
    nullif(btrim(p_reference),''), 'manual', v_currency, 1, 'draft',
    nullif(btrim(p_idempotency_key),''), v_request_hash, v_user_id
  ) returning id into v_entry_id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_line_number := v_line_number + 1;
    begin
      v_account_id := (v_line->>'account_id')::uuid;
      v_debit := coalesce(nullif(v_line->>'debit','')::numeric,0);
      v_credit := coalesce(nullif(v_line->>'credit','')::numeric,0);
    exception when others then
      raise exception 'Invalid account_id, debit or credit on journal line %', v_line_number
        using errcode = '22023';
    end;

    if v_debit < 0 or v_credit < 0
       or not ((v_debit > 0 and v_credit = 0) or (v_credit > 0 and v_debit = 0)) then
      raise exception 'Each journal line must have either a positive debit or a positive credit, not both (line %)', v_line_number
        using errcode = '22023';
    end if;

    if not exists (
      select 1 from public.chart_of_accounts a
      where a.company_id = p_company_id
        and a.id = v_account_id
        and a.is_active
        and a.is_postable
        and a.allow_manual_journal
    ) then
      raise exception 'Account on line % is unavailable for manual journal posting', v_line_number
        using errcode = '22023';
    end if;

    insert into public.journal_lines (
      company_id, journal_entry_id, account_id, line_number,
      description, debit, credit
    ) values (
      p_company_id, v_entry_id, v_account_id, v_line_number,
      nullif(btrim(v_line->>'description'),''), v_debit, v_credit
    );

    v_total_debit := v_total_debit + v_debit;
    v_total_credit := v_total_credit + v_credit;
  end loop;

  if v_total_debit <= 0 or v_total_debit <> v_total_credit then
    raise exception 'Journal is not balanced. Debits: %, credits: %', v_total_debit, v_total_credit
      using errcode = '23514';
  end if;

  update public.journal_entries
  set total_debit = v_total_debit,
      total_credit = v_total_credit,
      updated_at = now()
  where id = v_entry_id and company_id = p_company_id;

  return v_entry_id;
end;
$$;

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
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  select * into v_entry
  from public.journal_entries
  where id = p_journal_entry_id
  for update;

  if not found then
    raise exception 'Journal entry not found';
  end if;
  if not private.has_company_permission(v_entry.company_id,'accounting.post') then
    raise exception 'You do not have permission to post journals for this company' using errcode = '42501';
  end if;

  if v_entry.status = 'posted' then
    return v_entry.journal_number;
  end if;
  if v_entry.status <> 'draft' then
    raise exception 'Only draft journal entries can be posted';
  end if;

  select * into v_period
  from public.accounting_periods
  where company_id = v_entry.company_id and id = v_entry.fiscal_period_id
  for update;

  select * into v_year
  from public.fiscal_years
  where company_id = v_period.company_id and id = v_period.fiscal_year_id;

  if v_period.status <> 'open' or v_year.status <> 'open'
     or v_entry.journal_date not between v_period.start_date and v_period.end_date then
    raise exception 'The journal accounting period is not open for posting';
  end if;

  select count(*), coalesce(sum(debit),0), coalesce(sum(credit),0)
  into v_line_count, v_debit, v_credit
  from public.journal_lines
  where company_id = v_entry.company_id
    and journal_entry_id = v_entry.id;

  if v_line_count < 2 or v_debit <= 0 or v_debit <> v_credit then
    raise exception 'Journal failed the double-entry balance check';
  end if;

  if exists (
    select 1
    from public.journal_lines l
    join public.chart_of_accounts a
      on a.company_id = l.company_id and a.id = l.account_id
    where l.company_id = v_entry.company_id
      and l.journal_entry_id = v_entry.id
      and (not a.is_active or not a.is_postable)
  ) then
    raise exception 'A journal line uses an inactive or non-postable account';
  end if;

  insert into private.journal_number_counters(company_id, fiscal_year_id, next_number)
  values (v_entry.company_id, v_period.fiscal_year_id, 2)
  on conflict (company_id, fiscal_year_id)
  do update set next_number = private.journal_number_counters.next_number + 1
  returning next_number - 1 into v_next_number;

  v_journal_number := 'JRN-' || to_char(v_period.start_date,'YYYY') || '-' ||
                      lpad(v_next_number::text,6,'0');

  update public.journal_entries
  set journal_number = v_journal_number,
      total_debit = v_debit,
      total_credit = v_credit,
      status = 'posted',
      posted_by = v_user_id,
      posted_at = now(),
      updated_at = now()
  where id = v_entry.id and company_id = v_entry.company_id;

  insert into public.audit_logs (
    company_id, actor_user_id, action, entity_table, entity_id, new_values
  ) values (
    v_entry.company_id, v_user_id, 'journal.posted', 'journal_entries',
    v_entry.id::text,
    jsonb_build_object('journal_number',v_journal_number,'total_debit',v_debit,'total_credit',v_credit)
  );

  return v_journal_number;
end;
$$;

create or replace function private.reverse_journal_entry(
  p_journal_entry_id uuid,
  p_reversal_date date,
  p_reason text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_original public.journal_entries%rowtype;
  v_period_id uuid;
  v_reversal_id uuid;
  v_reversal_number text;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  select * into v_original
  from public.journal_entries
  where id = p_journal_entry_id
  for update;

  if not found then
    raise exception 'Original journal entry not found';
  end if;
  if not private.has_company_permission(v_original.company_id,'accounting.post') then
    raise exception 'You do not have permission to reverse journals for this company' using errcode = '42501';
  end if;
  if v_original.status <> 'posted' then
    raise exception 'Only a posted journal entry can be reversed';
  end if;
  if p_reversal_date is null or p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'A reversal date and reason are required' using errcode = '22023';
  end if;

  select p.id into v_period_id
  from public.accounting_periods p
  join public.fiscal_years fy
    on fy.company_id = p.company_id and fy.id = p.fiscal_year_id
  where p.company_id = v_original.company_id
    and p_reversal_date between p.start_date and p.end_date
    and p.status = 'open' and fy.status = 'open'
  limit 1;

  if v_period_id is null then
    raise exception 'No open accounting period covers the reversal date';
  end if;

  insert into public.journal_entries (
    company_id, branch_id, fiscal_period_id, journal_date, description,
    reference, source_module, source_type, source_id, currency_code,
    exchange_rate, total_debit, total_credit, status, reversal_of_journal_id,
    created_by
  ) values (
    v_original.company_id, v_original.branch_id, v_period_id, p_reversal_date,
    'Reversal of ' || coalesce(v_original.journal_number,v_original.id::text) || ': ' || btrim(p_reason),
    v_original.journal_number, 'accounting', 'journal_reversal', v_original.id,
    v_original.currency_code, v_original.exchange_rate,
    v_original.total_credit, v_original.total_debit, 'draft',
    v_original.id, v_user_id
  ) returning id into v_reversal_id;

  insert into public.journal_lines (
    company_id, journal_entry_id, account_id, line_number,
    description, debit, credit
  )
  select company_id, v_reversal_id, account_id, line_number,
         coalesce(description,'Reversal'), credit, debit
  from public.journal_lines
  where company_id = v_original.company_id
    and journal_entry_id = v_original.id
  order by line_number;

  v_reversal_number := private.post_journal_entry(v_reversal_id);

  update public.journal_entries
  set status = 'reversed', updated_at = now()
  where company_id = v_original.company_id and id = v_original.id;

  insert into public.audit_logs (
    company_id, actor_user_id, action, entity_table, entity_id, old_values, new_values
  ) values (
    v_original.company_id, v_user_id, 'journal.reversed', 'journal_entries',
    v_original.id::text,
    jsonb_build_object('status','posted','journal_number',v_original.journal_number),
    jsonb_build_object('status','reversed','reversal_journal_id',v_reversal_id,'reversal_journal_number',v_reversal_number,'reason',btrim(p_reason))
  );

  return v_reversal_number;
end;
$$;

revoke all on function private.create_journal_draft(uuid,date,text,jsonb,text,text,uuid) from public, anon;
revoke all on function private.post_journal_entry(uuid) from public, anon;
revoke all on function private.reverse_journal_entry(uuid,date,text) from public, anon;
grant execute on function private.create_journal_draft(uuid,date,text,jsonb,text,text,uuid) to authenticated;
grant execute on function private.post_journal_entry(uuid) to authenticated;
grant execute on function private.reverse_journal_entry(uuid,date,text) to authenticated;

-- Public RPC wrappers are SECURITY INVOKER; authorization is repeated in the
-- private implementations, and no broad SECURITY DEFINER endpoint is exposed.
create or replace function public.create_journal_draft(
  p_company_id uuid,
  p_journal_date date,
  p_description text,
  p_lines jsonb,
  p_reference text default null,
  p_idempotency_key text default null,
  p_branch_id uuid default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.create_journal_draft(
    p_company_id,p_journal_date,p_description,p_lines,
    p_reference,p_idempotency_key,p_branch_id
  );
$$;

create or replace function public.post_journal_entry(p_journal_entry_id uuid)
returns text
language sql
security invoker
set search_path = ''
as $$
  select private.post_journal_entry(p_journal_entry_id);
$$;

create or replace function public.reverse_journal_entry(
  p_journal_entry_id uuid,
  p_reversal_date date,
  p_reason text
)
returns text
language sql
security invoker
set search_path = ''
as $$
  select private.reverse_journal_entry(p_journal_entry_id,p_reversal_date,p_reason);
$$;

revoke all on function public.create_journal_draft(uuid,date,text,jsonb,text,text,uuid) from public, anon;
revoke all on function public.post_journal_entry(uuid) from public, anon;
revoke all on function public.reverse_journal_entry(uuid,date,text) from public, anon;
grant execute on function public.create_journal_draft(uuid,date,text,jsonb,text,text,uuid) to authenticated;
grant execute on function public.post_journal_entry(uuid) to authenticated;
grant execute on function public.reverse_journal_entry(uuid,date,text) to authenticated;

-- Security-invoker views respect the RLS policies on the source tables.
create or replace view public.general_ledger
with (security_invoker = true)
as
select
  j.company_id,
  j.branch_id,
  j.id as journal_entry_id,
  j.journal_number,
  j.journal_date,
  j.fiscal_period_id,
  l.id as journal_line_id,
  l.line_number,
  a.id as account_id,
  a.account_code,
  a.account_name,
  a.account_type,
  a.account_subtype,
  l.description as line_description,
  j.description as journal_description,
  j.reference,
  j.source_module,
  j.source_type,
  j.source_id,
  l.debit,
  l.credit,
  j.currency_code,
  j.posted_at
from public.journal_entries j
join public.journal_lines l
  on l.company_id = j.company_id and l.journal_entry_id = j.id
join public.chart_of_accounts a
  on a.company_id = l.company_id and a.id = l.account_id
where j.status = 'posted';

create or replace view public.account_balances
with (security_invoker = true)
as
select
  company_id,
  account_id,
  account_code,
  account_name,
  account_type,
  account_subtype,
  sum(debit) as total_debits,
  sum(credit) as total_credits,
  case when account_type in ('asset','expense')
       then sum(debit) - sum(credit)
       else sum(credit) - sum(debit)
  end as balance
from public.general_ledger
group by company_id, account_id, account_code, account_name, account_type, account_subtype;

revoke all on public.general_ledger, public.account_balances from anon;
grant select on public.general_ledger, public.account_balances to authenticated;

comment on function public.create_journal_draft(uuid,date,text,jsonb,text,text,uuid)
  is 'Creates a balanced draft journal after validating company access, period and manual-postable accounts.';
comment on function public.post_journal_entry(uuid)
  is 'Atomically validates and posts a draft journal, assigns its number and writes an audit record.';
comment on function public.reverse_journal_entry(uuid,date,text)
  is 'Creates and posts a linked opposite journal in an open period; the original is marked reversed.';
