# Pickup & Delivery Proof — Design (2026-05-12)

## Status
Draft — pending user review

## Summary
Add QR-tag-based order tracking with photo + count proof at the two customer-facing bookends of a laundry order: **pickup** (at the customer's house) and **delivery** (back at the customer's house). The driver's phone generates the QR at pickup time; the same QR is scanned at delivery to verify the right bag reaches the right customer. Photo and count evidence is captured at both ends and stored locally on the device.

This is the first concrete dispute-resolution feature in the staff app and the foundation for later chain-of-custody work.

## Problem
Across the research summarized in [`docs/superpowers/research/2026-05-12-laundry-staff-feature-research.md`](../research/2026-05-12-laundry-staff-feature-research.md), the single most-cited operational failure in busy laundries is **mix-ups and lost items**, closely followed by **pickup/delivery disputes** ("the driver didn't pick up what we said he did" / "you delivered me the wrong bag"). Today Amuwak Staff has no way for a rider to capture what was picked up or to verify the right bag reaches the right customer at delivery — status transitions are blind taps.

## Goal
Make every pickup and delivery a scannable, photographed event with a numeric count, so:

- A bag that leaves the customer's house always has a tag that uniquely identifies its order.
- A bag delivered back is verified against that tag before the order can be marked completed.
- Pickup-time photos + count are available for visual comparison at delivery.
- Disputes have an evidence trail (photos + count + timestamp + handover photo) without requiring a backend.

## Non-Goals
- Backend persistence or sync (deferred per SPEC-000).
- Scanning at the two shop-floor transitions (received-at-shop, ready) — deferred.
- Itemized item lists (shirts/trousers/etc.) — total-count model only for M1.
- Customer signatures, customer-side phone interaction.
- WhatsApp confirmation messages (overlaps with B1; out of scope here).
- Re-capture / correction flow (deferred to a future B2 incident feature).
- A janitor sweep for orphan photo files left by interrupted captures.
- RFID, pre-printed sticker rolls, external scanner hardware.
- "View other order" navigation when scanning a foreign tag — the rider re-scans the correct tag instead of being routed away.

## Decisions Locked In
1. **Tag origin**: generated at pickup, on the driver's phone (QR encoding the orderId). The rider transfers the order id onto the bag — either by writing it on the bag with a marker, attaching a handwritten paper tag, or (if the shop has tags) tying a pre-printed numbered tag. The app does not assume the physical mark is itself a scannable QR.
2. **Item counting**: total count integer + 1–3 photos at pickup.
3. **Scan stages**: pickup and delivery only (the two bookends). Shop-floor transitions stay manual.
4. **Handoff flow**: rider photographs the handover; no customer interaction with the rider's phone.
5. **Architecture**: a `List<ProofEvent>` on `LaundryOrder` (not embedded `pickupProof` / `deliveryProof` fields) — future-proof for additional scan stages and an order-history view.

## Data Model

### New: `ProofEvent` (`lib/src/orders/proof_event.dart`)
```dart
enum ProofEventType { pickup, delivery }

class ProofEvent {
  final ProofEventType type;
  final DateTime capturedAt;
  final int count;
  final List<String> photoPaths; // local file paths under app docs
  final String? notes;
}
```
Implements value equality and `hashCode` matching the repo's existing pattern in [`lib/src/orders/order.dart`](../../../lib/src/orders/order.dart).

### Modified: `LaundryOrder`
- Gains `final List<ProofEvent> proofEvents` (defaults to `const []`).
- New helper getters:
  - `ProofEvent? get pickupProof` → first event of type `pickup`, or null.
  - `ProofEvent? get deliveryProof` → first event of type `delivery`, or null.
  - `bool get hasPickupProof`, `bool get hasDeliveryProof`.
- `copyWith` extended to take `List<ProofEvent>? proofEvents`.
- Value-equality and `hashCode` updated to include `proofEvents`.
- Existing `int itemCount` stays. It represents the **expected** count from the order; `pickupProof.count` is the **actual** count captured at pickup. A mismatch is informational, not blocking.

## File Layout

```
lib/src/orders/
  order.dart                    (modified)
  order_status.dart             (unchanged)
  order_details_screen.dart     (modified — wires the proof screens)
  proof_event.dart              (new)
  proof/
    pickup_capture_screen.dart  (new)
    delivery_capture_screen.dart(new)
    scanner_screen.dart         (new — wraps mobile_scanner)
    qr_display_widget.dart      (new — wraps qr_flutter)
    proof_photo_storage.dart    (new — narrow service; saves & compresses)
    barcode_reader.dart         (new — thin adapter over mobile_scanner)
```

## User Flow

### Pickup (status `pendingPickup`)
1. Rider opens order details → taps **Confirm pickup**.
2. `PickupCaptureScreen` opens with:
   - Order summary header (customer name, expected itemCount, address).
   - Count stepper (default 0; −/+ buttons; manual input allowed).
   - Photo grid: 1–3 photo slots, each opens the camera via `image_picker`.
   - Optional notes textfield.
   - **Confirm with customer** button — disabled until `count > 0 AND photos.length >= 1`.
3. Tap Confirm → screen flips to QR display:
   - Large QR encoding the `orderId` string.
   - Instruction text: "Tie tag #<short-id> to the bag and write the order number on it."
   - **Done** button.
4. Tap Done → app:
   - Calls `ProofPhotoStorage.save(...)` for each captured photo, getting back paths.
   - Appends `ProofEvent(type: pickup, capturedAt: now, count, photoPaths, notes)` to the order.
   - Transitions `status: pendingPickup → inProgress`.
   - Pops back to order details, which now shows a read-only pickup-proof panel.

