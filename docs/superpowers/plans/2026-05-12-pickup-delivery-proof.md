# Pickup & Delivery Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add QR-tag-based order tracking with photo + count proof at the two customer-facing bookends of a laundry order — **pickup** (rider at customer's house, status `pendingPickup`) and **delivery** (rider back at customer's house, status `readyForDelivery`). Status can only advance through these bookends *after* the proof is captured.

**Architecture:** A `List<ProofEvent>` is added to `LaundryOrder`. Two new screens (`PickupCaptureScreen`, `DeliveryCaptureScreen`) capture proof and append a `ProofEvent`, then return the updated order via `Navigator.pop`. A third screen (`ScannerScreen`) is pushed before `DeliveryCaptureScreen` to validate the bag's tag against the order id. All platform-bound surfaces (camera, image picker, image compressor, app docs dir) sit behind narrow interfaces so widget tests use fakes. Backend persistence is out of scope (per SPEC-000); photos are written to the app's documents directory only.

**Tech Stack:** Flutter (Dart `^3.8.0`), `flutter_test`. New packages: `mobile_scanner`, `qr_flutter`, `image_picker`, `flutter_image_compress`, `path_provider`.

**Out of scope (deliberate):**
- Backend / sync of `ProofEvent`s and photos (deferred per SPEC-000).
- Scanning the two shop-floor transitions (`inProgress`, `readyForDelivery`) — only the pickup and delivery bookends are scanned in M1.
- Itemized item lists (shirts, trousers, etc.) — total-count model only.
- Customer-side phone interaction (signatures, taps).
- WhatsApp customer notifications (overlaps with feature B1).
- Re-capture / correction flow for an already-captured event (deferred to future B2 incident feature).
- Cleanup of orphan photo files left by mid-capture app kills.
- RFID, pre-printed sticker rolls, hardware scanners.

**Design source:** `docs/superpowers/specs/2026-05-12-pickup-delivery-proof-design.md`.

**File Structure:**

| File | Role | Action |
|---|---|---|
| `lib/src/orders/proof_event.dart` | `ProofEvent` value class + enum | **Create** |
| `lib/src/orders/order.dart` | `LaundryOrder` model | Modify (add `proofEvents`, getters, copyWith/==/hashCode) |
| `lib/src/orders/proof/proof_photo_storage.dart` | `ProofPhotoStorage` abstract + in-memory fake + file impl | **Create** |
| `lib/src/orders/proof/barcode_reader.dart` | `CameraViewBuilder` typedef + fake camera widget + real builder factory | **Create** |
| `lib/src/orders/proof/qr_display_widget.dart` | Renders a QR for an order id | **Create** |
| `lib/src/orders/proof/scanner_screen.dart` | Camera + manual-entry tag validation screen | **Create** |
| `lib/src/orders/proof/pickup_capture_screen.dart` | Count + photos + QR-display flow | **Create** |
| `lib/src/orders/proof/delivery_capture_screen.dart` | Handover photo + finalize delivery | **Create** |
| `lib/src/orders/order_details_screen.dart` | Order details | Modify (route bookend transitions through capture screens; render history panel) |
| `pubspec.yaml` | Dependencies | Modify (5 new packages) |
| `test/orders/proof_event_test.dart` | `ProofEvent` unit tests | **Create** |
| `test/orders/order_test.dart` | `LaundryOrder` unit tests | Modify (add tests for `proofEvents`) |
| `test/orders/proof/proof_photo_storage_test.dart` | `InMemoryProofPhotoStorage` + `FileProofPhotoStorage` tests | **Create** |
| `test/orders/proof/barcode_reader_test.dart` | `FakeCameraView` test | **Create** |
| `test/orders/proof/qr_display_widget_test.dart` | QR widget test | **Create** |
| `test/orders/proof/scanner_screen_test.dart` | Scanner widget tests | **Create** |
| `test/orders/proof/pickup_capture_screen_test.dart` | Pickup widget tests | **Create** |
| `test/orders/proof/delivery_capture_screen_test.dart` | Delivery widget tests | **Create** |
| `test/orders/proof/pickup_delivery_flow_test.dart` | End-to-end integration test | **Create** |
| `test/orders/order_details_screen_test.dart` | Order details routing + history panel tests | **Create** |

---

## Pre-flight

- [ ] **Step 0a: Confirm working tree state**

Run: `git status`
Expected: clean tree or only the design/research docs from the prior brainstorm. If unrelated changes are present, stash them or **STOP** and resolve before starting.

- [ ] **Step 0b: Confirm baseline tests pass**

Run: `flutter test`
Expected: all existing tests pass (the 4 widget tests in `test/widget_test.dart` plus the 3 order-related unit test files). If any fail, **STOP** and fix before continuing.

- [ ] **Step 0c: Confirm static analysis is clean**

Run: `flutter analyze`
Expected: `No issues found!` Note any pre-existing warnings — we will not regress them.

- [ ] **Step 0d: Read the design spec end-to-end**

Open and read `docs/superpowers/specs/2026-05-12-pickup-delivery-proof-design.md`. Every decision in this plan ties back to that doc; skim it now so you can disambiguate as questions arise.

---

### Task 1: `ProofEvent` value class + enum

**Files:**
- Create: `lib/src/orders/proof_event.dart`
- Create: `test/orders/proof_event_test.dart`

- [ ] **Step 1.1: Write the failing test**

Create `test/orders/proof_event_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/proof_event.dart';

void main() {
  final pickedAt = DateTime(2026, 5, 12, 9, 42);

  group('ProofEvent', () {
    test('two ProofEvents with identical fields are equal', () {
      final a = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 12,
        photoPaths: const ['a.jpg', 'b.jpg'],
        notes: 'gate locked',
      );
      final b = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 12,
        photoPaths: const ['a.jpg', 'b.jpg'],
        notes: 'gate locked',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different type makes events unequal', () {
      final a = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 12,
        photoPaths: const ['a.jpg'],
      );
      final b = ProofEvent(
        type: ProofEventType.delivery,
        capturedAt: pickedAt,
        count: 12,
        photoPaths: const ['a.jpg'],
      );

      expect(a, isNot(equals(b)));
    });

    test('different photoPaths order makes events unequal', () {
      final a = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 1,
        photoPaths: const ['a.jpg', 'b.jpg'],
      );
      final b = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 1,
        photoPaths: const ['b.jpg', 'a.jpg'],
      );

      expect(a, isNot(equals(b)));
    });

    test('notes default to null when omitted', () {
      final a = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 1,
        photoPaths: const [],
      );

      expect(a.notes, isNull);
    });
  });
}
```

- [ ] **Step 1.2: Run the test to verify it fails**

Run: `flutter test test/orders/proof_event_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:amuwak_staff/src/orders/proof_event.dart'`.

- [ ] **Step 1.3: Write the minimal implementation**

Create `lib/src/orders/proof_event.dart`:

```dart
enum ProofEventType { pickup, delivery }

class ProofEvent {
  const ProofEvent({
    required this.type,
    required this.capturedAt,
    required this.count,
    required this.photoPaths,
    this.notes,
  });

  final ProofEventType type;
  final DateTime capturedAt;
  final int count;
  final List<String> photoPaths;
  final String? notes;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ProofEvent) return false;
    if (type != other.type) return false;
    if (capturedAt != other.capturedAt) return false;
    if (count != other.count) return false;
    if (notes != other.notes) return false;
    if (photoPaths.length != other.photoPaths.length) return false;
    for (var i = 0; i < photoPaths.length; i++) {
      if (photoPaths[i] != other.photoPaths[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        type,
        capturedAt,
        count,
        notes,
        Object.hashAll(photoPaths),
      );
}
```

- [ ] **Step 1.4: Run the test to verify it passes**

Run: `flutter test test/orders/proof_event_test.dart`
Expected: All 4 tests PASS.

- [ ] **Step 1.5: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 1.6: Commit**

```bash
git add lib/src/orders/proof_event.dart test/orders/proof_event_test.dart
git commit -m "Add ProofEvent value class with pickup/delivery types"
```

---

### Task 2: Add `proofEvents` to `LaundryOrder`

**Files:**
- Modify: `lib/src/orders/order.dart`
- Modify: `test/orders/order_test.dart`

- [ ] **Step 2.1: Add the failing tests**

Append to `test/orders/order_test.dart` (inside the existing `void main() { ... }`):

