# Drift + Outbox Offline-Sync Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the offline-first sync foundation in the Flutter app on top of the Supabase backend from Plan 1 — Drift-backed local SQLite + an outbox queue for client → server writes + a polling puller for server → client reads + a visible sync status indicator.

**Architecture:** Reads go to local SQLite via Drift (always available, even offline). Writes go to local SQLite **and** an `outbox` table in the same transaction; an `OutboxWorker` drains the outbox to Supabase using `supabase_flutter` when the device is online. A `SyncPuller` fetches rows updated since the last per-table watermark on a periodic timer and on reconnect. Conflict resolution is last-write-wins by `updated_at`; the `order_status_events` table is append-only and uses the existing `device_event_id` idempotency key for safe replay. This replaces the abandoned PowerSync layer (see [2026-05-19-powersync-sync-layer.md](2026-05-19-powersync-sync-layer.md) for the historical record).

**Tech Stack:** Dart 3.8, Flutter, Drift 2.x (sqlite_async backend), supabase_flutter 2.x, connectivity_plus, riverpod (or provider-style state mgmt — see Task 2), Mocktail for unit tests.

**Source spec:** [../specs/2026-05-18-supabase-backend-design.md](../specs/2026-05-18-supabase-backend-design.md) + the Drift + outbox design discussion in the project conversation log on 2026-05-19.
**Prerequisite plan:** [2026-05-18-supabase-database-foundation.md](2026-05-18-supabase-database-foundation.md) (must be merged + applied; migrations 0001–0016 in place, the `custom_access_token_hook` from migration 0009 wired in the Supabase dashboard).

---

## Glossary of file paths used in this plan

```
lib/
├── main.dart                                         [modify]
└── src/
    ├── bootstrap/
    │   ├── app_config.dart                           [new]
    │   └── app_bootstrap.dart                        [new]
    ├── auth/
    │   ├── auth_service.dart                         [new]
    │   ├── session.dart                              [new]
    │   └── login_screen.dart                         [modify]
    ├── data/
    │   ├── app_database.dart                         [new]
    │   ├── app_database.g.dart                       [generated]
    │   └── tables/
    │       ├── staff_table.dart                      [new]
    │       ├── customers_table.dart                  [new]
    │       ├── orders_table.dart                     [new]
    │       ├── order_status_events_table.dart        [new]
    │       ├── proof_events_table.dart               [new]
    │       ├── proof_photos_table.dart               [new]
    │       ├── issues_table.dart                     [new]
    │       ├── shifts_table.dart                     [new]
    │       ├── valid_transitions_table.dart          [new]
    │       ├── outbox_table.dart                     [new]
    │       └── sync_watermarks_table.dart            [new]
    ├── sync/
    │   ├── outbox_repository.dart                    [new]
    │   ├── outbox_worker.dart                        [new]
    │   ├── connectivity_watcher.dart                 [new]
    │   ├── sync_puller.dart                          [new]
    │   ├── sync_registry.dart                        [new]
    │   └── sync_status.dart                          [new]
    └── shared/widgets/
        └── sync_status_banner.dart                   [new]
test/
├── auth_service_test.dart                            [new]
├── outbox_repository_test.dart                       [new]
├── outbox_worker_test.dart                           [new]
└── sync_puller_test.dart                             [new]
integration_test/
└── end_to_end_sync_test.dart                         [new]
```

---

## Task 1: Add dependencies and wire Drift codegen

**Files:**
- Modify: `pubspec.yaml`
- Create: `build.yaml`

- [ ] **Step 1: Modify `pubspec.yaml` to add runtime dependencies**

Append to the `dependencies:` block (before `dev_dependencies`):

```yaml
  # Backend + offline sync
  supabase_flutter: ^2.5.0
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.0
  path_provider: ^2.1.4
  path: ^1.9.0
  connectivity_plus: ^6.0.0
  flutter_riverpod: ^2.5.0
  rxdart: ^0.27.0
```

Append to the `dev_dependencies:` block:

```yaml
  drift_dev: ^2.18.0
  build_runner: ^2.4.0
  mocktail: ^1.0.4
  integration_test:
    sdk: flutter
```

- [ ] **Step 2: Create `build.yaml` at the repo root**

```yaml
targets:
  $default:
    builders:
      drift_dev:
        options:
          store_date_time_values_as_text: true
          named_parameters: true
```

`store_date_time_values_as_text: true` stores `DateTime`s as ISO 8601 strings — easier to diff against Supabase's `timestamptz` values.

- [ ] **Step 3: Resolve dependencies**

```powershell
flutter pub get
```

Expected: `Got dependencies!`. If `pub get` errors on a transitive resolution, run `flutter pub upgrade` to refresh the lockfile.

- [ ] **Step 4: Commit**

```powershell
git add pubspec.yaml pubspec.lock build.yaml
git commit -m "Add supabase_flutter, drift, riverpod, connectivity_plus deps"
```

---

## Task 2: App bootstrap — `AppConfig` and Supabase initialization

**Files:**
- Create: `lib/src/bootstrap/app_config.dart`
- Create: `lib/src/bootstrap/app_bootstrap.dart`
- Modify: `lib/main.dart`
- Create: `test/app_config_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/app_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/bootstrap/app_config.dart';

void main() {
  group('AppConfig', () {
    test('reads SUPABASE_URL and SUPABASE_ANON_KEY from --dart-define', () {
      const cfg = AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'eyJ.anon.key',
      );
      expect(cfg.supabaseUrl, 'https://example.supabase.co');
      expect(cfg.supabaseAnonKey, 'eyJ.anon.key');
    });

    test('throws if required values are blank', () {
      expect(() => const AppConfig(supabaseUrl: '', supabaseAnonKey: 'x').validate(),
             throwsA(isA<StateError>()));
      expect(() => const AppConfig(supabaseUrl: 'x', supabaseAnonKey: '').validate(),
             throwsA(isA<StateError>()));
    });
  });
}
```

- [ ] **Step 2: Run the test — confirm it fails**

```powershell
flutter test test/app_config_test.dart
```

