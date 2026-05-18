-- 0004_events_proofs_issues_shifts.sql
-- Append-only event tables (status transitions, proof captures) plus the
-- issue log and shift table.
--
-- `device_event_id` on order_status_events is a client-generated idempotency
-- key so that a queued offline status change which gets retried on reconnect
-- is applied at most once.

CREATE TABLE order_status_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        uuid NOT NULL REFERENCES orders(id),
  from_status     text,
  to_status       text NOT NULL,
  changed_by      uuid NOT NULL REFERENCES staff(id),
  changed_at      timestamptz NOT NULL DEFAULT now(),
  source          text NOT NULL CHECK (source IN ('qr_scan','manual','system')),
  device_event_id text UNIQUE
);

CREATE TABLE proof_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        uuid NOT NULL REFERENCES orders(id),
  type            text NOT NULL CHECK (type IN ('pickup','delivery')),
  captured_at     timestamptz NOT NULL,
  item_count      int NOT NULL,
  notes           text,
  captured_by     uuid NOT NULL REFERENCES staff(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- Enforce "one pickup proof, one delivery proof per order" — but only over
-- non-deleted rows so soft-delete + re-capture flows still work.
CREATE UNIQUE INDEX proof_events_one_per_type
  ON proof_events (order_id, type) WHERE deleted_at IS NULL;

CREATE TABLE proof_photos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  proof_event_id  uuid NOT NULL REFERENCES proof_events(id) ON DELETE CASCADE,
  storage_path    text NOT NULL,
  width           int,
  height          int,
  bytes           int,
  uploaded_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE issues (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        uuid REFERENCES orders(id),
  kind            text NOT NULL CHECK (kind IN ('damage','missing','complaint','other')),
  description     text NOT NULL,
  reported_by     uuid NOT NULL REFERENCES staff(id),
  reported_at     timestamptz NOT NULL DEFAULT now(),
  resolved_at     timestamptz,
  resolved_by     uuid REFERENCES staff(id)
);

CREATE TABLE shifts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id        uuid NOT NULL REFERENCES staff(id),
  started_at      timestamptz NOT NULL,
  started_lat     numeric,
  started_lng     numeric,
  ended_at        timestamptz,
  ended_lat       numeric,
  ended_lng       numeric
);
