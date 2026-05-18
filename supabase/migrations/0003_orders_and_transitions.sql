-- 0003_orders_and_transitions.sql
-- Orders table plus the valid_transitions matrix that drives the status state
-- machine. Seeding lives at the bottom of the migration (not in seed.sql) so
-- that `supabase db push` populates the matrix on every environment without an
-- extra step.

CREATE TABLE orders (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_code          text UNIQUE NOT NULL,
  customer_id         uuid REFERENCES customers(id),
  customer_name       text NOT NULL,
  phone               text NOT NULL,
  address             text NOT NULL,
  service_type        text NOT NULL,
  status              text NOT NULL,
  intake_method       text NOT NULL
    CHECK (intake_method IN ('driver_pickup','walk_in','phone_order')),
  fulfillment_method  text NOT NULL
    CHECK (fulfillment_method IN ('delivery','customer_collect')),
  item_count          int NOT NULL CHECK (item_count > 0),
  notes               text NOT NULL DEFAULT '',
  scheduled_for       timestamptz,
  assigned_driver     uuid REFERENCES staff(id),
  intake_recorded_by  uuid NOT NULL REFERENCES staff(id),
  created_by          uuid NOT NULL REFERENCES staff(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz
);

CREATE INDEX orders_status_idx          ON orders (status)          WHERE deleted_at IS NULL;
CREATE INDEX orders_assigned_driver_idx ON orders (assigned_driver) WHERE deleted_at IS NULL;

-- valid_transitions: synthetic PK (required for PowerSync sync of reference
-- data) plus a UNIQUE NULLS NOT DISTINCT on the natural key so we can store
-- NULL in `from_status` to mean "initial state allowed". NULLS NOT DISTINCT is
-- a Postgres 15+ feature; Supabase ships Postgres 15+.
CREATE TABLE valid_transitions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intake_method       text NOT NULL,
  fulfillment_method  text NOT NULL,
  from_status         text,
  to_status           text NOT NULL,
  CONSTRAINT valid_transitions_natural_key
    UNIQUE NULLS NOT DISTINCT (intake_method, fulfillment_method, from_status, to_status)
);

-- Seed the transition matrix. NULL from_status marks legal initial states.
INSERT INTO valid_transitions (intake_method, fulfillment_method, from_status, to_status) VALUES
  -- walk_in + customer_collect: received → in_progress → ready → completed
  ('walk_in',       'customer_collect', NULL,               'received'),
  ('walk_in',       'customer_collect', 'received',         'in_progress'),
  ('walk_in',       'customer_collect', 'in_progress',      'ready'),
  ('walk_in',       'customer_collect', 'ready',            'completed'),

  -- walk_in + delivery: received → in_progress → ready → out_for_delivery → completed
  ('walk_in',       'delivery',         NULL,               'received'),
  ('walk_in',       'delivery',         'received',         'in_progress'),
  ('walk_in',       'delivery',         'in_progress',      'ready'),
  ('walk_in',       'delivery',         'ready',            'out_for_delivery'),
  ('walk_in',       'delivery',         'out_for_delivery', 'completed'),

  -- driver_pickup + customer_collect: pending_pickup → received → in_progress → ready → completed
  ('driver_pickup', 'customer_collect', NULL,               'pending_pickup'),
  ('driver_pickup', 'customer_collect', 'pending_pickup',   'received'),
  ('driver_pickup', 'customer_collect', 'received',         'in_progress'),
  ('driver_pickup', 'customer_collect', 'in_progress',      'ready'),
  ('driver_pickup', 'customer_collect', 'ready',            'completed'),

  -- driver_pickup + delivery: pending_pickup → received → in_progress → ready → out_for_delivery → completed
  ('driver_pickup', 'delivery',         NULL,               'pending_pickup'),
  ('driver_pickup', 'delivery',         'pending_pickup',   'received'),
  ('driver_pickup', 'delivery',         'received',         'in_progress'),
  ('driver_pickup', 'delivery',         'in_progress',      'ready'),
  ('driver_pickup', 'delivery',         'ready',            'out_for_delivery'),
  ('driver_pickup', 'delivery',         'out_for_delivery', 'completed')
ON CONFLICT ON CONSTRAINT valid_transitions_natural_key DO NOTHING;

-- phone_order shares driver_pickup's transitions; expand by copy.
INSERT INTO valid_transitions (intake_method, fulfillment_method, from_status, to_status)
SELECT 'phone_order', fulfillment_method, from_status, to_status
FROM valid_transitions
WHERE intake_method = 'driver_pickup'
ON CONFLICT ON CONSTRAINT valid_transitions_natural_key DO NOTHING;