Expected: compilation error (`app_config.dart` doesn't exist).

- [ ] **Step 3: Implement `AppConfig`**

Create `lib/src/bootstrap/app_config.dart`:

```dart
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;

  factory AppConfig.fromEnvironment() => const AppConfig(
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
      );

  void validate() {
    if (supabaseUrl.isEmpty) {
      throw StateError('SUPABASE_URL is required (pass via --dart-define)');
    }
    if (supabaseAnonKey.isEmpty) {
      throw StateError('SUPABASE_ANON_KEY is required (pass via --dart-define)');
    }
  }
}
```

- [ ] **Step 4: Run the test — confirm it passes**

```powershell
flutter test test/app_config_test.dart
```

Expected: 2 passing tests.

- [ ] **Step 5: Implement `app_bootstrap.dart`**

Create `lib/src/bootstrap/app_bootstrap.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';

class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    final config = AppConfig.fromEnvironment()..validate();
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
  }
}
```

- [ ] **Step 6: Wire `main.dart` to call bootstrap**

Replace `lib/main.dart` contents:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/auth/login_screen.dart';
import 'src/bootstrap/app_bootstrap.dart';
import 'src/shared/widgets/app_theme.dart';

Future<void> main() async {
  await AppBootstrap.initialize();
  runApp(const ProviderScope(child: AmuwakStaffApp()));
}

class AmuwakStaffApp extends StatelessWidget {
  const AmuwakStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amuwak Staff',
      debugShowCheckedModeBanner: false,
      theme: buildAmuwakTheme(),
      home: const LoginScreen(),
    );
  }
}
```

- [ ] **Step 7: Smoke-build the app**

```powershell
flutter build apk --debug `
  --dart-define=SUPABASE_URL=https://rrxcsscinwqrxivczrfg.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
```

The anon key is at https://supabase.com/dashboard/project/rrxcsscinwqrxivczrfg/settings/api → **Project API keys → anon public**.

Expected: `Built build\app\outputs\flutter-apk\app-debug.apk.`

- [ ] **Step 8: Commit**

```powershell
git add lib/main.dart lib/src/bootstrap/ test/app_config_test.dart
git commit -m "Add AppConfig + bootstrap that initializes Supabase at startup"
```

---

## Task 3: Drift schema and database class

This task is the largest in the plan because every synced table needs a Dart mirror. Each table file is ~25–60 lines.

**Files:**
- Create: `lib/src/data/tables/staff_table.dart`
- Create: `lib/src/data/tables/customers_table.dart`
- Create: `lib/src/data/tables/orders_table.dart`
- Create: `lib/src/data/tables/order_status_events_table.dart`
- Create: `lib/src/data/tables/proof_events_table.dart`
- Create: `lib/src/data/tables/proof_photos_table.dart`
- Create: `lib/src/data/tables/issues_table.dart`
- Create: `lib/src/data/tables/shifts_table.dart`
- Create: `lib/src/data/tables/valid_transitions_table.dart`
- Create: `lib/src/data/tables/outbox_table.dart`
- Create: `lib/src/data/tables/sync_watermarks_table.dart`
- Create: `lib/src/data/app_database.dart`
- Create: `test/app_database_test.dart`
- Generated: `lib/src/data/app_database.g.dart`

- [ ] **Step 1: Write the failing test**

Create `test/app_database_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('all 11 tables exist on a fresh in-memory database', () async {
    final names = await db.customStatement(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    // customStatement returns nothing; query directly via select:
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    ).get();
    final tableNames = rows.map((r) => r.read<String>('name')).toSet();
    expect(tableNames, containsAll(<String>[
      'staff', 'customers', 'orders',
      'order_status_events', 'proof_events', 'proof_photos',
      'issues', 'shifts', 'valid_transitions',
      'outbox', 'sync_watermarks',
    ]));
  });

  test('inserting an order round-trips', () async {
    await db.into(db.orders).insert(OrdersCompanion.insert(
      id: 'order-1',
      orderCode: 'AMW-1',
      customerName: 'C',
      phone: '+254700',
      address: 'A',
      serviceType: 'wash_fold',
      status: 'received',
      intakeMethod: 'walk_in',
      fulfillmentMethod: 'delivery',
      itemCount: 3,
      intakeRecordedBy: 'staff-1',
      createdBy: 'staff-1',
    ));
    final rows = await db.select(db.orders).get();
    expect(rows, hasLength(1));
    expect(rows.first.orderCode, 'AMW-1');
  });
}
```

- [ ] **Step 2: Run — confirm it fails**

```powershell
flutter test test/app_database_test.dart
```

Expected: compile error — `AppDatabase` doesn't exist.

- [ ] **Step 3: Write the table files**

Create `lib/src/data/tables/staff_table.dart`:

```dart
import 'package:drift/drift.dart';

class Staff extends Table {
  TextColumn get id            => text()();
  TextColumn get username      => text()();
  TextColumn get displayName   => text().named('display_name')();
  TextColumn get phone         => text().nullable()();
  TextColumn get role          => text()();
  BoolColumn get active        => boolean().withDefault(const Constant(true))();
  BoolColumn get mustChangePin => boolean().named('must_change_pin').withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/customers_table.dart`:

```dart
import 'package:drift/drift.dart';

class Customers extends Table {
  TextColumn get id            => text()();
  TextColumn get name          => text()();
  TextColumn get phone         => text()();
  TextColumn get address       => text().nullable()();
  TextColumn get notes         => text().nullable()();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/orders_table.dart`:

```dart
import 'package:drift/drift.dart';

class Orders extends Table {
  TextColumn    get id                 => text()();
  TextColumn    get orderCode          => text().named('order_code')();
  TextColumn    get customerId         => text().named('customer_id').nullable()();
  TextColumn    get customerName       => text().named('customer_name')();
  TextColumn    get phone              => text()();
  TextColumn    get address            => text()();
  TextColumn    get serviceType        => text().named('service_type')();
  TextColumn    get status             => text()();
  TextColumn    get intakeMethod       => text().named('intake_method')();
  TextColumn    get fulfillmentMethod  => text().named('fulfillment_method')();
  IntColumn     get itemCount          => integer().named('item_count')();
  TextColumn    get notes              => text().withDefault(const Constant(''))();
  DateTimeColumn get scheduledFor      => dateTime().named('scheduled_for').nullable()();
  TextColumn    get assignedDriver     => text().named('assigned_driver').nullable()();
  TextColumn    get intakeRecordedBy   => text().named('intake_recorded_by')();
  TextColumn    get createdBy          => text().named('created_by')();
  DateTimeColumn get createdAt         => dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt         => dateTime().named('updated_at').withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt         => dateTime().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/order_status_events_table.dart`:

```dart
import 'package:drift/drift.dart';

class OrderStatusEvents extends Table {
  TextColumn    get id              => text()();
  TextColumn    get orderId         => text().named('order_id')();
  TextColumn    get fromStatus      => text().named('from_status').nullable()();
  TextColumn    get toStatus        => text().named('to_status')();
  TextColumn    get changedBy       => text().named('changed_by')();
  DateTimeColumn get changedAt      => dateTime().named('changed_at')();
  TextColumn    get source          => text()();
  TextColumn    get deviceEventId   => text().named('device_event_id').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/proof_events_table.dart`:

```dart
import 'package:drift/drift.dart';

class ProofEvents extends Table {
  TextColumn    get id            => text()();
  TextColumn    get orderId       => text().named('order_id')();
  TextColumn    get type          => text()();
  DateTimeColumn get capturedAt   => dateTime().named('captured_at')();
  IntColumn     get itemCount     => integer().named('item_count')();
  TextColumn    get notes         => text().nullable()();
  TextColumn    get capturedBy    => text().named('captured_by')();
  DateTimeColumn get createdAt    => dateTime().named('created_at')();
  DateTimeColumn get updatedAt    => dateTime().named('updated_at')();
  DateTimeColumn get deletedAt    => dateTime().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/proof_photos_table.dart`:

```dart
import 'package:drift/drift.dart';

class ProofPhotos extends Table {
  TextColumn    get id            => text()();
  TextColumn    get proofEventId  => text().named('proof_event_id')();
  TextColumn    get storagePath   => text().named('storage_path')();
  IntColumn     get width         => integer().nullable()();
  IntColumn     get height        => integer().nullable()();
  IntColumn     get bytes         => integer().nullable()();
  DateTimeColumn get uploadedAt   => dateTime().named('uploaded_at').nullable()();
  DateTimeColumn get createdAt    => dateTime().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/issues_table.dart`:

```dart
import 'package:drift/drift.dart';

class Issues extends Table {
  TextColumn    get id           => text()();
  TextColumn    get orderId      => text().named('order_id').nullable()();
  TextColumn    get kind         => text()();
  TextColumn    get description  => text()();
  TextColumn    get reportedBy   => text().named('reported_by')();
  DateTimeColumn get reportedAt  => dateTime().named('reported_at')();
  DateTimeColumn get resolvedAt  => dateTime().named('resolved_at').nullable()();
  TextColumn    get resolvedBy   => text().named('resolved_by').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/shifts_table.dart`:

```dart
import 'package:drift/drift.dart';

class Shifts extends Table {
  TextColumn    get id          => text()();
  TextColumn    get staffId     => text().named('staff_id')();
  DateTimeColumn get startedAt  => dateTime().named('started_at')();
  RealColumn    get startedLat  => real().named('started_lat').nullable()();
  RealColumn    get startedLng  => real().named('started_lng').nullable()();
  DateTimeColumn get endedAt    => dateTime().named('ended_at').nullable()();
  RealColumn    get endedLat    => real().named('ended_lat').nullable()();
  RealColumn    get endedLng    => real().named('ended_lng').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/valid_transitions_table.dart`:

```dart
import 'package:drift/drift.dart';

class ValidTransitions extends Table {
  TextColumn get id                 => text()();
  TextColumn get intakeMethod       => text().named('intake_method')();
  TextColumn get fulfillmentMethod  => text().named('fulfillment_method')();
  TextColumn get fromStatus         => text().named('from_status').nullable()();
  TextColumn get toStatus           => text().named('to_status')();

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/outbox_table.dart` — **local-only** table, no Supabase mirror:

```dart
import 'package:drift/drift.dart';

class Outbox extends Table {
  TextColumn    get id              => text()();
  TextColumn    get tableName       => text().named('table_name')();
  TextColumn    get op              => text()();          // 'insert' | 'update' | 'delete'
  TextColumn    get rowId           => text().named('row_id')();
  TextColumn    get payloadJson     => text().named('payload_json')();
  DateTimeColumn get createdAt      => dateTime().named('created_at').withDefault(currentDateAndTime)();
  IntColumn     get retryCount      => integer().named('retry_count').withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptedAt=> dateTime().named('last_attempted_at').nullable()();
  TextColumn    get lastError       => text().named('last_error').nullable()();
  TextColumn    get status          => text().withDefault(const Constant('pending'))();
  //  'pending' | 'in_flight' | 'failed' | 'sent'

  @override
  Set<Column> get primaryKey => {id};
}
```

Create `lib/src/data/tables/sync_watermarks_table.dart` — also local-only:

```dart
import 'package:drift/drift.dart';

class SyncWatermarks extends Table {
  TextColumn    get tableName    => text().named('table_name')();
  DateTimeColumn get lastSyncedAt=> dateTime().named('last_synced_at')();

  @override
  Set<Column> get primaryKey => {tableName};
}
```

- [ ] **Step 4: Write the database class**

Create `lib/src/data/app_database.dart`:

```dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/staff_table.dart';
import 'tables/customers_table.dart';
import 'tables/orders_table.dart';
import 'tables/order_status_events_table.dart';
import 'tables/proof_events_table.dart';
import 'tables/proof_photos_table.dart';
import 'tables/issues_table.dart';
import 'tables/shifts_table.dart';
import 'tables/valid_transitions_table.dart';
import 'tables/outbox_table.dart';
import 'tables/sync_watermarks_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Staff, Customers, Orders, OrderStatusEvents,
  ProofEvents, ProofPhotos, Issues, Shifts,
  ValidTransitions, Outbox, SyncWatermarks,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() => LazyDatabase(() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  final file = File(p.join(dbFolder.path, 'amuwak_staff.db'));
  return NativeDatabase.createInBackground(file);
});
```

- [ ] **Step 5: Run codegen**

```powershell
flutter pub run build_runner build --delete-conflicting-outputs
```

Expected: writes `lib/src/data/app_database.g.dart` (and possibly other generated files). No errors.

- [ ] **Step 6: Run the test — confirm it passes**

```powershell
flutter test test/app_database_test.dart
```

Expected: both tests pass.

- [ ] **Step 7: Commit**

```powershell
git add lib/src/data/ test/app_database_test.dart
git commit -m "Add Drift schema for synced tables + outbox + watermarks"
```

---

## Task 4: AuthService (email-trick PIN auth)

**Files:**
- Create: `lib/src/auth/auth_service.dart`
- Create: `lib/src/auth/session.dart`
- Create: `test/auth_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/auth_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/auth/auth_service.dart';

class _FakeGoTrue extends Mock implements GoTrueClient {}
class _FakeAuthResponse extends Fake implements AuthResponse {}
class _FakeAuthOptions extends Fake implements SignInOptions {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAuthOptions());
  });

  group('AuthService.signInWithUsernamePin', () {
    late _FakeGoTrue goTrue;
    late AuthService service;

    setUp(() {
      goTrue = _FakeGoTrue();
      service = AuthService(goTrue: goTrue);
    });

    test('composes the synthetic email from the username', () async {
      when(() => goTrue.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenAnswer((_) async => _FakeAuthResponse());

      await service.signInWithUsernamePin(username: 'john', pin: '123456');

      verify(() => goTrue.signInWithPassword(
        email: 'john@amuwak.local',
        password: '123456',
      )).called(1);
    });

    test('throws AuthFailure on AuthException', () async {
      when(() => goTrue.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenThrow(const AuthException('Invalid login credentials'));

      expect(
        () => service.signInWithUsernamePin(username: 'john', pin: 'wrong'),
        throwsA(isA<AuthFailure>()
          .having((e) => e.message, 'message', contains('Invalid'))),
      );
    });
  });
}
```

