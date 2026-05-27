# New Pickup Form — Design (2026-05-25)

## Status
Draft — pending user review

## Summary
Replace the placeholder `NewPickupScreen` with a real form that lets a rider create a brand-new pickup order on the spot — at the customer's house, in the field — and have it land in the local Drift DB + sync-outbox automatically. On submit, the form writes a customer row (via a new `CustomersRepository.upsertCustomer`) and an order row (via the existing `OrdersRepository.upsertOrder`); if the rider chose "pickup now," the dashboard immediately routes into `PickupCaptureScreen` so photos + count + QR can be captured without extra taps.

This is PR-B in the planning ladder. PR-A (Plan 3b, orders-stream migration) has already shipped the read + write rails this depends on.

## Problem
Today, every order on a rider's dashboard came from one of two places: the four hardcoded `OrdersSeeder` fixtures, or a backend pull. Riders cannot create a new order in the field. When a customer says "please pick up my laundry," the rider has no UI to capture name / phone / address / service type and feed it into the order pipeline — they have to call the office, who manually inserts the row somewhere upstream. That's slow, error-prone, and gates field-level growth.

The infrastructure to fix this — `OrdersRepository.upsertOrder`, `OutboxRepository`, `OrdersStreamProvider`, `currentUserIdProvider`, the Drift schema with `customer_id` / `intake_method` / `fulfillment_method` / `scheduled_for` columns — already exists from Plans 1-4. The only missing piece is the form UI plus a small `CustomersRepository.upsertCustomer` write method to mirror the orders side.

## Goal
- A rider taps the "New pickup" button on the dashboard, fills a single short form (5 visible required fields), and creates a new pickup order in the local DB. The dashboard's `ordersStreamProvider` reactively shows the new card without a manual refresh.
- The same submit creates (or links to) a customer row, so the customers table starts accumulating real entries that future returning-customer flows can dedupe against.
- If the rider chose "pickup now," they are immediately routed into `PickupCaptureScreen` for the new order — no detour back to the dashboard to find the card and tap "Confirm pickup."
- Existing customers (by phone match) are recognized at entry-time; the form offers a one-tap pre-fill of name + address from the most recent matching customer row.
- The form is offline-safe: writes land in Drift + outbox the same way as proof events; the existing `OutboxWorker` drains them to Supabase whenever connectivity is up.

## Non-Goals
- **No `intakeMethod` / `fulfillmentMethod` UI.** Both are hardcoded to `'driver_pickup'` and `'delivery'`. A `walk_in` / `walk_out` choice is deferred until those cases are real.
- **No prices, no payment, no rider assignment beyond `createdBy`** (which is automatically the actor staff id).
- **No multi-bag / multi-service.** One pickup = one `serviceType`. Customers with mixed services need two orders.
- **No customer-detail screen.** `CustomersRepository.upsertCustomer` is the only customer-side write API this PR adds; reading customers stays via the existing `watchAll` / `watchById`.
- **No real-time customer search dropdown.** Phone-on-blur lookup is the only dedup mechanism.
- **No web GPS support.** `geolocate()` and `reverseGeocode()` return null on web; the "Use my location" chip is shown but does nothing on web (`onPressed: null` with a tooltip).
- **No router refactor.** The new form is pushed via `Navigator.push(MaterialPageRoute(...))`, matching the dashboard's existing pattern.
- **No `proofEvents` capture inside this PR.** That happens in `PickupCaptureScreen` after the route-on-success branch lands the rider there.