```dart
  group('LaundryOrder.proofEvents', () {
    final pickupEvent = ProofEvent(
      type: ProofEventType.pickup,
      capturedAt: DateTime(2026, 5, 12, 9, 42),
      count: 12,
      photoPaths: const ['pickup_0.jpg'],
    );
    final deliveryEvent = ProofEvent(
      type: ProofEventType.delivery,
      capturedAt: DateTime(2026, 5, 12, 16, 13),
      count: 12,
      photoPaths: const ['delivery_0.jpg'],
    );

    test('defaults to an empty list', () {
      expect(a.proofEvents, isEmpty);
      expect(a.hasPickupProof, isFalse);
      expect(a.hasDeliveryProof, isFalse);
      expect(a.pickupProof, isNull);
      expect(a.deliveryProof, isNull);
    });

    test('pickupProof returns the first pickup event', () {
      final order = a.copyWith(proofEvents: [pickupEvent, deliveryEvent]);

      expect(order.pickupProof, equals(pickupEvent));
      expect(order.hasPickupProof, isTrue);
    });

    test('deliveryProof returns the first delivery event', () {
      final order = a.copyWith(proofEvents: [pickupEvent, deliveryEvent]);

      expect(order.deliveryProof, equals(deliveryEvent));
      expect(order.hasDeliveryProof, isTrue);
    });

    test('value equality includes proofEvents', () {
      final withEvents = a.copyWith(proofEvents: [pickupEvent]);
      final withSameEvents = a.copyWith(proofEvents: [pickupEvent]);
      final withDifferentEvents = a.copyWith(proofEvents: [deliveryEvent]);

      expect(withEvents, equals(withSameEvents));
      expect(withEvents.hashCode, equals(withSameEvents.hashCode));
      expect(withEvents, isNot(equals(withDifferentEvents)));
    });

    test('copyWith preserves proofEvents when omitted', () {
      final original = a.copyWith(proofEvents: [pickupEvent]);
      final updated = original.copyWith(status: OrderStatus.inProgress);

      expect(updated.proofEvents, equals([pickupEvent]));
    });
  });
```

Then add the `ProofEvent` import at the top of the file, just below the existing imports:

```dart
import 'package:amuwak_staff/src/orders/proof_event.dart';
```

- [ ] **Step 2.2: Run the tests to verify they fail**

Run: `flutter test test/orders/order_test.dart`
Expected: the new tests FAIL — `The getter 'proofEvents' isn't defined for the type 'LaundryOrder'` (and similar for the other getters). Existing tests still PASS.

- [ ] **Step 2.3: Modify `LaundryOrder` to add the field, getters, copyWith, and equality**

Replace the entire contents of `lib/src/orders/order.dart` with:

```dart
import 'order_status.dart';
import 'proof_event.dart';

class LaundryOrder {
  const LaundryOrder({
    required this.orderId,
    required this.customerName,
    required this.serviceType,
    required this.status,
    required this.timeLabel,
    required this.itemCount,
    required this.phone,
    required this.address,
    required this.notes,
    this.proofEvents = const [],
  });

  final String orderId;
  final String customerName;
  final String serviceType;
  final OrderStatus status;
  final String timeLabel;
  final int itemCount;
  final String phone;
  final String address;
  final String notes;
  final List<ProofEvent> proofEvents;

  ProofEvent? get pickupProof => _firstOfType(ProofEventType.pickup);
  ProofEvent? get deliveryProof => _firstOfType(ProofEventType.delivery);
  bool get hasPickupProof => pickupProof != null;
  bool get hasDeliveryProof => deliveryProof != null;

  ProofEvent? _firstOfType(ProofEventType type) {
    for (final event in proofEvents) {
      if (event.type == type) return event;
    }
    return null;
  }

  LaundryOrder copyWith({
    String? orderId,
    String? customerName,
    String? serviceType,
    OrderStatus? status,
    String? timeLabel,
    int? itemCount,
    String? phone,
    String? address,
    String? notes,
    List<ProofEvent>? proofEvents,
  }) {
    return LaundryOrder(
      orderId: orderId ?? this.orderId,
      customerName: customerName ?? this.customerName,
      serviceType: serviceType ?? this.serviceType,
      status: status ?? this.status,
      timeLabel: timeLabel ?? this.timeLabel,
      itemCount: itemCount ?? this.itemCount,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      proofEvents: proofEvents ?? this.proofEvents,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LaundryOrder) return false;
    if (other.orderId != orderId ||
        other.customerName != customerName ||
        other.serviceType != serviceType ||
        other.status != status ||
        other.timeLabel != timeLabel ||
        other.itemCount != itemCount ||
        other.phone != phone ||
        other.address != address ||
        other.notes != notes) {
      return false;
    }
    if (proofEvents.length != other.proofEvents.length) return false;
    for (var i = 0; i < proofEvents.length; i++) {
      if (proofEvents[i] != other.proofEvents[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        orderId,
        customerName,
        serviceType,
        status,
        timeLabel,
        itemCount,
        phone,
        address,
        notes,
        Object.hashAll(proofEvents),
      );
}
```

- [ ] **Step 2.4: Run the tests to verify they pass**

Run: `flutter test test/orders/order_test.dart`
Expected: all tests (existing + new) PASS.

- [ ] **Step 2.5: Run the full test suite + analysis**

Run: `flutter test && flutter analyze`
Expected: all tests PASS; analysis clean.

- [ ] **Step 2.6: Commit**

```bash
git add lib/src/orders/order.dart test/orders/order_test.dart
git commit -m "Add proofEvents field and proof getters to LaundryOrder"
```

---

### Task 3: `ProofPhotoStorage` abstract + `InMemoryProofPhotoStorage` fake

**Files:**
- Create: `lib/src/orders/proof/proof_photo_storage.dart`
- Create: `test/orders/proof/proof_photo_storage_test.dart`

- [ ] **Step 3.1: Write the failing test**

Create `test/orders/proof/proof_photo_storage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

void main() {
  group('InMemoryProofPhotoStorage', () {
    test('save returns a unique-looking path that encodes order, type, index',
        () async {
      final storage = InMemoryProofPhotoStorage();

      final path = await storage.save(
        orderId: 'AMW-0421',
        type: ProofEventType.pickup,
        index: 0,
        bytes: const [1, 2, 3],
      );

      expect(path, contains('AMW-0421'));
      expect(path, contains('pickup'));
      expect(path, contains('0'));
    });

    test('save retains the bytes and path in savedPhotos', () async {
      final storage = InMemoryProofPhotoStorage();

      final path = await storage.save(
        orderId: 'AMW-1',
        type: ProofEventType.delivery,
        index: 2,
        bytes: const [9, 8, 7],
      );

      expect(storage.savedPhotos, hasLength(1));
      expect(storage.savedPhotos.single.path, equals(path));
      expect(storage.savedPhotos.single.bytes, equals(const [9, 8, 7]));
    });
  });
}
```

- [ ] **Step 3.2: Run the test to verify it fails**

Run: `flutter test test/orders/proof/proof_photo_storage_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart'`.

- [ ] **Step 3.3: Write the minimal implementation**

Create `lib/src/orders/proof/proof_photo_storage.dart`:

```dart
import '../proof_event.dart';

abstract class ProofPhotoStorage {
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  });
}

class SavedProofPhoto {
  const SavedProofPhoto({required this.path, required this.bytes});

  final String path;
  final List<int> bytes;
}

class InMemoryProofPhotoStorage implements ProofPhotoStorage {
  InMemoryProofPhotoStorage();

  final List<SavedProofPhoto> savedPhotos = [];

  @override
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  }) async {
    final path = 'memory://$orderId/${type.name}_$index';
    savedPhotos.add(SavedProofPhoto(path: path, bytes: bytes));
    return path;
  }
}
```

- [ ] **Step 3.4: Run the test to verify it passes**

Run: `flutter test test/orders/proof/proof_photo_storage_test.dart`
Expected: both tests PASS.

- [ ] **Step 3.5: Run analysis**

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 3.6: Commit**

```bash
git add lib/src/orders/proof/proof_photo_storage.dart test/orders/proof/proof_photo_storage_test.dart
git commit -m "Add ProofPhotoStorage interface with in-memory fake"
```

---

### Task 4: `CameraViewBuilder` typedef + `FakeCameraView`