- [ ] **Step 2: Run — confirm it fails**

```powershell
flutter test test/auth_service_test.dart
```

Expected: compilation error — `AuthService` doesn't exist.

- [ ] **Step 3: Implement `AuthService`**

Create `lib/src/auth/auth_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => 'AuthFailure: $message';
}

class AuthService {
  AuthService({GoTrueClient? goTrue})
      : _goTrue = goTrue ?? Supabase.instance.client.auth;

  final GoTrueClient _goTrue;

  static const _emailSuffix = '@amuwak.local';

  /// Sign in via the username + PIN scheme. `username` is what staff type at
  /// the login screen; we compose `<username>@amuwak.local` and use the PIN
  /// as the password. Supabase Auth is unaware of the scheme — it sees a
  /// plain email/password sign-in.
  Future<void> signInWithUsernamePin({
    required String username,
    required String pin,
  }) async {
    try {
      await _goTrue.signInWithPassword(
        email: '${username.toLowerCase()}$_emailSuffix',
        password: pin,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  Future<void> signOut() => _goTrue.signOut();

  Session? get currentSession => _goTrue.currentSession;
  User?    get currentUser    => _goTrue.currentUser;
  Stream<AuthState> get authStateChanges => _goTrue.onAuthStateChange;
}
```

- [ ] **Step 4: Implement `session.dart` (Riverpod providers)**

Create `lib/src/auth/session.dart`:

```dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.session?.user.id;
});

/// The `role` claim is injected by the custom_access_token_hook in Supabase
/// migration 0009. Read it from the access-token JWT payload.
final currentRoleProvider = Provider<String?>((ref) {
  final token = ref.watch(authStateProvider).valueOrNull?.session?.accessToken;
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  final padded = parts[1] + '=' * ((4 - parts[1].length % 4) % 4);
  final payload = jsonDecode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>;
  return payload['role'] as String?;
});
```

- [ ] **Step 5: Run the test — confirm it passes**

```powershell
flutter test test/auth_service_test.dart
```

Expected: 2 passing tests.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/auth/auth_service.dart lib/src/auth/session.dart test/auth_service_test.dart
git commit -m "Add AuthService (email-trick PIN auth) and Riverpod session providers"
```

---

## Task 5: Wire `LoginScreen` to `AuthService`

**Files:**
- Modify: `lib/src/auth/login_screen.dart`

- [ ] **Step 1: Replace `login_screen.dart` with the Supabase-backed version**

This task changes the labels from "Email or phone / Password" to "Username / PIN" and replaces the hardcoded mock check with a call to `AuthService.signInWithUsernamePin`. The visual layout is unchanged.

Replace `lib/src/auth/login_screen.dart` entirely with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dashboard/staff_dashboard_screen.dart';
import '../shared/widgets/app_theme.dart';
import 'auth_service.dart';
import 'session.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _pinController = TextEditingController();

  String? _errorMessage;
  bool _busy = false;

  Future<void> _login() async {
    setState(() {
      _errorMessage = null;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).signInWithUsernamePin(
            username: _usernameController.text.trim(),
            pin: _pinController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StaffDashboardScreen()),
      );
    } on AuthFailure catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: amuwakBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: amuwakPrimary,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.local_laundry_service_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Amuwak Staff',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: amuwakDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Login to manage laundry orders',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter your PIN' : null,
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Login', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Smoke-build to confirm compilation**

```powershell
flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Commit**

```powershell
git add lib/src/auth/login_screen.dart
git commit -m "Wire LoginScreen to AuthService.signInWithUsernamePin"
```

---

## Task 6: OutboxRepository

**Files:**
- Create: `lib/src/sync/outbox_repository.dart`
- Create: `test/outbox_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/outbox_repository_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';

void main() {
  late AppDatabase db;
  late OutboxRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OutboxRepository(db);
  });

  tearDown(() async => db.close());

  test('enqueue stores a pending row', () async {
    await repo.enqueue(
      id: 'mut-1',
      tableName: 'orders',
      op: 'insert',
      rowId: 'order-1',
      payload: {'id': 'order-1', 'order_code': 'AMW-1'},
    );
    final pending = await repo.peekPending(limit: 10);
    expect(pending, hasLength(1));
    expect(pending.first.id, 'mut-1');
    expect(pending.first.status, 'pending');
  });

  test('markSent removes the row', () async {
    await repo.enqueue(
      id: 'mut-2', tableName: 'orders', op: 'insert',
      rowId: 'order-2', payload: const {},
    );
    await repo.markSent('mut-2');
    expect(await repo.peekPending(limit: 10), isEmpty);
  });

  test('markFailed increments retry_count and stores error', () async {
    await repo.enqueue(
      id: 'mut-3', tableName: 'orders', op: 'insert',
      rowId: 'order-3', payload: const {},
    );
    await repo.markFailed('mut-3', 'network timeout');
    final rows = await repo.peekPending(limit: 10);
    expect(rows.first.retryCount, 1);
    expect(rows.first.lastError, 'network timeout');
  });
}
```

- [ ] **Step 2: Run — confirm it fails**

```powershell
flutter test test/outbox_repository_test.dart
```

Expected: compilation error.

- [ ] **Step 3: Implement**

Create `lib/src/sync/outbox_repository.dart`:

