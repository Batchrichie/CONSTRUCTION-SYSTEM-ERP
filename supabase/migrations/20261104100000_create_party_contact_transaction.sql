-- Atomically create a party contact and, when requested, replace the active primary contact.
-- SECURITY INVOKER preserves the caller's table grants and RLS policies.
CREATE OR REPLACE FUNCTION public.create_party_contact(
  p_company_id uuid,
  p_party_id uuid,
  p_contact_name text,
  p_job_title text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_is_primary boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_contact_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT private.has_company_permission(p_company_id, 'parties.manage') THEN
    RAISE EXCEPTION 'You do not have permission to manage business parties'
      USING ERRCODE = '42501';
  END IF;

  IF p_contact_name IS NULL OR length(btrim(p_contact_name)) = 0 THEN
    RAISE EXCEPTION 'Contact name is required'
      USING ERRCODE = '22023';
  END IF;

  -- The update and insert execute in the same transaction. If the insert fails,
  -- PostgreSQL rolls back the primary-contact change as well.
  IF coalesce(p_is_primary, false) THEN
    UPDATE public.party_contacts
       SET is_primary = false
     WHERE company_id = p_company_id
       AND party_id = p_party_id
       AND is_primary = true;
  END IF;

  INSERT INTO public.party_contacts (
    company_id,
    party_id,
    contact_name,
    job_title,
    email,
    phone,
    is_primary,
    is_active,
    created_by
  )
  VALUES (
    p_company_id,
    p_party_id,
    btrim(p_contact_name),
    NULLIF(btrim(coalesce(p_job_title, '')), ''),
    NULLIF(btrim(coalesce(p_email, '')), ''),
    NULLIF(btrim(coalesce(p_phone, '')), ''),
    coalesce(p_is_primary, false),
    true,
    auth.uid()
  )
  RETURNING id INTO v_contact_id;

  RETURN v_contact_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_party_contact(
  uuid, uuid, text, text, text, text, boolean
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_party_contact(
  uuid, uuid, text, text, text, text, boolean
) TO authenticated;

COMMENT ON FUNCTION public.create_party_contact(
  uuid, uuid, text, text, text, text, boolean
) IS 'Creates a party contact atomically, including replacement of the primary contact when requested.';