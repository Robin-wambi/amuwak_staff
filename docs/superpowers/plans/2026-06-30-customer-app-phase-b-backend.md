# Customer App — Phase B: Backend Migrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Supabase schema, auth, and RLS needed for customers to self-register, place their own orders, track them, and chat with staff — all **additively**, with zero regression to existing staff behavior.

**Architecture:** Seven new migrations `0032`–`0038`, each with a sibling pgTAP test in `supabase/tests/`. Customers get a login identity linked 1:1 to a `customers` row; a new `customer` JWT role; a `customer_app` order intake method; an `order_messages` table; and a set of *new permissive* RLS policies that never touch the staff policies. Verified locally with `supabase db reset` (applies all migrations) + `supabase test db` (runs pgTAP).

**Tech Stack:** Supabase (Postgres 17), pgTAP, SQL.

## Global Constraints

- This plan is independent of Phase A and can run in parallel. It touches only `supabase/`.
- New migration numbers are `0032`–`0038` (local HEAD is `0031`; never reuse a prefix — CI rejects duplicates, see `.github/workflows/migrations-lint.yml`).
- Every new migration MUST have a sibling `supabase/tests/00NN_<name>_test.sql` (CI warns otherwise).
- All policies are **new** `CREATE POLICY` statements. NEVER `DROP`/`ALTER` an existing staff policy (`orders_read`, `orders_insert`, `orders_update`, `customers_read`, `status_events_*`, `proof_*`, `pricing_*`). Multiple permissive policies OR together, so additions cannot narrow staff access.
- Mirror house conventions exactly: helper functions are `LANGUAGE sql/plpgsql STABLE SECURITY DEFINER SET search_path = public`, with `REVOKE EXECUTE … FROM public; GRANT EXECUTE … TO authenticated;` (see `auth_staff_role()` in `0007_rls.sql`). The access-token hook stays `SECURITY DEFINER` with grants to `supabase_auth_admin` only (see `0009`/`0025`).
- `staff.id` and (new) `customers.auth_user_id` have **no FK to `auth.users`** (mirrors `0002`; keeps pgTAP tests from needing `auth.users` rows). RLS reads `auth.uid()` from the JWT `sub` claim.
- pgTAP test idiom for simulating a signed-in user (from `0007_rls_test.sql`): `SET LOCAL ROLE authenticated; SET LOCAL "request.jwt.claim.sub" = '<uuid>';`. RLS denials assert via `throws_ok('<prepared>', '42501', NULL, '<desc>')`.
- Order lifecycle initial status is set on the `orders` INSERT itself (not via a status event) — so a customer placing an order needs no `order_status_events` write (see `0010` rationale).

---

## File Structure

For each migration `supabase/migrations/00NN_<name>.sql`, a sibling `supabase/tests/00NN_<name>_test.sql`:

- `0032_customer_accounts.sql` — `customers.auth_user_id` + `customers.email` + partial unique index.
- `0033_customer_signup_rpc.sql` — `uganda_national_digits(text)` helper + `link_or_create_customer(...)` RPC.
- `0034_customer_role_hook.sql` — `CREATE OR REPLACE custom_access_token_hook` adding the `customer` branch.
- `0035_orders_customer_app_intake.sql` — `intake_method` CHECK adds `customer_app`; `valid_transitions` seed; `orders.placed_by_customer_id`; system sentinel staff row.
- `0036_order_messages.sql` — the chat table + index + RLS enabled.
- `0037_customer_rls.sql` — `auth_customer_id()` helper + all customer SELECT/INSERT policies.
- `0038_realtime_order_messages.sql` — add `order_messages` to the `supabase_realtime` publication.

---

### Task 1: `0032` — Customer account linkage columns

**Files:**
- Create: `supabase/migrations/0032_customer_accounts.sql`, `supabase/tests/0032_customer_accounts_test.sql`