**Files:**
- Create: `lib/src/orders/proof/barcode_reader.dart`
- Create: `test/orders/proof/barcode_reader_test.dart`

- [ ] **Step 4.1: Write the failing test**

Create `test/orders/proof/barcode_reader_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/proof/barcode_reader.dart';

void main() {
  testWidgets('FakeCameraView calls onDetected with scannedValue when tapped',
      (tester) async {
    String? detected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FakeCameraView(
            scannedValue: 'AMW-0421',
            onDetected: (value) => detected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Simulate scan'));
    await tester.pump();

    expect(detected, equals('AMW-0421'));
  });
}
```

- [ ] **Step 4.2: Run the test to verify it fails**

Run: `flutter test test/orders/proof/barcode_reader_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 4.3: Write the minimal implementation**

Create `lib/src/orders/proof/barcode_reader.dart`:

```dart
import 'package:flutter/material.dart';

typedef OnBarcodeDetected = void Function(String value);

typedef CameraViewBuilder = Widget Function(
  BuildContext context,
  OnBarcodeDetected onDetected,
);

class FakeCameraView extends StatelessWidget {
  const FakeCameraView({
    super.key,
    required this.scannedValue,
    required this.onDetected,
  });

  final String scannedValue;
  final OnBarcodeDetected onDetected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => onDetected(scannedValue),
        child: const Text('Simulate scan'),
      ),
    );
  }
}
```

- [ ] **Step 4.4: Run the test to verify it passes**

Run: `flutter test test/orders/proof/barcode_reader_test.dart`
Expected: PASS.

- [ ] **Step 4.5: Commit**

```bash
git add lib/src/orders/proof/barcode_reader.dart test/orders/proof/barcode_reader_test.dart
git commit -m "Add CameraViewBuilder abstraction and FakeCameraView"
```

---

### Task 5: Add new dependencies to `pubspec.yaml`

**Files:**
- Modify: `pubspec.yaml`

No tests for this task — it's a pure dependency declaration. Verification is `flutter pub get` succeeding and `flutter test` not regressing.

- [ ] **Step 5.1: Add the dependencies**

Modify the `dependencies:` block in `pubspec.yaml`. Find:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8
```

Replace with:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8

  # Pickup & delivery proof feature
  mobile_scanner: ^5.2.3
  qr_flutter: ^4.1.0
  image_picker: ^1.1.2
  flutter_image_compress: ^2.3.0
  path_provider: ^2.1.4
```

(If any of those exact versions has been yanked or supplanted by the time you execute this, run `flutter pub upgrade --major-versions <package>` after the first `pub get` and accept the latest stable. Keep the package set the same.)

- [ ] **Step 5.2: Resolve dependencies**

Run: `flutter pub get`
Expected: dependencies resolved; `pubspec.lock` updated. If resolution fails, **STOP** and investigate (likely a version conflict; pin compatible versions).

- [ ] **Step 5.3: Run the full test suite + analysis**

Run: `flutter test && flutter analyze`
Expected: all existing tests PASS; analysis clean. (No new code calls these packages yet.)

- [ ] **Step 5.4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "Add packages for pickup/delivery proof: scanner, qr, picker, compress, path_provider"
```

---

### Task 6: `FileProofPhotoStorage` concrete implementation

**Files:**
- Modify: `lib/src/orders/proof/proof_photo_storage.dart`
- Modify: `test/orders/proof/proof_photo_storage_test.dart`

- [ ] **Step 6.1: Add failing tests for `FileProofPhotoStorage`**

Append to `test/orders/proof/proof_photo_storage_test.dart` (inside the existing `void main() { ... }`):

```dart
  group('FileProofPhotoStorage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('proof_photo_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<Uint8List> identityCompressor(Uint8List bytes) async => bytes;

    test('save writes a jpg under <baseDir>/proofs/<orderId>/', () async {
      final fixedClock = DateTime(2026, 5, 12, 9, 42, 0).millisecondsSinceEpoch;
      final storage = FileProofPhotoStorage(
        baseDir: tempDir,
        compressor: identityCompressor,
        clock: () => DateTime.fromMillisecondsSinceEpoch(fixedClock),
      );

      final path = await storage.save(
        orderId: 'AMW-1',
        type: ProofEventType.pickup,
        index: 0,
        bytes: const [1, 2, 3, 4],
      );

      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(path, contains('proofs${Platform.pathSeparator}AMW-1'));
      expect(path, endsWith('pickup_${fixedClock}_0.jpg'));
      expect(await file.readAsBytes(), equals(const [1, 2, 3, 4]));
    });

    test('save creates the order directory if missing', () async {
      final storage = FileProofPhotoStorage(
        baseDir: tempDir,
        compressor: identityCompressor,
      );

      final orderDir =
          Directory('${tempDir.path}/proofs/NEW-ORDER');
      expect(await orderDir.exists(), isFalse);

      await storage.save(
        orderId: 'NEW-ORDER',
        type: ProofEventType.delivery,
        index: 1,
        bytes: const [9, 9, 9],
      );

      expect(await orderDir.exists(), isTrue);
    });

    test('save runs bytes through the compressor before writing', () async {
      var compressorCalled = false;
      Future<Uint8List> spyCompressor(Uint8List bytes) async {
        compressorCalled = true;
        return Uint8List.fromList(bytes.reversed.toList());
      }

      final storage = FileProofPhotoStorage(
        baseDir: tempDir,
        compressor: spyCompressor,
      );

      final path = await storage.save(
        orderId: 'AMW-2',
        type: ProofEventType.pickup,
        index: 0,
        bytes: const [1, 2, 3],
      );

      expect(compressorCalled, isTrue);
      expect(await File(path).readAsBytes(), equals(const [3, 2, 1]));
    });
  });
```

Add the following imports to the top of `test/orders/proof/proof_photo_storage_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
```

- [ ] **Step 6.2: Run the tests to verify they fail**

Run: `flutter test test/orders/proof/proof_photo_storage_test.dart`
Expected: the 3 new `FileProofPhotoStorage` tests FAIL — `Undefined name 'FileProofPhotoStorage'`. Existing `InMemoryProofPhotoStorage` tests still PASS.

- [ ] **Step 6.3: Implement `FileProofPhotoStorage`**

Replace the entire contents of `lib/src/orders/proof/proof_photo_storage.dart` with:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../proof_event.dart';

abstract class ProofPhotoStorage {
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  });
}

class SavedProofPhoto {
  const SavedProofPhoto({required this.path, required this.bytes});

  final String path;
  final List<int> bytes;
}

class InMemoryProofPhotoStorage implements ProofPhotoStorage {
  InMemoryProofPhotoStorage();

  final List<SavedProofPhoto> savedPhotos = [];

  @override
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  }) async {
    final path = 'memory://$orderId/${type.name}_$index';
    savedPhotos.add(SavedProofPhoto(path: path, bytes: bytes));
    return path;
  }
}

typedef PhotoCompressor = Future<Uint8List> Function(Uint8List bytes);

