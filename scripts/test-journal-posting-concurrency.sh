#!/usr/bin/env bash
set -Eeuo pipefail

# This test uses only the disposable local Supabase database started by CI.
# Never point it at production or a shared development database.
DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
COMPANY_ID="82000000-0000-4000-8000-000000000005"
USER_ID="81000000-0000-4000-8000-000000000005"
FISCAL_YEAR_ID="85000000-0000-4000-8000-000000000005"
PERIOD_ID="86000000-0000-4000-8000-000000000005"

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

  if [[ -n "${JOURNAL_ID:-}" ]]; then
    psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<SQL >/dev/null
DELETE FROM public.audit_logs
WHERE company_id = '$COMPANY_ID'
  AND entity_table = 'journal_entries'
  AND entity_id = '$JOURNAL_ID';
DELETE FROM public.journal_lines
WHERE company_id = '$COMPANY_ID' AND journal_entry_id = '$JOURNAL_ID';
DELETE FROM public.journal_entries
WHERE company_id = '$COMPANY_ID' AND id = '$JOURNAL_ID';
DELETE FROM private.journal_number_counters
WHERE company_id = '$COMPANY_ID' AND fiscal_year_id = '$FISCAL_YEAR_ID';
SQL
  fi

  psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<SQL >/dev/null
DELETE FROM public.accounting_periods
WHERE company_id = '$COMPANY_ID' AND id = '$PERIOD_ID';
DELETE FROM public.fiscal_years
WHERE company_id = '$COMPANY_ID' AND id = '$FISCAL_YEAR_ID';
DELETE FROM public.company_memberships WHERE company_id = '$COMPANY_ID';
UPDATE public.chart_of_accounts SET parent_account_id = NULL WHERE company_id = '$COMPANY_ID';
DELETE FROM public.chart_of_accounts WHERE company_id = '$COMPANY_ID';
DELETE FROM public.companies WHERE id = '$COMPANY_ID';
DELETE FROM auth.users WHERE id = '$USER_ID';
SQL
  rm -f "$A_LOG" "$B_LOG"
}
trap cleanup EXIT

echo "Creating committed journal-posting fixtures in the disposable local database..."
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<SQL
INSERT INTO auth.users (
  id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '$USER_ID', 'authenticated', 'authenticated',
  'journal-concurrency@example.test', 'test-password',
  now(), now(), now(), '{}'::jsonb, '{}'::jsonb
);

INSERT INTO public.companies (
  id, legal_name, display_name, base_currency, country_code, created_by
) VALUES (
  '$COMPANY_ID', 'Journal Concurrency Test Ltd',
  'Journal Concurrency Test', 'GHS', 'GH', '$USER_ID'
);

SELECT private.seed_default_chart_of_accounts('$COMPANY_ID');

INSERT INTO public.company_memberships (company_id, user_id, role_id, status, joined_at)
SELECT '$COMPANY_ID', '$USER_ID', id, 'active', now()
FROM public.roles WHERE code = 'owner';

INSERT INTO public.fiscal_years (
  id, company_id, year_code, start_date, end_date, status, created_by
) VALUES (
  '$FISCAL_YEAR_ID', '$COMPANY_ID', 'JRN-CONC-2026',
  date '2026-01-01', date '2026-12-31', 'open', '$USER_ID'
);

INSERT INTO public.accounting_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, status
) VALUES (
  '$PERIOD_ID', '$COMPANY_ID', '$FISCAL_YEAR_ID', 1, 'January',
  date '2026-01-01', date '2026-01-31', 'open'
);
SQL

JOURNAL_ID="$(psql "$DB_URL" -X -Atq -v ON_ERROR_STOP=1 <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$USER_ID', false) AS jwt_sub \gset
SELECT public.create_journal_draft(
  '$COMPANY_ID',
  date '2026-01-15',
  'Concurrent duplicate posting test',
  jsonb_build_array(
    jsonb_build_object(
      'account_id', (SELECT id FROM public.chart_of_accounts
                     WHERE company_id = '$COMPANY_ID' AND account_code = '1110'),
      'debit', 125, 'credit', 0
    ),
    jsonb_build_object(
      'account_id', (SELECT id FROM public.chart_of_accounts
                     WHERE company_id = '$COMPANY_ID' AND account_code = '1120'),
      'debit', 0, 'credit', 125
    )
  ),
  'JOURNAL-CONCURRENCY-TEST',
  'journal-post-concurrency-once'
);
RESET ROLE;
SQL
)"

