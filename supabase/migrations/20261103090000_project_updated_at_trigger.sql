-- Keep project register ordering accurate after project edits.
-- The timestamp is maintained in the database so every update path (not only
-- the frontend) produces a reliable last-modified value.

create or replace function private.touch_project_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists projects_touch_updated_at on public.projects;

create trigger projects_touch_updated_at
before update on public.projects
for each row
execute function private.touch_project_updated_at();