## Decisions Locked In
1. **Customer is always saved + linked.** Every new pickup writes to both `customers` and `orders`. Phone-matched existing customers reuse their id; new customers get a fresh UUID.
2. **`intakeMethod` and `fulfillmentMethod` hardcoded.** Form does not surface them; defaults written via the `LaundryOrder` model.
3. **`id` and `orderCode` are separate.** `LaundryOrder.id` is a UUID (Supabase-compatible); `LaundryOrder.orderCode` is the human-readable `AMW-{millisecondsSinceEpoch}`.
4. **`ServiceType` becomes an enum.** Four cases, `.label` for display, `.toDbString` for persistence. Mirrors the `OrderStatus` pattern.
5. **Form pops a result object,** `NewPickupResult(orderId, startPickupNow)`. The dashboard branches on `startPickupNow` to either return to the order list or push `PickupCaptureScreen`.
6. **GPS / reverse-geocoding via injected closures.** `geolocate: Future<Location?> Function()` and `reverseGeocode: Future<String?> Function(Location)` are constructor params on the form — same testability seam as `pickPhoto` on the capture screens.
7. **No real customer-search UI in this PR.** The phone-on-blur bottom sheet is the only dedup affordance.

## Data Model

### New: `ServiceType` (`lib/src/orders/service_type.dart`)
```dart
enum ServiceType { washAndIron, dryCleaning, ironOnly, washOnly }

extension ServiceTypeX on ServiceType {
  String get label => switch (this) {
    ServiceType.washAndIron => 'Wash & Iron',
    ServiceType.dryCleaning => 'Dry cleaning',
    ServiceType.ironOnly    => 'Iron only',
    ServiceType.washOnly    => 'Wash only',
  };

  String toDbString() => switch (this) {
    ServiceType.washAndIron => 'Wash & Iron',
    ServiceType.dryCleaning => 'Dry cleaning',
    ServiceType.ironOnly    => 'Iron only',
    ServiceType.washOnly    => 'Wash only',
  };

  static ServiceType fromDbString(String s) => switch (s) {
    'Wash & Iron'  => ServiceType.washAndIron,
    'Dry cleaning' => ServiceType.dryCleaning,
    'Iron only'    => ServiceType.ironOnly,
    'Wash only'    => ServiceType.washOnly,
    _ => throw ArgumentError.value(s, 'serviceType', 'unknown service type'),
  };
}
```
`.label` and `.toDbString` happen to return the same string today. Kept distinct because the human label and the persisted form will diverge if Amuwak ever localizes the UI or migrates the DB column to a normalized code (e.g. `'wash_iron'`).

### Modified: `LaundryOrder` (`lib/src/orders/order.dart`)
Add four nullable-or-defaulted fields. All other existing fields stay.

```dart
final String orderCode;                      // required, human-readable
final String? customerId;                    // null until linked
final String intakeMethod;                   // defaults to 'driver_pickup'
final String fulfillmentMethod;              // defaults to 'delivery'
final DateTime? scheduledFor;                // null = pickup now
// existing field migrates type:
final ServiceType serviceType;               // was String
```

`copyWith`, `==`, `hashCode`, and `fromDriftRow` updated to cover the new fields. `fromDriftRow` reads `row.orderCode`, `row.customerId`, `row.intakeMethod`, `row.fulfillmentMethod`, `row.scheduledFor`, and `ServiceType.fromDbString(row.serviceType)`.

`OrdersRepository._toCompanion` updated:
- `orderCode: Value(order.orderCode)` (was `Value(order.orderId)` — the TODO at line 167 closes here)
- `serviceType: Value(order.serviceType.toDbString())` (was free string)
- `intakeMethod: Value(order.intakeMethod)` (was hardcoded `'driver_pickup'`)
- `fulfillmentMethod: Value(order.fulfillmentMethod)` (was hardcoded `'delivery'`)
- `customerId: Value(order.customerId)` (new)
- `scheduledFor: Value(order.scheduledFor)` (new)

`OrdersRepository._toPayload` mirrors all of the above.

### Migrated: `OrdersSeeder` (`lib/src/data/orders_seeder.dart`)
Four `OrdersCompanion.insert` calls update to the new schema-facing structure: `serviceType` strings unchanged (still 'Wash & Iron' etc., now produced by `ServiceType.toDbString()` via the seeder rewriting its hardcoded strings); other new columns stay at their existing literals. No id changes.

