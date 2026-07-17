-- 0041_customer_accounts.sql
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