class FileProofPhotoStorage implements ProofPhotoStorage {
  FileProofPhotoStorage({
    required this.baseDir,
    required this.compressor,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory baseDir;
  final PhotoCompressor compressor;
  final DateTime Function() _clock;

  @override
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  }) async {
    final orderDir =
        Directory('${baseDir.path}${Platform.pathSeparator}proofs${Platform.pathSeparator}$orderId');
    if (!await orderDir.exists()) {
      await orderDir.create(recursive: true);
    }
    final compressed = await compressor(Uint8List.fromList(bytes));
    final filename =
        '${type.name}_${_clock().millisecondsSinceEpoch}_$index.jpg';
    final file = File('${orderDir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(compressed);
    return file.path;
  }
}

/// Production factory: resolves the app documents directory via path_provider
/// and uses flutter_image_compress to shrink images to 1280px max edge at
/// JPEG quality 80.
Future<FileProofPhotoStorage> createDefaultProofPhotoStorage() async {
  final dir = await getApplicationDocumentsDirectory();
  return FileProofPhotoStorage(
    baseDir: dir,
    compressor: (bytes) async {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1280,
        minHeight: 1280,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      return result;
    },
  );
}
```

- [ ] **Step 6.4: Run the tests to verify they pass**

Run: `flutter test test/orders/proof/proof_photo_storage_test.dart`
Expected: all 5 tests PASS.

- [ ] **Step 6.5: Run analysis**

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 6.6: Commit**

```bash
git add lib/src/orders/proof/proof_photo_storage.dart test/orders/proof/proof_photo_storage_test.dart
git commit -m "Add FileProofPhotoStorage with injectable baseDir and compressor"
```

---

### Task 7: `MobileScanner`-backed `CameraViewBuilder` factory

**Files:**
- Modify: `lib/src/orders/proof/barcode_reader.dart`

This task adds a small factory that returns a real-camera `CameraViewBuilder` using `mobile_scanner`. The widget itself is platform-bound (camera); we do not unit-test it. The fake we already have (`FakeCameraView`) is what tests use.

- [ ] **Step 7.1: Append the production factory to `barcode_reader.dart`**

Open `lib/src/orders/proof/barcode_reader.dart` and add this import at the top:

```dart
import 'package:mobile_scanner/mobile_scanner.dart';
```

Then append at the end of the file:

```dart
/// Production factory: returns a `CameraViewBuilder` that uses `mobile_scanner`
/// to scan QR codes via the device camera. The first detected barcode's raw
/// value is forwarded to `onDetected`.
CameraViewBuilder mobileScannerCameraViewBuilder() {
  return (context, onDetected) {
    return MobileScanner(
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null) {
            onDetected(value);
            return;
          }
        }
      },
    );
  };
}
```

- [ ] **Step 7.2: Run the test suite + analysis**

Run: `flutter test && flutter analyze`
Expected: all existing tests PASS; analysis clean.

- [ ] **Step 7.3: Commit**

```bash
git add lib/src/orders/proof/barcode_reader.dart
git commit -m "Add mobile_scanner-backed CameraViewBuilder factory"
```

---

### Task 8: `QrDisplayWidget`

**Files:**
- Create: `lib/src/orders/proof/qr_display_widget.dart`
- Create: `test/orders/proof/qr_display_widget_test.dart`

- [ ] **Step 8.1: Write the failing test**

Create `test/orders/proof/qr_display_widget_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:amuwak_staff/src/orders/proof/qr_display_widget.dart';

void main() {
  testWidgets('QrDisplayWidget renders a QrImageView with the given data',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QrDisplayWidget(data: 'AMW-0421', size: 200),
        ),
      ),
    );

    final qrFinder = find.byType(QrImageView);
    expect(qrFinder, findsOneWidget);

    final qr = tester.widget<QrImageView>(qrFinder);
    expect(qr.data, equals('AMW-0421'));
    expect(qr.size, equals(200));
  });
}
```

- [ ] **Step 8.2: Run the test to verify it fails**

Run: `flutter test test/orders/proof/qr_display_widget_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:amuwak_staff/src/orders/proof/qr_display_widget.dart'`.

- [ ] **Step 8.3: Write the minimal implementation**

Create `lib/src/orders/proof/qr_display_widget.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrDisplayWidget extends StatelessWidget {
  const QrDisplayWidget({
    super.key,
    required this.data,
    this.size = 240,
  });

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
    );
  }
}
```

- [ ] **Step 8.4: Run the test to verify it passes**

Run: `flutter test test/orders/proof/qr_display_widget_test.dart`
Expected: PASS.

- [ ] **Step 8.5: Commit**

```bash
git add lib/src/orders/proof/qr_display_widget.dart test/orders/proof/qr_display_widget_test.dart
git commit -m "Add QrDisplayWidget rendering a QR for an order id"
```

---

### Task 9: `ScannerScreen`

**Files:**
- Create: `lib/src/orders/proof/scanner_screen.dart`
- Create: `test/orders/proof/scanner_screen_test.dart`

- [ ] **Step 9.1: Write the failing test**

Create `test/orders/proof/scanner_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/proof/barcode_reader.dart';
import 'package:amuwak_staff/src/orders/proof/scanner_screen.dart';

Future<bool?> _pumpAndPushScanner(
  WidgetTester tester, {
  required String expectedOrderId,
  required String scannedValue,
}) async {
  bool? result;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ScannerScreen(
                        expectedOrderId: expectedOrderId,
                        cameraViewBuilder: (ctx, onDetected) {
                          return FakeCameraView(
                            scannedValue: scannedValue,
                            onDetected: onDetected,
                          );
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Open scanner'),
              ),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('Open scanner'));
  await tester.pumpAndSettle();
  return Future.value(result);
}

void main() {
  testWidgets('matching scanned value pops the screen with true',
      (tester) async {
    await _pumpAndPushScanner(
      tester,
      expectedOrderId: 'AMW-1',
      scannedValue: 'AMW-1',
    );

    await tester.tap(find.text('Simulate scan'));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerScreen), findsNothing);
  });

  testWidgets('wrong scanned value shows an error and stays on screen',
      (tester) async {
    await _pumpAndPushScanner(
      tester,
      expectedOrderId: 'AMW-1',
      scannedValue: 'AMW-9',
    );

    await tester.tap(find.text('Simulate scan'));
    await tester.pump();

    expect(find.byType(ScannerScreen), findsOneWidget);
    expect(find.textContaining('AMW-9'), findsOneWidget);
    expect(find.textContaining('AMW-1'), findsOneWidget);
  });

  testWidgets('manual entry path: matching id pops with true', (tester) async {
    await _pumpAndPushScanner(
      tester,
      expectedOrderId: 'AMW-1',
      scannedValue: 'unused',
    );

    await tester.tap(find.text('Enter order ID instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'AMW-1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerScreen), findsNothing);
  });

  testWidgets('manual entry path: wrong id shows error', (tester) async {
    await _pumpAndPushScanner(
      tester,
      expectedOrderId: 'AMW-1',
      scannedValue: 'unused',
    );

    await tester.tap(find.text('Enter order ID instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'AMW-9');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pump();

    expect(find.byType(ScannerScreen), findsOneWidget);
    expect(find.textContaining('AMW-9'), findsOneWidget);
  });
}
```

- [ ] **Step 9.2: Run the test to verify it fails**

Run: `flutter test test/orders/proof/scanner_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:amuwak_staff/src/orders/proof/scanner_screen.dart'`.

- [ ] **Step 9.3: Write the implementation**

Create `lib/src/orders/proof/scanner_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../shared/widgets/app_theme.dart';
import 'barcode_reader.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    required this.expectedOrderId,
    required this.cameraViewBuilder,
  });

  final String expectedOrderId;
  final CameraViewBuilder cameraViewBuilder;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _showManualEntry = false;
  final TextEditingController _manualController = TextEditingController();
  String? _errorMessage;

  void _handleDetected(String value) {
    final trimmed = value.trim();
    if (trimmed == widget.expectedOrderId) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _errorMessage =
          'This tag belongs to order #$trimmed, not #${widget.expectedOrderId}.';
    });
  }

  void _submitManual() {
    _handleDetected(_manualController.text);
  }

  void _toggleManual() {
    setState(() {
      _showManualEntry = !_showManualEntry;
      _errorMessage = null;
      _manualController.clear();
    });
  }

  @override
  void dispose() {
    _manualController.dispose();
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
        title: const Text('Scan order tag'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop<bool>(context, false),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _showManualEntry
                  ? _ManualEntryView(
                      controller: _manualController,
                      onSubmit: _submitManual,
                      errorMessage: _errorMessage,
                    )
                  : widget.cameraViewBuilder(context, _handleDetected),
            ),
            if (!_showManualEntry && _errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: TextButton(
                onPressed: _toggleManual,
                child: Text(
                  _showManualEntry
                      ? 'Use camera instead'
                      : 'Enter order ID instead',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualEntryView extends StatelessWidget {
  const _ManualEntryView({
    required this.controller,
    required this.onSubmit,
    required this.errorMessage,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Order ID written on the bag',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: amuwakDark,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'e.g. AMW-0421',
              border: OutlineInputBorder(),
            ),
            onFieldSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 12),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                errorMessage!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ElevatedButton(
            onPressed: onSubmit,
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 9.4: Run the test to verify it passes**

Run: `flutter test test/orders/proof/scanner_screen_test.dart`
Expected: all 4 tests PASS.

- [ ] **Step 9.5: Commit**

```bash
git add lib/src/orders/proof/scanner_screen.dart test/orders/proof/scanner_screen_test.dart
git commit -m "Add ScannerScreen with camera and manual-entry tag validation"
```

---

### Task 10: `PickupCaptureScreen`

**Files:**
- Create: `lib/src/orders/proof/pickup_capture_screen.dart`
- Create: `test/orders/proof/pickup_capture_screen_test.dart`

The screen has two visual stages: **collecting** (count + photos + notes), then **showQr** (after Confirm) showing the QR for the rider to transcribe. Tapping Done on the QR stage saves photos, appends a `ProofEvent`, transitions the order's status to `OrderStatus.inProgress`, and pops with the updated order. Photo capture is abstracted behind a `pickPhoto` function so tests can supply canned bytes.

- [ ] **Step 10.1: Write the failing test**

Create `test/orders/proof/pickup_capture_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/pickup_capture_screen.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

