# New Pickup Form (PR-B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder `NewPickupScreen` with a real on-the-spot order-creation form that writes a customer row and an order row to the local Drift DB (which the existing outbox worker syncs to Supabase).

**Architecture:** Form is a `StatefulWidget` with constructor-injected dependencies (`customersRepo`, `ordersRepo`, `geolocate`, `reverseGeocode`, `clock`, `orderIdGenerator`, `customerIdGenerator`, `actorStaffId`) — same testability pattern as the capture screens. Submit calls `CustomersRepository.upsertCustomer` (new) then `OrdersRepository.upsertOrder` (existing), pops a `NewPickupResult` to the dashboard; if `startPickupNow` is true the dashboard pushes `PickupCaptureScreen` for the new order.

**Tech Stack:** Dart 3.8, Flutter, Drift 2.18, supabase_flutter 2.5, flutter_riverpod 2.5, uuid 4.5, mocktail 1.0. Adds `geolocator ^14.0.0` + `geocoding ^4.0.0`.

**Source spec:** [docs/superpowers/specs/2026-05-25-new-pickup-form-design.md](../specs/2026-05-25-new-pickup-form-design.md)
**Prerequisite plan:** [2026-05-21-plan-3b-orders-stream-migration.md](2026-05-21-plan-3b-orders-stream-migration.md) (merged).

---

## File map

```
lib/src/
├── orders/
│   ├── service_type.dart                 [new — Task 1]
│   ├── order.dart                        [modify — Task 2 + 3]
│   ├── new_pickup_result.dart            [new — Task 8]
│   ├── geo_services.dart                 [new — Task 7]
│   └── new_pickup_screen.dart            [REPLACE — Tasks 9-13]
├── sync/
│   ├── orders_repository.dart            [modify — Task 4]
│   ├── customers_repository.dart         [modify — Task 5]
│   └── repository_providers.dart         [modify — Task 5]
├── data/
│   └── orders_seeder.dart                [modify — Task 2]
└── dashboard/
    └── staff_dashboard_screen.dart       [modify — Task 14]

pubspec.yaml                              [modify — Task 6]
android/app/src/main/AndroidManifest.xml  [modify — Task 6]
ios/Runner/Info.plist                     [modify — Task 6]

test/
├── orders/
│   ├── service_type_test.dart            [new — Task 1]
│   ├── order_test.dart                   [modify — Task 2 + 3]
│   ├── order_from_drift_row_test.dart    [modify — Task 2 + 3]
│   └── new_pickup_screen_test.dart       [REPLACE — Tasks 9-13]
├── sync/
│   ├── orders_repository_write_test.dart [modify — Task 4]
│   └── customers_repository_write_test.dart [new — Task 5]
└── dashboard/
    └── staff_dashboard_screen_test.dart  [modify — Task 14]

# Mass call-site migration in Task 2:
# 14 test files contain `serviceType: '<string>'` literals — all switch to ServiceType.X.
```

Each task ends in one commit. 14 tasks total.

---

### Task 1: `ServiceType` enum

**Files:**
- Create: `lib/src/orders/service_type.dart`
- Create: `test/orders/service_type_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/orders/service_type_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/service_type.dart';

void main() {
  group('ServiceType', () {
    test('has exactly four cases', () {
      expect(ServiceType.values, hasLength(4));
    });

    test('label matches the existing user-facing string for each case', () {
      expect(ServiceType.washAndIron.label, 'Wash & Iron');
      expect(ServiceType.dryCleaning.label, 'Dry cleaning');
      expect(ServiceType.ironOnly.label, 'Iron only');
      expect(ServiceType.washOnly.label, 'Wash only');
    });

    test('toDbString round-trips with fromDbString for every case', () {
      for (final t in ServiceType.values) {
        expect(ServiceType.fromDbString(t.toDbString()), t);
      }
    });

    test('fromDbString throws on unknown input', () {
      expect(
        () => ServiceType.fromDbString('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/orders/service_type_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:amuwak_staff/src/orders/service_type.dart'`.

- [ ] **Step 3: Create the enum**

Create `lib/src/orders/service_type.dart`:

```dart
/// User-facing service categories. The `.label` returns the human display
/// string; `.toDbString` returns the value persisted to `orders.service_type`
/// in Drift + Supabase.
///
/// `.label` and `.toDbString` happen to produce the same string today.
/// Kept distinct because the human label and the persisted form will diverge
/// if Amuwak ever localizes the UI or migrates the DB to a normalized code
/// (e.g. `'wash_iron'`).
enum ServiceType {
  washAndIron,
  dryCleaning,
  ironOnly,
  washOnly;

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

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/orders/service_type_test.dart`
Expected: PASS — `+4: All tests passed!`

- [ ] **Step 5: Analyze the new files**

Run: `flutter analyze lib/src/orders/service_type.dart test/orders/service_type_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/service_type.dart test/orders/service_type_test.dart
git commit -m "Add ServiceType enum with .label and .toDbString round-trip

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/service_type.dart test/orders/service_type_test.dart
```

---

### Task 2: Migrate `LaundryOrder.serviceType` from `String` to `ServiceType`

**Files:**
- Modify: `lib/src/orders/order.dart`
- Modify: `lib/src/data/orders_seeder.dart`
- Modify: 14 test files containing `serviceType: '...'` string literals (locate via `grep -rln "serviceType:" test/`).
- Modify: `test/orders/order_test.dart`, `test/orders/order_from_drift_row_test.dart` (assert against `ServiceType.X`).

- [ ] **Step 1: Map every callsite**

Run: `grep -rln "serviceType:" test/ lib/`
Expected: a list including `lib/src/orders/order.dart`, `lib/src/data/orders_seeder.dart`, plus 14 test files. Note them down — every one will change in this commit.

- [ ] **Step 2: Update `LaundryOrder` field + helpers to `ServiceType`**

Open `lib/src/orders/order.dart`. Add import: `import 'service_type.dart';`. Change field declaration:

```dart
// before:
final String serviceType;
// after:
final ServiceType serviceType;
```

Update constructor parameter type to `required this.serviceType` (already named, just type changes through the field).

Update `copyWith`:

```dart
LaundryOrder copyWith({
    String? orderId,
    String? customerName,
    ServiceType? serviceType,      // was String? — change to ServiceType?
    OrderStatus? status,
    String? timeLabel,
    int? itemCount,
    String? phone,
    String? address,
    String? notes,
    List<ProofEvent>? proofEvents,
  }) { /* body unchanged */ }
```

Update `fromDriftRow` mapping:

```dart
// before:
serviceType: row.serviceType,
// after:
serviceType: ServiceType.fromDbString(row.serviceType),
```

`==` and `hashCode` already include `serviceType` and compare by value equality — no code change there because `ServiceType` is an enum and enums have correct `==` for free.

- [ ] **Step 3: Update `OrdersSeeder`'s four fixture inserts**

In `lib/src/data/orders_seeder.dart`, the four `OrdersCompanion.insert` calls currently use string literals for `serviceType` (`'Wash & Iron'`, `'Dry cleaning'`, `'Iron only'`, `'Wash only'`). They write directly to Drift so they MUST remain strings. But to centralize the strings on the enum, replace each:

```dart
// before:
serviceType: 'Wash & Iron',
// after:
serviceType: ServiceType.washAndIron.toDbString(),
```

Repeat for the other three fixtures (`dryCleaning`, `ironOnly`, `washOnly`).

Add at top of file: `import '../orders/service_type.dart';`.

- [ ] **Step 4: Update every test that builds a `LaundryOrder` literal**

