-- Phase 2 / Migration 001: organisation, identity and access foundations.
-- This migration intentionally establishes a secure baseline before operational modules.

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null check (length(btrim(legal_name)) between 2 and 200),
  display_name text not null check (length(btrim(display_name)) between 2 and 120),
  base_currency char(3) not null default 'GHS',
  country_code char(2) not null default 'GH',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  is_system_role boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  module text not null,
  description text not null,
  created_at timestamptz not null default now()
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table public.company_memberships (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role_id uuid not null references public.roles(id) on delete restrict,
  status text not null default 'active' check (status in ('invited', 'active', 'suspended')),
  invited_by uuid references auth.users(id) on delete set null,
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, user_id)
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  code text not null,
  name text not null,
  address text,
  is_head_office boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, code),
  unique (company_id, id)
);

create unique index branches_one_head_office_per_company
  on public.branches(company_id) where is_head_office;

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  branch_id uuid,
  code text not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, code),
  foreign key (company_id, branch_id)
    references public.branches(company_id, id) on delete restrict
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  company_id uuid references public.companies(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_schema text not null default 'public',
  entity_table text not null,
  entity_id text,
  old_values jsonb,
  new_values jsonb,
  request_id text,
  created_at timestamptz not null default now()
);

create index company_memberships_user_status_idx
  on public.company_memberships(user_id, status);
create index company_memberships_company_role_idx
  on public.company_memberships(company_id, role_id);
create index branches_company_active_idx
  on public.branches(company_id, is_active);
create index departments_company_branch_idx
  on public.departments(company_id, branch_id);
create index audit_logs_company_created_idx
  on public.audit_logs(company_id, created_at desc);
create index audit_logs_entity_idx
  on public.audit_logs(entity_table, entity_id, created_at desc);

insert into public.roles (code, name, description) values
  ('owner', 'Owner', 'Full control of the company workspace'),
  ('admin', 'Administrator', 'Company administration and access management'),
  ('accountant', 'Accountant', 'Accounting and financial operations'),
  ('project_manager', 'Project Manager', 'Project commercial and delivery management'),
  ('site_supervisor', 'Site Supervisor', 'Site execution and daily reporting'),
  ('procurement_officer', 'Procurement Officer', 'Procurement and supplier workflows'),
  ('hr_officer', 'HR Officer', 'People and payroll administration'),
  ('viewer', 'Viewer', 'Read-only workspace access')
on conflict (code) do nothing;

insert into public.permissions (code, module, description) values
  ('company.manage', 'organisation', 'Manage company settings'),
  ('users.manage', 'organisation', 'Invite and manage company users'),
  ('branches.manage', 'organisation', 'Manage branches and departments'),
  ('accounting.read', 'accounting', 'View accounting records and reports'),
  ('accounting.manage', 'accounting', 'Manage accounting configuration and journals'),
  ('accounting.post', 'accounting', 'Post and reverse accounting transactions'),
  ('projects.read', 'projects', 'View projects and contracts'),
  ('projects.manage', 'projects', 'Manage projects, contracts and variations'),
  ('procurement.manage', 'procurement', 'Manage procurement workflows'),
  ('inventory.manage', 'inventory', 'Manage inventory and stock movements'),
  ('people.manage', 'people', 'Manage employees and payroll'),
  ('reports.read', 'reports', 'View management reports')
on conflict (code) do nothing;

-- Membership checks are isolated in a non-exposed schema to avoid RLS recursion.
create or replace function private.is_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.company_memberships m
    where m.company_id = p_company_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  );
$$;

create or replace function private.is_company_admin(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.roles r on r.id = m.role_id
    where m.company_id = p_company_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and r.code in ('owner', 'admin')
  );
$$;

revoke all on function private.is_company_member(uuid) from public, anon;
revoke all on function private.is_company_admin(uuid) from public, anon;
grant execute on function private.is_company_member(uuid) to authenticated;
grant execute on function private.is_company_admin(uuid) to authenticated;