const _baseOrder = LaundryOrder(
  orderId: 'AMW-0421',
  customerName: 'Jane Doe',
  serviceType: 'Wash & iron',
  status: OrderStatus.pendingPickup,
  timeLabel: 'Today, 09:00',
  itemCount: 12,
  phone: '+234000',
  address: '5 Yaba',
  notes: 'Gate locked',
);

Future<LaundryOrder?> _pumpAndPushPickup(
  WidgetTester tester, {
  required InMemoryProofPhotoStorage storage,
  required LaundryOrder order,
  Future<List<int>?> Function()? pickPhoto,
  DateTime Function()? clock,
}) async {
  LaundryOrder? result;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<LaundryOrder>(
                    MaterialPageRoute(
                      builder: (_) => PickupCaptureScreen(
                        order: order,
                        photoStorage: storage,
                        pickPhoto:
                            pickPhoto ?? () async => const [1, 2, 3, 4],
                        clock:
                            clock ?? () => DateTime(2026, 5, 12, 9, 42),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  // result is set inside the callback once Pickup pops; expose via closure.
  return Future<LaundryOrder?>.value().then((_) => result);
}

void main() {
  testWidgets(
      'Confirm button is disabled until count > 0 AND at least one photo is captured',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    await _pumpAndPushPickup(tester, storage: storage, order: _baseOrder);

    final confirmButton = find.widgetWithText(
      ElevatedButton,
      'Confirm with customer',
    );
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);

    // Increment count to 1; still no photo, still disabled.
    await tester.tap(find.byKey(const Key('count_increment')));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);

    // Add a photo; now enabled.
    await tester.tap(find.byKey(const Key('add_photo')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(confirmButton).onPressed,
      isNotNull,
    );
  });

  testWidgets(
      'Tapping Done writes a pickup ProofEvent and pops with status inProgress',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    LaundryOrder? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured =
                        await Navigator.of(context).push<LaundryOrder>(
                      MaterialPageRoute(
                        builder: (_) => PickupCaptureScreen(
                          order: _baseOrder,
                          photoStorage: storage,
                          pickPhoto: () async => const [10, 20, 30],
                          clock: () => DateTime(2026, 5, 12, 9, 42),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Bump count to 12 (matches expected itemCount).
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.byKey(const Key('count_increment')));
      await tester.pump();
    }

    // Add a photo.
    await tester.tap(find.byKey(const Key('add_photo')));
    await tester.pumpAndSettle();

    // Tap Confirm → moves to QR stage.
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Confirm with customer'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tie tag to the bag'), findsOneWidget);

    // Tap Done → pops back with updated order.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.status, equals(OrderStatus.inProgress));
    expect(captured!.proofEvents, hasLength(1));
    final event = captured!.proofEvents.single;
    expect(event.type, equals(ProofEventType.pickup));
    expect(event.count, equals(12));
    expect(event.photoPaths, hasLength(1));
    expect(storage.savedPhotos, hasLength(1));
    expect(storage.savedPhotos.single.bytes, equals(const [10, 20, 30]));
  });
}
```

- [ ] **Step 10.2: Run the test to verify it fails**

Run: `flutter test test/orders/proof/pickup_capture_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:amuwak_staff/src/orders/proof/pickup_capture_screen.dart'`.

- [ ] **Step 10.3: Write the implementation**

Create `lib/src/orders/proof/pickup_capture_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../shared/widgets/app_theme.dart';
import '../order.dart';
import '../order_status.dart';
import '../proof_event.dart';
import 'proof_photo_storage.dart';
import 'qr_display_widget.dart';

typedef PickPhotoFn = Future<List<int>?> Function();

enum _Stage { collecting, showQr }

class PickupCaptureScreen extends StatefulWidget {
  PickupCaptureScreen({
    super.key,
    required this.order,
    required this.photoStorage,
    required this.pickPhoto,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final LaundryOrder order;
  final ProofPhotoStorage photoStorage;
  final PickPhotoFn pickPhoto;
  final DateTime Function() clock;

  @override
  State<PickupCaptureScreen> createState() => _PickupCaptureScreenState();
}

class _PickupCaptureScreenState extends State<PickupCaptureScreen> {
  _Stage _stage = _Stage.collecting;
  int _count = 0;
  final List<List<int>> _photoBytes = [];
  final TextEditingController _notesController = TextEditingController();
  bool _saving = false;

  static const int _maxPhotos = 3;

  bool get _canConfirm =>
      _count > 0 && _photoBytes.isNotEmpty && !_saving;

  Future<void> _addPhoto() async {
    if (_photoBytes.length >= _maxPhotos) return;
    final bytes = await widget.pickPhoto();
    if (bytes == null) return;
    setState(() {
      _photoBytes.add(bytes);
    });
  }

  void _onConfirm() {
    setState(() {
      _stage = _Stage.showQr;
    });
  }

  Future<void> _onDone() async {
    if (_saving) return;
    setState(() => _saving = true);
    final paths = <String>[];
    for (var i = 0; i < _photoBytes.length; i++) {
      final path = await widget.photoStorage.save(
        orderId: widget.order.orderId,
        type: ProofEventType.pickup,
        index: i,
        bytes: _photoBytes[i],
      );
      paths.add(path);
    }
    final event = ProofEvent(
      type: ProofEventType.pickup,
      capturedAt: widget.clock(),
      count: _count,
      photoPaths: paths,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    final updated = widget.order.copyWith(
      status: OrderStatus.inProgress,
      proofEvents: [...widget.order.proofEvents, event],
    );
    if (!mounted) return;
    Navigator.pop<LaundryOrder>(context, updated);
  }

  @override
  void dispose() {
    _notesController.dispose();
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
        title: Text(
          _stage == _Stage.collecting ? 'Confirm pickup' : 'Tag the bag',
        ),
      ),
      body: SafeArea(
        child: _stage == _Stage.collecting
            ? _buildCollecting()
            : _buildQrStage(),
      ),
    );
  }

  Widget _buildCollecting() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          widget.order.customerName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: amuwakDark,
          ),
        ),
        Text(
          'Expected ${widget.order.itemCount} items · ${widget.order.address}',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        const Text(
          'How many items?',
          style: TextStyle(fontWeight: FontWeight.bold, color: amuwakDark),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('count_decrement'),
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: _count > 0
                  ? () => setState(() => _count--)
                  : null,
            ),
            SizedBox(
              width: 60,
              child: Text(
                '$_count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              key: const Key('count_increment'),
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => setState(() => _count++),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Photos (${_photoBytes.length}/$_maxPhotos)',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: amuwakDark,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _photoBytes.length; i++)
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: amuwakSoftAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.image_outlined),
              ),
            if (_photoBytes.length < _maxPhotos)
              GestureDetector(
                key: const Key('add_photo'),
                onTap: _addPhoto,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    border: Border.all(color: amuwakPrimary),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add_a_photo_outlined,
                    color: amuwakPrimary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _canConfirm ? _onConfirm : null,
          child: const Text('Confirm with customer'),
        ),
      ],
    );
  }

  Widget _buildQrStage() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'Tie tag to the bag',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: amuwakDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Write order #${widget.order.orderId} on the bag, or scan this QR.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          QrDisplayWidget(data: widget.order.orderId),
          const SizedBox(height: 16),
          Text(
            widget.order.orderId,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: amuwakDark,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _onDone,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 10.4: Run the test to verify it passes**

Run: `flutter test test/orders/proof/pickup_capture_screen_test.dart`
Expected: both tests PASS.

- [ ] **Step 10.5: Run analysis**

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 10.6: Commit**

```bash
git add lib/src/orders/proof/pickup_capture_screen.dart test/orders/proof/pickup_capture_screen_test.dart
git commit -m "Add PickupCaptureScreen with count, photos, and QR display"
```

---

### Task 11: `DeliveryCaptureScreen`

**Files:**
- Create: `lib/src/orders/proof/delivery_capture_screen.dart`
- Create: `test/orders/proof/delivery_capture_screen_test.dart`

This screen is reached **after** the scanner has already validated the tag (the OrderDetailsScreen pushes the scanner first; on `true`, it pushes this screen). It shows pickup-proof reference, takes one or more handover photos, and on Mark delivered appends a delivery `ProofEvent` and moves status to `completed`.

- [ ] **Step 11.1: Write the failing test**

Create `test/orders/proof/delivery_capture_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/delivery_capture_screen.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