```dart
import 'dart:convert';
import 'package:drift/drift.dart';
import '../data/app_database.dart';

class OutboxRepository {
  OutboxRepository(this._db);
  final AppDatabase _db;

  Future<void> enqueue({
    required String id,
    required String tableName,
    required String op,           // 'insert' | 'update' | 'delete'
    required String rowId,
    required Map<String, dynamic> payload,
  }) {
    return _db.into(_db.outbox).insert(
      OutboxCompanion.insert(
        id: id,
        tableName: tableName,
        op: op,
        rowId: rowId,
        payloadJson: jsonEncode(payload),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<List<OutboxData>> peekPending({required int limit}) {
    final query = _db.select(_db.outbox)
      ..where((t) => t.status.isIn(<String>['pending', 'failed']))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
      ..limit(limit);
    return query.get();
  }

  Future<void> markSent(String id) {
    return (_db.delete(_db.outbox)..where((t) => t.id.equals(id))).go();
  }

  Future<void> markFailed(String id, String error) {
    return (_db.update(_db.outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        retryCount: const Value.absent(), // incremented below
        lastError: Value(error),
        status: const Value('failed'),
        lastAttemptedAt: Value(DateTime.now()),
      ),
    ).then((_) async {
      // Increment retry_count separately because Drift companions
      // can't reference current values.
      await _db.customUpdate(
        'UPDATE outbox SET retry_count = retry_count + 1 WHERE id = ?',
        variables: [Variable.withString(id)],
        updates: {_db.outbox},
      );
    });
  }
}
```

- [ ] **Step 4: Run — confirm tests pass**

```powershell
flutter test test/outbox_repository_test.dart
```

Expected: 3 passing tests.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/sync/outbox_repository.dart test/outbox_repository_test.dart
git commit -m "Add OutboxRepository for offline-first writes"
```

---

## Task 7: OutboxWorker

**Files:**
- Create: `lib/src/sync/outbox_worker.dart`
- Create: `test/outbox_worker_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/outbox_worker_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_worker.dart';

class _FakeSupabase     extends Mock implements SupabaseClient {}
class _FakeQueryBuilder extends Mock implements SupabaseQueryBuilder {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  late AppDatabase db;
  late OutboxRepository repo;
  late _FakeSupabase supabase;
  late _FakeQueryBuilder builder;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OutboxRepository(db);
    supabase = _FakeSupabase();
    builder = _FakeQueryBuilder();
    when(() => supabase.from(any())).thenReturn(builder);
    when(() => builder.insert(any())).thenAnswer((_) async => null);
  });

  tearDown(() async => db.close());

  test('drains a pending insert by calling supabase.from(table).insert(payload)',
      () async {
    await repo.enqueue(
      id: 'mut-1', tableName: 'orders', op: 'insert',
      rowId: 'order-1',
      payload: {'id': 'order-1', 'order_code': 'AMW-1'},
    );

    final worker = OutboxWorker(repo: repo, supabase: supabase);
    final drained = await worker.drainOnce();

    expect(drained, 1);
    verify(() => supabase.from('orders')).called(1);
    verify(() => builder.insert({'id': 'order-1', 'order_code': 'AMW-1'})).called(1);
    expect(await repo.peekPending(limit: 10), isEmpty);
  });

  test('on PostgrestException it marks the row failed and stops processing later rows',
      () async {
    when(() => builder.insert(any())).thenThrow(
      const PostgrestException(message: 'unique violation', code: '23505'),
    );

    await repo.enqueue(id: 'm1', tableName: 'orders', op: 'insert',
                       rowId: 'r1', payload: const {});
    await repo.enqueue(id: 'm2', tableName: 'orders', op: 'insert',
                       rowId: 'r2', payload: const {});

    final worker = OutboxWorker(repo: repo, supabase: supabase);
    final drained = await worker.drainOnce();

    expect(drained, 0);
    final pending = await repo.peekPending(limit: 10);
    expect(pending, hasLength(2));
    expect(pending.first.lastError, contains('unique violation'));
  });
}
```

- [ ] **Step 2: Run — confirm it fails**

```powershell
flutter test test/outbox_worker_test.dart
```

Expected: `OutboxWorker` doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/src/sync/outbox_worker.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'outbox_repository.dart';

class OutboxWorker {
  OutboxWorker({
    required this.repo,
    required this.supabase,
    this.batchSize = 25,
  });

  final OutboxRepository repo;
  final SupabaseClient supabase;
  final int batchSize;

  Timer? _timer;

  /// Pump one batch of pending mutations. Returns the count successfully sent.
  Future<int> drainOnce() async {
    final batch = await repo.peekPending(limit: batchSize);
    var sent = 0;
    for (final row in batch) {
      try {
        final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
        final table = supabase.from(row.tableName);
        switch (row.op) {
          case 'insert':
            await table.insert(payload);
            break;
          case 'update':
            await table.update(payload).eq('id', row.rowId);
            break;
          case 'delete':
            await table.delete().eq('id', row.rowId);
            break;
          default:
            throw StateError('unknown op: ${row.op}');
        }
        await repo.markSent(row.id);
        sent++;
      } on PostgrestException catch (e) {
        await repo.markFailed(row.id, '${e.code ?? ''}: ${e.message}');
        return sent; // stop processing on error; let backoff kick in.
      } catch (e) {
        await repo.markFailed(row.id, e.toString());
        return sent;
      }
    }
    return sent;
  }

  /// Start a periodic drain (default 5s). Cancel with `stop()`.
  void start({Duration interval = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => drainOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
```

- [ ] **Step 4: Run tests — confirm pass**

```powershell
flutter test test/outbox_worker_test.dart
```

Expected: 2 passing tests.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/sync/outbox_worker.dart test/outbox_worker_test.dart
git commit -m "Add OutboxWorker that drains pending mutations to Supabase"
```

---

## Task 8: ConnectivityWatcher

**Files:**
- Create: `lib/src/sync/connectivity_watcher.dart`

- [ ] **Step 1: Implement**

Create `lib/src/sync/connectivity_watcher.dart`:

```dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityWatcher {
  ConnectivityWatcher({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Calls [onOnline] every time the device transitions from offline → online.
  void start({required void Function() onOnline}) {
    _sub?.cancel();
    bool wasOnline = false;
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && !wasOnline) onOnline();
      wasOnline = online;
    });
  }

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() => _sub?.cancel();
}
```

(No dedicated unit test — this is a thin wrapper. It will be exercised by the integration test in Task 11.)

- [ ] **Step 2: `flutter analyze` to confirm compilation**

```powershell
flutter analyze lib/src/sync/connectivity_watcher.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```powershell
git add lib/src/sync/connectivity_watcher.dart
git commit -m "Add ConnectivityWatcher wrapper over connectivity_plus"
```

---

## Task 9: SyncRegistry + SyncPuller

**Files:**
- Create: `lib/src/sync/sync_registry.dart`
- Create: `lib/src/sync/sync_puller.dart`
- Create: `test/sync_puller_test.dart`

- [ ] **Step 1: Implement `SyncRegistry`**

Create `lib/src/sync/sync_registry.dart`:

