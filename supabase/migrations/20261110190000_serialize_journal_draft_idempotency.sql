-- Serialize concurrent draft creation requests that reuse the same company idempotency key.
-- Without this lock, two transactions can both miss the initial lookup and race on
-- the unique index; one caller then receives a uniqueness error instead of the
-- original draft ID.

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
  v_idempotency_key text := nullif(btrim(p_idempotency_key),'');
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

  if v_idempotency_key is not null then
    -- A transaction-scoped advisory lock makes lookup + insert one serialized
    -- operation for this company/key pair. Hash collisions only serialize
    -- unrelated requests; they do not compromise correctness.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(p_company_id::text || ':' || v_idempotency_key, 0)
    );

    select j.id, j.request_hash into v_existing_id, v_existing_hash
    from public.journal_entries j
    where j.company_id = p_company_id
      and j.idempotency_key = v_idempotency_key;

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
    v_idempotency_key, v_request_hash, v_user_id
  ) returning id into v_entry_id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_line_number := v_line_number + 1;
    -- Keep precision validation outside the cast-error handler so the
    -- specific debit/credit validation messages are not swallowed.
    if nullif(v_line->>'debit','') is not null then
      begin
        if pg_catalog.scale((v_line->>'debit')::numeric) > 4 then
          raise exception 'Debit amounts must not exceed 4 decimal places (line %)', v_line_number
            using errcode = '22023';
        end if;
      exception when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid account_id, debit or credit on journal line %', v_line_number
          using errcode = '22023';
      end;
    end if;
    if nullif(v_line->>'credit','') is not null then
      begin
        if pg_catalog.scale((v_line->>'credit')::numeric) > 4 then
          raise exception 'Credit amounts must not exceed 4 decimal places (line %)', v_line_number
            using errcode = '22023';
        end if;
      exception when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid account_id, debit or credit on journal line %', v_line_number
          using errcode = '22023';
      end;
    end if;

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