LaundryOrder _orderReadyForDelivery() {
  return LaundryOrder(
    orderId: 'AMW-0421',
    customerName: 'Jane Doe',
    serviceType: 'Wash & iron',
    status: OrderStatus.readyForDelivery,
    timeLabel: 'Today, 16:00',
    itemCount: 12,
    phone: '+234000',
    address: '5 Yaba',
    notes: '',
    proofEvents: [
      ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: DateTime(2026, 5, 12, 9, 42),
        count: 12,
        photoPaths: const ['memory://AMW-0421/pickup_0'],
      ),
    ],
  );
}

void main() {
  testWidgets('Mark delivered is disabled until a handover photo is captured',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final order = _orderReadyForDelivery();

    await tester.pumpWidget(
      MaterialApp(
        home: DeliveryCaptureScreen(
          order: order,
          photoStorage: storage,
          pickPhoto: () async => const [1, 2, 3],
          clock: () => DateTime(2026, 5, 12, 16, 13),
        ),
      ),
    );

    final button = find.widgetWithText(ElevatedButton, 'Mark delivered');
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    expect(find.text('Pickup count: 12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_handover_photo')));
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
  });

  testWidgets(
      'Mark delivered appends a delivery ProofEvent and pops with status completed',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    LaundryOrder? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured =
                        await Navigator.of(context).push<LaundryOrder>(
                      MaterialPageRoute(
                        builder: (_) => DeliveryCaptureScreen(
                          order: _orderReadyForDelivery(),
                          photoStorage: storage,
                          pickPhoto: () async => const [50, 60, 70],
                          clock: () => DateTime(2026, 5, 12, 16, 13),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_handover_photo')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark delivered'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.status, equals(OrderStatus.completed));
    expect(captured!.proofEvents, hasLength(2));
    final delivery = captured!.deliveryProof!;
    expect(delivery.type, equals(ProofEventType.delivery));
    expect(delivery.photoPaths, hasLength(1));
    expect(storage.savedPhotos, hasLength(1));
    expect(storage.savedPhotos.single.bytes, equals(const [50, 60, 70]));
  });
}
```

- [ ] **Step 11.2: Run the test to verify it fails**

Run: `flutter test test/orders/proof/delivery_capture_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 11.3: Write the implementation**

Create `lib/src/orders/proof/delivery_capture_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../shared/widgets/app_theme.dart';
import '../order.dart';
import '../order_status.dart';
import '../proof_event.dart';
import 'pickup_capture_screen.dart' show PickPhotoFn;
import 'proof_photo_storage.dart';

class DeliveryCaptureScreen extends StatefulWidget {
  DeliveryCaptureScreen({
    super.key,
    required this.order,
    required this.photoStorage,
    required this.pickPhoto,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final LaundryOrder order;
  final ProofPhotoStorage photoStorage;
  final PickPhotoFn pickPhoto;
  final DateTime Function() clock;

  @override
  State<DeliveryCaptureScreen> createState() => _DeliveryCaptureScreenState();
}

class _DeliveryCaptureScreenState extends State<DeliveryCaptureScreen> {
  final List<List<int>> _photoBytes = [];
  final TextEditingController _notesController = TextEditingController();
  bool _saving = false;

  static const int _maxPhotos = 3;

  bool get _canDeliver => _photoBytes.isNotEmpty && !_saving;

  Future<void> _addPhoto() async {
    if (_photoBytes.length >= _maxPhotos) return;
    final bytes = await widget.pickPhoto();
    if (bytes == null) return;
    setState(() {
      _photoBytes.add(bytes);
    });
  }

  Future<void> _markDelivered() async {
    if (_saving) return;
    setState(() => _saving = true);
    final paths = <String>[];
    for (var i = 0; i < _photoBytes.length; i++) {
      final path = await widget.photoStorage.save(
        orderId: widget.order.orderId,
        type: ProofEventType.delivery,
        index: i,
        bytes: _photoBytes[i],
      );
      paths.add(path);
    }
    final event = ProofEvent(
      type: ProofEventType.delivery,
      capturedAt: widget.clock(),
      count: widget.order.pickupProof?.count ?? widget.order.itemCount,
      photoPaths: paths,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    final updated = widget.order.copyWith(
      status: OrderStatus.completed,
      proofEvents: [...widget.order.proofEvents, event],
    );
    if (!mounted) return;
    Navigator.pop<LaundryOrder>(context, updated);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.order.pickupProof;
    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text('Hand over'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              widget.order.customerName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: amuwakDark,
              ),
            ),
            Text(
              widget.order.address,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: amuwakWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: amuwakSoftAccent),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'From pickup',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: amuwakDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pickup == null
                        ? 'No pickup proof on file.'
                        : 'Pickup count: ${pickup.count}',
                    style: const TextStyle(color: Colors.black87),
                  ),
                  if (pickup != null && pickup.photoPaths.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${pickup.photoPaths.length} photo(s) on file',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Handover photos (${_photoBytes.length}/$_maxPhotos)',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: amuwakDark,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _photoBytes.length; i++)
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: amuwakSoftAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.image_outlined),
                  ),
                if (_photoBytes.length < _maxPhotos)
                  GestureDetector(
                    key: const Key('add_handover_photo'),
                    onTap: _addPhoto,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        border: Border.all(color: amuwakPrimary),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add_a_photo_outlined,
                        color: amuwakPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _canDeliver ? _markDelivered : null,
              child: const Text('Mark delivered'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 11.4: Run the test to verify it passes**

Run: `flutter test test/orders/proof/delivery_capture_screen_test.dart`
Expected: both tests PASS.

- [ ] **Step 11.5: Run the full test suite + analysis**

Run: `flutter test && flutter analyze`
Expected: all tests PASS; analysis clean.

- [ ] **Step 11.6: Commit**

```bash
git add lib/src/orders/proof/delivery_capture_screen.dart test/orders/proof/delivery_capture_screen_test.dart
git commit -m "Add DeliveryCaptureScreen with handover photo and pickup reference"
```

---

### Task 12: Wire `OrderDetailsScreen` to route bookend transitions through proof screens

**Files:**
- Modify: `lib/src/orders/order_details_screen.dart`
- Create: `test/orders/order_details_screen_test.dart`

The existing button (`Move to {nextStatus.label}`) is replaced with a status-aware action: at `pendingPickup` → "Confirm pickup" (routes to `PickupCaptureScreen`); at `readyForDelivery` → "Deliver" (routes to `ScannerScreen`, then `DeliveryCaptureScreen` on success); at `inProgress` → keeps the existing "Move to Ready for delivery" tap (still a direct status change); at `completed` → disabled.

For testability the screen takes optional injected `photoStorage`, `pickPhoto`, `cameraViewBuilder`, and `clock` — production passes the defaults via a factory in `main.dart` (Task 14b below).

- [ ] **Step 12.1: Write the failing widget test**

Create `test/orders/order_details_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/barcode_reader.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

const _pendingPickup = LaundryOrder(
  orderId: 'AMW-0421',
  customerName: 'Jane',
  serviceType: 'Wash',
  status: OrderStatus.pendingPickup,
  timeLabel: 't',
  itemCount: 12,
  phone: 'p',
  address: 'a',
  notes: '',
);