```dart
/// Declarative list of which Postgres tables to pull and how. The puller
/// loops over this list every sync cycle.
class SyncTable {
  const SyncTable({required this.name, required this.pkColumn});
  final String name;
  final String pkColumn;
}

const List<SyncTable> kSyncTables = [
  SyncTable(name: 'staff',                pkColumn: 'id'),
  SyncTable(name: 'customers',            pkColumn: 'id'),
  SyncTable(name: 'orders',               pkColumn: 'id'),
  SyncTable(name: 'order_status_events',  pkColumn: 'id'),
  SyncTable(name: 'proof_events',         pkColumn: 'id'),
  SyncTable(name: 'proof_photos',         pkColumn: 'id'),
  SyncTable(name: 'issues',               pkColumn: 'id'),
  SyncTable(name: 'shifts',               pkColumn: 'id'),
  SyncTable(name: 'valid_transitions',    pkColumn: 'id'),
];
```

- [ ] **Step 2: Write the failing test**

Create `test/sync_puller_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/sync_puller.dart';

class _FakeSupabase    extends Mock implements SupabaseClient {}
class _FakeQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class _FakeFilterBuilder<T> extends Mock implements PostgrestFilterBuilder<T> {}

void main() {
  late AppDatabase db;
  late _FakeSupabase supabase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    supabase = _FakeSupabase();
  });

  tearDown(() async => db.close());

  test('pulls customers updated since the watermark and writes them to Drift',
      () async {
    final builder = _FakeQueryBuilder();
    final filter1 = _FakeFilterBuilder<dynamic>();
    final filter2 = _FakeFilterBuilder<dynamic>();
    final rows = <Map<String, dynamic>>[
      {
        'id': 'c-1', 'name': 'Alice', 'phone': '+254',
        'address': null, 'notes': null,
        'created_at': '2026-05-19T10:00:00Z',
        'updated_at': '2026-05-19T10:00:00Z',
        'deleted_at': null,
      },
    ];

    when(() => supabase.from('customers')).thenReturn(builder);
    when(() => builder.select()).thenReturn(filter1 as dynamic);
    when(() => filter1.gt(any(), any())).thenReturn(filter2);
    when(() => filter2.order(any())).thenAnswer((_) async => rows);

    final puller = SyncPuller(db: db, supabase: supabase);
    final pulled = await puller.pullTable('customers');

    expect(pulled, 1);
    final localRows = await db.select(db.customers).get();
    expect(localRows, hasLength(1));
    expect(localRows.first.name, 'Alice');
  });
}
```

- [ ] **Step 3: Run — confirm it fails**

```powershell
flutter test test/sync_puller_test.dart
```

Expected: `SyncPuller` doesn't exist.

- [ ] **Step 4: Implement `SyncPuller`**

Create `lib/src/sync/sync_puller.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_database.dart';
import 'sync_registry.dart';

/// Pulls Postgres rows whose `updated_at` is newer than the local watermark
/// and upserts them into the local Drift database. Per-table mapping is
/// kept simple — each row is upserted by its primary key.
class SyncPuller {
  SyncPuller({required this.db, required this.supabase});

  final AppDatabase db;
  final SupabaseClient supabase;

  static final DateTime _epoch = DateTime.utc(1970);

  Future<DateTime> _readWatermark(String tableName) async {
    final row = await (db.select(db.syncWatermarks)
          ..where((t) => t.tableName.equals(tableName)))
        .getSingleOrNull();
    return row?.lastSyncedAt ?? _epoch;
  }

  Future<void> _writeWatermark(String tableName, DateTime at) {
    return db.into(db.syncWatermarks).insertOnConflictUpdate(
      SyncWatermarksCompanion.insert(tableName: tableName, lastSyncedAt: at),
    );
  }

  /// Pull a single table. Returns the number of rows upserted.
  Future<int> pullTable(String name) async {
    final since = await _readWatermark(name);
    final query = supabase.from(name)
        .select()
        .gt('updated_at', since.toIso8601String())
        .order('updated_at');
    final List<dynamic> rows = await query;
    if (rows.isEmpty) return 0;

    DateTime maxUpdated = since;
    await db.batch((batch) {
      for (final row in rows.cast<Map<String, dynamic>>()) {
        _upsertRow(batch, name, row);
        final u = DateTime.parse(row['updated_at'] as String);
        if (u.isAfter(maxUpdated)) maxUpdated = u;
      }
    });
    await _writeWatermark(name, maxUpdated);
    return rows.length;
  }

  Future<int> pullAll() async {
    var total = 0;
    for (final t in kSyncTables) {
      total += await pullTable(t.name);
    }
    return total;
  }

  void _upsertRow(Batch batch, String table, Map<String, dynamic> row) {
    switch (table) {
      case 'staff':
        batch.insert(db.staff, _staffFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'customers':
        batch.insert(db.customers, _customersFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'orders':
        batch.insert(db.orders, _ordersFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'order_status_events':
        batch.insert(db.orderStatusEvents, _statusEventsFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'proof_events':
        batch.insert(db.proofEvents, _proofEventsFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'proof_photos':
        batch.insert(db.proofPhotos, _proofPhotosFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'issues':
        batch.insert(db.issues, _issuesFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'shifts':
        batch.insert(db.shifts, _shiftsFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'valid_transitions':
        batch.insert(db.validTransitions, _validTransitionsFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      default:
        throw StateError('no upsert mapper for table $table');
    }
  }

  // ------------- per-table JSON → Drift Companion mappers -------------

  DateTime _dt(Object? v) => DateTime.parse(v as String);
  DateTime? _dtNullable(Object? v) => v == null ? null : DateTime.parse(v as String);

  StaffCompanion _staffFromJson(Map<String, dynamic> r) => StaffCompanion.insert(
    id: r['id'] as String,
    username: r['username'] as String,
    displayName: r['display_name'] as String,
    phone: Value(r['phone'] as String?),
    role: r['role'] as String,
    active: Value(r['active'] as bool? ?? true),
    mustChangePin: Value(r['must_change_pin'] as bool? ?? false),
    createdAt: _dt(r['created_at']),
    updatedAt: _dt(r['updated_at']),
    deletedAt: Value(_dtNullable(r['deleted_at'])),
  );

  CustomersCompanion _customersFromJson(Map<String, dynamic> r) => CustomersCompanion.insert(
    id: r['id'] as String,
    name: r['name'] as String,
    phone: r['phone'] as String,
    address: Value(r['address'] as String?),
    notes: Value(r['notes'] as String?),
    createdAt: _dt(r['created_at']),
    updatedAt: _dt(r['updated_at']),
    deletedAt: Value(_dtNullable(r['deleted_at'])),
  );

  OrdersCompanion _ordersFromJson(Map<String, dynamic> r) => OrdersCompanion.insert(
    id: r['id'] as String,
    orderCode: r['order_code'] as String,
    customerId: Value(r['customer_id'] as String?),
    customerName: r['customer_name'] as String,
    phone: r['phone'] as String,
    address: r['address'] as String,
    serviceType: r['service_type'] as String,
    status: r['status'] as String,
    intakeMethod: r['intake_method'] as String,
    fulfillmentMethod: r['fulfillment_method'] as String,
    itemCount: r['item_count'] as int,
    notes: Value(r['notes'] as String? ?? ''),
    scheduledFor: Value(_dtNullable(r['scheduled_for'])),
    assignedDriver: Value(r['assigned_driver'] as String?),
    intakeRecordedBy: r['intake_recorded_by'] as String,
    createdBy: r['created_by'] as String,
    createdAt: Value(_dt(r['created_at'])),
    updatedAt: Value(_dt(r['updated_at'])),
    deletedAt: Value(_dtNullable(r['deleted_at'])),
  );

  OrderStatusEventsCompanion _statusEventsFromJson(Map<String, dynamic> r) =>
      OrderStatusEventsCompanion.insert(
        id: r['id'] as String,
        orderId: r['order_id'] as String,
        fromStatus: Value(r['from_status'] as String?),
        toStatus: r['to_status'] as String,
        changedBy: r['changed_by'] as String,
        changedAt: _dt(r['changed_at']),
        source: r['source'] as String,
        deviceEventId: Value(r['device_event_id'] as String?),
      );

  ProofEventsCompanion _proofEventsFromJson(Map<String, dynamic> r) =>
      ProofEventsCompanion.insert(
        id: r['id'] as String,
        orderId: r['order_id'] as String,
        type: r['type'] as String,
        capturedAt: _dt(r['captured_at']),
        itemCount: r['item_count'] as int,
        notes: Value(r['notes'] as String?),
        capturedBy: r['captured_by'] as String,
        createdAt: _dt(r['created_at']),
        updatedAt: _dt(r['updated_at']),
        deletedAt: Value(_dtNullable(r['deleted_at'])),
      );

  ProofPhotosCompanion _proofPhotosFromJson(Map<String, dynamic> r) =>
      ProofPhotosCompanion.insert(
        id: r['id'] as String,
        proofEventId: r['proof_event_id'] as String,
        storagePath: r['storage_path'] as String,
        width: Value(r['width'] as int?),
        height: Value(r['height'] as int?),
        bytes: Value(r['bytes'] as int?),
        uploadedAt: Value(_dtNullable(r['uploaded_at'])),
        createdAt: _dt(r['created_at']),
      );

  IssuesCompanion _issuesFromJson(Map<String, dynamic> r) =>
      IssuesCompanion.insert(
        id: r['id'] as String,
        orderId: Value(r['order_id'] as String?),
        kind: r['kind'] as String,
        description: r['description'] as String,
        reportedBy: r['reported_by'] as String,
        reportedAt: _dt(r['reported_at']),
        resolvedAt: Value(_dtNullable(r['resolved_at'])),
        resolvedBy: Value(r['resolved_by'] as String?),
      );

  ShiftsCompanion _shiftsFromJson(Map<String, dynamic> r) =>
      ShiftsCompanion.insert(
        id: r['id'] as String,
        staffId: r['staff_id'] as String,
        startedAt: _dt(r['started_at']),
        startedLat: Value(r['started_lat'] as double?),
        startedLng: Value(r['started_lng'] as double?),
        endedAt: Value(_dtNullable(r['ended_at'])),
        endedLat: Value(r['ended_lat'] as double?),
        endedLng: Value(r['ended_lng'] as double?),
      );

  ValidTransitionsCompanion _validTransitionsFromJson(Map<String, dynamic> r) =>
      ValidTransitionsCompanion.insert(
        id: r['id'] as String,
        intakeMethod: r['intake_method'] as String,
        fulfillmentMethod: r['fulfillment_method'] as String,
        fromStatus: Value(r['from_status'] as String?),
        toStatus: r['to_status'] as String,
      );
}
```

