# Scan Tag Lookup Research - 2026-05-28

Research synthesis for adding a primary Scan entry point to Amuwak Staff. This builds on the earlier laundry staff research and the pickup/delivery proof design.

## Existing Product Context

- The staff app already uses QR/barcode scanning for delivery proof.
- The current proof flow verifies a tag against a known order when the rider is already inside an order detail flow.
- Staff also need the reverse flow: scan a physical tag first, then identify the owner/order.
- Riders need the same lookup during delivery when they have the bag/tag in hand and need to confirm the customer details quickly.

## Related Existing Docs

- `docs/superpowers/research/2026-05-12-laundry-staff-feature-research.md`
- `docs/superpowers/specs/2026-05-12-pickup-delivery-proof-design.md`
- `docs/superpowers/plans/2026-05-12-pickup-delivery-proof.md`

## Operational Problem

Laundry staff and riders often encounter a tagged bag away from the order screen:

- A staff member finds a bag and needs to know whose it is.
- A rider is making deliveries and needs to confirm the customer before handoff.
- A tag is present, but the staff member does not remember the order number.
- The bag may be in the shop, on a route, or at the customer's location.

In these moments, search-first workflows are slower than scan-first workflows.

## User Needs

### In-shop staff

- Scan a tag and identify the customer.
- See order status and service type.
- Confirm item count, notes, and current workflow stage.
- Open the full order details if more action is needed.

### Riders

- Scan a tag before delivery handoff.
- Confirm customer name, phone, and address.
- Confirm the bag belongs to the delivery stop.
- Continue into delivery confirmation when the order is ready for delivery.

## Product Implication

Scan should become a top-level operational mode, not only a step inside delivery proof.

Recommended bottom navigation:

```text
Home | Orders | Scan | Report | Account
```

## Reuse Opportunities

The app already has scanning infrastructure that should be reused or extended:

- `lib/src/orders/proof/barcode_reader.dart`
- `lib/src/orders/proof/scanner_screen.dart`
- `mobile_scanner` dependency
- existing fake camera view support for widget tests

## Key Design Decision

The new scan feature should scan first, then look up the order by scanned tag/order id.

The existing delivery-proof scanner should remain focused on validating a known order during handoff.

## Risks

- The scanned value may not map to a current local order.
- Offline mode may not have every order in the local database yet.
- The same tag could be scanned by both shop staff and riders, so the result screen must be role-neutral.
- The Scan tab must not become a dumping ground for every barcode-related action.

## Recommendation

Create a new Scan tab that:

- Opens from the center of the bottom navigation.
- Scans a tag or accepts manual tag entry.
- Resolves the scanned value to an order.
- Shows a compact owner/order result.
- Offers context-aware actions based on status.
