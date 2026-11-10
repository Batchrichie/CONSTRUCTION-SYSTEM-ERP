#!/usr/bin/env bash
set -Eeuo pipefail

# Runs only against the disposable local Supabase database started by CI.
DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
COMPANY_ID="82000000-0000-4000-8000-000000000006"
USER_ID="81000000-0000-4000-8000-000000000006"
FISCAL_YEAR_ID="85000000-0000-4000-8000-000000000006"
PERIOD_ID="86000000-0000-4000-8000-000000000006"
IDEMPOTENCY_KEY="journal-draft-concurrency-once"
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
DELETE FROM public.audit_logs WHERE company_id = '$COMPANY_ID';
DELETE FROM public.journal_lines WHERE company_id = '$COMPANY_ID';
DELETE FROM public.journal_entries WHERE company_id = '$COMPANY_ID';
DELETE FROM private.journal_number_counters
WHERE company_id = '$COMPANY_ID' AND fiscal_year_id = '$FISCAL_YEAR_ID';
DELETE FROM public.accounting_periods WHERE company_id = '$COMPANY_ID';
DELETE FROM public.fiscal_years WHERE company_id = '$COMPANY_ID';
DELETE FROM public.company_memberships WHERE company_id = '$COMPANY_ID';
UPDATE public.chart_of_accounts SET parent_account_id = NULL WHERE company_id = '$COMPANY_ID';
DELETE FROM public.chart_of_accounts WHERE company_id = '$COMPANY_ID';
DELETE FROM public.companies WHERE id = '$COMPANY_ID';
DELETE FROM auth.users WHERE id = '$USER_ID';
SQL
  rm -f "$A_LOG" "$B_LOG"
}
trap cleanup EXIT

echo "Creating isolated journal-draft idempotency fixtures..."
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<SQL
INSERT INTO auth.users (
  id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '$USER_ID', 'authenticated', 'authenticated',
  'journal-draft-idempotency@example.test', 'test-password',
  now(), now(), now(), '{}'::jsonb, '{}'::jsonb
);

INSERT INTO public.companies (
  id, legal_name, display_name, base_currency, country_code, created_by
) VALUES (
  '$COMPANY_ID', 'Journal Draft Idempotency Test Ltd',
  'Journal Draft Idempotency Test', 'GHS', 'GH', '$USER_ID'
);

SELECT private.seed_default_chart_of_accounts('$COMPANY_ID');

INSERT INTO public.company_memberships (company_id, user_id, role_id, status, joined_at)
SELECT '$COMPANY_ID', '$USER_ID', id, 'active', now()
FROM public.roles WHERE code = 'owner';

INSERT INTO public.fiscal_years (
  id, company_id, year_code, start_date, end_date, status, created_by
) VALUES (
  '$FISCAL_YEAR_ID', '$COMPANY_ID', 'JRN-IDEM-2026',
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

echo "Session A acquires the idempotency lock and creates the first draft..."
PGAPPNAME=journal_draft_idempotency_holder psql "$DB_URL" -X -Atq -v ON_ERROR_STOP=1 >"$A_LOG" 2>&1 <<SQL &
BEGIN;
SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('$COMPANY_ID:$IDEMPOTENCY_KEY', 0)
);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$USER_ID', true);
SELECT public.create_journal_draft(
  '$COMPANY_ID',
  date '2026-01-15',
  'Concurrent draft idempotency test',
  jsonb_build_array(
    jsonb_build_object(
      'account_id', (SELECT id FROM public.chart_of_accounts
                     WHERE company_id = '$COMPANY_ID' AND account_code = '1110'),
      'debit', 250, 'credit', 0
    ),
    jsonb_build_object(
      'account_id', (SELECT id FROM public.chart_of_accounts
                     WHERE company_id = '$COMPANY_ID' AND account_code = '1120'),
      'debit', 0, 'credit', 250
    )
  ),
  'JOURNAL-DRAFT-IDEMPOTENCY-TEST',
  '$IDEMPOTENCY_KEY'
);
SELECT pg_sleep(5);
COMMIT;
SQL
A_PID=$!

holder_ready=0
for _ in $(seq 1 100); do
  if [[ "$(psql "$DB_URL" -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'journal_draft_idempotency_holder' AND wait_event = 'PgSleep'")" == "1" ]]; then
    holder_ready=1
    break
  fi
  sleep 0.1
done
if [[ "$holder_ready" != "1" ]]; then
  echo "FAIL: session A did not reach its lock hold point."
  cat "$A_LOG"
  exit 1
fi

echo "Session B submits the identical draft while session A holds the key lock..."
PGAPPNAME=journal_draft_idempotency_contender psql "$DB_URL" -X -Atq -v ON_ERROR_STOP=1 >"$B_LOG" 2>&1 <<SQL &
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$USER_ID', false);
SELECT public.create_journal_draft(
  '$COMPANY_ID',
  date '2026-01-15',
  'Concurrent draft idempotency test',
  jsonb_build_array(
    jsonb_build_object(
      'account_id', (SELECT id FROM public.chart_of_accounts
                     WHERE company_id = '$COMPANY_ID' AND account_code = '1110'),
      'debit', 250, 'credit', 0
    ),
    jsonb_build_object(
      'account_id', (SELECT id FROM public.chart_of_accounts
                     WHERE company_id = '$COMPANY_ID' AND account_code = '1120'),
      'debit', 0, 'credit', 250
    )
  ),
  'JOURNAL-DRAFT-IDEMPOTENCY-TEST',
  '$IDEMPOTENCY_KEY'
);
SQL
B_PID=$!

contender_blocked=0
for _ in $(seq 1 60); do
  if [[ "$(psql "$DB_URL" -X -Atq -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'journal_draft_idempotency_contender' AND wait_event_type = 'Lock'")" == "1" ]]; then
    contender_blocked=1
    break
  fi
  sleep 0.1
done
if [[ "$contender_blocked" != "1" ]]; then
  echo "FAIL: session B was not observed waiting for the idempotency lock."
  cat "$A_LOG" "$B_LOG"
  exit 1
fi

echo "Confirmed: session B waits until session A commits the first draft."
wait "$A_PID"
A_PID=""
wait "$B_PID"
B_PID=""

A_ID="$(grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$A_LOG" | tail -n 1 || true)"
B_ID="$(grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$B_LOG" | tail -n 1 || true)"

if [[ -z "$A_ID" || "$A_ID" != "$B_ID" ]]; then
  echo "FAIL: concurrent callers did not receive the same draft ID."
  echo "Session A: $A_ID"
  echo "Session B: $B_ID"
  cat "$A_LOG" "$B_LOG"
  exit 1
fi

RESULT="$(psql "$DB_URL" -X -Atq -v ON_ERROR_STOP=1 -c "
SELECT
  count(*) || ':' ||
  min(status) || ':' ||
  min(total_debit)::text || ':' ||
  (SELECT count(*) FROM public.journal_lines
   WHERE company_id = '$COMPANY_ID' AND journal_entry_id = '$A_ID')
FROM public.journal_entries
WHERE company_id = '$COMPANY_ID'
  AND idempotency_key = '$IDEMPOTENCY_KEY'
  AND id = '$A_ID';
")"

if [[ "$RESULT" != "1:draft:250.0000:2" ]]; then
  echo "FAIL: expected one balanced draft with two lines; received '$RESULT'."
  exit 1
fi

echo "PASS: both concurrent callers returned the same draft ID ($A_ID)."
echo "PASS: exactly one draft, two journal lines and the expected debit total exist."