- [ ] **Step 5: Run tests — confirm pass**

```powershell
flutter test test/sync_puller_test.dart
```

Expected: 1 passing test.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/sync/sync_registry.dart lib/src/sync/sync_puller.dart test/sync_puller_test.dart
git commit -m "Add SyncPuller (watermarked incremental pull) + table registry"
```

---

## Task 10: SyncStatusProvider + SyncStatusBanner

**Files:**
- Create: `lib/src/sync/sync_status.dart`
- Create: `lib/src/shared/widgets/sync_status_banner.dart`

- [ ] **Step 1: Implement `sync_status.dart`**

Create `lib/src/sync/sync_status.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import '../data/app_database.dart';

class SyncStatus {
  const SyncStatus({
    required this.pendingCount,
    required this.lastSyncedAt,
    required this.online,
  });
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final bool online;
}

final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase());

final pendingOutboxCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final query = db.selectOnly(db.outbox)
    ..addColumns([db.outbox.id.count()])
    ..where(db.outbox.status.isIn(<String>['pending', 'failed']));
  return query.watch().map((rows) => rows.first.read(db.outbox.id.count()) ?? 0);
});

/// Combined sync-status stream. Online flag is set by ConnectivityWatcher at
/// app startup (see Task 11 integration wiring).
final onlineProvider = StateProvider<bool>((_) => true);

final syncStatusProvider = Provider<SyncStatus>((ref) {
  final pending = ref.watch(pendingOutboxCountProvider).valueOrNull ?? 0;
  final online = ref.watch(onlineProvider);
  // last_synced_at: take the max across all watermarks. (Could be its own
  // Stream — kept polled at provider read time for now.)
  return SyncStatus(pendingCount: pending, lastSyncedAt: null, online: online);
});
```

- [ ] **Step 2: Implement the banner widget**

Create `lib/src/shared/widgets/sync_status_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sync/sync_status.dart';

class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider);
    if (s.online && s.pendingCount == 0) {
      return const SizedBox.shrink();
    }
    final bg = !s.online
        ? Colors.orange.shade100
        : Colors.blue.shade100;
    final fg = !s.online
        ? Colors.orange.shade900
        : Colors.blue.shade900;
    final label = !s.online
        ? 'Offline${s.pendingCount > 0 ? " — ${s.pendingCount} pending" : ""}'
        : '${s.pendingCount} pending upload${s.pendingCount == 1 ? "" : "s"}';
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(!s.online ? Icons.cloud_off : Icons.sync, size: 16, color: fg),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fg, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Smoke-build**

