-- Generate installation-wide document references in the database.
-- Counters are transaction-safe and are seeded from existing references to avoid collisions.

create table private.reference_sequences (
  sequence_key text primary key,
  next_value bigint not null check (next_value > 0)
);

revoke all on private.reference_sequences from public, anon, authenticated;

create or replace function private.next_reference(
  p_sequence_key text,
  p_prefix text,
  p_padding integer default 4
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_number bigint;
begin
  if p_sequence_key is null or p_prefix is null
     or p_padding < 1 or p_padding > 12 then
    raise exception 'Invalid reference number configuration' using errcode = '22023';
  end if;

  insert into private.reference_sequences(sequence_key, next_value)
  values (p_sequence_key, 2)
  on conflict (sequence_key)
  do update set next_value = private.reference_sequences.next_value + 1
  returning next_value - 1 into v_number;

  return p_prefix || '-' || lpad(v_number::text, greatest(p_padding, length(v_number::text)), '0');
end;
$$;

revoke all on function private.next_reference(text,text,integer) from public, anon, authenticated;

create or replace function private.assign_company_reference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_field text := tg_argv[0];
  v_prefix text := tg_argv[1];
  v_existing text;
  v_generated text;
begin
  v_existing := to_jsonb(new)->>v_field;
  if nullif(btrim(v_existing), '') is null then
    v_generated := private.next_reference(tg_table_name, v_prefix, 4);
    new := jsonb_populate_record(new, jsonb_build_object(v_field, v_generated));
  end if;
  return new;
end;
$$;

revoke all on function private.assign_company_reference() from public, anon, authenticated;

-- Seed each counter above the highest existing generated reference.
do $$
declare
  v_item record;
begin
  for v_item in
    select * from (values
      ('projects','project_code','PRJ'),
      ('cost_codes','code','CST'),
      ('cost_centres','code','CTR'),
      ('business_parties','party_code','PTY'),
      ('project_contracts','contract_ref','CON'),
      ('estimates','estimate_number','EST')
    ) as refs(table_name, field_name, prefix)
  loop
    execute format(
      'insert into private.reference_sequences(sequence_key, next_value)
       select %L, coalesce(max((regexp_match(%I, %L))[1]::bigint), 0) + 1
       from public.%I
       where %I ~ %L
       having count(*) > 0
       on conflict (sequence_key)
       do update set next_value = greatest(
         private.reference_sequences.next_value,
         excluded.next_value
       )',
      v_item.table_name,
      v_item.field_name,
      '^' || v_item.prefix || '-([0-9]+)$',
      v_item.table_name,
      v_item.field_name,
      '^' || v_item.prefix || '-([0-9]+)$'
    );
  end loop;
end;
$$;

create trigger projects_assign_reference
before insert on public.projects
for each row execute function private.assign_company_reference('project_code','PRJ');

create trigger cost_codes_assign_reference
before insert on public.cost_codes
for each row execute function private.assign_company_reference('code','CST');

create trigger cost_centres_assign_reference
before insert on public.cost_centres
for each row execute function private.assign_company_reference('code','CTR');

create trigger business_parties_assign_reference
before insert on public.business_parties
for each row execute function private.assign_company_reference('party_code','PTY');

create trigger project_contracts_assign_reference
before insert on public.project_contracts
for each row execute function private.assign_company_reference('contract_ref','CON');

create trigger estimates_assign_reference
before insert on public.estimates
for each row execute function private.assign_company_reference('estimate_number','EST');

comment on table private.reference_sequences is
  'Atomic installation-wide counters for system-generated project and commercial document references for the single company in this installation.';
