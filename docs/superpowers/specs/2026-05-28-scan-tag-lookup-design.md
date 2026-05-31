# Scan Tag Lookup - Design (2026-05-28)

## Status

Draft - pending user review

## Summary

Add a top-level **Scan** tab to the staff app bottom navigation. Staff and riders can scan a laundry tag QR/barcode to identify the owner, order details, and current status without first searching for or opening an order.

This is a follow-up to the pickup/delivery proof work. The existing proof scanner validates a known order during delivery. This feature starts from the tag and resolves the order/customer.

## Problem

The app currently supports scanning as part of proof workflows, but not as a general lookup mode. In real laundry operations, staff may have a bag or tag in hand and need to answer:

- Whose laundry is this?
- What order does this tag belong to?
- Is this ready for delivery?
- Which customer/address should the rider deliver to?
- Is this tag unknown or already completed?

Searching manually by order ID or customer name is slower and more error-prone than scanning the tag.

## Goal

Make tag lookup a first-class workflow so staff and riders can scan a tag from anywhere in the main app and immediately see the owner/order details.

## Non-Goals

- Replacing the existing delivery proof scanner.
- Adding RFID or external scanner hardware support.
- Designing printed tag/sticker inventory.
- Changing the proof-event data model.
- Adding customer-facing QR flows.
- Solving backend sync conflicts for missing local orders.
- Adding manager-only audit tools.

## Bottom Navigation Changes

The bottom navigation should become:

```text
Home | Orders | Scan | Report | Account
```

Scan should be the center destination because it is an operational mode used by both in-shop staff and riders.

Recommended icons:

- Unselected: `Icons.qr_code_scanner_outlined`
- Selected: `Icons.qr_code_scanner`
- Label: `Scan`

Labels should always show so all five destinations remain understandable.

## User Flow

### Scan known tag

1. Staff taps **Scan** in the bottom navigation.
2. Scanner opens with camera view and manual entry fallback.
3. Staff scans the tag QR/barcode.
4. App looks up the scanned value in local orders.
5. App shows the owner/order result.

### Manual entry fallback

1. Staff taps **Enter tag manually**.
2. Staff enters order ID or tag ID.
3. App runs the same lookup path as a scanned value.

### Open full order

From the result screen, staff can tap **View order** to open the existing order details screen.

### Delivery-ready order

If the scanned order is `readyForDelivery`, riders should see a clear **Confirm delivery** action that continues into the existing delivery proof flow.

## Data Lookup Behavior

For the current app shape, lookup can start with the orders available in the dashboard/order stream or mock order list.

Lookup order:

1. Exact match on order ID.
2. Future: exact match on a dedicated tag ID field.
3. Future: repository/database lookup when local persistence is the source of truth.

Unknown scan behavior:

- Show **Tag not found**.
- Show the scanned value.
- Offer **Scan again** and **Enter manually**.

## Scan Result Screen

The result should show:

- Customer name
- Phone
- Address
- Order ID
- Service type
- Item count
- Current status
- Pickup/delivery time label
- Notes

Primary action by status:

| Status | Primary action |
|---|---|
| `pendingPickup` | View order |
| `inProgress` | View order |
| `readyForDelivery` | Confirm delivery |
| `completed` | View history |

## Rider Delivery Behavior

For riders, the scan result should reduce the chance of handing a bag to the wrong customer.

When the scanned order is ready for delivery:

1. Show customer and address prominently.
2. Show order ID and item count.
3. Allow continuing into delivery proof.
4. Preserve the existing requirement to capture delivery proof before completing the order.

## Error States

| Case | Behavior |
|---|---|
| Camera permission denied | Show permission help and manual entry fallback. |
| Unknown tag | Show `Tag not found`, scanned value, and retry/manual options. |
| Empty manual entry | Disable lookup until text is entered. |
| Completed order scanned | Show completed state and history/view-order action. |
| Local data unavailable | Show retry and explain that orders could not be loaded. |
| Wrong delivery stop | Show customer/order details so rider can detect mismatch before handoff. |

## Architecture Notes

Recommended new files:

```text
lib/src/orders/scan/
  scan_tag_tab.dart
  scan_result_card.dart
  tag_lookup.dart
```

Recommended tests:

```text
test/orders/scan/
  tag_lookup_test.dart
  scan_tag_tab_test.dart
  scan_result_card_test.dart
```

Reuse existing scanner support where possible:

- `lib/src/orders/proof/barcode_reader.dart`
- `lib/src/orders/proof/scanner_screen.dart`

If `scanner_screen.dart` is too delivery-specific, extract the common camera/manual-entry pieces into a shared scanner widget rather than duplicating camera code.

## Testing Strategy

### Unit tests

- Lookup returns an order for an exact order ID.
- Lookup returns null for an unknown tag.
- Lookup trims whitespace from manual entry.
- Future: lookup supports tag ID separately from order ID.

### Widget tests

- Scan tab renders camera/manual-entry UI.
- Fake scanner value shows a matching result.
- Unknown fake scanner value shows `Tag not found`.
- Result card shows customer, order ID, address, status, and item count.
- Ready-for-delivery result shows delivery action.
- Bottom navigation includes Scan as the center destination.

### Integration tests

- Scan a ready-for-delivery order, continue into delivery proof, and complete delivery.
- Scan a completed order and verify no completion action is offered.

## Success Criteria

1. Bottom navigation includes **Scan** as the center destination.
2. Staff can scan or manually enter a tag/order ID.
3. A known tag shows the matching owner/order details.
4. Unknown tags show a clear retry/manual-entry state.
5. Riders can continue from a ready-for-delivery result into the existing delivery proof flow.
6. Existing pickup/delivery proof flows keep working.
7. Tests cover lookup, scan result states, and bottom navigation rendering.

## Open Questions

- Should tag ID remain the same as order ID, or should `LaundryOrder` gain a separate `tagId` field?
- Should Scan open directly to camera, or should it first show a short scan landing panel?
- Should Account or Home show a recent scans list?
- When offline local data does not include the scanned order, should the app show only `Tag not found` or distinguish `Not synced on this device`?
