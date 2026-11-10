begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(21);

-- Exercise the public journal RPCs using authenticated JWT claims. All fixtures
-- are transaction-scoped and rolled back at the end of the test.
create temporary table _journal_fixture (
  company_id uuid not null,
  owner_id uuid not null,
  viewer_id uuid not null,
  fiscal_year_id uuid not null,
  period_id uuid not null,
  cash_account_id uuid,
  bank_account_id uuid,
  journal_id uuid,
  restricted_journal_id uuid
) on commit drop;

insert into _journal_fixture (
  company_id, owner_id, viewer_id, fiscal_year_id, period_id
)
values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
        gen_random_uuid(), gen_random_uuid());

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select owner_id, 'authenticated', 'authenticated',
       'journal-owner-' || owner_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _journal_fixture;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select viewer_id, 'authenticated', 'authenticated',
       'journal-viewer-' || viewer_id::text || '@example.test', '', now(),
       '{}'::jsonb, '{}'::jsonb
from _journal_fixture;

insert into public.companies (
  id, legal_name, display_name, base_currency, country_code, created_by
)
select company_id, 'Journal Test Company', 'Journal Test',
       'GHS', 'GH', owner_id
from _journal_fixture;

select private.seed_default_chart_of_accounts(company_id)
from _journal_fixture;

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.owner_id, r.id, 'active', now()
from _journal_fixture f
cross join public.roles r
where r.code = 'owner';

insert into public.company_memberships (
  company_id, user_id, role_id, status, joined_at
)
select f.company_id, f.viewer_id, r.id, 'active', now()
from _journal_fixture f
cross join public.roles r
where r.code = 'viewer';

insert into public.fiscal_years (
  id, company_id, year_code, start_date, end_date, status, created_by
)
select fiscal_year_id, company_id, 'JRN-' || left(company_id::text, 8),
       date '2026-01-01', date '2026-12-31', 'open', owner_id
from _journal_fixture;

insert into public.accounting_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, status
)
select period_id, company_id, fiscal_year_id, 1, 'January',
       date '2026-01-01', date '2026-01-31', 'open'
from _journal_fixture;

update _journal_fixture f
set cash_account_id = a.id
from public.chart_of_accounts a
where a.company_id = f.company_id and a.account_code = '1110';

update _journal_fixture f
set bank_account_id = a.id
from public.chart_of_accounts a
where a.company_id = f.company_id and a.account_code = '1120';

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _journal_fixture),
  true
);

update _journal_fixture
set journal_id = public.create_journal_draft(
  company_id,
  date '2026-01-15',
  'Journal posting integrity test',
  jsonb_build_array(
    jsonb_build_object('account_id', cash_account_id, 'debit', 100, 'credit', 0),
    jsonb_build_object('account_id', bank_account_id, 'debit', 0, 'credit', 100)
  ),
  'TEST-REFERENCE',
  'phase-7-3-idempotency-key'
);

select extensions.ok(
  (select journal_id is not null from _journal_fixture),
  'A valid balanced journal draft is created'
);

select extensions.is(
  (select status from public.journal_entries
   where id = (select journal_id from _journal_fixture)),
  'draft'::text,
  'A newly created journal remains a draft until explicitly posted'
);

select extensions.is(
  (select total_debit from public.journal_entries
   where id = (select journal_id from _journal_fixture)),
  100::numeric,
  'Draft totals are calculated from validated journal lines'
);

select extensions.is(
  public.create_journal_draft(
    (select company_id from _journal_fixture),
    date '2026-01-15',
    'Journal posting integrity test',
    jsonb_build_array(
      jsonb_build_object('account_id', (select cash_account_id from _journal_fixture), 'debit', 100, 'credit', 0),
      jsonb_build_object('account_id', (select bank_account_id from _journal_fixture), 'debit', 0, 'credit', 100)
    ),
    'TEST-REFERENCE',
    'phase-7-3-idempotency-key'
  ),
  (select journal_id from _journal_fixture),
  'A repeated idempotency key and identical payload return the original draft'
);

