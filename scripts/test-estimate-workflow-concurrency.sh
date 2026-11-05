#!/usr/bin/env bash
set -Eeuo pipefail

# This integration test is intentionally restricted to the disposable local
# Supabase database started by GitHub Actions. Never point it at production.
DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
COMPANY_ID="82000000-0000-4000-8000-000000000004"
USER_ID="81000000-0000-4000-8000-000000000004"
PARTY_ID="83000000-0000-4000-8000-000000000004"
ESTIMATE_ID="84000000-0000-4000-8000-000000000004"

A_LOG="$(mktemp)"
B_LOG="$(mktemp)"
A_PID=""
B_PID=""

cleanup() {
  # Stop/wait for both database sessions before removing their fixtures.
  for pid in "$A_PID" "$B_PID"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done

  # Respect restrictive foreign keys: BOQ items reference sections/estimates,
  # and status history references estimates and auth users.
  psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<SQL >/dev/null
DELETE FROM public.estimate_items WHERE estimate_id = '$ESTIMATE_ID';
DELETE FROM public.estimate_sections WHERE estimate_id = '$ESTIMATE_ID';
DELETE FROM public.estimate_status_history WHERE estimate_id = '$ESTIMATE_ID';
DELETE FROM public.estimates WHERE id = '$ESTIMATE_ID';
DELETE FROM public.business_parties WHERE id = '$PARTY_ID';
DELETE FROM public.company_memberships WHERE company_id = '$COMPANY_ID';
DELETE FROM public.companies WHERE id = '$COMPANY_ID';
DELETE FROM auth.users WHERE id = '$USER_ID';
SQL
  rm -f "$A_LOG" "$B_LOG"
}
trap cleanup EXIT

echo "Creating committed fixtures in the disposable local database..."
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<SQL
INSERT INTO auth.users (
  id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) VALUES (
  '$USER_ID', 'authenticated', 'authenticated',
  'phase744-concurrency@example.test', 'test-password', now(), now(), now()
);

INSERT INTO public.companies (id, legal_name, display_name, created_by)
VALUES (
  '$COMPANY_ID', 'Phase 7.4.4 Concurrency Test Ltd',
  'Phase 7.4.4 Concurrency Test', '$USER_ID'
);

INSERT INTO public.company_memberships (company_id, user_id, role_id, status, joined_at)
SELECT '$COMPANY_ID', '$USER_ID', id, 'active', now()
FROM public.roles WHERE code = 'accountant';

INSERT INTO public.business_parties (
  id, company_id, party_code, legal_name, is_customer, is_supplier, status, created_by
) VALUES (
  '$PARTY_ID', '$COMPANY_ID', 'T744-CONC',
  'Phase 7.4.4 Concurrency Customer', true, false, 'active', '$USER_ID'
);

INSERT INTO public.estimates (
  id, company_id, estimate_number, customer_party_id, title, created_by
) VALUES (
  '$ESTIMATE_ID', '$COMPANY_ID', 'T744-CONC',
  '$PARTY_ID', 'Concurrent transition test', '$USER_ID'
);

INSERT INTO public.estimate_items (
  company_id, estimate_id, item_number, description, unit, quantity, unit_rate
) VALUES (
  '$COMPANY_ID', '$ESTIMATE_ID', '1',
  'Priced concurrency test BOQ item', 'item', 1, 100
);
SQL

echo "Starting session A and holding the estimate row lock..."
PGAPPNAME=phase744_concurrency_holder psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 >"$A_LOG" 2>&1 <<SQL &
BEGIN;
SELECT id FROM public.estimates WHERE id = '$ESTIMATE_ID' FOR UPDATE;
SELECT pg_sleep(8);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$USER_ID', true);
SELECT public.transition_estimate('$COMPANY_ID', '$ESTIMATE_ID', 'submitted', 'Session A wins');
COMMIT;
SQL
A_PID=$!

# Do not start the competing call until PostgreSQL confirms session A owns
# the row lock and is in its deliberate hold interval.
holder_ready=0
for _ in $(seq 1 80); do
  if [[ "$(psql "$DB_URL" -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'phase744_concurrency_holder' AND wait_event = 'PgSleep'")" == "1" ]]; then
    holder_ready=1
    break
  fi
  sleep 0.1
done
if [[ "$holder_ready" != "1" ]]; then
  echo "FAIL: session A did not reach its row-lock hold point."
  cat "$A_LOG"
  exit 1
fi

echo "Starting session B against the same estimate..."
set +e
PGAPPNAME=phase744_concurrency_contender psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 >"$B_LOG" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$USER_ID', true);
SELECT public.transition_estimate('$COMPANY_ID', '$ESTIMATE_ID', 'submitted', 'Session B races');
COMMIT;
SQL
B_PID=$!
set -e

# Prove session B actually blocked on a PostgreSQL lock before A commits.
contender_blocked=0
for _ in $(seq 1 60); do
  if [[ "$(psql "$DB_URL" -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'phase744_concurrency_contender' AND wait_event_type = 'Lock'")" == "1" ]]; then
    contender_blocked=1
    break
  fi
  sleep 0.1
done

if [[ "$contender_blocked" != "1" ]]; then
  echo "FAIL: session B was not observed waiting on the estimate row lock."
  cat "$A_LOG" "$B_LOG"
  kill "$B_PID" 2>/dev/null || true
  wait "$B_PID" 2>/dev/null || true
  exit 1
fi

echo "Confirmed: session B is blocked behind session A."
wait "$A_PID"
A_PID=""

set +e
wait "$B_PID"
B_EXIT=$?
B_PID=""
set -e
if [[ "$B_EXIT" -eq 0 ]]; then
  echo "FAIL: session B unexpectedly succeeded."
  cat "$B_LOG"
  exit 1
fi

if ! grep -q "Invalid estimate status transition: submitted to submitted" "$B_LOG"; then
  echo "FAIL: session B failed for an unexpected reason."
  cat "$B_LOG"
  exit 1
fi

RESULT="$(psql "$DB_URL" -X -Atq -v ON_ERROR_STOP=1 -c "
SELECT e.status || ':' || (
  SELECT count(*) FROM public.estimate_status_history h
  WHERE h.estimate_id = e.id
    AND h.from_status = 'draft'
    AND h.to_status = 'submitted'
)
FROM public.estimates e
WHERE e.id = '$ESTIMATE_ID';
")"

if [[ "$RESULT" != "submitted:1" ]]; then
  echo "FAIL: expected final state/history submitted:1, received '$RESULT'."
  exit 1
fi

echo "PASS: two independent sessions raced the same transition."
echo "PASS: session A committed; session B waited, then was rejected as stale."
echo "PASS: final estimate status is submitted and exactly one draft-to-submitted history row exists."