### New write method on `CustomersRepository`
```dart
Future<void> upsertCustomer(Customer customer) async {
  final outbox = _requireOutbox();
  final now = _clock();
  await _db.transaction(() async {
    await _db.into(_db.customers).insertOnConflictUpdate(
      _toCompanion(customer, now: now),
    );
    await outbox.enqueue(
      id: OutboxRepository.dedupKeyFor(
        forTable: 'customers',
        op: 'insert',
        rowId: customer.id,
        extra: now.toUtc().toIso8601String(),
      ),
      forTable: 'customers',
      op: 'insert',
      rowId: customer.id,
      payload: _toPayload(customer, now: now),
    );
  });
}
```
Constructor gains `OutboxRepository? outbox` and `DateTime Function()? clock`, matching `OrdersRepository`'s shape. `_requireOutbox` throws `StateError` for read-only callers. `_toCompanion` and `_toPayload` are private helpers.

`customersRepositoryProvider` rewires to pass `outbox: ref.watch(outboxRepositoryProvider)` — mirrors the orders provider.

## File Layout

```
lib/src/
  orders/
    new_pickup_screen.dart           [REPLACE — stub becomes the real form]
    new_pickup_result.dart           [new — small value class popped from the form]
    service_type.dart                [new]
    order.dart                       [modify — add 5 fields, migrate serviceType]
    geo_services.dart                [new — createDefaultGeolocate / createDefaultReverseGeocode factories]
  sync/
    customers_repository.dart        [modify — add upsertCustomer]
    orders_repository.dart           [modify — _toCompanion / _toPayload use new fields]
    repository_providers.dart        [modify — customersRepositoryProvider gains outbox arg]
  dashboard/
    staff_dashboard_screen.dart      [modify — _handleNewPickup creates form deps + handles result]
  data/
    orders_seeder.dart               [modify — fixture serviceType now via ServiceType.toDbString]

test/
  orders/
    service_type_test.dart           [new]
    order_test.dart                  [modify — cover new fields]
    new_pickup_screen_test.dart      [REPLACE]
  sync/
    customers_repository_write_test.dart [new]
  dashboard/
    staff_dashboard_screen_test.dart [modify — assert PickupCaptureScreen push on startPickupNow=true]

pubspec.yaml                         [modify — add geolocator + geocoding]
android/app/src/main/AndroidManifest.xml  [modify — add location perms]
ios/Runner/Info.plist                [modify — add NSLocationWhenInUseUsageDescription]
```

## Form

Single `ListView` of fields, scrollable. From top to bottom:

1. **Customer name** — `TextFormField`, required, capitalizes words. Stored in `_nameController`.

2. **Phone** — `TextFormField`, required, prefilled with `'+256 '`. `keyboardType: TextInputType.phone`. Format-validated as 9+ digits after the prefix. Stored in `_phoneController`. **On blur** (focus listener), look up an existing customer via `customersRepo` for a phone-normalized match (strip whitespace, normalize +256/0). If found, show a `showModalBottomSheet` with the matched customer's name + address and two buttons: "Use this customer" (pre-fills `_nameController` and `_addressController`, stores the existing `customerId` for later) and "Different customer" (dismisses).

3. **Address** — `TextFormField`, required, multiline-soft (`maxLines: 1` collapsed, expands on edit). Above the field: a `Wrap` containing a single `ActionChip` labeled "Use my location" with `Icons.my_location`. On tap: `setState(_locating = true)` → `await widget.geolocate()` → if non-null, `await widget.reverseGeocode(location)` → if non-null, fill `_addressController`. Any null at any step quietly resets `_locating` without changing the field. On web (`kIsWeb`) the chip renders disabled with a tooltip "Location not available on web."

4. **Service type** — `DropdownButtonFormField<ServiceType>`, required. Items are the four `ServiceType` values rendering `.label`. Stored in `_serviceType`.