select extensions.throws_ok(
  format(
    'select public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb,%L,%L)',
    (select company_id from _journal_fixture),
    '2026-01-15',
    'Changed payload',
    jsonb_build_array(
      jsonb_build_object('account_id', (select cash_account_id from _journal_fixture), 'debit', 90, 'credit', 0),
      jsonb_build_object('account_id', (select bank_account_id from _journal_fixture), 'debit', 0, 'credit', 90)
    )::text,
    'TEST-REFERENCE',
    'phase-7-3-idempotency-key'
  ),
  '23505',
  'Idempotency key has already been used with a different journal payload',
  'Reusing an idempotency key with a different payload is rejected'
);

select extensions.throws_ok(
  format(
    'select public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb)',
    (select company_id from _journal_fixture),
    '2026-01-15',
    'Unbalanced journal',
    jsonb_build_array(
      jsonb_build_object('account_id', (select cash_account_id from _journal_fixture), 'debit', 100, 'credit', 0),
      jsonb_build_object('account_id', (select bank_account_id from _journal_fixture), 'debit', 0, 'credit', 90)
    )::text
  ),
  '23514',
  'Journal is not balanced. Debits: 100.0000, credits: 90.0000',
  'An unbalanced journal draft is rejected'
);

select extensions.throws_ok(
  format(
    'select public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb)',
    (select company_id from _journal_fixture),
    '2026-01-15',
    'Invalid journal line',
    jsonb_build_array(
      jsonb_build_object('account_id', (select cash_account_id from _journal_fixture), 'debit', 10, 'credit', 10),
      jsonb_build_object('account_id', (select bank_account_id from _journal_fixture), 'debit', 0, 'credit', 10)
    )::text
  ),
  '22023',
  'Each journal line must have either a positive debit or a positive credit, not both (line 1)',
  'A journal line cannot contain both a debit and a credit'
);

select extensions.is(
  public.post_journal_entry((select journal_id from _journal_fixture)),
  'JRN-2026-000001'::text,
  'Posting assigns the first sequential journal number for the fiscal year'
);

select extensions.is(
  (select status from public.journal_entries
   where id = (select journal_id from _journal_fixture)),
  'posted'::text,
  'Successful posting changes the journal status to posted'
);

select extensions.is(
  public.post_journal_entry((select journal_id from _journal_fixture)),
  'JRN-2026-000001'::text,
  'Repeating a post request returns the existing journal number'
);

update _journal_fixture
set restricted_journal_id = public.create_journal_draft(
  company_id,
  date '2026-01-16',
  'Permission boundary test',
  jsonb_build_array(
    jsonb_build_object('account_id', cash_account_id, 'debit', 25, 'credit', 0),
    jsonb_build_object('account_id', bank_account_id, 'debit', 0, 'credit', 25)
  )
);

select set_config(
  'request.jwt.claim.sub',
  (select viewer_id::text from _journal_fixture),
  true
);

select extensions.throws_ok(
  format(
    'select public.post_journal_entry(%L::uuid)',
    (select restricted_journal_id from _journal_fixture)
  ),
  '42501',
  'You do not have permission to post journals for this company',
  'A read-only company member cannot post a journal'
);

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _journal_fixture),
  true
);

-- An account disabled before draft creation must not be selectable.
update public.chart_of_accounts
set is_active = false
where id = (select bank_account_id from _journal_fixture);

select extensions.throws_ok(
  format(
    'select public.create_journal_draft(%L::uuid,%L::date,%L,%L::jsonb)',
    (select company_id from _journal_fixture),
    '2026-01-18',
    'Inactive account draft',
    jsonb_build_array(
      jsonb_build_object('account_id',(select cash_account_id from _journal_fixture),'debit',10,'credit',0),
      jsonb_build_object('account_id',(select bank_account_id from _journal_fixture),'debit',0,'credit',10)
    )::text
  ),
  '22023',
  'Account on line 2 is unavailable for manual journal posting',
  'An inactive account cannot be used when creating a journal draft'
);