For each of the 14 files surfaced in Step 1, replace `serviceType: 'Wash & iron'` (or whichever variant) with `serviceType: ServiceType.washAndIron` (or the matching enum value). Same for the other three.

The fixture variants in existing tests use slightly different cases like `'Wash & iron'` (lowercase i). They all map to `ServiceType.washAndIron` (lowercase variants are pre-existing typos that this migration straightens out — the canonical label is `'Wash & Iron'`).

Add `import 'package:amuwak_staff/src/orders/service_type.dart';` to each test file that didn't already import it.

- [ ] **Step 5: Run the analyzer to find every stragglerc**

Run: `flutter analyze 2>&1 | head -40`
Expected: any remaining type-mismatch errors point you to call sites you missed. Fix each, re-run. Target zero issues.

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: all tests pass. If any test references `'Wash & Iron'` as a string in an assertion (e.g. matching the dashboard's order card), update the assertion to use `ServiceType.washAndIron.label`.

- [ ] **Step 7: Commit**

```bash
git add lib/src/orders/order.dart lib/src/data/orders_seeder.dart test/
git commit -m "Migrate LaundryOrder.serviceType from String to ServiceType enum

Touches every test fixture and the seeder so the four user-facing
service strings now live on a single ServiceType enum. fromDriftRow
uses ServiceType.fromDbString to parse the stored value.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/order.dart lib/src/data/orders_seeder.dart test/
```

---

### Task 3: Add `orderCode`, `customerId`, `intakeMethod`, `fulfillmentMethod`, `scheduledFor` fields to `LaundryOrder`

All five new fields have defaults so existing `LaundryOrder` literals in tests continue to compile unchanged.

**Files:**
- Modify: `lib/src/orders/order.dart`
- Modify: `test/orders/order_test.dart` (assertions for new fields)
- Modify: `test/orders/order_from_drift_row_test.dart` (assert new fields are plumbed)

- [ ] **Step 1: Write the failing tests in `test/orders/order_test.dart`**

Append the following inside the existing `main()` block:

```dart
  group('LaundryOrder new fields (Plan PR-B)', () {
    test('orderCode defaults to orderId when not specified', () {
      const o = LaundryOrder(
        orderId: 'AMW-X1',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.orderCode, 'AMW-X1');
    });

    test('orderCode can be set distinctly from orderId', () {
      const o = LaundryOrder(
        orderId: 'uuid-1',
        orderCode: 'AMW-123',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.orderCode, 'AMW-123');
      expect(o.orderId, 'uuid-1');
    });

    test('intakeMethod defaults to driver_pickup', () {
      const o = LaundryOrder(
        orderId: 'X',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.intakeMethod, 'driver_pickup');
    });

    test('fulfillmentMethod defaults to delivery', () {
      const o = LaundryOrder(
        orderId: 'X',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.fulfillmentMethod, 'delivery');
    });

    test('customerId and scheduledFor default to null', () {
      const o = LaundryOrder(
        orderId: 'X',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.customerId, isNull);
      expect(o.scheduledFor, isNull);
    });

    test('copyWith preserves new fields when omitted', () {
      final scheduled = DateTime(2026, 6, 1, 9);
      final o = LaundryOrder(
        orderId: 'uuid-1',
        orderCode: 'AMW-123',
        customerId: 'cust-1',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
        intakeMethod: 'walk_in',
        fulfillmentMethod: 'walk_out',
        scheduledFor: scheduled,
      );
      final copy = o.copyWith(itemCount: 2);
      expect(copy.orderCode, 'AMW-123');
      expect(copy.customerId, 'cust-1');
      expect(copy.intakeMethod, 'walk_in');
      expect(copy.fulfillmentMethod, 'walk_out');
      expect(copy.scheduledFor, scheduled);
      expect(copy.itemCount, 2);
    });

    test('equality includes the new fields', () {
      const base = LaundryOrder(
        orderId: 'X',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      final withCode = base.copyWith(); // unchanged
      expect(withCode, equals(base));

      const differentCode = LaundryOrder(
        orderId: 'X',
        orderCode: 'AMW-OTHER',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(differentCode, isNot(equals(base)));
    });
  });
```

- [ ] **Step 2: Run the new tests, verify they fail**

Run: `flutter test test/orders/order_test.dart`
Expected: 7 new failures pointing at `LaundryOrder` not having the new fields.

- [ ] **Step 3: Add the fields to `LaundryOrder`**

In `lib/src/orders/order.dart`, update the constructor:

```dart
const LaundryOrder({
    required this.orderId,
    String? orderCode,
    this.customerId,
    required this.customerName,
    required this.serviceType,
    required this.status,
    required this.timeLabel,
    required this.itemCount,
    required this.phone,
    required this.address,
    required this.notes,
    this.intakeMethod = 'driver_pickup',
    this.fulfillmentMethod = 'delivery',
    this.scheduledFor,
    this.proofEvents = const [],
  }) : orderCode = orderCode ?? orderId;
```

(`orderCode` defaults to `orderId` via the initializer list — keeps every existing fixture literal compiling.)

Add the field declarations:

```dart
final String orderCode;
final String? customerId;
final String intakeMethod;
final String fulfillmentMethod;
final DateTime? scheduledFor;
```

- [ ] **Step 4: Update `copyWith`, `==`, `hashCode`, `fromDriftRow`**

Update `copyWith`:

```dart
LaundryOrder copyWith({
    String? orderId,
    String? orderCode,
    String? customerId,
    String? customerName,
    ServiceType? serviceType,
    OrderStatus? status,
    String? timeLabel,
    int? itemCount,
    String? phone,
    String? address,
    String? notes,
    String? intakeMethod,
    String? fulfillmentMethod,
    DateTime? scheduledFor,
    List<ProofEvent>? proofEvents,
  }) {
    return LaundryOrder(
      orderId: orderId ?? this.orderId,
      orderCode: orderCode ?? this.orderCode,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      serviceType: serviceType ?? this.serviceType,
      status: status ?? this.status,
      timeLabel: timeLabel ?? this.timeLabel,
      itemCount: itemCount ?? this.itemCount,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      intakeMethod: intakeMethod ?? this.intakeMethod,
      fulfillmentMethod: fulfillmentMethod ?? this.fulfillmentMethod,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      proofEvents: proofEvents ?? this.proofEvents,
    );
  }
```

Update `==`:

```dart
@override
bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LaundryOrder) return false;
    if (other.orderId != orderId ||
        other.orderCode != orderCode ||
        other.customerId != customerId ||
        other.customerName != customerName ||
        other.serviceType != serviceType ||
        other.status != status ||
        other.timeLabel != timeLabel ||
        other.itemCount != itemCount ||
        other.phone != phone ||
        other.address != address ||
        other.notes != notes ||
        other.intakeMethod != intakeMethod ||
        other.fulfillmentMethod != fulfillmentMethod ||
        other.scheduledFor != scheduledFor) {
      return false;
    }
    if (proofEvents.length != other.proofEvents.length) return false;
    for (var i = 0; i < proofEvents.length; i++) {
      if (proofEvents[i] != other.proofEvents[i]) return false;
    }
    return true;
  }
```

Update `hashCode`:

```dart
@override
int get hashCode => Object.hash(
        orderId,
        orderCode,
        customerId,
        customerName,
        serviceType,
        status,
        timeLabel,
        itemCount,
        phone,
        address,
        notes,
        intakeMethod,
        fulfillmentMethod,
        scheduledFor,
        Object.hashAll(proofEvents),
      );
```

Update `fromDriftRow` to populate the new fields:

```dart
factory LaundryOrder.fromDriftRow(
    drift.Order row,
    List<drift.ProofEvent> events,
  ) {
    return LaundryOrder(
      orderId: row.id,
      orderCode: row.orderCode,
      customerId: row.customerId,
      customerName: row.customerName,
      serviceType: ServiceType.fromDbString(row.serviceType),
      status: _statusFromString(row.status),
      timeLabel: _formatTime(row.scheduledFor ?? row.createdAt),
      itemCount: row.itemCount,
      phone: row.phone,
      address: row.address,
      notes: row.notes,
      intakeMethod: row.intakeMethod,
      fulfillmentMethod: row.fulfillmentMethod,
      scheduledFor: row.scheduledFor,
      proofEvents: events
          .map((e) => ProofEvent(
                id: e.id,
                type: _proofTypeFromString(e.type),
                capturedAt: e.capturedAt,
                count: e.itemCount,
                photoPaths: const [],
                notes: e.notes,
              ))
          .toList(growable: false),
    );
  }
```

- [ ] **Step 5: Add a fromDriftRow test for the new fields**

Open `test/orders/order_from_drift_row_test.dart`. Locate the existing test that pumps a Drift `Order` row through `fromDriftRow`. Extend its assertions to cover the new fields:

```dart
expect(hydrated.orderCode, equals(driftRow.orderCode));
expect(hydrated.customerId, equals(driftRow.customerId));
expect(hydrated.intakeMethod, equals(driftRow.intakeMethod));
expect(hydrated.fulfillmentMethod, equals(driftRow.fulfillmentMethod));
expect(hydrated.scheduledFor, equals(driftRow.scheduledFor));
```

If the existing test fixture's `Order` row doesn't include `customerId` / `scheduledFor`, set both explicitly in the row literal.

- [ ] **Step 6: Run tests, verify they pass**

Run: `flutter test test/orders/order_test.dart test/orders/order_from_drift_row_test.dart`
Expected: PASS — all tests green.

- [ ] **Step 7: Run the full test suite for regressions**

Run: `flutter test`
Expected: all tests pass. The default-valued fields keep every existing test fixture compiling without changes.

- [ ] **Step 8: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/src/orders/order.dart test/orders/order_test.dart test/orders/order_from_drift_row_test.dart
git commit -m "Add orderCode, customerId, intakeMethod, fulfillmentMethod, scheduledFor to LaundryOrder

All five new fields have safe defaults — orderCode falls back to orderId,
intakeMethod and fulfillmentMethod default to the values OrdersRepository
already hardcoded, and customerId / scheduledFor are nullable. fromDriftRow
plumbs the new columns through.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/order.dart test/orders/order_test.dart test/orders/order_from_drift_row_test.dart
```

---

### Task 4: Update `OrdersRepository._toCompanion` / `_toPayload` to use new fields

Resolves the TODO in `lib/src/sync/orders_repository.dart` line 167.

**Files:**
- Modify: `lib/src/sync/orders_repository.dart`
- Modify: `test/sync/orders_repository_write_test.dart`

- [ ] **Step 1: Write the failing test**

Open `test/sync/orders_repository_write_test.dart`. Find the existing `upsertOrder` test. Extend or add a new test asserting the new columns are written:

```dart
test('upsertOrder plumbs orderCode, customerId, intakeMethod, '
    'fulfillmentMethod, and scheduledFor through to the orders row', () async {
  final scheduled = DateTime(2026, 6, 1, 9, 0);
  final order = LaundryOrder(
    orderId: 'uuid-test-1',
    orderCode: 'AMW-9999',
    customerId: 'cust-test-1',
    customerName: 'X',
    serviceType: ServiceType.dryCleaning,
    status: OrderStatus.pendingPickup,
    timeLabel: 't',
    itemCount: 3,
    phone: '+256 700 000 001',
    address: 'Test address',
    notes: 'gate locked',
    intakeMethod: 'driver_pickup',
    fulfillmentMethod: 'delivery',
    scheduledFor: scheduled,
  );

  await repo.upsertOrder(order, actorStaffId: 'staff-1');

  final row =
      await (db.select(db.orders)..where((t) => t.id.equals('uuid-test-1')))
          .getSingle();
  expect(row.orderCode, 'AMW-9999');
  expect(row.customerId, 'cust-test-1');
  expect(row.serviceType, ServiceType.dryCleaning.toDbString());
  expect(row.intakeMethod, 'driver_pickup');
  expect(row.fulfillmentMethod, 'delivery');
  expect(row.scheduledFor, scheduled);
});
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/sync/orders_repository_write_test.dart`
Expected: FAIL — `row.orderCode` will equal `'uuid-test-1'` (because `_toCompanion` still uses `orderId` for both), not `'AMW-9999'`.

- [ ] **Step 3: Update `_toCompanion` to use the new fields**

In `lib/src/sync/orders_repository.dart`, replace `_toCompanion`:

```dart
OrdersCompanion _toCompanion(LaundryOrder order, String actorStaffId,
    {required DateTime now}) {
    return OrdersCompanion(
      id: Value(order.orderId),
      orderCode: Value(order.orderCode),
      customerId: Value(order.customerId),
      customerName: Value(order.customerName),
      phone: Value(order.phone),
      address: Value(order.address),
      serviceType: Value(order.serviceType.toDbString()),
      status: Value(order.status.toDbString()),
      intakeMethod: Value(order.intakeMethod),
      fulfillmentMethod: Value(order.fulfillmentMethod),
      itemCount: Value(order.itemCount),
      notes: Value(order.notes),
      scheduledFor: Value(order.scheduledFor),
      intakeRecordedBy: Value(actorStaffId),
      createdBy: Value(actorStaffId),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }
```

Replace `_toPayload`:

```dart
Map<String, dynamic> _toPayload(LaundryOrder order, String actorStaffId,
    {required DateTime now}) =>
    {
      'id': order.orderId,
      'order_code': order.orderCode,
      'customer_id': order.customerId,
      'customer_name': order.customerName,
      'phone': order.phone,
      'address': order.address,
      'service_type': order.serviceType.toDbString(),
      'status': order.status.toDbString(),
      'intake_method': order.intakeMethod,
      'fulfillment_method': order.fulfillmentMethod,
      'item_count': order.itemCount,
      'notes': order.notes,
      'scheduled_for': order.scheduledFor?.toUtc().toIso8601String(),
      'intake_recorded_by': actorStaffId,
      'created_by': actorStaffId,
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    };
```

Remove the two `TODO(pr-b-new-pickup-form):` comments — they're closed now.

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/sync/orders_repository_write_test.dart`
Expected: PASS — all `upsertOrder` write tests green, including the new assertion.

- [ ] **Step 5: Run the full test suite for regressions**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/src/sync/orders_repository.dart test/sync/orders_repository_write_test.dart
git commit -m "Plumb orderCode, customerId, intakeMethod, fulfillmentMethod, scheduledFor through OrdersRepository

Closes the PR-B TODO in _toCompanion / _toPayload. The columns these
methods wrote with hardcoded defaults now come from the domain model.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/sync/orders_repository.dart test/sync/orders_repository_write_test.dart
```

---

### Task 5: Add `CustomersRepository.upsertCustomer`

**Files:**
- Modify: `lib/src/sync/customers_repository.dart`
- Modify: `lib/src/sync/repository_providers.dart`
- Create: `test/sync/customers_repository_write_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/sync/customers_repository_write_test.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/customers_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';

void main() {
  late AppDatabase db;
  late OutboxRepository outbox;
  late CustomersRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxRepository(db);
    repo = CustomersRepository(db, outbox: outbox, clock: () => DateTime(2026, 5, 25, 10));
  });

  tearDown(() async => db.close());

  test('upsertCustomer writes the customer row + an outbox enqueue', () async {
    final customer = Customer(
      id: 'cust-1',
      name: 'Jane Doe',
      phone: '+256 700 111 222',
      address: 'Kikoni',
      notes: null,
      createdAt: DateTime(2026, 5, 25, 10),
      updatedAt: DateTime(2026, 5, 25, 10),
      deletedAt: null,
    );

    await repo.upsertCustomer(customer);

    final row = await (db.select(db.customers)
          ..where((t) => t.id.equals('cust-1')))
        .getSingle();
    expect(row.name, 'Jane Doe');
    expect(row.phone, '+256 700 111 222');
    expect(row.address, 'Kikoni');

    final outboxRows = await db.select(db.outbox).get();
    expect(outboxRows, hasLength(1));
    expect(outboxRows.single.forTable, 'customers');
    expect(outboxRows.single.op, 'insert');
    expect(outboxRows.single.rowId, 'cust-1');
  });

  test('upsertCustomer is idempotent on the same id within the same clock tick',
      () async {
    final customer = Customer(
      id: 'cust-2',
      name: 'Jane Doe',
      phone: '+256 700 111 222',
      address: 'Kikoni',
      notes: null,
      createdAt: DateTime(2026, 5, 25, 10),
      updatedAt: DateTime(2026, 5, 25, 10),
      deletedAt: null,
    );

    await repo.upsertCustomer(customer);
    await repo.upsertCustomer(customer);

    final rows = await db.select(db.customers).get();
    expect(rows, hasLength(1));
    final outboxRows = await db.select(db.outbox).get();
    expect(outboxRows, hasLength(1));
  });

  test('upsertCustomer throws StateError if constructed without outbox',
      () async {
    final readOnly = CustomersRepository(db); // no outbox
    expect(
      () => readOnly.upsertCustomer(Customer(
        id: 'cust-3',
        name: 'X',
        phone: 'X',
        address: null,
        notes: null,
        createdAt: DateTime(2026, 5, 25, 10),
        updatedAt: DateTime(2026, 5, 25, 10),
        deletedAt: null,
      )),
      throwsA(isA<StateError>()),
    );
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/sync/customers_repository_write_test.dart`
Expected: FAIL — `upsertCustomer` does not exist; `CustomersRepository` does not accept `outbox` or `clock`.

- [ ] **Step 3: Add `upsertCustomer` to `CustomersRepository`**

Replace `lib/src/sync/customers_repository.dart`:

```dart
import 'package:drift/drift.dart';

import '../data/app_database.dart';
import 'outbox_repository.dart';

/// Read + write repository for customers.
///
/// Write methods ([upsertCustomer]) require an [OutboxRepository] to be
/// supplied at construction time. Callers that only need the read API can
/// omit it; attempting a write on a read-only-configured instance throws a
/// [StateError]. Mirrors [OrdersRepository]'s shape.
class CustomersRepository {
  CustomersRepository(
    this._db, {
    OutboxRepository? outbox,
    DateTime Function()? clock,
  })  : _outbox = outbox,
        _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final OutboxRepository? _outbox;
  final DateTime Function() _clock;

  // ----- READ -----

  Stream<List<Customer>> watchAll() {
    return (_db.select(_db.customers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Stream<Customer?> watchById(String id) {
    return (_db.select(_db.customers)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  // ----- WRITE -----

  Future<void> upsertCustomer(Customer customer) async {
    final outbox = _requireOutbox();
    final now = _clock();
    await _db.transaction(() async {
      await _db.into(_db.customers).insertOnConflictUpdate(
        CustomersCompanion(
          id: Value(customer.id),
          name: Value(customer.name),
          phone: Value(customer.phone),
          address: Value(customer.address),
          notes: Value(customer.notes),
          createdAt: Value(customer.createdAt),
          updatedAt: Value(now),
        ),
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
        payload: <String, dynamic>{
          'id': customer.id,
          'name': customer.name,
          'phone': customer.phone,
          'address': customer.address,
          'notes': customer.notes,
          'created_at': customer.createdAt.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        },
      );
    });
  }

  // ----- PRIVATE HELPERS -----

  OutboxRepository _requireOutbox() {
    final o = _outbox;
    if (o == null) {
      throw StateError(
        'CustomersRepository was constructed without an OutboxRepository; '
        'upsertCustomer is unavailable.',
      );
    }
    return o;
  }
}
```

- [ ] **Step 4: Wire `outbox` into `customersRepositoryProvider`**

In `lib/src/sync/repository_providers.dart`, replace the provider:

```dart
final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => CustomersRepository(
    ref.watch(appDatabaseProvider),
    outbox: ref.watch(outboxRepositoryProvider),
  ),
);
```

- [ ] **Step 5: Run test, verify it passes**

Run: `flutter test test/sync/customers_repository_write_test.dart`
Expected: PASS — three tests green.

- [ ] **Step 6: Run the full test suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass; `No issues found!`. Existing customer-read tests continue to work because the constructor's new params are both optional.

- [ ] **Step 7: Commit**

```bash
git add lib/src/sync/customers_repository.dart lib/src/sync/repository_providers.dart test/sync/customers_repository_write_test.dart
git commit -m "Add CustomersRepository.upsertCustomer + outbox-aware provider

Mirrors OrdersRepository.upsertOrder — same transaction shape, same
deterministic outbox dedup key, same StateError fallback for read-only
construction. customersRepositoryProvider now wires the outbox in.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/sync/customers_repository.dart lib/src/sync/repository_providers.dart test/sync/customers_repository_write_test.dart
```

---

### Task 6: Add geo dependencies + native config

No code, just package + manifest plumbing. No tests in this task — the `geo_services.dart` factories arrive in Task 7 and get tested through the form tests in later tasks.

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`

- [ ] **Step 1: Add `geolocator` and `geocoding` to `pubspec.yaml`**

In `pubspec.yaml`, under `dependencies:` (alongside `connectivity_plus` and the other backend deps), add:

```yaml
  geolocator: ^14.0.0
  geocoding: ^4.0.0
```

- [ ] **Step 2: Run pub get**

Run: `flutter pub get`
Expected: `Got dependencies!` with no version conflicts.

- [ ] **Step 3: Add Android location permissions**

In `android/app/src/main/AndroidManifest.xml`, inside the top-level `<manifest>` element (alongside the existing CAMERA permission), add:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

- [ ] **Step 4: Add iOS location usage description**

In `ios/Runner/Info.plist`, inside the top-level `<dict>` element (alongside the existing `NSCameraUsageDescription`), add:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to pre-fill the customer address when you create a new pickup.</string>
```

- [ ] **Step 5: Verify the full test suite still passes**

Run: `flutter test`
Expected: all tests pass. Adding the deps shouldn't break anything; the analyzer might warn about unused imports (none yet — `geo_services.dart` arrives next task).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "Add geolocator + geocoding deps and platform location perms

Unlocks the 'Use my location' chip in the New Pickup form (Task 11).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
```

---

### Task 7: Add `geo_services.dart` factories

**Files:**
- Create: `lib/src/orders/geo_services.dart`

No unit tests for this file — it's a thin wrapper around the platform plugins; tests would be testing the plugins themselves. The factories are exercised through the form widget tests (Task 11) with stubbed closures.

- [ ] **Step 1: Create the file**

Create `lib/src/orders/geo_services.dart`:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart' as gc;
import 'package:geolocator/geolocator.dart';

/// Lightweight, plugin-free location value the form consumes.
class GeoLocation {
  const GeoLocation({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

typedef GeolocateFn = Future<GeoLocation?> Function();
typedef ReverseGeocodeFn = Future<String?> Function(GeoLocation location);

/// Production geolocate closure. Returns null on web, on permission denial,
/// and on any platform exception. Never throws.
GeolocateFn createDefaultGeolocate() {
  if (kIsWeb) return () async => null;
  return () async {
    try {
      final perm = await Geolocator.checkPermission();
      final granted =
          perm == LocationPermission.always || perm == LocationPermission.whileInUse
              ? perm
              : await Geolocator.requestPermission();
      if (granted == LocationPermission.denied ||
          granted == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition();
      return GeoLocation(latitude: pos.latitude, longitude: pos.longitude);
    } catch (_) {
      return null;
    }
  };
}

/// Production reverse-geocode closure. Returns null on web, on platform
/// errors, and on empty placemark results. Never throws.
ReverseGeocodeFn createDefaultReverseGeocode() {
  if (kIsWeb) return (_) async => null;
  return (loc) async {
    try {
      final placemarks =
          await gc.placemarkFromCoordinates(loc.latitude, loc.longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      final parts = <String>[];
      void addIfPresent(String? s) {
        if (s != null && s.isNotEmpty) parts.add(s);
      }

      addIfPresent(p.street);
      addIfPresent(p.subLocality);
      addIfPresent(p.locality);
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  };
}
```

- [ ] **Step 2: Run analyzer + tests**

Run: `flutter analyze lib/src/orders/geo_services.dart && flutter test`
Expected: `No issues found!` for the new file; all existing tests still pass.

- [ ] **Step 3: Commit**

```bash
git add lib/src/orders/geo_services.dart
git commit -m "Add geo_services.dart with GeoLocation, GeolocateFn, ReverseGeocodeFn

Production factories wrap the geolocator + geocoding plugins, return null
on web / permission denial / any platform error. Test closures stub these
directly via constructor injection in the New Pickup form.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/geo_services.dart
```

---

### Task 8: Create `NewPickupResult` value class

**Files:**
- Create: `lib/src/orders/new_pickup_result.dart`

Tiny task; no test file (covered through the form tests in Tasks 9-13 where it's actually consumed).

- [ ] **Step 1: Create the file**

Create `lib/src/orders/new_pickup_result.dart`:

```dart
/// Returned from `Navigator.pop` when the New Pickup form successfully
/// creates an order. The dashboard branches on [startPickupNow]: if true,
/// it immediately pushes PickupCaptureScreen for the new order.
class NewPickupResult {
  const NewPickupResult({
    required this.orderId,
    required this.startPickupNow,
  });

  final String orderId;
  final bool startPickupNow;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NewPickupResult &&
          other.orderId == orderId &&
          other.startPickupNow == startPickupNow);

  @override
  int get hashCode => Object.hash(orderId, startPickupNow);
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/src/orders/new_pickup_result.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/src/orders/new_pickup_result.dart
git commit -m "Add NewPickupResult value class for the form pop signal

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/new_pickup_result.dart
```

---

### Task 9: Replace `NewPickupScreen` stub with the required-fields form (happy path)

**Files:**
- Modify (effectively replace): `lib/src/orders/new_pickup_screen.dart`
- Replace: `test/orders/new_pickup_screen_test.dart`

Scope: required fields only (name, phone, address, service type), Create button enable/disable logic, happy-path submit that writes a customer + an order and pops a `NewPickupResult(startPickupNow: true)` (no schedule UI yet — that's Task 12). No dedup, no GPS, no optional details.

- [ ] **Step 1: Write the failing tests**

Replace `test/orders/new_pickup_screen_test.dart` with:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/orders/new_pickup_result.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/customers_repository.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';

void main() {
  late AppDatabase db;
  late OutboxRepository outbox;
  late CustomersRepository customersRepo;
  late OrdersRepository ordersRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxRepository(db);
    customersRepo = CustomersRepository(db, outbox: outbox,
        clock: () => DateTime(2026, 5, 25, 10));
    ordersRepo = OrdersRepository(db, outbox: outbox,
        clock: () => DateTime(2026, 5, 25, 10));
  });

  tearDown(() async => db.close());

  Future<NewPickupResult?> pumpFormAndOpen(
    WidgetTester tester, {
    Future<NewPickupResult?>? Function()? onOpen,
  }) async {
    NewPickupResult? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<NewPickupResult>(
                    MaterialPageRoute(
                      builder: (_) => NewPickupScreen(
                        customersRepo: customersRepo,
                        ordersRepo: ordersRepo,
                        actorStaffId: 'staff-1',
                        clock: () => DateTime(2026, 5, 25, 10),
                        orderIdGenerator: () => 'uuid-order-1',
                        customerIdGenerator: () => 'uuid-cust-1',
                        geolocate: () async => null,
                        reverseGeocode: (_) async => null,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('Create button is disabled until required fields are valid',
      (tester) async {
    await pumpFormAndOpen(tester);
    final create = find.widgetWithText(ElevatedButton, 'Create pickup');
    expect(tester.widget<ElevatedButton>(create).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni, Kampala');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(create).onPressed, isNotNull);
  });

  testWidgets('Submit happy path writes customer + order, pops with '
      'startPickupNow=true (default schedule)', (tester) async {
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni, Kampala');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final customers = await db.select(db.customers).get();
    expect(customers, hasLength(1));
    expect(customers.single.id, 'uuid-cust-1');
    expect(customers.single.name, 'Jane Doe');

    final orders = await db.select(db.orders).get();
    expect(orders, hasLength(1));
    expect(orders.single.id, 'uuid-order-1');
    expect(orders.single.customerId, 'uuid-cust-1');
    expect(orders.single.customerName, 'Jane Doe');
    expect(orders.single.serviceType, ServiceType.washAndIron.toDbString());
    expect(orders.single.status, 'pending_pickup');
    expect(orders.single.scheduledFor, isNull);
    // orderCode is AMW-{millisecondsSinceEpoch}; assert the prefix.
    expect(orders.single.orderCode, startsWith('AMW-'));
  });

  testWidgets('Cancel returns null and writes nothing', (tester) async {
    final popped = await pumpFormAndOpen(tester);
    // pumpFormAndOpen returns the awaited push, but we haven't tapped anything
    // inside the form yet — tap Cancel from inside the form's still-open route.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(popped, isNull);
    final customers = await db.select(db.customers).get();
    final orders = await db.select(db.orders).get();
    expect(customers, isEmpty);
    expect(orders, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: FAIL — the form doesn't exist yet (still the stub).

- [ ] **Step 3: Replace `NewPickupScreen` with the minimal form**

Replace `lib/src/orders/new_pickup_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../shared/widgets/app_theme.dart';
import '../sync/customers_repository.dart';
import '../sync/orders_repository.dart';
import '../data/app_database.dart' show Customer;
import 'geo_services.dart';
import 'new_pickup_result.dart';
import 'order.dart';
import 'order_status.dart';
import 'service_type.dart';

class NewPickupScreen extends StatefulWidget {
  const NewPickupScreen({
    super.key,
    required this.customersRepo,
    required this.ordersRepo,
    required this.actorStaffId,
    required this.clock,
    required this.orderIdGenerator,
    required this.customerIdGenerator,
    required this.geolocate,
    required this.reverseGeocode,
  });

  final CustomersRepository customersRepo;
  final OrdersRepository ordersRepo;
  final String actorStaffId;
  final DateTime Function() clock;
  final String Function() orderIdGenerator;
  final String Function() customerIdGenerator;
  final GeolocateFn geolocate;
  final ReverseGeocodeFn reverseGeocode;

  @override
  State<NewPickupScreen> createState() => _NewPickupScreenState();
}

class _NewPickupScreenState extends State<NewPickupScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+256 ');
  final _addressController = TextEditingController();
  ServiceType? _serviceType;
  bool _saving = false;

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      _phoneController.text.trim().length >= 9 &&
      _addressController.text.trim().isNotEmpty &&
      _serviceType != null &&
      !_saving;

  Future<void> _onSubmit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final now = widget.clock();
    final customer = Customer(
      id: widget.customerIdGenerator(),
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      notes: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
    try {
      await widget.customersRepo.upsertCustomer(customer);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not save customer. Please try again.')),
      );
      return;
    }
    final orderId = widget.orderIdGenerator();
    final order = LaundryOrder(
      orderId: orderId,
      orderCode: 'AMW-${now.millisecondsSinceEpoch}',
      customerId: customer.id,
      customerName: customer.name,
      phone: customer.phone,
      address: customer.address ?? '',
      serviceType: _serviceType!,
      status: OrderStatus.pendingPickup,
      timeLabel: 'Pickup: now',
      itemCount: 0,
      notes: '',
    );
    try {
      await widget.ordersRepo
          .upsertOrder(order, actorStaffId: widget.actorStaffId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Customer was saved, but the order could not be saved. '
            'Tap Create pickup again to retry.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop<NewPickupResult>(
      context,
      NewPickupResult(orderId: orderId, startPickupNow: true),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text('New pickup'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextFormField(
              key: const Key('np_name'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Customer name'),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('np_phone'),
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('np_address'),
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ServiceType>(
              key: const Key('np_service_type'),
              decoration: const InputDecoration(labelText: 'Service type'),
              value: _serviceType,
              items: ServiceType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _serviceType = v),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, null),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _onSubmit : null,
                    child: const Text('Create pickup'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: PASS — three tests green.

- [ ] **Step 5: Run the full test suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
git commit -m "Replace NewPickupScreen stub with the required-fields form (happy path)

Name, phone (prefilled +256), address, and service-type dropdown.
Submit writes customer + order via the repositories and pops a
NewPickupResult(startPickupNow: true). Cancel returns null.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
```

---

### Task 10: Phone-on-blur customer dedup + bottom sheet pre-fill

**Files:**
- Modify: `lib/src/orders/new_pickup_screen.dart`
- Modify: `test/orders/new_pickup_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Append to the `main()` block of `test/orders/new_pickup_screen_test.dart`:

```dart
  testWidgets('Phone-on-blur with a matching customer shows the bottom sheet; '
      'tapping "Use this customer" pre-fills name + address', (tester) async {
    // Seed an existing customer with the phone we'll type in.
    await customersRepo.upsertCustomer(Customer(
      id: 'existing-cust-1',
      name: 'Jane Existing',
      phone: '+256 700 111 222',
      address: 'Old address, Kampala',
      notes: null,
      createdAt: DateTime(2026, 5, 20, 9),
      updatedAt: DateTime(2026, 5, 20, 9),
      deletedAt: null,
    ));
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    // Trigger blur by tapping somewhere else (the name field).
    await tester.tap(find.byKey(const Key('np_name')));
    await tester.pumpAndSettle();

    expect(find.text('Use this customer'), findsOneWidget);
    expect(find.text('Jane Existing'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Use this customer'));
    await tester.pumpAndSettle();

    expect(
      (tester.widget<TextFormField>(find.byKey(const Key('np_name')))).controller!.text,
      'Jane Existing',
    );
    expect(
      (tester.widget<TextFormField>(find.byKey(const Key('np_address')))).controller!.text,
      'Old address, Kampala',
    );
  });

  testWidgets('Submit with a matched existing customer reuses customer id',
      (tester) async {
    await customersRepo.upsertCustomer(Customer(
      id: 'existing-cust-2',
      name: 'Bob Returning',
      phone: '+256 701 222 333',
      address: 'Wandegeya',
      notes: null,
      createdAt: DateTime(2026, 5, 20, 9),
      updatedAt: DateTime(2026, 5, 20, 9),
      deletedAt: null,
    ));
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_phone')), '+256 701 222 333');
    await tester.tap(find.byKey(const Key('np_name')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.dryCleaning.label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final customers = await db.select(db.customers).get();
    expect(customers, hasLength(1));            // no second customer row
    expect(customers.single.id, 'existing-cust-2');
    final orders = await db.select(db.orders).get();
    expect(orders.single.customerId, 'existing-cust-2');
  });
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: FAIL — no bottom sheet, no dedup logic in the form yet.

- [ ] **Step 3: Add dedup state + focus listener**

In `_NewPickupScreenState`, add:

```dart
String? _matchedCustomerId;
final FocusNode _phoneFocus = FocusNode();

@override
void initState() {
  super.initState();
  _phoneFocus.addListener(_onPhoneFocusChange);
}

@override
void dispose() {
  _phoneFocus.removeListener(_onPhoneFocusChange);
  _phoneFocus.dispose();
  _nameController.dispose();
  _phoneController.dispose();
  _addressController.dispose();
  super.dispose();
}

String _normalizePhone(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll('+', '');

Future<void> _onPhoneFocusChange() async {
  if (_phoneFocus.hasFocus) return;
  final typed = _normalizePhone(_phoneController.text);
  if (typed.length < 9) return;
  final all = await widget.customersRepo.watchAll().first;
  Customer? matched;
  for (final c in all) {
    if (_normalizePhone(c.phone) == typed) {
      matched = c;
      break;
    }
  }
  if (matched == null || !mounted) return;
  await _showCustomerMatchSheet(matched);
}

Future<void> _showCustomerMatchSheet(Customer match) async {
  final useIt = await showModalBottomSheet<bool>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Existing customer found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(match.name, style: const TextStyle(fontSize: 16)),
            if (match.address != null) ...[
              const SizedBox(height: 4),
              Text(match.address!,
                  style: const TextStyle(color: Colors.black54)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Different customer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Use this customer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (useIt == true && mounted) {
    setState(() {
      _matchedCustomerId = match.id;
      _nameController.text = match.name;
      _addressController.text = match.address ?? '';
    });
  }
}
```

In the phone `TextFormField`, add `focusNode: _phoneFocus`.

In `_onSubmit`, replace the `customerIdGenerator()` line with:

```dart
final customer = Customer(
  id: _matchedCustomerId ?? widget.customerIdGenerator(),
  ...
);
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: PASS — five tests green.

- [ ] **Step 5: Run the full suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
git commit -m "Add phone-on-blur customer dedup + bottom sheet pre-fill to the form

When the typed phone (normalized: strip whitespace and '+') matches an
existing customer, surface a bottom sheet with the customer's name and
address. 'Use this customer' pre-fills the name + address fields and
caches the existing customer id so submit reuses it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
```

---

### Task 11: GPS pre-fill chip

**Files:**
- Modify: `lib/src/orders/new_pickup_screen.dart`
- Modify: `test/orders/new_pickup_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Append to the test file:

```dart
  testWidgets('Use my location chip fills address from stubbed reverseGeocode',
      (tester) async {
    NewPickupResult? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<NewPickupResult>(
                    MaterialPageRoute(
                      builder: (_) => NewPickupScreen(
                        customersRepo: customersRepo,
                        ordersRepo: ordersRepo,
                        actorStaffId: 'staff-1',
                        clock: () => DateTime(2026, 5, 25, 10),
                        orderIdGenerator: () => 'uuid-order-1',
                        customerIdGenerator: () => 'uuid-cust-1',
                        geolocate: () async => const GeoLocation(
                            latitude: 0.3163, longitude: 32.5822),
                        reverseGeocode: (loc) async => 'Detected address, Kampala',
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Use my location'));
    await tester.pumpAndSettle();

    expect(
      (tester.widget<TextFormField>(find.byKey(const Key('np_address')))).controller!.text,
      'Detected address, Kampala',
    );
    // Silence the popped reference (test is asserting field contents only).
    expect(popped, isNull);
  });
```

Add an import to the test file: `import 'package:amuwak_staff/src/orders/geo_services.dart';`.

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: FAIL — no `ActionChip` with that label.

- [ ] **Step 3: Add the chip to the form**

In the build method, replace the address `TextFormField` block with:

```dart
Align(
  alignment: Alignment.centerLeft,
  child: ActionChip(
    avatar: const Icon(Icons.my_location, size: 18),
    label: const Text('Use my location'),
    onPressed: _locating ? null : _useMyLocation,
  ),
),
const SizedBox(height: 8),
TextFormField(
  key: const Key('np_address'),
  controller: _addressController,
  decoration: const InputDecoration(labelText: 'Address'),
  onChanged: (_) => setState(() {}),
),
```

Add state + method to `_NewPickupScreenState`:

```dart
bool _locating = false;

Future<void> _useMyLocation() async {
  setState(() => _locating = true);
  try {
    final loc = await widget.geolocate();
    if (loc == null) return;
    final addr = await widget.reverseGeocode(loc);
    if (addr == null || !mounted) return;
    setState(() => _addressController.text = addr);
  } finally {
    if (mounted) setState(() => _locating = false);
  }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: PASS — six tests green.

- [ ] **Step 5: Run the full suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
git commit -m "Add 'Use my location' chip to the New Pickup form

Tap → injected geolocate() → reverseGeocode() → fills address field.
Null at any step quietly resets the locating spinner without changing
the address. Web returns null cleanly via the geo_services factories.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
```

---

### Task 12: Schedule-for-later toggle + quick chips

**Files:**
- Modify: `lib/src/orders/new_pickup_screen.dart`
- Modify: `test/orders/new_pickup_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Append to the test file:

```dart
  testWidgets('Schedule for later → Tomorrow morning sets scheduledFor to '
      '9 AM next day and pops with startPickupNow=false', (tester) async {
    NewPickupResult? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<NewPickupResult>(
                    MaterialPageRoute(
                      builder: (_) => NewPickupScreen(
                        customersRepo: customersRepo,
                        ordersRepo: ordersRepo,
                        actorStaffId: 'staff-1',
                        clock: () => DateTime(2026, 5, 25, 10),
                        orderIdGenerator: () => 'uuid-order-1',
                        customerIdGenerator: () => 'uuid-cust-1',
                        geolocate: () async => null,
                        reverseGeocode: (_) async => null,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schedule for later'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tomorrow morning'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.startPickupNow, isFalse);
    final orders = await db.select(db.orders).get();
    expect(orders.single.scheduledFor, DateTime(2026, 5, 26, 9));
  });
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: FAIL — `'Schedule for later'` not found, no `ChoiceChip` for `'Tomorrow morning'`.

- [ ] **Step 3: Add the schedule UI**

At the top level of `lib/src/orders/new_pickup_screen.dart` (outside any class), add:

```dart
enum _PickupTimeMode { now, scheduled }
```

Then add to `_NewPickupScreenState`:

```dart
_PickupTimeMode _pickupMode = _PickupTimeMode.now;
DateTime? _scheduledFor;

void _setQuickSchedule(DateTime when) {
  setState(() => _scheduledFor = when);
}

Future<void> _pickCustomDateTime() async {
  final now = widget.clock();
  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: now,
    lastDate: now.add(const Duration(days: 14)),
  );
  if (date == null || !mounted) return;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now),
  );
  if (time == null || !mounted) return;
  setState(() => _scheduledFor = DateTime(
        date.year, date.month, date.day, time.hour, time.minute,
      ));
}
```

Add the UI block after the service-type dropdown, before the action buttons:

```dart
const SizedBox(height: 12),
SegmentedButton<_PickupTimeMode>(
  segments: const [
    ButtonSegment(value: _PickupTimeMode.now, label: Text('Pickup now')),
    ButtonSegment(
        value: _PickupTimeMode.scheduled, label: Text('Schedule for later')),
  ],
  selected: <_PickupTimeMode>{_pickupMode},
  onSelectionChanged: (sel) => setState(() {
    _pickupMode = sel.first;
    if (_pickupMode == _PickupTimeMode.now) _scheduledFor = null;
  }),
),
if (_pickupMode == _PickupTimeMode.scheduled) ...[
  const SizedBox(height: 12),
  Wrap(
    spacing: 8,
    children: [
      ChoiceChip(
        label: const Text('In 1 hour'),
        selected: false,
        onSelected: (_) => _setQuickSchedule(
            widget.clock().add(const Duration(hours: 1))),
      ),
      ChoiceChip(
        label: const Text('Tomorrow morning'),
        selected: false,
        onSelected: (_) {
          final t = widget.clock().add(const Duration(days: 1));
          _setQuickSchedule(DateTime(t.year, t.month, t.day, 9));
        },
      ),
      ChoiceChip(
        label: const Text('Tomorrow afternoon'),
        selected: false,
        onSelected: (_) {
          final t = widget.clock().add(const Duration(days: 1));
          _setQuickSchedule(DateTime(t.year, t.month, t.day, 14));
        },
      ),
      ChoiceChip(
        label: const Text('Custom…'),
        selected: false,
        onSelected: (_) => _pickCustomDateTime(),
      ),
    ],
  ),
  if (_scheduledFor != null) ...[
    const SizedBox(height: 8),
    Text('Scheduled for: $_scheduledFor', style: const TextStyle(color: Colors.black54)),
  ],
],
```

Update `_onSubmit` to:
- Set `scheduledFor: _scheduledFor` on the `LaundryOrder`.
- Pop with `startPickupNow: _scheduledFor == null`.
- Update the `timeLabel` to `_scheduledFor == null ? 'Pickup: now' : 'Pickup: $_scheduledFor'`.

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: PASS — seven tests green.

- [ ] **Step 5: Run the full suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
git commit -m "Add 'Schedule for later' toggle and quick-chip preset times

'Pickup now' is the default; 'Schedule for later' reveals four chips
(In 1 hour, Tomorrow morning, Tomorrow afternoon, Custom…). The
Custom… chip opens the full date+time picker. Submit pops with
startPickupNow=true when no schedule was set, false when a chip was
tapped.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
```

---

### Task 13: Optional details expansion (item count + notes)

**Files:**
- Modify: `lib/src/orders/new_pickup_screen.dart`
- Modify: `test/orders/new_pickup_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Append to the test file:

```dart
  testWidgets('Optional details: expand → stepper increments count, notes '
      'are persisted in the order row', (tester) async {
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    // Expand optional details.
    await tester.tap(find.text('Add optional details'));
    await tester.pumpAndSettle();
    // Bump count to 4.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('np_count_inc')));
      await tester.pump();
    }
    await tester.enterText(
        find.byKey(const Key('np_notes')), 'Gate locked after 6');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final orders = await db.select(db.orders).get();
    expect(orders.single.itemCount, 4);
    expect(orders.single.notes, 'Gate locked after 6');
  });
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: FAIL — `'Add optional details'` text not found.

- [ ] **Step 3: Add the expansion UI**

Add to `_NewPickupScreenState`:

```dart
bool _optionalExpanded = false;
int _count = 0;
final _notesController = TextEditingController();
```

Update `dispose` to `_notesController.dispose();`.

Insert into the build method between the schedule chips and the action buttons:

```dart
const SizedBox(height: 12),
InkWell(
  onTap: () => setState(() => _optionalExpanded = !_optionalExpanded),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Icon(_optionalExpanded ? Icons.expand_less : Icons.expand_more),
        const SizedBox(width: 8),
        const Text(
          'Add optional details',
          style: TextStyle(fontWeight: FontWeight.bold, color: amuwakDark),
        ),
      ],
    ),
  ),
),
if (_optionalExpanded) ...[
  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: _count > 0 ? () => setState(() => _count--) : null,
      ),
      SizedBox(
        width: 60,
        child: Text('$_count', textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      ),
      IconButton(
        key: const Key('np_count_inc'),
        icon: const Icon(Icons.add_circle_outline),
        onPressed: () => setState(() => _count++),
      ),
    ],
  ),
  const SizedBox(height: 8),
  TextFormField(
    key: const Key('np_notes'),
    controller: _notesController,
    decoration: const InputDecoration(labelText: 'Notes (optional)'),
    maxLines: 3,
  ),
],
```

Update `_onSubmit` to pass `itemCount: _count` and `notes: _notesController.text.trim()` into the `LaundryOrder`.

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: PASS — eight tests green.

- [ ] **Step 5: Run the full suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
git commit -m "Add collapsible 'Optional details' (item count + notes) to the form

Visible-by-default required fields stay at 5. Tap to expand reveals
the +/- stepper and a multiline notes field; submit plumbs both
through to the LaundryOrder.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
```

---

### Task 14: Dashboard wiring — `_handleNewPickup` + branch into PickupCaptureScreen

**Files:**
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart`
- Modify: `test/dashboard/staff_dashboard_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/dashboard/staff_dashboard_screen_test.dart`:

```dart
testWidgets('Tapping "New pickup", creating an order with startPickupNow=true, '
    'lands the rider on PickupCaptureScreen for the new order', (tester) async {
  // Use an in-memory DB + override providers; ensure currentUserIdProvider
  // returns a staff id so the New pickup button doesn't bail.
  // (Exact override scaffolding mirrors the existing "Tapping the bell"
  // test setup in this file — see that test for the ProviderScope shape.)
  // ... pump StaffDashboardScreen wrapped in ProviderScope with overrides ...
  await tester.tap(find.text('New pickup'));
  await tester.pumpAndSettle();

  expect(find.byType(NewPickupScreen), findsOneWidget);

  // Fill the form's required fields and submit (orderIdGenerator override
  // makes the new order id deterministic).
  await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
  await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
  await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni');
  await tester.tap(find.byKey(const Key('np_service_type')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(ServiceType.washAndIron.label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
  await tester.pumpAndSettle();

  expect(find.byType(NewPickupScreen), findsNothing);
  expect(find.byType(PickupCaptureScreen), findsOneWidget);
});
```

This test reuses the file's existing `ProviderScope` override pattern. The plan task should look at one of the existing tests in the file (e.g. "Tapping the bell opens NotificationsScreen") and copy the same `pumpWidget`/`overrides` block — including the override that stubs `currentUserIdProvider` to a non-null `'staff-1'`.

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/dashboard/staff_dashboard_screen_test.dart`
Expected: FAIL — `'New pickup'` tap currently pushes the stub `NewPickupScreen` (no required-field UI), so the form interactions can't proceed.

Note: this test will already partially pass with the old stub (the `NewPickupScreen` line) — the failure is on the form-filling step. That's expected.

- [ ] **Step 3: Add the imports**

At the top of `lib/src/dashboard/staff_dashboard_screen.dart`, add:

```dart
import '../orders/geo_services.dart';
import '../orders/new_pickup_result.dart';
import '../orders/proof/pickup_capture_screen.dart';
import '../shared/uuid.dart';
```

(The `pickup_capture_screen.dart` import probably already exists — verify before adding.)

- [ ] **Step 4: Add `_handleNewPickup`**

Insert this method into `_StaffDashboardScreenState`, alongside `_openOrderDetails`:

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
        clock: DateTime.now,
        orderIdGenerator: defaultUuidV4,
        customerIdGenerator: defaultUuidV4,
        geolocate: createDefaultGeolocate(),
        reverseGeocode: createDefaultReverseGeocode(),
      ),
    ),
  );
  if (result == null || !mounted) return;
  if (!result.startPickupNow) return;
  // Look up the freshly-written order in the current stream snapshot.
  final orders = ref.read(ordersStreamProvider).valueOrNull ?? const [];
  LaundryOrder? newOrder;
  for (final o in orders) {
    if (o.orderId == result.orderId) {
      newOrder = o;
      break;
    }
  }
  if (newOrder == null) return;          // stream hasn't emitted yet; safe to bail
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => PickupCaptureScreen(
        order: newOrder!,
        photoStorage: _photoStorage,
        pickPhoto: _pickPhoto,
        ordersRepo: ref.read(ordersRepositoryProvider),
        proofEventsRepo: ref.read(proofEventsRepositoryProvider),
        actorStaffId: staffId,
      ),
    ),
  );
}
```

- [ ] **Step 5: Rewire the "New pickup" button**

In `_QuickActions` / wherever the "New pickup" `_ActionButton` lives (currently at line 588-589 per the spec map), change:

```dart
onTap: () => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => const NewPickupScreen()),
),
```

to:

```dart
onTap: _handleNewPickup,
```

The `onTap` field's surrounding lambda will need to be reshaped — `_ActionButton` likely takes a `VoidCallback`. If the existing call is wrapped in a `Builder` or has captured context, follow the pattern at the AppBar bell's `onPressed: () => Navigator.of(context).push(...)` style — replace with a direct method tear-off.

If `_handleNewPickup` is on the State and the button is in a `StatelessWidget` subtree, pass it down as a parameter — see how `_openOrderDetails` is plumbed into `_DashboardBody` for the existing pattern.

- [ ] **Step 6: Run tests, verify they pass**

Run: `flutter test test/dashboard/staff_dashboard_screen_test.dart`
Expected: PASS — the new dashboard navigation test, plus the pre-existing ones.

- [ ] **Step 7: Run the full suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass; `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
git commit -m "Wire the dashboard's 'New pickup' button to the real form

Tapping 'New pickup' now pushes NewPickupScreen with all its
dependencies injected (customers + orders repos, actor staff id from
Riverpod, geo factories, UUID generators, clock). If the form pops a
NewPickupResult with startPickupNow=true, the dashboard looks up the
new order in the current stream snapshot and pushes
PickupCaptureScreen directly so the rider doesn't have to find the
new card and tap 'Confirm pickup'.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
```

---

## Post-execution checklist

After Task 14:

- [ ] `flutter test` is fully green.
- [ ] `flutter analyze` reports `No issues found!`.
- [ ] `grep -r 'EmptyState' lib/src/orders/new_pickup_screen.dart` returns no matches (the stub's old reference is gone).
- [ ] `git log --oneline -16` shows the 14 task commits stacked on the branch tip.
- [ ] Smoke test in a debug build: log in → tap "New pickup" → fill in name / phone / address / service type → tap "Create pickup" → confirm dashboard shows the new card AND `PickupCaptureScreen` opens with the new order.
- [ ] Smoke test the schedule path: same flow but pick "Schedule for later" → "Tomorrow morning" → submit → confirm dashboard shows the new card and PickupCaptureScreen does NOT open.
- [ ] Smoke test dedup: enter a phone that matches a seeded fixture (e.g. `+256 700 123 456`) → confirm the bottom sheet appears with `Sarah N.` → tap "Use this customer" → name + address auto-fill → submit → confirm only one customer row exists.
- [ ] Smoke test GPS chip: tap "Use my location" → confirm permission prompt → confirm address field fills.
