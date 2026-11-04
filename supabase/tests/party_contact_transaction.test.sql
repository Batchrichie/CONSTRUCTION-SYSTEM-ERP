BEGIN;

SELECT plan(6);

SELECT ok(
  to_regprocedure('public.create_party_contact(uuid,uuid,text,text,text,text,boolean)') IS NOT NULL,
  'party contact RPC exists with the expected signature'
);

SELECT ok(
  (
    SELECT NOT p.prosecdef
    FROM pg_proc p
    WHERE p.oid = to_regprocedure('public.create_party_contact(uuid,uuid,text,text,text,text,boolean)')
  ),
  'party contact RPC runs with invoker privileges'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.create_party_contact(uuid,uuid,text,text,text,text,boolean)',
    'EXECUTE'
  ),
  'authenticated users can invoke the RPC'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.create_party_contact(uuid,uuid,text,text,text,text,boolean)',
    'EXECUTE'
  ),
  'anonymous users cannot invoke the RPC'
);

SELECT ok(
  position(
    'private.has_company_permission' IN pg_get_functiondef(
      to_regprocedure('public.create_party_contact(uuid,uuid,text,text,text,text,boolean)')
    )
  ) > 0,
  'RPC enforces the parties.manage permission'
);

SELECT ok(
  position(
    'UPDATE public.party_contacts' IN pg_get_functiondef(
      to_regprocedure('public.create_party_contact(uuid,uuid,text,text,text,text,boolean)')
    )
  ) > 0
  AND
  position(
    'INSERT INTO public.party_contacts' IN pg_get_functiondef(
      to_regprocedure('public.create_party_contact(uuid,uuid,text,text,text,text,boolean)')
    )
  ) > 0,
  'primary-contact replacement and contact insertion are in one database function'
);

SELECT * FROM finish();

ROLLBACK;