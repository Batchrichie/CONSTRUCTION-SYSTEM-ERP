-- Phase 7.4 Step 3: versioned project budgets and controlled approval workflow.
-- Budget lines remain in public.project_budgets; each set of lines belongs to
-- an immutable revision header in public.project_budget_versions.

create table public.project_budget_versions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  project_id uuid not null,
  revision_number integer not null check (revision_number > 0),
  status text not null default 'draft'
    check (status in ('draft','submitted','approved','rejected')),
  currency_code char(3) not null default 'GHS',
  notes text,
  submitted_by uuid references auth.users(id) on delete restrict,
  submitted_at timestamptz,
  decided_by uuid references auth.users(id) on delete restrict,
  decided_at timestamptz,
  rejection_reason text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, id),
  unique (company_id, project_id, revision_number),
  foreign key (company_id, project_id)
    references public.projects(company_id, id) on delete restrict,
  check (
    (status = 'submitted' and submitted_by is not null and submitted_at is not null)
    or status <> 'submitted'
  ),
  check (
    (status in ('approved','rejected') and decided_by is not null and decided_at is not null)
    or status not in ('approved','rejected')
  ),
  check (
    (status = 'rejected' and nullif(btrim(rejection_reason), '') is not null)
    or status <> 'rejected'
  )
);

-- Preserve existing budget rows while attaching them to a first revision.
alter table public.project_budgets
  add column budget_version_id uuid;

insert into public.project_budget_versions (
  company_id, project_id, revision_number, status, currency_code,
  notes, created_by, created_at, updated_at
)
select
  b.company_id,
  b.project_id,
  1,
  'draft',
  max(b.currency_code)::text,
  'Initial revision migrated from the original project budget register.',
  min(b.created_by::text)::uuid,
  min(b.created_at),
  max(b.updated_at)
from public.project_budgets b
group by b.company_id, b.project_id;

update public.project_budgets b
set budget_version_id = v.id
from public.project_budget_versions v
where v.company_id = b.company_id
  and v.project_id = b.project_id
  and v.revision_number = 1;

alter table public.project_budgets
  alter column budget_version_id set not null;

alter table public.project_budgets
  drop constraint if exists project_budgets_company_id_project_id_cost_code_id_key;

alter table public.project_budgets
  add constraint project_budgets_company_version_cost_code_key
  unique (company_id, budget_version_id, cost_code_id);

alter table public.project_budgets
  add constraint project_budgets_company_version_fkey
  foreign key (company_id, budget_version_id)
  references public.project_budget_versions(company_id, id)
  on delete restrict;

create index project_budget_versions_project_status_idx
  on public.project_budget_versions(company_id, project_id, status, revision_number desc);
create index project_budgets_version_idx
  on public.project_budgets(company_id, budget_version_id, cost_code_id);

create table public.project_budget_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  budget_version_id uuid not null,
  from_status text,
  to_status text not null check (to_status in ('draft','submitted','approved','rejected')),
  note text,
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  foreign key (company_id, budget_version_id)
    references public.project_budget_versions(company_id, id) on delete restrict
);

create index project_budget_history_version_idx
  on public.project_budget_history(company_id, budget_version_id, changed_at);

alter table public.project_budget_versions enable row level security;
alter table public.project_budget_history enable row level security;

create policy project_budget_versions_read
  on public.project_budget_versions for select to authenticated
  using ((select private.has_company_permission(company_id, 'project_costs.read')));

create policy project_budget_history_read
  on public.project_budget_history for select to authenticated
  using ((select private.has_company_permission(company_id, 'project_costs.read')));

-- Approval is intentionally separate from budget preparation. Only owners and
-- administrators receive this permission; accountants/project managers can prepare.
insert into public.permissions(code, module, description)
values ('project_costs.approve', 'project_costs', 'Approve or reject submitted project budget revisions')
on conflict (code) do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.code in ('owner','admin')
  and p.code = 'project_costs.approve'
on conflict do nothing;

-- Drafts and workflow records are changed only through the validated RPCs below.
revoke all on public.project_budget_versions, public.project_budget_history
  from anon, authenticated;
grant select on public.project_budget_versions, public.project_budget_history
  to authenticated;
revoke insert, update, delete on public.project_budgets from anon, authenticated;
grant select on public.project_budgets to authenticated;

create or replace function private.touch_project_budget_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger project_budget_versions_touch_updated_at
before update on public.project_budget_versions
for each row execute function private.touch_project_budget_updated_at();

