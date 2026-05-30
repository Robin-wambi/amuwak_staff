-- 0002_staff_and_customers.sql
-- Identity tables: staff (linked 1:1 with auth.users via shared UUID) and customers.
--
-- staff.role drives RLS branching in later migrations. `must_change_pin` is set
-- when a manager resets a teammate's PIN, prompting the Flutter app to force a
-- PIN change on next sign-in.

CREATE TABLE staff (
  id              uuid PRIMARY KEY,
  username        text UNIQUE NOT NULL,
  display_name    text NOT NULL,
  phone           text,
  role            text NOT NULL CHECK (role IN ('driver','in_shop','manager')),
  active          boolean NOT NULL DEFAULT true,
  must_change_pin boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE customers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name            text NOT NULL,
  phone           text NOT NULL,
  address         text,
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