update public.chart_of_accounts
set is_active = true
where id = (select bank_account_id from _journal_fixture);

-- A valid draft must be rechecked if its account is disabled before posting.
create temporary table _activation_fixture (
  journal_id uuid not null
) on commit drop;

insert into _activation_fixture
select public.create_journal_draft(
  (select company_id from _journal_fixture),
  date '2026-01-19',
  'Account deactivation before posting',
  jsonb_build_array(
    jsonb_build_object('account_id',(select cash_account_id from _journal_fixture),'debit',15,'credit',0),
    jsonb_build_object('account_id',(select bank_account_id from _journal_fixture),'debit',0,'credit',15)
  )
);

update public.chart_of_accounts
set is_active = false
where id = (select bank_account_id from _journal_fixture);

select extensions.throws_ok(
  format(
    'select public.post_journal_entry(%L::uuid)',
    (select journal_id from _activation_fixture)
  ),
  'P0001',
  'A journal line uses an inactive or non-postable account',
  'Posting rejects a draft whose account was deactivated after draft creation'
);

update public.chart_of_accounts
set is_active = true
where id = (select bank_account_id from _journal_fixture);

select extensions.is(
  public.reverse_journal_entry(
    (select journal_id from _journal_fixture),
    date '2026-01-20',
    'Posting integrity reversal test'
  ),
  'JRN-2026-000002'::text,
  'Reversal creates and posts a sequential opposite journal'
);

select extensions.is(
  (select status from public.journal_entries
   where id = (select journal_id from _journal_fixture)),
  'reversed'::text,
  'The original journal is marked reversed without being deleted'
);

select extensions.is(
  (select count(*)::integer from public.journal_entries r
   where r.reversal_of_journal_id = (select journal_id from _journal_fixture)
     and r.status = 'posted'),
  1,
  'The reversal is linked to exactly one posted reversing journal'
);

select extensions.ok(
  not exists (
    (
      select account_id, line_number, debit, credit
      from public.journal_lines
      where journal_entry_id = (select journal_id from _journal_fixture)
      except
      select account_id, line_number, credit, debit
      from public.journal_lines
      where journal_entry_id = (
        select id from public.journal_entries
        where reversal_of_journal_id = (select journal_id from _journal_fixture)
      )
    )
    union all
    (
      select account_id, line_number, credit, debit
      from public.journal_lines
      where journal_entry_id = (
        select id from public.journal_entries
        where reversal_of_journal_id = (select journal_id from _journal_fixture)
      )
      except
      select account_id, line_number, debit, credit
      from public.journal_lines
      where journal_entry_id = (select journal_id from _journal_fixture)
    )
  ),
  'Every reversal line mirrors its original account, line number, debit and credit exactly'
);

select extensions.is(
  (select count(*)::integer from public.general_ledger
   where company_id = (select company_id from _journal_fixture)),
  4,
  'Both original and reversing journal lines remain in the general ledger'
);

select extensions.is(
  (select balance from public.account_balances
   where company_id = (select company_id from _journal_fixture)
     and account_code = '1110'),
  0::numeric,
  'The original and reversing cash entries net to zero'
);

select extensions.is(
  (select balance from public.account_balances
   where company_id = (select company_id from _journal_fixture)
     and account_code = '1120'),
  0::numeric,
  'The original and reversing bank entries net to zero'
);

select extensions.throws_ok(
  format(
    'select public.reverse_journal_entry(%L::uuid,%L::date,%L)',
    (select journal_id from _journal_fixture),
    '2026-01-21',
    'Duplicate reversal attempt'
  ),
  'P0001',
  'Only a posted journal entry can be reversed',
  'A journal cannot be reversed more than once'
);

select * from extensions.finish();
rollback;