if [[ -z "$JOURNAL_ID" ]]; then
  echo "FAIL: the test journal draft was not created."
  exit 1
fi

echo "Starting session A and holding the journal row lock..."
PGAPPNAME=journal_post_concurrency_holder psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 >"$A_LOG" 2>&1 <<SQL &
BEGIN;
SELECT id FROM public.journal_entries WHERE id = '$JOURNAL_ID' FOR UPDATE;
SELECT pg_sleep(6);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$USER_ID', true);
SELECT public.post_journal_entry('$JOURNAL_ID');
COMMIT;
SQL
A_PID=$!

holder_ready=0
for _ in $(seq 1 100); do
  if [[ "$(psql "$DB_URL" -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'journal_post_concurrency_holder' AND wait_event = 'PgSleep'")" == "1" ]]; then
    holder_ready=1
    break
  fi
  sleep 0.1
done
if [[ "$holder_ready" != "1" ]]; then
  echo "FAIL: session A did not reach its journal-lock hold point."
  cat "$A_LOG"
  exit 1
fi

echo "Starting session B to post the same journal concurrently..."
PGAPPNAME=journal_post_concurrency_contender psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 >"$B_LOG" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$USER_ID', true);
SELECT public.post_journal_entry('$JOURNAL_ID');
COMMIT;
SQL
B_PID=$!

contender_blocked=0
for _ in $(seq 1 60); do
  if [[ "$(psql "$DB_URL" -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'journal_post_concurrency_contender' AND wait_event_type = 'Lock'")" == "1" ]]; then
    contender_blocked=1
    break
  fi
  sleep 0.1
done
if [[ "$contender_blocked" != "1" ]]; then
  echo "FAIL: session B was not observed waiting on the journal row lock."
  cat "$A_LOG" "$B_LOG"
  exit 1
fi

echo "Confirmed: session B is blocked behind session A."
wait "$A_PID"
A_PID=""
wait "$B_PID"
B_PID=""

A_NUMBER="$(grep -Eo 'JRN-[0-9]{4}-[0-9]{6}' "$A_LOG" | tail -n 1 || true)"
B_NUMBER="$(grep -Eo 'JRN-[0-9]{4}-[0-9]{6}' "$B_LOG" | tail -n 1 || true)"
if [[ -z "$A_NUMBER" || "$A_NUMBER" != "$B_NUMBER" ]]; then
  echo "FAIL: concurrent requests did not return the same journal number."
  echo "Session A: $A_NUMBER"
  echo "Session B: $B_NUMBER"
  cat "$A_LOG" "$B_LOG"
  exit 1
fi

RESULT="$(psql "$DB_URL" -X -Atq -v ON_ERROR_STOP=1 -c "
SELECT
  e.status || ':' ||
  (SELECT count(*) FROM public.journal_lines l
   WHERE l.company_id = e.company_id AND l.journal_entry_id = e.id) || ':' ||
  (SELECT count(*) FROM public.general_ledger gl
   WHERE gl.company_id = e.company_id AND gl.journal_entry_id = e.id) || ':' ||
  (SELECT count(*) FROM public.audit_logs al
   WHERE al.company_id = e.company_id
     AND al.entity_table = 'journal_entries'
     AND al.entity_id = e.id::text
     AND al.action = 'journal.posted') || ':' ||
  (SELECT next_number FROM private.journal_number_counters c
   WHERE c.company_id = e.company_id AND c.fiscal_year_id = '$FISCAL_YEAR_ID')
FROM public.journal_entries e
WHERE e.company_id = '$COMPANY_ID' AND e.id = '$JOURNAL_ID';
")"

if [[ "$RESULT" != "posted:2:2:1:2" ]]; then
  echo "FAIL: expected posted:2:2:1:2, received '$RESULT'."
  exit 1
fi

echo "PASS: both sessions returned the same journal number ($A_NUMBER)."
echo "PASS: exactly one posting, two ledger lines, one posting audit record and one counter increment."