Widget _wrap(LaundryOrder order, {
  required InMemoryProofPhotoStorage storage,
  String scannedValue = 'AMW-0421',
  Future<List<int>?> Function()? pickPhoto,
}) {
  return MaterialApp(
    home: OrderDetailsScreen(
      order: order,
      photoStorage: storage,
      pickPhoto: pickPhoto ?? () async => const [1, 2, 3],
      cameraViewBuilder: (context, onDetected) {
        return FakeCameraView(
          scannedValue: scannedValue,
          onDetected: onDetected,
        );
      },
      clock: () => DateTime(2026, 5, 12, 9, 42),
    ),
  );
}

void main() {
  testWidgets(
      'pendingPickup shows "Confirm pickup" and routes to PickupCaptureScreen',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    await tester.pumpWidget(_wrap(_pendingPickup, storage: storage));

    expect(
      find.widgetWithText(ElevatedButton, 'Confirm pickup'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm pickup'));
    await tester.pumpAndSettle();

    expect(find.text('How many items?'), findsOneWidget);
  });

  testWidgets(
      'readyForDelivery shows "Deliver" and routes through scanner to delivery',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final readyOrder = _pendingPickup.copyWith(
      status: OrderStatus.readyForDelivery,
      proofEvents: [
        ProofEvent(
          type: ProofEventType.pickup,
          capturedAt: DateTime(2026, 5, 12, 9, 42),
          count: 12,
          photoPaths: const ['memory://AMW-0421/pickup_0'],
        ),
      ],
    );

    await tester.pumpWidget(_wrap(readyOrder, storage: storage));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Deliver'));
    await tester.pumpAndSettle();

    expect(find.text('Scan order tag'), findsOneWidget);

    await tester.tap(find.text('Simulate scan'));
    await tester.pumpAndSettle();

    expect(find.text('Hand over'), findsOneWidget);
  });

  testWidgets(
      'inProgress keeps existing direct status-advance button',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final inProgress = _pendingPickup.copyWith(status: OrderStatus.inProgress);

    await tester.pumpWidget(_wrap(inProgress, storage: storage));

    expect(
      find.widgetWithText(ElevatedButton, 'Move to Ready for delivery'),
      findsOneWidget,
    );
  });

  testWidgets(
      'order with proofEvents renders a History panel',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final delivered = _pendingPickup.copyWith(
      status: OrderStatus.completed,
      proofEvents: [
        ProofEvent(
          type: ProofEventType.pickup,
          capturedAt: DateTime(2026, 5, 12, 9, 42),
          count: 12,
          photoPaths: const ['memory://AMW-0421/pickup_0'],
        ),
        ProofEvent(
          type: ProofEventType.delivery,
          capturedAt: DateTime(2026, 5, 12, 16, 13),
          count: 12,
          photoPaths: const ['memory://AMW-0421/delivery_0'],
        ),
      ],
    );

    await tester.pumpWidget(_wrap(delivered, storage: storage));

    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('Pickup'), findsWidgets);
    expect(find.textContaining('Delivery'), findsWidgets);
  });
}
```

- [ ] **Step 12.2: Run the test to verify it fails**

Run: `flutter test test/orders/order_details_screen_test.dart`
Expected: tests FAIL — `The named parameter 'photoStorage' isn't defined` (plus several similar). The existing widget tests in `test/widget_test.dart` still PASS because they don't open the order details screen.

- [ ] **Step 12.3: Modify `OrderDetailsScreen`**

Replace the entire contents of `lib/src/orders/order_details_screen.dart` with:

```dart
import 'package:flutter/material.dart';

import '../shared/widgets/app_theme.dart';
import 'order.dart';
import 'order_status.dart';
import 'proof_event.dart';
import 'proof/barcode_reader.dart';
import 'proof/delivery_capture_screen.dart';
import 'proof/pickup_capture_screen.dart';
import 'proof/proof_photo_storage.dart';
import 'proof/scanner_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  OrderDetailsScreen({
    super.key,
    required this.order,
    required this.photoStorage,
    required this.pickPhoto,
    required this.cameraViewBuilder,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final LaundryOrder order;
  final ProofPhotoStorage photoStorage;
  final PickPhotoFn pickPhoto;
  final CameraViewBuilder cameraViewBuilder;
  final DateTime Function() clock;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late LaundryOrder _order;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  void _advanceStatusDirectly() {
    final nextStatus = _order.status.nextStatus;
    if (nextStatus == null) return;
    setState(() {
      _order = _order.copyWith(status: nextStatus);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Order moved to ${nextStatus.label}.')),
    );
  }

  Future<void> _confirmPickup() async {
    final result = await Navigator.of(context).push<LaundryOrder>(
      MaterialPageRoute(
        builder: (_) => PickupCaptureScreen(
          order: _order,
          photoStorage: widget.photoStorage,
          pickPhoto: widget.pickPhoto,
          clock: widget.clock,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _order = result);
    }
  }

  Future<void> _confirmDelivery() async {
    final scanOk = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          expectedOrderId: _order.orderId,
          cameraViewBuilder: widget.cameraViewBuilder,
        ),
      ),
    );
    if (scanOk != true || !mounted) return;
    final result = await Navigator.of(context).push<LaundryOrder>(
      MaterialPageRoute(
        builder: (_) => DeliveryCaptureScreen(
          order: _order,
          photoStorage: widget.photoStorage,
          pickPhoto: widget.pickPhoto,
          clock: widget.clock,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _order = result);
    }
  }

  void _handleBackNavigation() {
    Navigator.pop(context, _order);
  }

  Widget _buildPrimaryAction() {
    switch (_order.status) {
      case OrderStatus.pendingPickup:
        return ElevatedButton.icon(
          onPressed: _confirmPickup,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Confirm pickup'),
        );
      case OrderStatus.inProgress:
        return ElevatedButton.icon(
          onPressed: _advanceStatusDirectly,
          icon: const Icon(Icons.update_rounded),
          label: const Text('Move to Ready for delivery'),
        );
      case OrderStatus.readyForDelivery:
        return ElevatedButton.icon(
          onPressed: _confirmDelivery,
          icon: const Icon(Icons.delivery_dining_rounded),
          label: const Text('Deliver'),
        );
      case OrderStatus.completed:
        return ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Order completed'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _order.status.color;

    return PopScope<LaundryOrder>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: amuwakBackground,
        appBar: AppBar(
          backgroundColor: amuwakBackground,
          foregroundColor: amuwakDark,
          elevation: 0,
          title: const Text(
            'Order details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context, _order),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _OrderHeader(order: _order),
              const SizedBox(height: 18),
              _StatusChip(color: statusColor, label: _order.status.label),
              const SizedBox(height: 18),
              _DetailsSection(
                title: 'Customer',
                children: [
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: 'Name',
                    value: _order.customerName,
                  ),
                  _DetailRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: _order.phone,
                  ),
                  _DetailRow(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: _order.address,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailsSection(
                title: 'Laundry details',
                children: [
                  _DetailRow(
                    icon: Icons.receipt_long_outlined,
                    label: 'Order ID',
                    value: _order.orderId,
                  ),
                  _DetailRow(
                    icon: Icons.checkroom_outlined,
                    label: 'Service',
                    value: _order.serviceType,
                  ),
                  _DetailRow(
                    icon: Icons.inventory_2_outlined,
                    label: 'Items',
                    value: '${_order.itemCount} items',
                  ),
                  _DetailRow(
                    icon: Icons.access_time_rounded,
                    label: 'Time',
                    value: _order.timeLabel,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailsSection(
                title: 'Notes',
                children: [
                  Text(
                    _order.notes.isEmpty ? '—' : _order.notes,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              if (_order.proofEvents.isNotEmpty) ...[
                const SizedBox(height: 14),
                _DetailsSection(
                  title: 'History',
                  children: [
                    for (final event in _order.proofEvents)
                      _ProofEventRow(event: event),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              _buildPrimaryAction(),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});
  final LaundryOrder order;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: amuwakPrimary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.local_laundry_service_rounded,
              color: amuwakPrimary,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderId,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.customerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.serviceType,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: amuwakWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: amuwakSoftAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: amuwakDark,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: amuwakPrimary, size: 21),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: amuwakDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofEventRow extends StatelessWidget {
  const _ProofEventRow({required this.event});
  final ProofEvent event;

  String get _label =>
      event.type == ProofEventType.pickup ? 'Pickup' : 'Delivery';

  String get _timeText {
    final dt = event.capturedAt;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Icon(
            event.type == ProofEventType.pickup
                ? Icons.qr_code_2_rounded
                : Icons.delivery_dining_rounded,
            color: amuwakPrimary,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$_label · $_timeText · ${event.count} items · '
              '${event.photoPaths.length} photo(s)',
              style: const TextStyle(
                color: amuwakDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 12.4: Run the new test to verify it passes**

Run: `flutter test test/orders/order_details_screen_test.dart`
Expected: all 4 tests PASS.

- [ ] **Step 12.5: Update the single caller of `OrderDetailsScreen`**

`OrderDetailsScreen` now requires `photoStorage`, `pickPhoto`, and `cameraViewBuilder`. There is exactly one call site: [`lib/src/dashboard/staff_dashboard_screen.dart`](../../../lib/src/dashboard/staff_dashboard_screen.dart) at line 82, inside `_openOrderDetails`.

Open `lib/src/dashboard/staff_dashboard_screen.dart`. Add these imports to the existing import block at the top of the file (after the existing `package:flutter/material.dart` import):

```dart
import 'package:image_picker/image_picker.dart';