```powershell
flutter analyze lib/src/sync/sync_status.dart lib/src/shared/widgets/sync_status_banner.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```powershell
git add lib/src/sync/sync_status.dart lib/src/shared/widgets/sync_status_banner.dart
git commit -m "Add SyncStatus provider and the dashboard banner widget"
```

---

## Task 11: Manual setup — create a test staff user

This is a one-time SQL invocation by the developer; it's not a code task and there is no commit. It creates a `manager` staff row + a matching `auth.users` row so the AuthService has something to sign in as during the integration test in Task 12.

- [ ] **Step 1: Run this in the Supabase SQL editor**

Open https://supabase.com/dashboard/project/rrxcsscinwqrxivczrfg/sql/new and run:

```sql
-- Choose a stable UUID for the test manager; record this somewhere
-- (it is used by Task 12's integration test).
DO $$
DECLARE
  v_user_id uuid := '11111111-1111-1111-1111-111111111111';
  v_username text := 'testmgr';
  v_pin text := '123456';   -- swap for something stronger in long-lived envs
BEGIN
  -- 1. Create the Supabase Auth user via the auth admin function
  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
  ) VALUES (
    v_user_id, '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_username || '@amuwak.local',
    crypt(v_pin, gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb, now(), now(), '', '', '', ''
  ) ON CONFLICT (id) DO UPDATE SET encrypted_password = EXCLUDED.encrypted_password;

  -- 2. Create the matching staff row
  INSERT INTO public.staff (id, username, display_name, role)
  VALUES (v_user_id, v_username, 'Test Manager', 'manager')
  ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;
END $$;
```

Expected: `DO`. No errors.

- [ ] **Step 2: Verify**

```sql
SELECT s.username, s.role, u.email
FROM public.staff s
JOIN auth.users  u ON u.id = s.id
WHERE s.username = 'testmgr';
```

Expected: one row, `(testmgr, manager, testmgr@amuwak.local)`.

- [ ] **Step 3: Record the credentials for the integration test**

The integration test in Task 12 expects:
- Username: `testmgr`
- PIN: `123456`

Do not change these without updating that test.

---

## Task 12: End-to-end integration test

This test exercises the full happy path: sign in via `AuthService`, fetch initial data via `SyncPuller`, write an offline mutation, drain via `OutboxWorker`, observe the round-trip.

**Files:**
- Create: `integration_test/end_to_end_sync_test.dart`

- [ ] **Step 1: Write the integration test**

Create `integration_test/end_to_end_sync_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/auth/auth_service.dart';
import 'package:amuwak_staff/src/bootstrap/app_config.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_worker.dart';
import 'package:amuwak_staff/src/sync/sync_puller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final cfg = AppConfig.fromEnvironment()..validate();
    await Supabase.initialize(url: cfg.supabaseUrl, anonKey: cfg.supabaseAnonKey);
    final auth = AuthService();
    await auth.signInWithUsernamePin(username: 'testmgr', pin: '123456');
  });

  tearDownAll(() async {
    await AuthService().signOut();
  });

  testWidgets('round-trip a new customer through outbox + puller', (_) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = OutboxRepository(db);
    final supabase = Supabase.instance.client;
    final worker = OutboxWorker(repo: repo, supabase: supabase);
    final puller = SyncPuller(db: db, supabase: supabase);

    final newId = 'e2e-${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'id': newId,
      'name': 'E2E Sync Test',
      'phone': '+254700009999',
      'address': 'E2E address',
    };

    // 1. Enqueue an insert offline-style
    await repo.enqueue(
      id: 'mut-$newId', tableName: 'customers', op: 'insert',
      rowId: newId, payload: payload,
    );
    expect((await repo.peekPending(limit: 10)).length, 1);

    // 2. Drain the outbox (online)
    final sent = await worker.drainOnce();
    expect(sent, 1);
    expect(await repo.peekPending(limit: 10), isEmpty);

    // 3. Pull the customers table and assert the new row is local
    final pulled = await puller.pullTable('customers');
    expect(pulled, greaterThan(0));

    final local = await (db.select(db.customers)
          ..where((c) => c.id.equals(newId)))
        .getSingleOrNull();
    expect(local, isNotNull);
    expect(local!.name, 'E2E Sync Test');

    // 4. Cleanup (delete on remote so reruns don't accumulate)
    await supabase.from('customers').delete().eq('id', newId);
    await db.close();
  });
}
```

- [ ] **Step 2: Run the integration test against the linked project**

```powershell
flutter test integration_test/end_to_end_sync_test.dart `
  --dart-define=SUPABASE_URL=https://rrxcsscinwqrxivczrfg.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=<anon-key-from-supabase-dashboard>
```

Expected: 1 passing test. Round-trip latency may run a few seconds; that's normal for cloud hops.

- [ ] **Step 3: Commit**

```powershell
git add integration_test/end_to_end_sync_test.dart
git commit -m "Add end-to-end integration test for outbox + puller round-trip"
```

---

## Self-review checklist (for the implementer)

After all tasks merge, verify:

- [ ] `flutter test` passes all unit tests (auth, app_database, outbox_repository, outbox_worker, sync_puller, app_config).
- [ ] `flutter test integration_test/` passes the end-to-end test (network-dependent).
- [ ] `flutter analyze` is clean.
- [ ] `lib/src/data/app_database.g.dart` is checked in.
- [ ] No anon-key / DB password is committed to the repo.
- [ ] The dashboard wraps `SyncStatusBanner` somewhere visible to staff (in StaffDashboardScreen — confirm during Plan 3 UI wiring).

## What this plan does not do

- **Wire existing UI screens to the new repositories.** The dashboard, order list, scanner, etc. still use their in-memory stores. Replacing those is Plan 3.
- **Photo upload.** Proof photos go to Supabase Storage and have their own outbox path that isn't appropriate for the generic row-based outbox built here. Plan 4.
- **`create-staff` Edge Function.** Plan 5; for now staff users are seeded manually by the SQL in Task 11.
- **Walk-in and phone-order UX flows.** Plan 6 — they consume the data layer this plan builds.

## Known limitations to document for users of this plan

- The puller is polling-based (manual `pullAll()` invocations or a Task-12-style timer); there is no Supabase Realtime channel wiring. If push freshness becomes important, layer Realtime on top in a follow-up.
- Conflict resolution is last-write-wins by `updated_at`. For mutable tables with concurrent multi-user edits, divergent writes are possible. The append-only `order_status_events` table is naturally conflict-free.
- `OutboxWorker.markFailed` stops processing the rest of the batch on the first error. This is intentional to avoid hammering Supabase during outages, but means slow-failing operations block faster ones. Acceptable for pilot scale; revisit if seen in practice.