5. **Pickup time** — `SegmentedButton<_PickupTimeMode>` with two segments: `.now` (default) and `.scheduled`. When `.scheduled` is selected, a `Wrap` of four `ChoiceChip`s appears below: `In 1 hour`, `Tomorrow morning`, `Tomorrow afternoon`, `Custom…`. Each chip sets `_scheduledFor`:
   - `In 1 hour`: `clock().add(Duration(hours: 1))`
   - `Tomorrow morning`: `DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9)` where `tomorrow` is `clock().toLocal().add(Duration(days: 1))`.
   - `Tomorrow afternoon`: same but hour 14.
   - `Custom…`: opens `showDatePicker` (range: now → +14 days) then `showTimePicker`; combines both into a `DateTime`.

6. **Add optional details** — a tappable `InkWell` row with `Icons.expand_more` and the label "Add optional details (count, notes)". Tap toggles `_optionalExpanded`. When expanded, two fields appear:

   - **Expected item count** — `Row` with `IconButton(Icons.remove_circle_outline)` + a 60-wide centered `Text('$_count')` + `IconButton(Icons.add_circle_outline)`. Same shape as `PickupCaptureScreen` for consistency.
   - **Notes** — `TextFormField`, `maxLines: 3`, label "Notes (optional)".

7. **Footer buttons** — a `Row` with `OutlinedButton('Cancel')` on the left and `ElevatedButton('Create pickup')` on the right. Create stays disabled until `_nameController.text.trim().isNotEmpty && _phoneController.text.trim().length >= 9 && _addressController.text.trim().isNotEmpty && _serviceType != null && !_saving`. Cancel pops `null`.

## Submit Flow

`_onSubmit` is gated by `_saving` (re-entrancy guard, same pattern as the capture screens). On entry:

1. `setState(_saving = true)`.
2. Build the `Customer` value object:
   ```dart
   final customer = Customer(
     id: _matchedCustomerId ?? widget.customerIdGenerator(),
     name: _nameController.text.trim(),
     phone: _phoneController.text.trim(),
     address: _addressController.text.trim(),
     notes: null,
     createdAt: now,
     updatedAt: now,
     deletedAt: null,
   );
   ```
   `_matchedCustomerId` is non-null only if the bottom-sheet "Use this customer" was tapped.

3. Build the `LaundryOrder` value object:
   ```dart
   final orderId = widget.orderIdGenerator();
   final order = LaundryOrder(
     orderId: orderId,
     orderCode: 'AMW-${widget.clock().millisecondsSinceEpoch}',
     customerId: customer.id,
     customerName: customer.name,
     phone: customer.phone,
     address: customer.address,
     serviceType: _serviceType!,
     status: OrderStatus.pendingPickup,
     timeLabel: _scheduledFor == null
         ? 'Pickup: now'
         : 'Pickup: ${_formatScheduled(_scheduledFor!)}',
     itemCount: _count,
     notes: _notesController.text.trim(),
     intakeMethod: 'driver_pickup',
     fulfillmentMethod: 'delivery',
     scheduledFor: _scheduledFor,
     proofEvents: const [],
   );
   ```

4. `try { await widget.customersRepo.upsertCustomer(customer); } catch (_) { ... show SnackBar, reset _saving, return; }`

5. `try { await widget.ordersRepo.upsertOrder(order, actorStaffId: widget.actorStaffId); } catch (_) { ... show SnackBar mentioning that the customer was saved but the order wasn't; reset _saving; return; }`

6. `if (!mounted) return;` then:
   ```dart
   Navigator.pop<NewPickupResult>(context, NewPickupResult(
     orderId: orderId,
     startPickupNow: _scheduledFor == null,
   ));
   ```

The error SnackBar copy distinguishes which write failed so the rider doesn't think nothing was saved when in fact the customer was created. Re-tapping "Create pickup" reuses the cached `customer.id` and `order.id` (held in `_state`), so a retry that succeeds doesn't create a duplicate Customer or Order row — `upsertCustomer` / `upsertOrder` are both idempotent on row id.

## Dashboard Wiring

`_handleNewPickup` in `staff_dashboard_screen.dart`:

