-- 0021_expenses.sql
-- Daily consumables / operational expenditure. Each row is a standalone, dated
-- expense (detergent, packaging, fuel, airtime/misc) the staff log against the
-- day's revenue; the Daily Report nets these against earned revenue to show
-- profit. No per-order link by design — consumables are bought in bulk.
--
-- Follows the house style: integer UGX money, soft-delete via deleted_at, audit
-- columns, and RLS with the role check embedded in USING/WITH CHECK via
-- auth_staff_role() (see 0007_rls.sql / 0019_order_pricing.sql).

CREATE TABLE expenses (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category     text NOT NULL CHECK (category IN
                 ('detergent','packaging','fuel','airtime_misc')),
  amount_ugx   integer NOT NULL CHECK (amount_ugx > 0),
  note         text NOT NULL DEFAULT '',
  spent_at     timestamptz NOT NULL DEFAULT now(),  -- the day it counts against
  recorded_by  uuid REFERENCES staff(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  deleted_at   timestamptz
);

-- The report reads "today"; index the live rows by the day they count against.
CREATE INDEX expenses_spent_at_idx ON expenses (spent_at) WHERE deleted_at IS NULL;

-- RLS: any signed-in staff may read/record/soft-delete expenses (no role gate
-- beyond "is staff", matching customers_read / pricing_settings). recorded_by is
-- set by the Dart layer to the acting staff; there is no self-attribution CHECK
-- here because expenses are an operational ledger any staff can maintain.
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY expenses_read ON expenses FOR SELECT
  USING (auth_staff_role() IN ('driver','in_shop','manager'));

CREATE POLICY expenses_insert ON expenses FOR INSERT
  WITH CHECK (auth_staff_role() IN ('driver','in_shop','manager'));

-- UPDATE is for soft-delete (and any future edit); DELETE is intentionally
-- omitted so rows are tombstoned, never hard-deleted.
CREATE POLICY expenses_update ON expenses FOR UPDATE
  USING      (auth_staff_role() IN ('driver','in_shop','manager'))
  WITH CHECK (auth_staff_role() IN ('driver','in_shop','manager'));

-- Realtime so the report's Expenses card updates live in-session, same as
-- orders/customers. Membership of supabase_realtime is otherwise an ops step
-- (see repository_providers.dart); do it here too so a fresh env is correct.
-- Guarded: a re-run, or a non-Supabase environment without the publication,
-- must not fail the migration.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.expenses;
EXCEPTION
  WHEN duplicate_object THEN NULL;  -- already in the publication
  WHEN undefined_object THEN NULL;  -- publication absent (non-Supabase env)
END $$;
