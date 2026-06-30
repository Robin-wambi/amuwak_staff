-- 0031_orders_payment_collected.sql
-- Records how much CASH has actually been collected against an order, so the
-- Daily Report can distinguish money in hand (collected) from money still owed
-- (outstanding = total_ugx - payment_amount_ugx). Before this, a "completed"
-- order was assumed paid; it only meant delivered.
--
-- Single source of truth: we store the cumulative amount collected, NOT a
-- paid/unpaid status. Paid / partial / unpaid is derived at render time from
-- payment_amount_ugx vs total_ugx, so it can never drift from the amount or
-- from a later total change (final weight recorded). Same chokepoint philosophy
-- as total_ugx (see OrdersRepository.recomputeOrderTotal).
--
-- House style: integer UGX money with a >= 0 CHECK (see total_ugx /
-- manual_adjustment_ugx in 0019). DEFAULT 0 backfills existing rows as
-- "nothing collected yet"; the Dart layer always supplies a real value on write.
--
-- IF NOT EXISTS makes this idempotent so `supabase db push` reconciles an
-- environment that already had the column added out-of-band as a no-op.
--
-- No RLS change: orders_update (migration 0010) gates UPDATEs by role and driver
-- assignment, not by column, so a driver recording payment on their own assigned
-- order is already covered. The pricing-write gate (0024) is on the pricing
-- tables, not on orders columns, so it does not apply here.

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS payment_amount_ugx integer NOT NULL DEFAULT 0
    CHECK (payment_amount_ugx >= 0);
