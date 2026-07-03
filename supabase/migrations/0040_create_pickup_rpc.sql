-- 0040_create_pickup_rpc.sql
-- Replace the temporary "rider = manager" access (0039) with a least-privilege,
-- purpose-built RPC for creating a pickup.
--
-- Background: a rider (role='driver') creating a New Pickup must write a
-- `customers` row (blocked by customers_write, 0007) and an `orders` row (the
-- orders_insert driver branch already allows it, but requires assigned_driver =
-- self, which the client omitted). 0039 unblocked this by collapsing driver into
-- manager everywhere — far more access than the workflow needs (it also granted
-- delete-any-order, staff writes, pricing writes).
--
-- This migration:
--   1. RESTORES auth_staff_role() to its original behaviour (a driver is a
--      driver again) — reverting 0039. Every RLS policy returns to its intended
--      least-privilege shape.
--   2. Adds create_pickup(), a SECURITY DEFINER RPC that atomically upserts the
--      customer + inserts the order with server-set attribution. Drivers get NO
--      new direct table access — they can only create a pickup through this
--      validated function. Mirrors the house pattern of next_order_code() (0017)
--      and the planned link_or_create_customer() (customer-app phase B).

-- 1. Revert the 0039 remap: a driver's role is reported as-is again.
CREATE OR REPLACE FUNCTION auth_staff_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT role FROM staff WHERE id = auth.uid() AND active = true
$$;

REVOKE EXECUTE ON FUNCTION auth_staff_role() FROM public;
GRANT  EXECUTE ON FUNCTION auth_staff_role() TO authenticated;

-- 2. create_pickup: atomic customer-upsert + order-insert for the New Pickup
-- flow. The caller supplies the customer fields and the order's descriptive +
-- frozen-pricing fields as JSON; the function owns order_code (via
-- next_order_code), the initial status, and the audit/assignment columns.
--
-- SECURITY DEFINER lets it write `customers` (which drivers cannot write
-- directly) and mint an order code, but only AFTER confirming the caller is an
-- active staff member. assigned_driver is set to the caller only for the driver
-- role (satisfying the assigned_driver trigger, 0011/0014, which requires an
-- active driver); in_shop/manager creators leave it NULL.
--
-- Idempotent: a retry with the same p_order->>'id' returns the existing order's
-- code without minting a new one or duplicating rows.
CREATE FUNCTION create_pickup(p_customer jsonb, p_order jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_caller      uuid := auth.uid();
  v_role        text := auth_staff_role();
  v_customer_id uuid := (p_customer->>'id')::uuid;
  v_order_id    uuid := (p_order->>'id')::uuid;
  v_code        text;
  v_assigned    uuid;
BEGIN
  IF v_caller IS NULL OR v_role IS NULL THEN
    RAISE EXCEPTION 'create_pickup requires an active staff caller';
  END IF;
  IF v_customer_id IS NULL OR v_order_id IS NULL THEN
    RAISE EXCEPTION 'create_pickup requires customer id and order id';
  END IF;

  -- Upsert the customer (bypasses customers_write via SECURITY DEFINER; only
  -- reachable after the staff check above). Intentional shared-CRM behaviour:
  -- passing an existing customer id overwrites the stored
  -- name/phone/address/notes/custom_rate_per_kg_ugx. Customers are shared,
  -- non-owned records (this mirrors the unscoped customers_write RLS policy for
  -- in_shop/manager), so any active staff caller -- including a driver via this
  -- RPC -- may update a known id, including billing-relevant fields. This is
  -- deliberate, not a per-owner write.
  INSERT INTO customers (
    id, name, phone, address, notes, custom_rate_per_kg_ugx, created_at, updated_at
  ) VALUES (
    v_customer_id,
    p_customer->>'name',
    p_customer->>'phone',
    p_customer->>'address',
    p_customer->>'notes',
    (p_customer->>'custom_rate_per_kg_ugx')::numeric,
    COALESCE((p_customer->>'created_at')::timestamptz, now()),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    name                   = EXCLUDED.name,
    phone                  = EXCLUDED.phone,
    address                = EXCLUDED.address,
    notes                  = EXCLUDED.notes,
    custom_rate_per_kg_ugx = EXCLUDED.custom_rate_per_kg_ugx,
    updated_at             = now();

  -- Idempotent order create: a retry with the same id returns the existing code.
  SELECT o.order_code INTO v_code FROM orders o WHERE o.id = v_order_id;
  IF v_code IS NOT NULL THEN
    RETURN jsonb_build_object('order_id', v_order_id, 'order_code', v_code);
  END IF;

  v_code     := next_order_code();
  v_assigned := CASE WHEN v_role = 'driver' THEN v_caller ELSE NULL END;

  INSERT INTO orders (
    id, order_code, customer_id, customer_name, phone, address,
    service_type, status, intake_method, fulfillment_method, item_count, notes,
    scheduled_for, rate_per_kg_snapshot_ugx, estimated_weight_kg, final_weight_kg,
    line_items, manual_adjustment_ugx, delivery_fee_snapshot_ugx, is_express,
    express_flat_snapshot_ugx, express_pct_snapshot, total_ugx,
    assigned_driver, intake_recorded_by, created_by, created_at, updated_at
  ) VALUES (
    v_order_id, v_code, v_customer_id,
    p_order->>'customer_name', p_order->>'phone', p_order->>'address',
    p_order->>'service_type', 'pending_pickup',
    COALESCE(p_order->>'intake_method', 'driver_pickup'),
    COALESCE(p_order->>'fulfillment_method', 'delivery'),
    (p_order->>'item_count')::int, COALESCE(p_order->>'notes', ''),
    (p_order->>'scheduled_for')::timestamptz,
    COALESCE((p_order->>'rate_per_kg_snapshot_ugx')::numeric, 0),
    (p_order->>'estimated_weight_kg')::numeric,
    (p_order->>'final_weight_kg')::numeric,
    COALESCE(p_order->'line_items', '[]'::jsonb),
    COALESCE((p_order->>'manual_adjustment_ugx')::int, 0),
    COALESCE((p_order->>'delivery_fee_snapshot_ugx')::int, 0),
    COALESCE((p_order->>'is_express')::boolean, false),
    COALESCE((p_order->>'express_flat_snapshot_ugx')::int, 0),
    COALESCE((p_order->>'express_pct_snapshot')::numeric, 0),
    COALESCE((p_order->>'total_ugx')::int, 0),
    v_assigned, v_caller, v_caller, now(), now()
  );

  RETURN jsonb_build_object('order_id', v_order_id, 'order_code', v_code);
END;
$$;

REVOKE EXECUTE ON FUNCTION create_pickup(jsonb, jsonb) FROM public;
GRANT  EXECUTE ON FUNCTION create_pickup(jsonb, jsonb) TO authenticated;