### Delivery (status `readyForDelivery`)
1. Rider opens order details → taps **Deliver**.
2. `ScannerScreen` opens with the camera viewfinder AND a clearly visible **"Enter order ID instead"** button. Either path is treated as a first-class way to identify the bag — scanning is faster when a QR sticker is on the bag, manual entry is the primary path when the bag has only a handwritten number.
   - **Scan path — match** (decoded id == current order id) → continue.
   - **Scan path — wrong tag** → inline error message below the viewfinder: "This tag belongs to order #X, not #Y." The camera stays active so the rider can immediately re-scan (implicit retry). Navigating *to* the other order is deferred — see Non-Goals.
   - **Manual entry path** → text field validates entered id against the current order's id. Mismatch shows the same inline error.
3. `DeliveryCaptureScreen` opens with:
   - Pickup-proof reference panel: pickup count + photo thumbnails (tappable to view full size).
   - Photo grid for the handover photo (≥1 required).
   - Optional notes.
   - **Mark delivered** button — disabled until ≥1 handover photo captured.
4. Tap Mark delivered → app:
   - Saves photos via `ProofPhotoStorage`.
   - Appends `ProofEvent(type: delivery, ...)` to the order.
   - Transitions `status: readyForDelivery → completed`.
   - Pops back to order details.

### Already-captured states
If `hasPickupProof` (or `hasDeliveryProof`) is true, the corresponding button slot on order details renders a read-only summary instead:
```
Pickup captured · 09:42 · 12 items · 3 photos
```
Re-capture is intentionally not exposed in M1.

### History panel
Order details gains a "History" section listing both `ProofEvent`s in chronological order, with timestamp, type label, count, and thumbnails.

## Photo Storage

`ProofPhotoStorage` is the only class that knows where photos live. Contract:

```dart
abstract class ProofPhotoStorage {
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  });
}
```

Default implementation:
- Uses `path_provider` to resolve `<app_documents_dir>/proofs/<orderId>/`.
- Filename: `<eventType>_<unixMillis>_<index>.jpg`.
- Compresses incoming bytes with `flutter_image_compress` to a max edge of 1280px at JPEG quality 80 before writing.

Photos are not uploaded in M1. The interface is shaped so a future Firebase- or S3-backed implementation drops in without touching screen code.

## Edge Cases

| Case | Behavior |
|---|---|
| Bag has only a handwritten number, no scannable QR | Manual entry on `ScannerScreen` is the primary path; same validation as a scanned id. |
| Wrong tag scanned (id ≠ current order) | Inline error message naming both order numbers; camera stays active for immediate re-scan. |
| Camera permission denied | Capture/scanner screens show a permission-prompt panel with an "Open Settings" CTA. No silent failure. |
| Photo compression / save fails | The whole capture is rolled back (no partial `ProofEvent`); user sees a retry toast. |
| App killed mid-capture | Photos write to disk *before* `ProofEvent` is appended. On next launch any orphan photos stay on disk unreferenced. Acceptable in M1. |
| Pickup or delivery already captured | The button slot becomes a read-only summary. Re-capture not exposed. |
| Scanning the QR of an already-delivered order | Scanner accepts the scan; screen shows "This order is already delivered" with the existing delivery proof. No status change. |
| Order has no pickup proof but somehow reaches `readyForDelivery` | `DeliveryCaptureScreen` still functions; the reference panel shows "No pickup proof on file." Should not happen in normal flow. |

## Packages Added (`pubspec.yaml`)
- `mobile_scanner` — QR scanning.
- `qr_flutter` — QR display.
- `image_picker` — camera capture.
- `flutter_image_compress` — image compression.
- `path_provider` — app documents directory.

## Testing Strategy

**Unit tests** (alongside model files):
- `ProofEvent` value equality and `hashCode`.
- `LaundryOrder.copyWith(proofEvents:)`, helper getters with empty / pickup-only / both / delivery-only lists.

**Widget tests**:
- `PickupCaptureScreen`:
  - Confirm disabled until count > 0 AND ≥1 photo present.
  - Tap Done writes a pickup `ProofEvent` and transitions status.
  - QR display step renders the correct encoded value.
- `DeliveryCaptureScreen`:
  - Renders pickup count and photo thumbnails as reference.
  - Mark delivered disabled until ≥1 handover photo.
  - Writes a delivery `ProofEvent` and transitions to `completed`.
- `ScannerScreen`:
  - Wrong-tag path shows the right error and restores scanner.
  - Manual-id-fallback path validates and proceeds on match.

**Integration test**:
- Full pickup → in-progress → ready → delivery flow on a mock order. Asserts two `ProofEvent`s present and final status `completed`.

`mobile_scanner` and the camera are mocked at their service-boundary classes (`BarcodeReader`, `ProofPhotoStorage`) so widget tests don't need real hardware.

## Success Criteria
1. Rider cannot advance status from `pendingPickup` without a pickup `ProofEvent` (count > 0, ≥1 photo).
2. Rider cannot advance status from `readyForDelivery` without scanning (or manually entering) the matching tag and capturing ≥1 handover photo.
3. Order details shows a History panel rendering both `ProofEvent`s with timestamps, counts, and tappable thumbnails after both events are captured.
4. All existing tests in `test/` continue to pass; new unit, widget, and integration tests cover the new model fields, both capture screens, the scanner, and the end-to-end flow.
5. Photo file paths persist for the in-memory lifetime of the order; reopening the order details screen still shows the thumbnails (no re-capture needed within a session).

## Open Questions for the User
None at design time; all flow and model decisions are locked in (see "Decisions Locked In" above). Open items for the implementation plan:
- Exact package versions for the new dependencies (pinned by the writing-plans step).
- Whether `qr_display_widget` should also offer a "share QR as image" button — could be a stretch task or deferred.
