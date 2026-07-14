-- 0042_customer_signup_rpc.sql
-- Self-registration primitive for the customer app.
--
-- uganda_national_digits(): SQL mirror of Dart ugandaNationalDigits()
-- (packages/amuwak_core/lib/src/shared/phone.dart) — strip non-digits, drop a
-- leading 256 country code, then a single leading 0 trunk prefix. Parity is
-- asserted by a shared test-vector list (Dart side + the sibling pgTAP test).
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
