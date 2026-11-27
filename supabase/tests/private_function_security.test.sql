-- Phase 7.5: private function and trigger execution boundaries.
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(3);

select extensions.ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private'
      and p.prorettype='trigger'::regtype
      and (
        has_function_privilege('anon',p.oid,'EXECUTE')
        or has_function_privilege('authenticated',p.oid,'EXECUTE')
      )
  ),
  'Private trigger functions are not directly executable by API roles'
);

select extensions.ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private'
      and p.prosecdef
      and not coalesce(p.proconfig, array[]::text[]) @> array['search_path=""']
  ),
  'Every private SECURITY DEFINER function pins an empty search_path'
);

select extensions.ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
  ),
  'No exposed public RPC is SECURITY DEFINER'
);

select * from extensions.finish();
rollback;
