-- Reject null/non-array payloads before the private replacement implementation.
-- An empty array remains valid for clearing draft allocations; posting controls
-- still require every expense debit line to be fully attributed.
create or replace function public.replace_journal_line_cost_allocations(
  p_company_id uuid,
  p_journal_line_id uuid,
  p_allocations jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_allocations is null or jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'Allocations must be supplied as a JSON array' using errcode = '22023';
  end if;
  perform private.replace_journal_line_cost_allocations(
    p_company_id,p_journal_line_id,p_allocations
  );
end;
$$;
revoke all on function public.replace_journal_line_cost_allocations(uuid,uuid,jsonb) from public,anon;
grant execute on function public.replace_journal_line_cost_allocations(uuid,uuid,jsonb) to authenticated;