create or replace function private.save_project_budget_draft(
  p_company_id uuid,
  p_project_id uuid,
  p_budget_version_id uuid,
  p_notes text,
  p_lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_budget public.project_budget_versions%rowtype;
  v_line jsonb;
  v_cost_code_id uuid;
  v_amount numeric(20,4);
  v_notes text;
  v_version_id uuid;
  v_revision integer;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if not private.has_company_permission(p_company_id, 'project_costs.manage') then
    raise exception 'You do not have permission to manage project budgets' using errcode = '42501';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) < 1 or jsonb_array_length(p_lines) > 200 then
    raise exception 'A budget must contain between 1 and 200 cost-code lines' using errcode = '22023';
  end if;

  select * into v_project
  from public.projects
  where company_id = p_company_id and id = p_project_id
  for update;
  if not found or v_project.status = 'cancelled' then
    raise exception 'Project not found or cancelled' using errcode = 'P0002';
  end if;

  if p_budget_version_id is null then
    select coalesce(max(revision_number), 0) + 1 into v_revision
    from public.project_budget_versions
    where company_id = p_company_id and project_id = p_project_id;
    insert into public.project_budget_versions (
      company_id, project_id, revision_number, status, currency_code,
      notes, created_by
    ) values (
      p_company_id, p_project_id, v_revision, 'draft', v_project.currency_code,
      nullif(btrim(coalesce(p_notes, '')), ''), v_user_id
    ) returning id into v_version_id;
  else
    select * into v_budget
    from public.project_budget_versions
    where company_id = p_company_id
      and project_id = p_project_id
      and id = p_budget_version_id
    for update;
    if not found then
      raise exception 'Budget revision not found for this project' using errcode = 'P0002';
    end if;
    if v_budget.status <> 'draft' then
      raise exception 'Only draft budget revisions can be edited' using errcode = '22023';
    end if;
    v_version_id := v_budget.id;
    update public.project_budget_versions
    set notes = nullif(btrim(coalesce(p_notes, '')), '')
    where company_id = p_company_id and id = v_version_id;
    delete from public.project_budgets
    where company_id = p_company_id and budget_version_id = v_version_id;
  end if;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    begin
      v_cost_code_id := nullif(v_line->>'cost_code_id', '')::uuid;
      v_amount := (v_line->>'budget_amount')::numeric(20,4);
      v_notes := nullif(btrim(coalesce(v_line->>'notes', '')), '');
    exception when others then
      raise exception 'Invalid budget line data' using errcode = '22023';
    end;

    if v_cost_code_id is null or v_amount is null or v_amount <= 0 then
      raise exception 'Each budget line requires an active cost code and a positive amount' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.cost_codes
      where company_id = p_company_id and id = v_cost_code_id and is_active
    ) then
      raise exception 'A selected cost code is invalid or inactive' using errcode = '23503';
    end if;

    insert into public.project_budgets (
      company_id, project_id, budget_version_id, cost_code_id,
      budget_amount, approved_amount, currency_code, notes, created_by
    ) values (
      p_company_id, p_project_id, v_version_id, v_cost_code_id,
      v_amount, 0, v_project.currency_code, v_notes, v_user_id
    );
    v_count := v_count + 1;
  end loop;

  insert into public.project_budget_history (
    company_id, budget_version_id, from_status, to_status, note, changed_by
  ) values (
    p_company_id, v_version_id, case when p_budget_version_id is null then null else 'draft' end,
    'draft', 'Draft budget saved.', v_user_id
  );

  return v_version_id;
end;
$$;

revoke all on function private.save_project_budget_draft(uuid,uuid,uuid,text,jsonb) from public, anon;
grant execute on function private.save_project_budget_draft(uuid,uuid,uuid,text,jsonb) to authenticated;