```dart
Future<void> _handleNewPickup() async {
  final staffId = ref.read(currentUserIdProvider);
  if (staffId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session expired — please sign in again.')),
    );
    return;
  }
  final result = await Navigator.of(context).push<NewPickupResult>(
    MaterialPageRoute(
      builder: (_) => NewPickupScreen(
        customersRepo: ref.read(customersRepositoryProvider),
        ordersRepo: ref.read(ordersRepositoryProvider),
        actorStaffId: staffId,
        geolocate: createDefaultGeolocate(),
        reverseGeocode: createDefaultReverseGeocode(),
        clock: DateTime.now,
        orderIdGenerator: defaultUuidV4,
        customerIdGenerator: defaultUuidV4,
      ),
    ),
  );
  if (result == null || !mounted) return;
  if (result.startPickupNow) {
    final order = ref
        .read(ordersStreamProvider)
        .valueOrNull
        ?.firstWhere((o) => o.orderId == result.orderId,
            orElse: () => throw StateError(
                'New order ${result.orderId} not in current stream snapshot'));
    if (order == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PickupCaptureScreen(
          order: order,
          photoStorage: _photoStorage,
          pickPhoto: _pickPhoto,
          ordersRepo: ref.read(ordersRepositoryProvider),
          proofEventsRepo: ref.read(proofEventsRepositoryProvider),
          actorStaffId: staffId,
        ),
      ),
    );
  }
}
```

The bell-icon `_ActionButton` "New pickup" `onTap` becomes `_handleNewPickup` (replaces the current push of the stub).

## Service Wiring

### `geo_services.dart`

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as gc;

