-- 0045_order_messages.sql
-- Per-order chat between staff and the order's customer. sender_id is
-- polymorphic (staff.id or customers.id) so it is deliberately NOT a FK;
-- integrity is enforced by the insert policies in 0046 (sender must be the
-- authenticated party of the right kind). RLS is enabled here with no policies
-- (deny-all) until 0046 adds them.

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