create or replace function public.save_project_budget_draft(
  p_company_id uuid,
  p_project_id uuid,
  p_budget_version_id uuid,
  p_notes text,
  p_lines jsonb
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.save_project_budget_draft(
    p_company_id, p_project_id, p_budget_version_id, p_notes, p_lines
  );
$$;

revoke all on function public.save_project_budget_draft(uuid,uuid,uuid,text,jsonb) from public, anon;
grant execute on function public.save_project_budget_draft(uuid,uuid,uuid,text,jsonb) to authenticated;

create or replace function private.create_project_budget_revision(
  p_company_id uuid,
  p_project_id uuid,
  p_source_budget_version_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_source public.project_budget_versions%rowtype;
  v_revision integer;
  v_new_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if not private.has_company_permission(p_company_id, 'project_costs.manage') then
    raise exception 'You do not have permission to manage project budgets' using errcode = '42501';
  end if;

  select * into v_project
  from public.projects
  where company_id = p_company_id and id = p_project_id
  for update;
  if not found or v_project.status = 'cancelled' then
    raise exception 'Project not found or cancelled' using errcode = 'P0002';
  end if;

  if p_source_budget_version_id is null then
    select * into v_source
    from public.project_budget_versions
    where company_id = p_company_id and project_id = p_project_id and status in ('approved','rejected')
    order by revision_number desc limit 1;
  else
    select * into v_source
    from public.project_budget_versions
    where company_id = p_company_id and project_id = p_project_id
      and id = p_source_budget_version_id and status in ('approved','rejected');
  end if;
  if not found then
    raise exception 'An approved or rejected budget revision is required to create a revision' using errcode = 'P0002';
  end if;

  select coalesce(max(revision_number), 0) + 1 into v_revision
  from public.project_budget_versions
  where company_id = p_company_id and project_id = p_project_id;

  insert into public.project_budget_versions (
    company_id, project_id, revision_number, status, currency_code, notes, created_by
  ) values (
    p_company_id, p_project_id, v_revision, 'draft', v_project.currency_code,
    'Revision copied from prior revision ' || v_source.revision_number::text,
    v_user_id
  ) returning id into v_new_id;

  insert into public.project_budgets (
    company_id, project_id, budget_version_id, cost_code_id,
    budget_amount, approved_amount, currency_code, notes, created_by
  )
  select company_id, project_id, v_new_id, cost_code_id,
         budget_amount, 0, currency_code, notes, v_user_id
  from public.project_budgets
  where company_id = p_company_id and budget_version_id = v_source.id;

  insert into public.project_budget_history (
    company_id, budget_version_id, from_status, to_status, note, changed_by
  ) values (
    p_company_id, v_new_id, null, 'draft',
    'Created from prior revision ' || v_source.revision_number::text, v_user_id
  );

  return v_new_id;
end;
$$;

revoke all on function private.create_project_budget_revision(uuid,uuid,uuid) from public, anon;
grant execute on function private.create_project_budget_revision(uuid,uuid,uuid) to authenticated;

create or replace function public.create_project_budget_revision(
  p_company_id uuid,
  p_project_id uuid,
  p_source_budget_version_id uuid default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.create_project_budget_revision(
    p_company_id, p_project_id, p_source_budget_version_id
  );
$$;

revoke all on function public.create_project_budget_revision(uuid,uuid,uuid) from public, anon;
grant execute on function public.create_project_budget_revision(uuid,uuid,uuid) to authenticated;

create or replace function private.transition_project_budget(
  p_company_id uuid,
  p_budget_version_id uuid,
  p_new_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_budget public.project_budget_versions%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if p_new_status not in ('submitted','approved','rejected') then
    raise exception 'Unsupported budget status transition' using errcode = '22023';
  end if;

  select * into v_budget
  from public.project_budget_versions
  where company_id = p_company_id and id = p_budget_version_id
  for update;
  if not found then
    raise exception 'Budget revision not found' using errcode = 'P0002';
  end if;

  if p_new_status = 'submitted' then
    if not private.has_company_permission(p_company_id, 'project_costs.manage') then
      raise exception 'You do not have permission to submit project budgets' using errcode = '42501';
    end if;
    if v_budget.status <> 'draft' then
      raise exception 'Only draft budgets can be submitted' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.project_budgets
      where company_id = p_company_id and budget_version_id = p_budget_version_id
    ) then
      raise exception 'A budget must contain at least one cost-code line before submission' using errcode = '23514';
    end if;
    update public.project_budget_versions
    set status = 'submitted', submitted_by = v_user_id, submitted_at = now(),
        rejection_reason = null, decided_by = null, decided_at = null
    where company_id = p_company_id and id = p_budget_version_id;
  else
    if not private.has_company_permission(p_company_id, 'project_costs.approve') then
      raise exception 'You do not have permission to approve or reject project budgets' using errcode = '42501';
    end if;
    if v_budget.status <> 'submitted' then
      raise exception 'Only submitted budgets can be approved or rejected' using errcode = '22023';
    end if;
    if p_new_status = 'rejected' and nullif(btrim(coalesce(p_note,'')), '') is null then
      raise exception 'A rejection reason is required' using errcode = '22023';
    end if;

    update public.project_budget_versions
    set status = p_new_status,
        decided_by = v_user_id,
        decided_at = now(),
        rejection_reason = case when p_new_status = 'rejected' then btrim(p_note) else null end
    where company_id = p_company_id and id = p_budget_version_id;

    if p_new_status = 'approved' then
      update public.project_budgets
      set approved_amount = budget_amount
      where company_id = p_company_id and budget_version_id = p_budget_version_id;
    end if;
  end if;

  insert into public.project_budget_history (
    company_id, budget_version_id, from_status, to_status, note, changed_by
  ) values (
    p_company_id, p_budget_version_id, v_budget.status, p_new_status,
    nullif(btrim(coalesce(p_note,'')), ''), v_user_id
  );
end;
$$;

revoke all on function private.transition_project_budget(uuid,uuid,text,text) from public, anon;
grant execute on function private.transition_project_budget(uuid,uuid,text,text) to authenticated;

create or replace function public.transition_project_budget(
  p_company_id uuid,
  p_budget_version_id uuid,
  p_new_status text,
  p_note text default null
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.transition_project_budget(
    p_company_id, p_budget_version_id, p_new_status, p_note
  );
$$;

revoke all on function public.transition_project_budget(uuid,uuid,text,text) from public, anon;
grant execute on function public.transition_project_budget(uuid,uuid,text,text) to authenticated;

comment on table public.project_budget_versions is
  'Versioned project budget submissions with controlled owner/administrator approval.';
comment on table public.project_budget_history is
  'Append-only status transition history for project budget revisions.';
