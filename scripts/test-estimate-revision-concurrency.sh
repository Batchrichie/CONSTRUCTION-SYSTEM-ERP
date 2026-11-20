#!/usr/bin/env bash
set -Eeuo pipefail

# Two-session revision-number race test. This script must run only against the
# disposable local Supabase database started by GitHub Actions.
DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
COMPANY_ID="92000000-0000-4000-8000-000000000004"
USER_ID="91000000-0000-4000-8000-000000000004"
PARTY_ID="93000000-0000-4000-8000-000000000004"
SOURCE_ESTIMATE_ID="94000000-0000-4000-8000-000000000004"

A_LOG="$(mktemp)"
B_LOG="$(mktemp)"
A_PID=""
B_PID=""

cleanup() {
  for pid in "$A_PID" "$B_PID"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done

  psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<SQL >/dev/null
DELETE FROM public.estimate_items
 WHERE estimate_id IN (
   SELECT id FROM public.estimates
   WHERE company_id = '$COMPANY_ID' AND estimate_number = 'T745-REV-CONC'
 );
DELETE FROM public.estimate_sections
 WHERE estimate_id IN (
   SELECT id FROM public.estimates
   WHERE company_id = '$COMPANY_ID' AND estimate_number = 'T745-REV-CONC'
 );
DELETE FROM public.estimate_status_history
 WHERE estimate_id IN (
   SELECT id FROM public.estimates
   WHERE company_id = '$COMPANY_ID' AND estimate_number = 'T745-REV-CONC'
 );
DELETE FROM public.estimates
 WHERE company_id = '$COMPANY_ID' AND estimate_number = 'T745-REV-CONC';
DELETE FROM public.business_parties WHERE id = '$PARTY_ID';
DELETE FROM public.company_memberships WHERE company_id = '$COMPANY_ID';
DELETE FROM public.companies WHERE id = '$COMPANY_ID';
DELETE FROM auth.users WHERE id = '$USER_ID';
SQL
  rm -f "$A_LOG" "$B_LOG"
}
trap cleanup EXIT

echo "Creating fixtures in the disposable local database..."
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<SQL
INSERT INTO auth.users (
  id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) VALUES (
  '$USER_ID', 'authenticated', 'authenticated',
  'phase745-revision-concurrency@example.test', 'test-password', now(), now(), now()
);

INSERT INTO public.companies (id, legal_name, display_name, created_by)
VALUES (
  '$COMPANY_ID', 'Phase 7.4.5 Revision Concurrency Ltd',
  'Phase 7.4.5 Revision Concurrency', '$USER_ID'
);

INSERT INTO public.company_memberships (company_id, user_id, role_id, status, joined_at)
SELECT '$COMPANY_ID', '$USER_ID', id, 'active', now()
FROM public.roles WHERE code = 'accountant';

INSERT INTO public.business_parties (
  id, company_id, party_code, legal_name, is_customer, is_supplier, status, created_by
) VALUES (
  '$PARTY_ID', '$COMPANY_ID', 'T745-REV-CONC',
  'Revision Concurrency Customer', true, false, 'active', '$USER_ID'
);

INSERT INTO public.estimates (
  id, company_id, estimate_number, revision_number, customer_party_id,
  title, status, created_by
) VALUES (
  '$SOURCE_ESTIMATE_ID', '$COMPANY_ID', 'T745-REV-CONC', 1,
  '$PARTY_ID', 'Approved source estimate', 'approved', '$USER_ID'
);

INSERT INTO public.estimate_sections (
  company_id, estimate_id, section_number, title, description, sort_order
) VALUES (
  '$COMPANY_ID', '$SOURCE_ESTIMATE_ID', 1, 'Preliminaries',
  'Copied once into each revision', 1
);

INSERT INTO public.estimate_items (
  company_id, estimate_id, section_id, item_number, description,
  unit, quantity, unit_rate, sort_order
)
SELECT '$COMPANY_ID', '$SOURCE_ESTIMATE_ID', id, '1.1',
       'Site establishment', 'item', 1, 1250, 1
FROM public.estimate_sections
WHERE company_id = '$COMPANY_ID' AND estimate_id = '$SOURCE_ESTIMATE_ID';
SQL

echo "Session A acquires the estimate-number advisory lock and holds it..."
PGAPPNAME=phase745_revision_holder psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 >"$A_LOG" 2>&1 <<SQL &
BEGIN;
SELECT pg_advisory_xact_lock(
  hashtextextended('$COMPANY_ID' || ':' || 'T745-REV-CONC', 0)
);
SELECT pg_sleep(8);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$USER_ID', true);
SELECT public.clone_estimate_revision('$COMPANY_ID', '$SOURCE_ESTIMATE_ID');
COMMIT;
SQL
A_PID=$!

holder_ready=0
for _ in $(seq 1 80); do
  if [[ "$(psql "$DB_URL" -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'phase745_revision_holder' AND wait_event = 'PgSleep'")" == "1" ]]; then
    holder_ready=1
    break
  fi
  sleep 0.1
done
if [[ "$holder_ready" != "1" ]]; then
  echo "FAIL: session A did not reach its advisory-lock hold point."
  cat "$A_LOG"
  exit 1
fi

echo "Session B requests a revision for the same estimate number..."
PGAPPNAME=phase745_revision_contender psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 >"$B_LOG" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$USER_ID', true);
SELECT public.clone_estimate_revision('$COMPANY_ID', '$SOURCE_ESTIMATE_ID');
COMMIT;
SQL
B_PID=$!

contender_blocked=0
for _ in $(seq 1 60); do
  if [[ "$(psql "$DB_URL" -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'phase745_revision_contender' AND wait_event_type = 'Lock'")" == "1" ]]; then
    contender_blocked=1
    break
  fi
  sleep 0.1
done

if [[ "$contender_blocked" != "1" ]]; then
  echo "FAIL: session B was not observed waiting for the estimate-number lock."
  cat "$A_LOG" "$B_LOG"
  exit 1
fi

echo "Confirmed: session B is blocked until session A commits."
wait "$A_PID"
A_PID=""
wait "$B_PID"
B_PID=""

RESULT="$(psql "$DB_URL" -X -Atq -v ON_ERROR_STOP=1 -c "
SELECT string_agg(revision_number::text, ',' ORDER BY revision_number)
FROM public.estimates
WHERE company_id = '$COMPANY_ID' AND estimate_number = 'T745-REV-CONC';
")"

if [[ "$RESULT" != "1,2,3" ]]; then
  echo "FAIL: expected source and two unique revisions 1,2,3; received '$RESULT'."
  cat "$A_LOG" "$B_LOG"
  exit 1
fi

COUNTS="$(psql "$DB_URL" -X -Atq -v ON_ERROR_STOP=1 -c "
SELECT
  (SELECT count(*) FROM public.estimate_sections s
   JOIN public.estimates e ON e.id = s.estimate_id
   WHERE e.company_id = '$COMPANY_ID' AND e.estimate_number = 'T745-REV-CONC')
  || ':' ||
  (SELECT count(*) FROM public.estimate_items i
   JOIN public.estimates e ON e.id = i.estimate_id
   WHERE e.company_id = '$COMPANY_ID' AND e.estimate_number = 'T745-REV-CONC');
")"

if [[ "$COUNTS" != "2:2" ]]; then
  echo "FAIL: expected one copied section and item per new revision (2:2); received '$COUNTS'."
  exit 1
fi

echo "PASS: two independent sessions requested revisions for the same estimate number."
echo "PASS: PostgreSQL serialized both requests and assigned unique revisions 2 and 3."
echo "PASS: each new revision contains its own copied BOQ section and item."