class Location {
  const Location(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

Future<Location?> Function() createDefaultGeolocate() {
  if (kIsWeb) return () async => null;
  return () async {
    try {
      final perm = await Geolocator.checkPermission();
      final granted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse
          ? perm
          : await Geolocator.requestPermission();
      if (granted == LocationPermission.denied ||
          granted == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition();
      return Location(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  };
}

Future<String?> Function(Location) createDefaultReverseGeocode() {
  if (kIsWeb) return (_) async => null;
  return (loc) async {
    try {
      final placemarks =
          await gc.placemarkFromCoordinates(loc.latitude, loc.longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      return [p.street, p.subLocality, p.locality]
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');
    } catch (_) {
      return null;
    }
  };
}
```

Both factories are pure functions of the platform — production wiring is just `createDefaultGeolocate()` and `createDefaultReverseGeocode()` called inline in the dashboard.

### `pubspec.yaml`
Add (under `dependencies`):
```yaml
  geolocator: ^14.0.0
  geocoding: ^4.0.0
```

### Android `AndroidManifest.xml`
Inside `<manifest>` (top-level, alongside the existing CAMERA permission):
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### iOS `Info.plist`
Inside `<dict>` (alongside the existing camera-usage entry):
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to pre-fill the customer address when you create a new pickup.</string>
```

## Testing

### `service_type_test.dart`
- `.label` for each case matches its existing display string.
- `.toDbString` round-trips with `ServiceType.fromDbString`.
- `ServiceType.fromDbString` throws `ArgumentError` on unknown input.

### `order_test.dart` (extend)
- Equality, `copyWith`, `hashCode` include the new fields (`orderCode`, `customerId`, `intakeMethod`, `fulfillmentMethod`, `scheduledFor`).
- `serviceType` is a `ServiceType`, not a `String`. Old test literals migrate.

### `customers_repository_write_test.dart` (new)
- `upsertCustomer` writes a `customers` row.
- Same call enqueues one `outbox` row with `forTable='customers'`, `op='insert'`, matching `rowId`, and a JSON payload whose `name`/`phone`/`address` match the input.
- A second `upsertCustomer` with the same `id` is idempotent (insertOnConflictUpdate semantics) and produces a new outbox row only if the `updated_at` differs (deterministic dedup key).
- Constructing `CustomersRepository` without an outbox and calling `upsertCustomer` throws `StateError`.

### `new_pickup_screen_test.dart` (replace)
- Create button is disabled until name, phone, address, and serviceType are all set.
- Typing a phone that matches an existing customer (set up via `customersRepo.upsertCustomer` before pumping) shows the bottom sheet; tapping "Use this customer" pre-fills name + address.
- Tapping "Use my location" with a stubbed `geolocate()` + `reverseGeocode()` fills the address field.
- "Schedule for later" → tapping each quick-chip populates the right `_scheduledFor` value (assert via the resulting payload after submit).
- Submitting:
  - With `pickup now` (no schedule): pop returns `NewPickupResult(orderId, startPickupNow: true)`; one customer row written; one order row written with `scheduledFor: null`, `status: 'pending_pickup'`, `intakeMethod: 'driver_pickup'`, `fulfillmentMethod: 'delivery'`; two outbox rows (one customers, one orders).
  - With `Tomorrow morning`: same as above plus `scheduledFor` non-null and 9 AM next day; pop returns `startPickupNow: false`.
  - With matched existing customer: order row's `customerId` equals the matched customer's `id`; only one customer row in the DB (no duplicate).
- Submit where `customersRepo.upsertCustomer` throws: SnackBar visible mentioning the customer save failed, Create button re-enabled, no order row written.
- Submit where `customersRepo.upsertCustomer` succeeds but `ordersRepo.upsertOrder` throws: SnackBar mentioning the customer was saved but the order wasn't; Create button re-enabled; customer row exists; no order row; retry uses the same customer id.
- Cancel returns `null` and writes nothing.

### `staff_dashboard_screen_test.dart` (extend)
- After the existing "Tapping New pickup opens NewPickupScreen" test: simulate the form popping `NewPickupResult(orderId: '...', startPickupNow: true)`. Assert `PickupCaptureScreen` is now on the navigator stack with the new order.
- Variant: `startPickupNow: false` → no PickupCaptureScreen push; dashboard renders the new card from the stream.

## Migration risk & rollback

- **Risk:** Adding non-nullable `orderCode`, `intakeMethod`, `fulfillmentMethod` to `LaundryOrder` breaks any existing in-memory constructor calls (tests, fixtures) that don't pass them. Mitigation: scope the migration task in the plan to update all 12-or-so existing call sites in one pass, listed by the analyzer.
- **Risk:** `serviceType` migrating from `String` to `ServiceType` enum changes value-equality semantics. Mitigation: the same migration task converts all literal usages; the seeder's `'Wash & Iron'` strings become `ServiceType.washAndIron.toDbString()`.
- **Risk:** `customersRepositoryProvider` gaining an `outbox` dependency may break existing tests that override only `appDatabaseProvider`. Mitigation: also override `outboxRepositoryProvider` in the affected test setup (or let it resolve through the same overridden DB — works because `outboxRepositoryProvider` only depends on `appDatabaseProvider`).
- **Rollback:** revert PR-B; the only schema-coupling is in `LaundryOrder` and `OrdersRepository._toCompanion`. Both revert cleanly. Outbox rows already enqueued from new pickups stay valid (they were correct against the production Supabase schema).

## Open Questions / Items the plan must resolve

1. **Phone normalization for the dedup match.** Two reasonable approaches: strict ("+256 700 123 456" matches only itself, normalized whitespace) or fuzzy (strip prefix, compare last 9 digits). The plan task that wires the bottom-sheet should pick one and document it; the test suite covers whichever lands.
2. **Bottom-sheet trigger.** "On blur" or "on debounced typing" — the spec says blur for predictability; the plan can revisit if usability testing prefers eager match.
3. **Custom datetime chip's max range.** Spec defaults to +14 days; plan may adjust based on product input.

## Out of scope (deferred — call out so future plans know)

- `walk_in` / `walk_out` UI for `intakeMethod` / `fulfillmentMethod` (PR-B.1).
- Real-time customer search dropdown (PR-B.2).
- Multi-bag / multi-service orders.
- Price quote / estimate at creation.
- Rider self-assignment beyond `createdBy`.
- Customer detail screen / customer list screen.
- Photo / signature at creation time (deferred — proof photos are captured in `PickupCaptureScreen` after the "pickup now" branch).
- Pull-to-refresh on the dashboard stream.
- Web GPS support.
