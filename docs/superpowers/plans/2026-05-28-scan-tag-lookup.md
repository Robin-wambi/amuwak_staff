# Scan Tag Lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a top-level Scan tab that lets staff and riders scan a laundry tag QR/barcode and see the matching owner/order details.

**Design source:** `docs/superpowers/specs/2026-05-28-scan-tag-lookup-design.md`

**Architecture:** Reuse the existing scanner adapter/fake-camera boundary. Add a small lookup layer that maps scanned values to orders. Add a Scan tab to the bottom navigation and render a result card with status-aware actions.

**Out of scope:**

- Backend tag registry changes.
- New sync conflict handling.
- RFID/external scanner hardware.
- Replacing the existing pickup/delivery proof scanner.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/src/dashboard/staff_dashboard_screen.dart` | Modify | Add Scan as center bottom-nav destination and route tab index to Scan tab |
| `lib/src/orders/scan/tag_lookup.dart` | Create | Pure lookup helpers for scanned values |
| `lib/src/orders/scan/scan_result_card.dart` | Create | Owner/order result UI |
| `lib/src/orders/scan/scan_tag_tab.dart` | Create | Scanner/manual-entry tab UI |
| `test/orders/scan/tag_lookup_test.dart` | Create | Unit tests for lookup behavior |
| `test/orders/scan/scan_result_card_test.dart` | Create | Widget tests for result states |
| `test/orders/scan/scan_tag_tab_test.dart` | Create | Widget tests for scan/manual-entry behavior |
| `test/dashboard/staff_dashboard_screen_test.dart` | Modify | Bottom-nav test includes center Scan tab |

---

## Pre-flight

- [ ] **Step 0.1: Confirm working tree state**

Run:

```bash
git status --short
```

Expected: only intentional local changes. If unrelated changes exist, do not overwrite them.

- [ ] **Step 0.2: Read the design spec**

Read:

```text
docs/superpowers/specs/2026-05-28-scan-tag-lookup-design.md
```

- [ ] **Step 0.3: Run the current focused tests**

Run individually on this Windows host:

```bash
flutter test test/dashboard/staff_dashboard_screen_test.dart
flutter test test/orders/proof/scanner_screen_test.dart
```

Expected: baseline passes before adding Scan tab.

---

## Task 1: Add pure tag lookup helper

**Files:**

- Create `lib/src/orders/scan/tag_lookup.dart`
- Create `test/orders/scan/tag_lookup_test.dart`

- [ ] **Step 1.1: Write failing tests**

Cover:

- Exact order ID match returns the order.
- Unknown value returns null.
- Leading/trailing whitespace is ignored.
- Empty input returns null.

- [ ] **Step 1.2: Implement lookup helper**

Recommended API:

```dart
LaundryOrder? findOrderByScannedTag({
  required String scannedValue,
  required List<LaundryOrder> orders,
});
```

For now, match against `order.orderId`.

- [ ] **Step 1.3: Run tests**

```bash
flutter test test/orders/scan/tag_lookup_test.dart
```

- [ ] **Step 1.4: Commit**

```bash
git add lib/src/orders/scan/tag_lookup.dart test/orders/scan/tag_lookup_test.dart
git commit -m "Add tag lookup helper for scanned order ids"
```

---

## Task 2: Add scan result card

**Files:**

- Create `lib/src/orders/scan/scan_result_card.dart`
- Create `test/orders/scan/scan_result_card_test.dart`

- [ ] **Step 2.1: Write widget tests**

Cover:

- Shows customer name, order ID, service type, address, phone, item count, and status.
- Shows **Confirm delivery** for `readyForDelivery`.
- Shows **View order** for non-delivery states.
- Shows completed/history wording for `completed`.

- [ ] **Step 2.2: Implement card**

Keep the card mobile-first and consistent with current order cards.

Recommended constructor:

```dart
class ScanResultCard extends StatelessWidget {
  const ScanResultCard({
    super.key,
    required this.order,
    required this.onViewOrder,
    required this.onConfirmDelivery,
  });
}
```

- [ ] **Step 2.3: Run tests**

```bash
flutter test test/orders/scan/scan_result_card_test.dart
```

- [ ] **Step 2.4: Commit**

```bash
git add lib/src/orders/scan/scan_result_card.dart test/orders/scan/scan_result_card_test.dart
git commit -m "Add scan result card for owner lookup"
```

---

## Task 3: Add Scan tab UI

**Files:**

- Create `lib/src/orders/scan/scan_tag_tab.dart`
- Create `test/orders/scan/scan_tag_tab_test.dart`

- [ ] **Step 3.1: Write widget tests**

Cover:

- Renders scan/manual-entry UI.
- Fake scanned value resolves to an order result.
- Unknown scanned value shows `Tag not found`.
- Manual entry resolves through the same lookup path.
- Scan again clears the current result/error.

- [ ] **Step 3.2: Implement tab**

Recommended constructor:

```dart
class ScanTagTab extends StatefulWidget {
  const ScanTagTab({
    super.key,
    required this.orders,
    required this.onOpenOrder,
    required this.onConfirmDelivery,
    required this.cameraViewBuilder,
  });
}
```

Use the existing `CameraViewBuilder` seam for tests and production scanner wiring.

- [ ] **Step 3.3: Run tests**

```bash
flutter test test/orders/scan/scan_tag_tab_test.dart
```

- [ ] **Step 3.4: Commit**

```bash
git add lib/src/orders/scan/scan_tag_tab.dart test/orders/scan/scan_tag_tab_test.dart
git commit -m "Add scan tag lookup tab"
```

---

## Task 4: Add Scan to bottom navigation

**Files:**

- Modify `lib/src/dashboard/staff_dashboard_screen.dart`
- Modify `test/dashboard/staff_dashboard_screen_test.dart`

- [ ] **Step 4.1: Update bottom navigation**

Change nav order to:

```text
Home | Orders | Scan | Report | Account
```

Index mapping:

```text
0 Home
1 Orders
2 Scan
3 Report
4 Account
```

Use:

```dart
NavigationDestination(
  icon: Icon(Icons.qr_code_scanner_outlined),
  selectedIcon: Icon(Icons.qr_code_scanner),
  label: 'Scan',
)
```

- [ ] **Step 4.2: Route the Scan tab**

For the current mock-data branch, pass `_orders` to `ScanTagTab`.

For the Riverpod/sync branch, pass orders from `ordersStreamProvider`.

- [ ] **Step 4.3: Update quick action Report**

The dashboard quick action **Report** should select tab index `3`, not `2`.

- [ ] **Step 4.4: Update tests**

Dashboard bottom-nav tests should verify:

- There are five destinations.
- Scan label is present.
- Scan icon is present.
- Tapping Scan changes app bar title to `Scan`.
- Tapping Report still changes app bar title to `Daily report`.

- [ ] **Step 4.5: Run focused tests**

```bash
flutter test test/dashboard/staff_dashboard_screen_test.dart
flutter test test/orders/scan/scan_tag_tab_test.dart
```

- [ ] **Step 4.6: Commit**

```bash
git add lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
git commit -m "Add Scan as center bottom navigation destination"
```

---

## Task 5: Wire delivery-ready action

**Files:**

- Modify `lib/src/dashboard/staff_dashboard_screen.dart`
- Modify `lib/src/orders/scan/scan_tag_tab.dart`
- Modify relevant tests

- [ ] **Step 5.1: Reuse existing delivery flow**

When a scan result is `readyForDelivery`, the **Confirm delivery** action should continue into the existing delivery proof path.

If the current code only exposes delivery proof from `OrderDetailsScreen`, start by opening order details. A later task can extract a shared delivery-confirmation method.

- [ ] **Step 5.2: Test ready-for-delivery action**

Add a test that scans a ready-for-delivery order and verifies the action is available.

- [ ] **Step 5.3: Commit**

```bash
git add lib/src/dashboard/staff_dashboard_screen.dart lib/src/orders/scan/scan_tag_tab.dart test/
git commit -m "Wire scan results into delivery-ready action"
```

---

## Task 6: Final verification

- [ ] **Step 6.1: Run all related tests one file at a time**

```bash
flutter test test/orders/scan/tag_lookup_test.dart
flutter test test/orders/scan/scan_result_card_test.dart
flutter test test/orders/scan/scan_tag_tab_test.dart
flutter test test/dashboard/staff_dashboard_screen_test.dart
flutter test test/orders/proof/scanner_screen_test.dart
```

- [ ] **Step 6.2: Run analyzer**

```bash
flutter analyze
```

- [ ] **Step 6.3: Manual smoke test**

Run the app and confirm:

- Scan appears as the center bottom-nav item.
- Scan tab opens from anywhere.
- Known tag shows owner/order details.
- Unknown tag shows retry/manual-entry state.
- Ready-for-delivery result offers the delivery action.
- Existing order details proof flow still works.

---

## Acceptance Checklist

- [ ] Scan is the center bottom-nav item.
- [ ] Bottom nav has five always-labeled destinations.
- [ ] Scan supports fake scanner tests.
- [ ] Scan supports manual entry fallback.
- [ ] Known tag shows owner/order details.
- [ ] Unknown tag is handled clearly.
- [ ] Ready-for-delivery result has a delivery action.
- [ ] Existing pickup/delivery proof tests still pass.
- [ ] No backend/schema work is included in this feature unless a later spec approves a separate `tagId`.