import '../orders/proof/barcode_reader.dart';
import '../orders/proof/proof_photo_storage.dart';
```

Then, inside `_StaffDashboardScreenState` (currently spans roughly lines 18–89), add these members just below the `_orders` list (around line 65, before `_replaceUpdatedOrder`):

```dart
  final ProofPhotoStorage _photoStorage = InMemoryProofPhotoStorage();
  final ImagePicker _imagePicker = ImagePicker();

  Future<List<int>?> _pickPhoto() async {
    final XFile? file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }
```

(The comment "For real device runs, swap for `createDefaultProofPhotoStorage()`" is intentionally NOT added — it ages badly; the implementer note at the bottom of this plan covers it once.)

Find this line (currently line 82):

```dart
      MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order)),
```

Replace with:

```dart
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(
          order: order,
          photoStorage: _photoStorage,
          pickPhoto: _pickPhoto,
          cameraViewBuilder: mobileScannerCameraViewBuilder(),
        ),
      ),
```

Leave `_replaceUpdatedOrder`, the `if (!mounted) return;` guard, and the `.push<LaundryOrder>` call exactly as they are — only the inner `OrderDetailsScreen(...)` construction changes.

- [ ] **Step 12.6: Run the full test suite + analysis**

Run: `flutter test && flutter analyze`
Expected: all tests PASS; analysis clean. (If `test/widget_test.dart`'s dashboard test fails because it now needs the new params, expand it to mirror the order-details test wiring above — but the existing tests only assert the login flow and a heading, so they likely still pass.)

- [ ] **Step 12.7: Commit**

```bash
git add lib/src/orders/order_details_screen.dart lib/src/dashboard/staff_dashboard_screen.dart test/orders/order_details_screen_test.dart
git commit -m "Route order-detail bookend transitions through pickup/delivery proof screens"
```

---

### Task 13: End-to-end integration test for the full pickup → delivery flow

**Files:**
- Create: `test/orders/proof/pickup_delivery_flow_test.dart`

This test drives the entire flow against `OrderDetailsScreen` with fake services, asserting two `ProofEvent`s end up on the order and final status is `completed`.

- [ ] **Step 13.1: Write the integration test**

Create `test/orders/proof/pickup_delivery_flow_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/barcode_reader.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

void main() {
  testWidgets(
      'full pickup -> in-progress -> ready -> delivery flow appends two ProofEvents',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    LaundryOrder current = const LaundryOrder(
      orderId: 'AMW-0421',
      customerName: 'Jane',
      serviceType: 'Wash',
      status: OrderStatus.pendingPickup,
      timeLabel: 't',
      itemCount: 3,
      phone: 'p',
      address: 'a',
      notes: '',
    );

    Widget buildHost() {
      return MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final updated =
                        await Navigator.of(context).push<LaundryOrder>(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailsScreen(
                          order: current,
                          photoStorage: storage,
                          pickPhoto: () async => const [1, 2, 3],
                          cameraViewBuilder: (ctx, onDetected) {
                            return FakeCameraView(
                              scannedValue: 'AMW-0421',
                              onDetected: onDetected,
                            );
                          },
                          clock: () => DateTime(2026, 5, 12, 9, 42),
                        ),
                      ),
                    );
                    if (updated != null) {
                      setState(() => current = updated);
                    }
                  },
                  child: const Text('Open order'),
                ),
              ),
            );
          },
        ),
      );
    }

    await tester.pumpWidget(buildHost());

    // 1) Pickup phase: enter count, add photo, confirm, done.
    await tester.tap(find.text('Open order'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('count_increment')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('add_photo')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Confirm with customer'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
    await tester.pumpAndSettle();

    expect(current.status, equals(OrderStatus.inProgress));
    expect(current.proofEvents, hasLength(1));

    // Close + reopen to refresh the OrderDetailsScreen with the new status.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    // 2) Move inProgress -> readyForDelivery via the existing direct button.
    await tester.tap(find.text('Open order'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(ElevatedButton, 'Move to Ready for delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(current.status, equals(OrderStatus.readyForDelivery));

    // 3) Delivery phase: open, scan, add handover photo, mark delivered.
    await tester.tap(find.text('Open order'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Deliver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simulate scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_handover_photo')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(ElevatedButton, 'Mark delivered'));
    await tester.pumpAndSettle();

    expect(current.status, equals(OrderStatus.completed));
    expect(current.proofEvents, hasLength(2));
    expect(current.pickupProof, isNotNull);
    expect(current.deliveryProof, isNotNull);
    expect(storage.savedPhotos, hasLength(2));
  });
}
```

- [ ] **Step 13.2: Run the test to verify it passes**

Run: `flutter test test/orders/proof/pickup_delivery_flow_test.dart`
Expected: PASS.

- [ ] **Step 13.3: Run the full test suite + analysis one last time**

Run: `flutter test && flutter analyze`
Expected: every test PASSES; analysis clean.

- [ ] **Step 13.4: Commit**

```bash
git add test/orders/proof/pickup_delivery_flow_test.dart
git commit -m "Add end-to-end pickup -> delivery integration test"
```

---

## Post-flight

- [ ] **Step P1: Manual smoke test on a real device or simulator**

Run: `flutter run`
Manually exercise: log in, open a `pendingPickup` order, tap **Confirm pickup**, increment count, take a real photo, tap Confirm, then Done. Verify status moves to *In progress*. Move to *Ready for delivery* via the existing button. Tap **Deliver**, scan the QR (or use manual entry), take a real handover photo, tap **Mark delivered**. Verify status moves to *Completed* and the History panel renders both events.

Expected: full flow works; photos appear in `<app_documents>/proofs/<orderId>/` on the device file system; no crashes; permission prompts (camera) work as expected.

If the smoke test reveals issues, fix them with TDD-style follow-up tasks rather than amending the existing commits.

- [ ] **Step P2: Verify the design's success criteria**

Walk through each of the 5 success criteria in `docs/superpowers/specs/2026-05-12-pickup-delivery-proof-design.md` (§ Success Criteria) and confirm each is met. If any fails, file a follow-up task and address it before considering the feature done.

---

## Notes for the implementer

- **Why `pickPhoto` returns `List<int>?`** — Image-picker's `XFile` is awkward to fake. Reducing the contract to "give me bytes or null" makes the test fakes trivial and keeps the screens decoupled from the picker package.
- **Why `clock` is injected** — `ProofEvent.capturedAt` participates in value equality. Tests assert on the captured event, so the clock must be deterministic.
- **Why a separate `ScannerScreen`** — The OrderDetailsScreen orchestrates "scan, then capture" so each screen has one responsibility. Pushing two screens in sequence is cheaper than a stateful super-screen.
- **Why `InMemoryProofPhotoStorage` instead of mocking the real one** — Production code never uses `InMemory*`; it exists purely as a test double. The real `FileProofPhotoStorage` is integration-tested against a temp directory in Task 6.
- **`mobile_scanner` widget tests** — Not feasible. The fake camera view (`FakeCameraView`) is the only viewfinder used in tests; production swaps in `mobileScannerCameraViewBuilder()` via the dashboard.
- **Dashboard wiring (Task 12.5)** — `InMemoryProofPhotoStorage()` is used for now since the rest of the app still runs on mock orders. Swap to `createDefaultProofPhotoStorage()` (Future-returning factory; needs async bootstrap) when the backend lands or when you want real photo files on device.
