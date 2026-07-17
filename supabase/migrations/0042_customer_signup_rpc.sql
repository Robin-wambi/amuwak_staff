-- 0042_customer_signup_rpc.sql
-- Self-registration primitive for the customer app.
--
-- uganda_national_digits(): SQL mirror of Dart ugandaNationalDigits()
-- (packages/amuwak_core/lib/src/shared/phone.dart) — strip non-digits, drop a
-- leading 256 country code, then a single leading 0 trunk prefix. Parity is
-- asserted by a shared test-vector list (Dart side + the sibling pgTAP test).
-- No SQL caller today (see link_or_create_customer below); kept as the pinned
-- mirror of the Dart helper and for the deferred phone-claim flow.
--
-- link_or_create_customer(): on first authenticated session, create a customers
-- row linked to the caller's auth user. Idempotent: returns the existing link if
-- already linked. SECURITY DEFINER because a customer has no INSERT privilege on
-- customers under RLS (customers_write is in_shop/manager only, see 0007).
--
-- DELIBERATELY does NOT claim an existing unowned customers row by phone match.
-- Signup is email+password (0041), so p_phone is unverified caller input: a bare
-- digit match is not proof of phone ownership, and auto-linking on it would let
-- anyone who knows a walk-in customer's number inherit that customer's order
-- history, address and chat. Letting a walk-in see their pre-app history needs
-- proof of ownership first (phone OTP, or a staff-issued claim code) — deferred
-- to a follow-up. Until then a returning walk-in starts a fresh customer row and
-- staff merge it by hand.

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
  v_uid uuid := auth.uid();
  v_id  uuid;
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

  -- Create a fresh linked customer. ON CONFLICT keeps two concurrent
  -- first-session calls idempotent instead of raising 23505 on
  -- customers_auth_user_id_key (0041).
  INSERT INTO customers (name, phone, email, auth_user_id)
  VALUES (p_name, p_phone, NULLIF(btrim(p_email), ''), v_uid)
  ON CONFLICT (auth_user_id) WHERE auth_user_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    -- Lost the race above, or this auth user is linked to a soft-deleted row.
    SELECT id INTO v_id FROM customers
     WHERE auth_user_id = v_uid AND deleted_at IS NULL
     LIMIT 1;
  END IF;

  IF v_id IS NULL THEN
    RAISE EXCEPTION
      'link_or_create_customer: auth user % is linked to a deleted customer', v_uid;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION link_or_create_customer(text, text, text) FROM public, anon;
GRANT  EXECUTE ON FUNCTION link_or_create_customer(text, text, text) TO authenticated;
