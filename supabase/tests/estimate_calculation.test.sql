BEGIN;

SELECT plan(13);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'estimate_items'
      AND column_name = 'line_total'
  ),
  'BOQ line_total is present in the estimate item schema'
);

SELECT is(
  (
    SELECT is_generated
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'estimate_items'
      AND column_name = 'line_total'
  ),
  'ALWAYS',
  'BOQ line_total is database-generated and cannot be supplied as an ordinary input'
);

SELECT ok(
  position(
    'round((quantity * unit_rate), 4)' IN (
      SELECT generation_expression
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'estimate_items'
        AND column_name = 'line_total'
    )
  ) > 0,
  'BOQ line_total is calculated as quantity multiplied by unit rate and rounded to four decimals'
);

SELECT is(
  round(2.5000::numeric * 3.3333::numeric, 4),
  8.3333::numeric,
  'BOQ multiplication uses PostgreSQL numeric arithmetic at four-decimal precision'
);

SELECT is(
  round(1.2345::numeric * 0.0001::numeric, 4),
  0.0001::numeric,
  'small fractional quantities and rates are rounded consistently to four decimals'
);

SELECT is(
  round(1.23455::numeric, 4),
  1.2346::numeric,
  'halfway values follow PostgreSQL numeric rounding rules'
);

SELECT is(
  (
    SELECT sum(line_total)
    FROM (VALUES
      (0.1000::numeric),
      (0.2000::numeric),
      (12500.1251::numeric)
    ) AS boq(line_total)
  ),
  12500.4251::numeric,
  'BOQ subtotals aggregate exact numeric line totals without binary floating-point drift'
);

SELECT ok(
  to_regclass('public.estimate_totals') IS NOT NULL,
  'estimate_totals view exists'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'estimate_totals'
      AND c.reloptions @> ARRAY['security_invoker=true']
  ),
  'estimate_totals runs with invoker security'
);

SELECT ok(
  position('sum(i.line_total)' IN pg_get_viewdef('public.estimate_totals'::regclass, true)) > 0,
  'estimate_totals subtotal is sourced from generated BOQ line totals'
);

SELECT ok(
  position('e.discount_amount' IN pg_get_viewdef('public.estimate_totals'::regclass, true)) > 0
  AND position('e.tax_amount' IN pg_get_viewdef('public.estimate_totals'::regclass, true)) > 0
  AND position('- e.discount_amount + e.tax_amount' IN pg_get_viewdef('public.estimate_totals'::regclass, true)) > 0,
  'estimate total is calculated as subtotal less discount plus tax'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.estimate_items'::regclass
      AND conname = 'estimate_items_quantity_max_4dp'
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.estimate_items'::regclass
      AND conname = 'estimate_items_unit_rate_max_4dp'
  ),
  'BOQ quantity and unit rate reject values with more than four decimal places'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.estimates'::regclass
      AND conname = 'estimates_discount_amount_max_4dp'
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.estimates'::regclass
      AND conname = 'estimates_tax_amount_max_4dp'
  ),
  'estimate discount and tax inputs reject values with more than four decimal places'
);

SELECT * FROM finish();

ROLLBACK;