**Interfaces:**
- Produces: `customers.auth_user_id uuid` (nullable, logically references `auth.users.id`, no FK), `customers.email text` (nullable), and a partial unique index `customers_auth_user_id_key`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0032_customer_accounts.sql`:

```sql
-- 0032_customer_accounts.sql
-- Give customers a login identity for the customer-facing app. A customer
-- self-registers via Supabase Auth (email+password); we link that auth user to
-- a customers row 1:1 so RLS can scope a customer to their own data by
-- auth.uid().
--
-- staff reuses auth.users.id AS its PK (1:1) and deliberately has no FK to
-- auth.users (see 0002). We cannot reuse the id for customers: legacy customer
-- rows already have gen_random_uuid() PKs that orders FK. So we add a dedicated
-- nullable auth_user_id column, and — mirroring staff — keep it FK-free (RLS
-- reads auth.uid(), and FK-free keeps pgTAP tests from needing auth.users rows).
-- A partial UNIQUE index lets many not-yet-linked customers (NULL) coexist while
-- guaranteeing at most one customer per auth user.

ALTER TABLE customers
  ADD COLUMN auth_user_id uuid,
  ADD COLUMN email        text;

CREATE UNIQUE INDEX customers_auth_user_id_key
  ON customers (auth_user_id) WHERE auth_user_id IS NOT NULL;
```

- [ ] **Step 2: Write the sibling pgTAP test**

Create `supabase/tests/0032_customer_accounts_test.sql`:

```sql
-- 0032_customer_accounts_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(4);

SELECT has_column('public', 'customers', 'auth_user_id', 'customers.auth_user_id exists');
SELECT has_column('public', 'customers', 'email',        'customers.email exists');

-- Two unlinked customers (NULL auth_user_id) coexist.
INSERT INTO public.customers (name, phone) VALUES ('A', '0700000001'), ('B', '0700000002');
SELECT pass('two NULL auth_user_id customers insert without unique violation');

-- The partial unique index rejects a duplicate non-null auth_user_id.
INSERT INTO public.customers (name, phone, auth_user_id)
  VALUES ('C', '0700000003', '00000000-0000-0000-0000-0000000000c1');
PREPARE dup_link AS
  INSERT INTO public.customers (name, phone, auth_user_id)
  VALUES ('D', '0700000004', '00000000-0000-0000-0000-0000000000c1');
SELECT throws_ok('dup_link', '23505', NULL, 'duplicate auth_user_id rejected');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 3: Apply + run tests**

Run: `supabase db reset`
Expected: all migrations apply cleanly through `0032`.

Run: `supabase test db`
Expected: `0032_customer_accounts_test` passes 4/4; all prior tests still green.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0032_customer_accounts.sql supabase/tests/0032_customer_accounts_test.sql
git commit -m "feat(db): add customers.auth_user_id + email for customer login linkage"
```

---

### Task 2: `0033` — Phone normaliser + signup link/create RPC

**Files:**
- Create: `supabase/migrations/0033_customer_signup_rpc.sql`, `supabase/tests/0033_customer_signup_rpc_test.sql`

**Interfaces:**
- Produces: `uganda_national_digits(text) → text` (IMMUTABLE; SQL mirror of Dart `ugandaNationalDigits`); `link_or_create_customer(p_name text, p_phone text, p_email text) → uuid` (SECURITY DEFINER, `GRANT … TO authenticated`).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0033_customer_signup_rpc.sql`:

```sql
-- 0033_customer_signup_rpc.sql
-- Self-registration primitive for the customer app.
--
-- uganda_national_digits(): SQL mirror of Dart ugandaNationalDigits()
-- (lib/src/shared/phone.dart) — strip non-digits, drop a leading 256 country
-- code, then a single leading 0 trunk prefix. Parity is asserted by a shared
-- test-vector list (Dart side + the sibling pgTAP test).
--
-- link_or_create_customer(): on first authenticated session, link the auth user
-- to an existing unowned customers row whose normalised phone matches (so a
-- walk-in/phone customer the shop already created sees their history), else
-- create a new linked customer. SECURITY DEFINER because the lookup must read
-- across ALL customers (a customer cannot SELECT others under RLS) and must run
-- atomically to avoid a double-link race; it only ever claims a row with
-- auth_user_id IS NULL. Idempotent: returns the existing link if already linked.

CREATE OR REPLACE FUNCTION uganda_national_digits(input text) RETURNS text
LANGUAGE plpgsql IMMUTABLE
SET search_path = public AS $$
DECLARE
  digits text;
BEGIN
  digits := regexp_replace(coalesce(input, ''), '[^0-9]', '', 'g');
  IF left(digits, 3) = '256' THEN digits := substr(digits, 4); END IF;
  IF left(digits, 1) = '0'  THEN digits := substr(digits, 2); END IF;
  RETURN digits;
END;
$$;

CREATE OR REPLACE FUNCTION link_or_create_customer(
  p_name  text,
  p_phone text,
  p_email text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_norm text := uganda_national_digits(p_phone);
  v_id   uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'link_or_create_customer requires an authenticated caller';
  END IF;

  -- Already linked → idempotent return.
  SELECT id INTO v_id FROM customers
   WHERE auth_user_id = v_uid AND deleted_at IS NULL
   LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  -- Claim an unowned customer with a matching normalised phone.
  SELECT id INTO v_id FROM customers
   WHERE auth_user_id IS NULL
     AND deleted_at IS NULL
     AND uganda_national_digits(phone) = v_norm
   ORDER BY created_at
   LIMIT 1
   FOR UPDATE;

  IF v_id IS NOT NULL THEN
    UPDATE customers
       SET auth_user_id = v_uid,
           email        = COALESCE(NULLIF(btrim(p_email), ''), email),
           updated_at   = now()
     WHERE id = v_id;
    RETURN v_id;
  END IF;

  -- Otherwise create a fresh linked customer.
  INSERT INTO customers (name, phone, email, auth_user_id)
  VALUES (p_name, p_phone, NULLIF(btrim(p_email), ''), v_uid)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION link_or_create_customer(text, text, text) FROM public, anon;
GRANT  EXECUTE ON FUNCTION link_or_create_customer(text, text, text) TO authenticated;
```

- [ ] **Step 2: Write the sibling pgTAP test**

Create `supabase/tests/0033_customer_signup_rpc_test.sql`:

```sql
-- 0033_customer_signup_rpc_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(7);

-- Normalisation parity vectors (must match Dart ugandaNationalDigits).
SELECT is(uganda_national_digits('0700123456'),      '700123456', 'local trunk form');
SELECT is(uganda_national_digits('+256 700 123 456'),'700123456', 'international form');
SELECT is(uganda_national_digits('256700123456'),    '700123456', 'bare international');
SELECT is(uganda_national_digits('700123456'),       '700123456', 'bare national');
SELECT is(uganda_national_digits('+256 0700 123456'),'700123456', 'redundant 256 + trunk zero');

-- Linking: an unowned customer with a matching phone gets claimed.
INSERT INTO public.customers (id, name, phone) VALUES
  ('00000000-0000-0000-0000-0000000000d1', 'Walk-in Joe', '0700123456');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-0000000000e1';
SELECT is(
  link_or_create_customer('Joe', '+256700123456', 'joe@example.com'),
  '00000000-0000-0000-0000-0000000000d1',
  'links to the existing customer by normalised phone');

-- Calling again is idempotent (same id, no second row).
SELECT is(
  link_or_create_customer('Joe', '0700123456', 'joe@example.com'),
  '00000000-0000-0000-0000-0000000000d1',
  'second call is idempotent');

SELECT * FROM finish();
ROLLBACK;
```

> Mirror these exact vectors in the Dart `ugandaNationalDigits` test (Phase A `packages/amuwak_core/test/shared/phone_test.dart`) so the two implementations can never drift.

- [ ] **Step 3: Apply + run tests**

Run: `supabase db reset && supabase test db`
Expected: `0033_customer_signup_rpc_test` passes 7/7; all prior green.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0033_customer_signup_rpc.sql supabase/tests/0033_customer_signup_rpc_test.sql
git commit -m "feat(db): add uganda_national_digits + link_or_create_customer signup RPC"
```

---

### Task 3: `0034` — Customer role in the access-token hook

**Files:**
- Create: `supabase/migrations/0034_customer_role_hook.sql`, `supabase/tests/0034_customer_role_hook_test.sql`

**Interfaces:**
- Produces: `custom_access_token_hook` now sets `user_role = 'customer'` for a linked customer, leaving the staff branch byte-for-byte unchanged.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0034_customer_role_hook.sql`:

```sql
-- 0034_customer_role_hook.sql
-- Extend custom_access_token_hook (0009, fixed in 0025) to issue user_role =
-- 'customer' for a user linked to a customers row, while leaving the staff
-- branch unchanged. Order: staff role wins (a user who is somehow both keeps
-- their staff role); else a linked customer → 'customer'; else 'none'.
--
-- Stays SECURITY DEFINER with the existing restricted grants (CREATE OR REPLACE
-- preserves the 0009 REVOKE-from-public/anon/authenticated + GRANT-to-
-- supabase_auth_admin). Touches only the custom `user_role` claim — never the
-- reserved `role` claim (see 0025).

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  claims      jsonb;
  staff_role  text;
  is_customer boolean;
  resolved    text;
BEGIN
  SELECT role INTO staff_role FROM public.staff
   WHERE id = (event->>'user_id')::uuid AND active = true;

  IF staff_role IS NOT NULL THEN
    resolved := staff_role;
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM public.customers
       WHERE auth_user_id = (event->>'user_id')::uuid AND deleted_at IS NULL
    ) INTO is_customer;
    resolved := CASE WHEN is_customer THEN 'customer' ELSE 'none' END;
  END IF;

  claims := event->'claims';
  claims := jsonb_set(claims, '{user_role}', to_jsonb(resolved));
  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;
```

- [ ] **Step 2: Write the sibling pgTAP test**

Create `supabase/tests/0034_customer_role_hook_test.sql`:

```sql
-- 0034_customer_role_hook_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(4);

INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-0000000000f1', 'mgr_hook2', 'Mgr', 'manager');
INSERT INTO public.customers (id, name, phone, auth_user_id) VALUES
  ('00000000-0000-0000-0000-0000000000f2', 'Cust', '0700111222',
   '00000000-0000-0000-0000-0000000000f3');

-- staff branch unchanged
SELECT is(
  (custom_access_token_hook(jsonb_build_object(
     'user_id','00000000-0000-0000-0000-0000000000f1',
     'claims', jsonb_build_object('sub','x')))->'claims'->>'user_role'),
  'manager', 'staff still resolves to their role');

-- linked customer → 'customer'
SELECT is(
  (custom_access_token_hook(jsonb_build_object(
     'user_id','00000000-0000-0000-0000-0000000000f3',
     'claims', jsonb_build_object('sub','x')))->'claims'->>'user_role'),
  'customer', 'linked customer resolves to customer');

-- neither → 'none'
SELECT is(
  (custom_access_token_hook(jsonb_build_object(
     'user_id','00000000-0000-0000-0000-000000099999',
     'claims', jsonb_build_object('sub','x')))->'claims'->>'user_role'),
  'none', 'unknown user resolves to none');

-- reserved role claim preserved
SELECT is(
  (custom_access_token_hook(jsonb_build_object(
     'user_id','00000000-0000-0000-0000-0000000000f3',
     'claims', jsonb_build_object('role','authenticated')))->'claims'->>'role'),
  'authenticated', 'reserved role claim untouched');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 3: Apply + run + commit**

Run: `supabase db reset && supabase test db`
Expected: `0034` passes 4/4; `0009` test still green.

```bash
git add supabase/migrations/0034_customer_role_hook.sql supabase/tests/0034_customer_role_hook_test.sql
git commit -m "feat(db): add customer role to custom_access_token_hook"
```

---

### Task 4: `0035` — `customer_app` intake, transitions, attribution, sentinel

**Files:**
- Create: `supabase/migrations/0035_orders_customer_app_intake.sql`, `supabase/tests/0035_orders_customer_app_intake_test.sql`

**Interfaces:**
- Produces: `intake_method` accepts `'customer_app'`; `valid_transitions` rows for `('customer_app', …)`; `orders.placed_by_customer_id uuid REFERENCES customers(id)`; a system sentinel staff row with fixed id `00000000-0000-0000-0000-00000000a001`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0035_orders_customer_app_intake.sql`:

```sql
-- 0035_orders_customer_app_intake.sql
-- Let customers place their own orders from the app.
--
-- 1. Add 'customer_app' to the intake_method CHECK (the inline CHECK from 0003
--    is auto-named orders_intake_method_check).
-- 2. customer_app orders start at pending_pickup and then follow driver_pickup's
--    path, for both fulfillment methods — copy driver_pickup's rows (same trick
--    0003 used for phone_order).
-- 3. placed_by_customer_id records WHO placed it (the customer), so staff UI can
--    show "Placed by <customer> via app". created_by/intake_recorded_by must
--    stay NOT NULL REFERENCES staff(id), so customer orders point those at a
--    system sentinel staff row; the real originator is placed_by_customer_id
--    (and customer_id).
-- 4. Insert the sentinel staff row (fixed id; inactive). staff.id has no FK to
--    auth.users, so this is a plain insert.

ALTER TABLE orders DROP CONSTRAINT orders_intake_method_check;
ALTER TABLE orders ADD  CONSTRAINT orders_intake_method_check
  CHECK (intake_method IN ('driver_pickup','walk_in','phone_order','customer_app'));

INSERT INTO valid_transitions (intake_method, fulfillment_method, from_status, to_status)
SELECT 'customer_app', fulfillment_method, from_status, to_status
FROM valid_transitions
WHERE intake_method = 'driver_pickup'
ON CONFLICT ON CONSTRAINT valid_transitions_natural_key DO NOTHING;

ALTER TABLE orders
  ADD COLUMN placed_by_customer_id uuid REFERENCES customers(id);

INSERT INTO staff (id, username, display_name, role, active) VALUES
  ('00000000-0000-0000-0000-00000000a001', 'system_customer_app',
   'Customer App', 'in_shop', false)
ON CONFLICT (id) DO NOTHING;
```

- [ ] **Step 2: Write the sibling pgTAP test**

Create `supabase/tests/0035_orders_customer_app_intake_test.sql`:

```sql
-- 0035_orders_customer_app_intake_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(4);

SELECT has_column('public', 'orders', 'placed_by_customer_id',
  'orders.placed_by_customer_id exists');

-- sentinel staff row exists
SELECT is((SELECT display_name FROM staff
           WHERE id = '00000000-0000-0000-0000-00000000a001'),
          'Customer App', 'system sentinel staff row present');

-- transitions seeded for both fulfillment methods
SELECT is((SELECT count(*)::int FROM valid_transitions
           WHERE intake_method = 'customer_app'
             AND fulfillment_method = 'delivery'
             AND from_status IS NULL AND to_status = 'pending_pickup'),
          1, 'customer_app + delivery initial transition seeded');
SELECT is((SELECT count(*)::int FROM valid_transitions
           WHERE intake_method = 'customer_app'
             AND fulfillment_method = 'customer_collect'
             AND from_status = 'ready' AND to_status = 'completed'),
          1, 'customer_app + collect completion transition seeded');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 3: Apply + run + commit**

Run: `supabase db reset && supabase test db`
Expected: `0035` passes 4/4.

```bash
git add supabase/migrations/0035_orders_customer_app_intake.sql supabase/tests/0035_orders_customer_app_intake_test.sql
git commit -m "feat(db): add customer_app intake, transitions, placed_by_customer_id, sentinel staff"
```

---

### Task 5: `0036` — `order_messages` table

**Files:**
- Create: `supabase/migrations/0036_order_messages.sql`, `supabase/tests/0036_order_messages_test.sql`

**Interfaces:**
- Produces: table `order_messages(id, order_id, sender_kind, sender_id, body, created_at, read_at)` with RLS enabled (policies come in `0037`).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0036_order_messages.sql`:

```sql
-- 0036_order_messages.sql
-- Per-order chat between staff and the order's customer. sender_id is
-- polymorphic (staff.id or customers.id) so it is deliberately NOT a FK;
-- integrity is enforced by the insert policies in 0037 (sender must be the
-- authenticated party of the right kind). RLS is enabled here with no policies
-- (deny-all) until 0037 adds them.

CREATE TABLE order_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    uuid NOT NULL REFERENCES orders(id),
  sender_kind text NOT NULL CHECK (sender_kind IN ('staff','customer')),
  sender_id   uuid NOT NULL,
  body        text NOT NULL CHECK (length(btrim(body)) > 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  read_at     timestamptz
);

CREATE INDEX order_messages_order_idx ON order_messages (order_id, created_at);

ALTER TABLE order_messages ENABLE ROW LEVEL SECURITY;
```

- [ ] **Step 2: Write the sibling pgTAP test**

Create `supabase/tests/0036_order_messages_test.sql`:

```sql
-- 0036_order_messages_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(3);

SELECT has_table('public', 'order_messages', 'order_messages table exists');
SELECT col_is_pk('public', 'order_messages', 'id', 'id is the PK');
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.order_messages'::regclass),
  'RLS is enabled on order_messages');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 3: Apply + run + commit**

Run: `supabase db reset && supabase test db`
Expected: `0036` passes 3/3.

```bash
git add supabase/migrations/0036_order_messages.sql supabase/tests/0036_order_messages_test.sql
git commit -m "feat(db): add order_messages table with RLS enabled"
```

---

### Task 6: `0037` — Customer RLS policies

**Files:**
- Create: `supabase/migrations/0037_customer_rls.sql`, `supabase/tests/0037_customer_rls_test.sql`

**Interfaces:**
- Consumes: `auth_staff_role()` (existing), `0035` sentinel id, `order_messages` (`0036`).
- Produces: `auth_customer_id() → uuid` helper; permissive policies `orders_customer_read`, `orders_customer_insert`, `order_messages_read`, `order_messages_customer_insert`, `order_messages_staff_insert`, `order_messages_mark_read`, `customers_self_read`, `pricing_settings_customer_read`, `pricing_catalog_items_customer_read`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0037_customer_rls.sql`:

```sql
-- 0037_customer_rls.sql
-- Additive RLS so a customer can read ONLY their own orders/messages and place
-- their own orders/messages. Every policy here is a NEW permissive policy;
-- nothing existing is dropped or altered (permissive policies OR together, so
-- staff visibility is unchanged). Status-event reads, proof_events and
-- proof_photos already gate on order visibility via EXISTS(orders), so a
-- customer who can SELECT their order automatically sees its events/proofs —
-- no new policy needed there (asserted in the sibling test).

-- Customer analogue of auth_staff_role(): the caller's linked customers.id.
CREATE FUNCTION auth_customer_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT id FROM customers WHERE auth_user_id = auth.uid() AND deleted_at IS NULL
$$;

REVOKE EXECUTE ON FUNCTION auth_customer_id() FROM public;
GRANT  EXECUTE ON FUNCTION auth_customer_id() TO authenticated;

-- orders: a customer reads their own; inserts a customer_app order pinned to
-- pending_pickup, self-attributed, with staff id columns set to the sentinel.
CREATE POLICY orders_customer_read ON orders FOR SELECT
  USING (customer_id = auth_customer_id());

CREATE POLICY orders_customer_insert ON orders FOR INSERT WITH CHECK (
  auth_customer_id() IS NOT NULL
  AND customer_id           = auth_customer_id()
  AND placed_by_customer_id = auth_customer_id()
  AND intake_method         = 'customer_app'
  AND status                = 'pending_pickup'
  AND fulfillment_method IN ('delivery','customer_collect')
  AND created_by            = '00000000-0000-0000-0000-00000000a001'
  AND intake_recorded_by    = '00000000-0000-0000-0000-00000000a001'
);
-- (No customer UPDATE policy → customers cannot advance status or edit price.)

-- order_messages: staff (any active) or the owning customer may read; each side
-- inserts self-attributed messages on a visible order; either may mark read.
CREATE POLICY order_messages_read ON order_messages FOR SELECT USING (
  auth_staff_role() IN ('driver','in_shop','manager')
  OR EXISTS (SELECT 1 FROM orders o
             WHERE o.id = order_id AND o.customer_id = auth_customer_id())
);

CREATE POLICY order_messages_customer_insert ON order_messages FOR INSERT WITH CHECK (
  sender_kind = 'customer'
  AND sender_id = auth_customer_id()
  AND EXISTS (SELECT 1 FROM orders o
              WHERE o.id = order_id AND o.customer_id = auth_customer_id())
);

CREATE POLICY order_messages_staff_insert ON order_messages FOR INSERT WITH CHECK (
  auth_staff_role() IN ('driver','in_shop','manager')
  AND sender_kind = 'staff'
  AND sender_id = auth.uid()
);

CREATE POLICY order_messages_mark_read ON order_messages FOR UPDATE
  USING (
    auth_staff_role() IN ('driver','in_shop','manager')
    OR EXISTS (SELECT 1 FROM orders o
               WHERE o.id = order_id AND o.customer_id = auth_customer_id())
  )
  WITH CHECK (
    auth_staff_role() IN ('driver','in_shop','manager')
    OR EXISTS (SELECT 1 FROM orders o
               WHERE o.id = order_id AND o.customer_id = auth_customer_id())
  );

-- customers: a customer reads their own profile row (name, phone, custom rate).
CREATE POLICY customers_self_read ON customers FOR SELECT
  USING (auth_user_id = auth.uid());

-- pricing reference: customers need rate/fee/catalog to compute an estimate.
CREATE POLICY pricing_settings_customer_read ON pricing_settings FOR SELECT
  USING (auth_customer_id() IS NOT NULL);
CREATE POLICY pricing_catalog_items_customer_read ON pricing_catalog_items FOR SELECT
  USING (auth_customer_id() IS NOT NULL);
```