-- Company creation is the controlled onboarding path. The first member becomes owner.
create or replace function public.create_company_for_current_user(
  p_legal_name text,
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_owner_role_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  if p_legal_name is null or length(btrim(p_legal_name)) < 2
     or p_display_name is null or length(btrim(p_display_name)) < 2 then
    raise exception 'A valid legal name and display name are required' using errcode = '22023';
  end if;

  select id into v_owner_role_id from public.roles where code = 'owner';
  if v_owner_role_id is null then
    raise exception 'Owner role is not configured';
  end if;

  insert into public.companies (legal_name, display_name, created_by)
  values (btrim(p_legal_name), btrim(p_display_name), v_user_id)
  returning id into v_company_id;

  insert into public.company_memberships (company_id, user_id, role_id, status, joined_at)
  values (v_company_id, v_user_id, v_owner_role_id, 'active', now());

  insert into public.user_profiles (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;

  return v_company_id;
end;
$$;

revoke all on function public.create_company_for_current_user(text, text) from public, anon;
grant execute on function public.create_company_for_current_user(text, text) to authenticated;

-- RLS is enabled on every application table in the exposed public schema.
alter table public.companies enable row level security;
alter table public.user_profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.company_memberships enable row level security;
alter table public.branches enable row level security;
alter table public.departments enable row level security;
alter table public.audit_logs enable row level security;

create policy companies_select_for_members
  on public.companies for select to authenticated
  using ((select private.is_company_member(id)));
create policy companies_update_for_admins
  on public.companies for update to authenticated
  using ((select private.is_company_admin(id)))
  with check ((select private.is_company_admin(id)));

create policy profiles_select_self
  on public.user_profiles for select to authenticated
  using (user_id = (select auth.uid()));
create policy profiles_update_self
  on public.user_profiles for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy roles_read_authenticated
  on public.roles for select to authenticated using (true);
create policy permissions_read_authenticated
  on public.permissions for select to authenticated using (true);
create policy role_permissions_read_authenticated
  on public.role_permissions for select to authenticated using (true);

create policy memberships_select_self_or_admin
  on public.company_memberships for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.is_company_admin(company_id))
  );
create policy memberships_insert_for_admins
  on public.company_memberships for insert to authenticated
  with check ((select private.is_company_admin(company_id)));
create policy memberships_update_for_admins
  on public.company_memberships for update to authenticated
  using ((select private.is_company_admin(company_id)))
  with check ((select private.is_company_admin(company_id)));
create policy memberships_delete_for_admins
  on public.company_memberships for delete to authenticated
  using ((select private.is_company_admin(company_id)));

create policy branches_select_for_members
  on public.branches for select to authenticated
  using ((select private.is_company_member(company_id)));
create policy branches_insert_for_admins
  on public.branches for insert to authenticated
  with check ((select private.is_company_admin(company_id)));
create policy branches_update_for_admins
  on public.branches for update to authenticated
  using ((select private.is_company_admin(company_id)))
  with check ((select private.is_company_admin(company_id)));
create policy branches_delete_for_admins
  on public.branches for delete to authenticated
  using ((select private.is_company_admin(company_id)));

create policy departments_select_for_members
  on public.departments for select to authenticated
  using ((select private.is_company_member(company_id)));
create policy departments_insert_for_admins
  on public.departments for insert to authenticated
  with check ((select private.is_company_admin(company_id)));
create policy departments_update_for_admins
  on public.departments for update to authenticated
  using ((select private.is_company_admin(company_id)))
  with check ((select private.is_company_admin(company_id)));
create policy departments_delete_for_admins
  on public.departments for delete to authenticated
  using ((select private.is_company_admin(company_id)));

create policy audit_logs_select_for_admins
  on public.audit_logs for select to authenticated
  using (company_id is not null and (select private.is_company_admin(company_id)));

-- Explicit grants: object access and RLS row access are separate controls.
revoke all on all tables in schema public from anon;
grant select, update on public.companies to authenticated;
grant select, update on public.user_profiles to authenticated;
grant select on public.roles, public.permissions, public.role_permissions to authenticated;
grant select, insert, update, delete on public.company_memberships to authenticated;
grant select, insert, update, delete on public.branches, public.departments to authenticated;
grant select on public.audit_logs to authenticated;
grant usage, select on all sequences in schema public to authenticated;

comment on table public.companies is 'Company workspace root. Each customer deployment normally operates one company.';
comment on table public.company_memberships is 'Maps authenticated users to company workspaces and system roles.';
comment on table public.audit_logs is 'Append-oriented audit record store; writes are reserved for trusted database operations.';