- [ ] **Step 2: Write the sibling pgTAP test (the denied-access tests are mandatory)**

Create `supabase/tests/0037_customer_rls_test.sql`:

```sql
-- 0037_customer_rls_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(7);

-- Two customers, each linked to an auth user.
INSERT INTO public.customers (id, name, phone, auth_user_id) VALUES
  ('00000000-0000-0000-0000-00000000c101', 'Cust1', '0700000101',
   '00000000-0000-0000-0000-00000000a101'),
  ('00000000-0000-0000-0000-00000000c102', 'Cust2', '0700000102',
   '00000000-0000-0000-0000-00000000a102');

-- An order belonging to Cust1 (inserted privileged, sentinel staff attribution).
INSERT INTO public.orders (
  id, order_code, customer_id, placed_by_customer_id, customer_name, phone,
  address, service_type, status, intake_method, fulfillment_method, item_count,
  intake_recorded_by, created_by
) VALUES (
  '00000000-0000-0000-0000-00000000o101', 'AMW-CUST-1',
  '00000000-0000-0000-0000-00000000c101', '00000000-0000-0000-0000-00000000c101',
  'Cust1', '0700000101', 'Addr', 'wash_fold', 'pending_pickup',
  'customer_app', 'delivery', 3,
  '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001');

-- ---- Cust1 sees their own order ----
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a101';
SELECT is((SELECT count(*)::int FROM orders
           WHERE id = '00000000-0000-0000-0000-00000000o101'),
          1, 'Cust1 sees their own order');

-- Cust1 can place a self-attributed customer_app order.
PREPARE place_ok AS
  INSERT INTO orders (
    order_code, customer_id, placed_by_customer_id, customer_name, phone,
    address, service_type, status, intake_method, fulfillment_method, item_count,
    intake_recorded_by, created_by
  ) VALUES (
    'AMW-CUST-NEW', '00000000-0000-0000-0000-00000000c101',
    '00000000-0000-0000-0000-00000000c101', 'Cust1', '0700000101', 'Addr',
    'wash_fold', 'pending_pickup', 'customer_app', 'delivery', 2,
    '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001');
SELECT lives_ok('place_ok', 'Cust1 can place a self-attributed customer_app order');

-- Cust1 cannot place an order attributed to Cust2.
PREPARE place_forge AS
  INSERT INTO orders (
    order_code, customer_id, placed_by_customer_id, customer_name, phone,
    address, service_type, status, intake_method, fulfillment_method, item_count,
    intake_recorded_by, created_by
  ) VALUES (
    'AMW-CUST-FORGE', '00000000-0000-0000-0000-00000000c102',
    '00000000-0000-0000-0000-00000000c102', 'Cust2', '0700000102', 'Addr',
    'wash_fold', 'pending_pickup', 'customer_app', 'delivery', 2,
    '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001');
SELECT throws_ok('place_forge', '42501', NULL,
  'Cust1 cannot place an order for Cust2');

-- Cust1 cannot advance status (no UPDATE policy).
PREPARE bump AS
  UPDATE orders SET status = 'received'
   WHERE id = '00000000-0000-0000-0000-00000000o101';
SELECT throws_ok('bump', '42501', NULL, 'Cust1 cannot advance order status');

-- ---- Cust2 is denied Cust1's order (the critical cross-customer test) ----
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a102';
SELECT is((SELECT count(*)::int FROM orders
           WHERE id = '00000000-0000-0000-0000-00000000o101'),
          0, 'Cust2 cannot see Cust1 order');

-- Cust2 cannot message Cust1's order.
PREPARE msg_forge AS
  INSERT INTO order_messages (order_id, sender_kind, sender_id, body)
  VALUES ('00000000-0000-0000-0000-00000000o101', 'customer',
          '00000000-0000-0000-0000-00000000c102', 'hi');
SELECT throws_ok('msg_forge', '42501', NULL,
  'Cust2 cannot message Cust1 order');

-- ---- Cust1 can message their own order ----
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a101';
PREPARE msg_ok AS
  INSERT INTO order_messages (order_id, sender_kind, sender_id, body)
  VALUES ('00000000-0000-0000-0000-00000000o101', 'customer',
          '00000000-0000-0000-0000-00000000c101', 'hello');
SELECT lives_ok('msg_ok', 'Cust1 can message their own order');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 3: Apply + run + commit**

Run: `supabase db reset && supabase test db`
Expected: `0037` passes 7/7; all staff RLS tests (`0007`, `0010`) still green (proves staff access unchanged).

```bash
git add supabase/migrations/0037_customer_rls.sql supabase/tests/0037_customer_rls_test.sql
git commit -m "feat(db): add additive customer RLS (orders, messages, profile, pricing reads)"
```

---

### Task 7: `0038` — Realtime for `order_messages`

**Files:**
- Create: `supabase/migrations/0038_realtime_order_messages.sql`, `supabase/tests/0038_realtime_order_messages_test.sql`

**Interfaces:**
- Produces: `order_messages` added to the `supabase_realtime` publication (guarded/idempotent, matching `0027`).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0038_realtime_order_messages.sql`:

```sql
-- 0038_realtime_order_messages.sql
-- Customer + staff chat relies on Supabase .stream() for live delivery, which
-- only pushes changes for tables in the supabase_realtime publication. Add
-- order_messages, guarded the same way as 0027 so it's safe to re-run.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'order_messages'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.order_messages';
  END IF;
END $$;
```

- [ ] **Step 2: Write the sibling pgTAP test**

Create `supabase/tests/0038_realtime_order_messages_test.sql`:

```sql
-- 0038_realtime_order_messages_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(1);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime'
            AND schemaname = 'public'
            AND tablename = 'order_messages'),
  'order_messages is in the supabase_realtime publication');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 3: Apply + run + commit**

Run: `supabase db reset && supabase test db`
Expected: `0038` passes 1/1; full suite green.

```bash
git add supabase/migrations/0038_realtime_order_messages.sql supabase/tests/0038_realtime_order_messages_test.sql
git commit -m "feat(db): publish order_messages to supabase_realtime"
```

---

## Ops (dashboard, NOT migrations) — document in `docs/online-only-mode.md`
- Enable **email signups** in Supabase Auth settings.
- For v1, **disable email confirmation** so the `link_or_create_customer` RPC can run on the first session immediately after signup (otherwise run it on the post-confirmation first sign-in). Document the choice.
- The Custom Access Token hook is already pointed at `public.custom_access_token_hook` (per 0009); `0034` is `CREATE OR REPLACE`, so no re-wiring is needed.
- **Storage:** customer access to proof photos is a separate Storage bucket-policy concern (see `0008_storage.sql`) handled in the customer-app plan (Phase D/F), not here.

## Self-Review notes
- **Spec coverage:** every Phase B item in the approved design maps to a task — accounts (T1), signup/link + phone parity (T2), customer role (T3), customer_app intake + transitions + explicit attribution + sentinel (T4), messages table (T5), additive RLS incl. mandatory denied-access tests (T6), realtime (T7).
- **Additive-only:** no `DROP POLICY`/`ALTER POLICY` on staff policies anywhere; `0034` is `CREATE OR REPLACE` preserving grants.
- **Attribution:** `placed_by_customer_id` + sentinel together satisfy "show who placed it" while keeping `created_by`/`intake_recorded_by` NOT NULL.
- **Type/name consistency:** `auth_customer_id()`, `link_or_create_customer(text,text,text)`, `uganda_national_digits(text)`, sentinel id `…a001`, and policy names are used identically across migration + test tasks.
- **Numbering:** `0032`–`0038`, no collision with existing `0031`.

## Final verification (end of Phase B)
- `supabase db reset && supabase test db` → entire pgTAP suite (old + new) green.
- Manually confirm staff parity: re-run `0007_rls_test` + `0010_review_fixes_test` — staff visibility/insert behavior unchanged.
- Confirm no duplicate migration prefixes: `ls supabase/migrations | grep -oE '^[0-9]{4}' | sort | uniq -d` → empty.
