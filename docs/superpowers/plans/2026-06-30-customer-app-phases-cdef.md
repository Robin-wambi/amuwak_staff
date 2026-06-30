# Customer App — Phases C–F: Customer Flutter App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the customer-facing Flutter app (`apps/amuwak_customer`) — self-registration, self-service order placement with a live price estimate, live order tracking, and per-order chat + an in-app inbox — reusing `amuwak_core` and the customer backend.

**Architecture:** A new Flutter app in the workspace, depending on `amuwak_core` (Phase A) and the customer backend (Phase B). `go_router` with an auth redirect; Riverpod stream providers over Supabase realtime, mirroring the staff repository pattern. A small set of shared additions land in `amuwak_core` first (Drift-free model split + the customer-facing repository methods + `OrderMessagesRepository`), then the app is assembled on top.

**Tech Stack:** Flutter (Dart `^3.8.0`), `amuwak_core`, `flutter_riverpod`, `supabase_flutter`, `go_router`, `flutter_test` + `mocktail`.

**Prerequisites:** Phase A (workspace + `amuwak_core`) and Phase B (migrations `0032`–`0038`) are merged. Supabase ops done: email signups enabled, email confirmation decision made (v1: disabled).

## Global Constraints

- All constraints from Phase A apply (SDK `^3.8.0`; one-test-file-or-whole-package on this host; scoped `git commit -- <paths>`; local commits only).
- The app is `apps/amuwak_customer`, package name `amuwak_customer`, with `resolution: workspace` and a path dep on `amuwak_core`.
- Reuse `amuwak_core` for everything shared (theme via `buildAmuwakTheme`, `AppCard`, `EmptyState`, motion, `formatUgx`, `recomputeTotal`, `AuthService`, session providers, `AppConfig`/`AppBootstrap`). Do NOT copy staff screens.
- Supabase config is injected via `--dart-define SUPABASE_URL=… SUPABASE_ANON_KEY=…` (same as staff app).
- Customers never advance status or edit price (enforced by RLS; the UI must not offer it).
- Money is integer UGX; price shown to a customer pre-weigh is an **estimate** (`isProvisional`) with a persistent disclaimer.

## How to read this plan
- **Stage 1 (Tasks 1–4)** = shared-core foundations + app scaffold + auth. Written as full bite-sized TDD steps.
- **Stage 2 (Tasks 5–10)** = the screens (tracking, place-order, chat, inbox, staff chat, hardening). Each task lists exact files, interfaces (signatures other tasks rely on), the test to write first, and key code for the non-obvious parts. **Per the executing skill, expand each Stage-2 task's UI into 2–5-minute red/green/commit steps just-in-time** (the exact widget code depends on `amuwak_core` existing after Stage 1) — the interfaces and tests below are the contract to build to.

---

## Stage 1 — Foundations

### Task 1: Split a Drift-free `LaundryOrder` + `Customer` into `amuwak_core`

**Files:**
- Modify: `lib/src/orders/order.dart` (staff) — remove `LaundryOrder` body; add a staff-only `fromDriftRow` extension.
- Create: `packages/amuwak_core/lib/src/orders/order.dart` — the Drift-free `LaundryOrder` (everything in today's class **except** `fromDriftRow` and the `drift` import).
- Create: `packages/amuwak_core/lib/src/customers/customer.dart` — a plain `Customer` domain model + `fromSupabase`.
- Create: `packages/amuwak_core/lib/src/sync/supabase_mappers.dart`, `packages/amuwak_core/lib/src/sync/supabase_payloads.dart` — moved from staff (Drift-free parts).
- Test: `packages/amuwak_core/test/orders/order_supabase_test.dart`, `packages/amuwak_core/test/sync/supabase_payloads_test.dart` (move existing payload test).

**Interfaces:**
- Produces (via barrel): `LaundryOrder` (with `fromSupabase`, `copyWith`, getters `outstandingUgx`, `isFullyPaid`, `relevantDate`, `pickupProof`, `deliveryProof`), `Customer` (`id`, `name`, `phone`, `address?`, `notes?`, `email?`, `customRatePerKgUgx?`, `authUserId?`, `fromSupabase`), `orderUpsertPayload(...)`, `orderDetailsUpdatePayload(...)`, `customerUpsertPayload(...)`.
- Staff-only: `extension LaundryOrderDrift on never`-style helper — `LaundryOrderDriftX.fromDriftRow(drift.Order, List<drift.ProofEvent>)` stays in `lib/`.

- [ ] **Step 1: Move the model, dropping the Drift factory**

Create `packages/amuwak_core/lib/src/orders/order.dart` as the current `lib/src/orders/order.dart` **verbatim except**: delete the `import '../data/app_database.dart' as drift;` line and delete the entire `factory LaundryOrder.fromDriftRow(...)` block (lines 120-163). Change the remaining relative imports to in-package ones: `import 'order_status.dart';`, `import 'pricing/line_item.dart';`, `import 'proof_event.dart';`, `import 'service_type.dart';` all already resolve inside `amuwak_core` (those moved in Phase A). Add `export 'src/orders/order.dart';` to the barrel.

- [ ] **Step 2: Keep `fromDriftRow` in the staff app as an extension**

Replace `lib/src/orders/order.dart` contents with a staff-only extension that re-exports the core type and adds the Drift hydrator:

```dart
import 'package:amuwak_core/amuwak_core.dart';
import '../data/app_database.dart' as drift;
import 'package:amuwak_core/amuwak_core.dart' show LaundryOrder, ProofEvent, ProofEventType, ServiceType, OrderStatus, LineItem;

export 'package:amuwak_core/amuwak_core.dart' show LaundryOrder;

extension LaundryOrderDriftX on LaundryOrder {
  static LaundryOrder fromDriftRow(drift.Order row, List<drift.ProofEvent> events) {
    // ... (the body of the old fromDriftRow factory, unchanged) ...
  }
}
```

Update the one staff caller of `LaundryOrder.fromDriftRow(...)` (in `lib/src/sync/` Drift read path, currently dormant under online-only) to `LaundryOrderDriftX.fromDriftRow(...)`.

- [ ] **Step 3: Move `Customer`, mappers, payloads**

Create `packages/amuwak_core/lib/src/customers/customer.dart` with the plain `Customer` model (fields per the Interfaces block) and a `Customer.fromSupabase(Map<String,dynamic>)`. Move the Drift-free contents of `lib/src/sync/supabase_mappers.dart` and `lib/src/sync/supabase_payloads.dart` into `packages/amuwak_core/lib/src/sync/`; where `customerUpsertPayload` referenced the Drift `Customer` row type, retarget it to the new core `Customer`. Add barrel exports. In the staff app, map Drift `Customer` row ↔ core `Customer` at the repository edge.

- [ ] **Step 4: Move + repoint tests, verify green**

Move `test/sync/supabase_payloads_test.dart` → `packages/amuwak_core/test/sync/supabase_payloads_test.dart`, imports → `package:amuwak_core/amuwak_core.dart`. Add a new `order_supabase_test.dart` asserting `LaundryOrder.fromSupabase` round-trips a representative row (provisional total when `final_weight_kg` null; degrades missing pricing cols to 0).

Run: `cd packages/amuwak_core && flutter analyze && flutter test && cd ../..` → green.
Run: `flutter test` (staff) → green (Drift extension path compiles; staff suite unchanged).

- [ ] **Step 5: Commit**

```bash
git add -A packages/amuwak_core lib test
git commit -m "refactor: split Drift-free LaundryOrder + Customer + mappers/payloads into amuwak_core"
```

---

### Task 2: Customer-facing repository methods + `OrderMessagesRepository` in `amuwak_core`

**Files:**
- Create: `packages/amuwak_core/lib/src/sync/orders_customer_repository.dart`
- Create: `packages/amuwak_core/lib/src/sync/order_messages_repository.dart`
- Create: `packages/amuwak_core/lib/src/sync/customer_profile_repository.dart`
- Test: sibling tests using the `.forTest()` seam pattern (no live client).

**Interfaces:**
- Produces:
  - `CustomerOrdersRepository(SupabaseClient)` with `Stream<List<LaundryOrder>> watchMine(String customerId)` (`.stream(primaryKey: ['id']).eq('customer_id', id).order('created_at')` then fetch proof rows per order, hydrate via `LaundryOrder.fromSupabase`), `Stream<LaundryOrder?> watchById(String orderId)`, and `Future<String> placeOrder(LaundryOrder draft)` (mints `order_code` via the `next_order_code` RPC, inserts with `intake_method='customer_app'`, `status='pending_pickup'`, `created_by`/`intake_recorded_by` = the sentinel id constant `kCustomerAppSentinelStaffId = '00000000-0000-0000-0000-00000000a001'`, `placed_by_customer_id = customerId`, returns the order id).
  - `OrderMessagesRepository(SupabaseClient)` with `Stream<List<OrderMessage>> watchByOrder(String orderId)`, `Future<void> send({required String orderId, required String senderKind, required String senderId, required String body})`, `Future<void> markRead(List<String> ids)`. Plus a small `OrderMessage` model (`id, orderId, senderKind, senderId, body, createdAt, readAt`).
  - `CustomerProfileRepository(SupabaseClient)` with `Stream<Customer?> watchMe()` (self row), `Future<String> linkOrCreate({required String name, required String phone, required String email})` (calls the `link_or_create_customer` RPC, returns `customers.id`).

- [ ] **Step 1 (TDD): Write a failing test for `placeOrder` payload**

In `packages/amuwak_core/test/sync/orders_customer_repository_test.dart`, drive `placeOrder` through a `.forTest()` seam (inject an `insertRow`/`rpc` lambda like the staff `OrdersRepository.forTest`) and assert the row map has `intake_method='customer_app'`, `status='pending_pickup'`, `created_by == kCustomerAppSentinelStaffId`, `placed_by_customer_id == <customerId>`, and an `order_code` from the injected RPC. Run → FAIL (class/method absent).

- [ ] **Step 2: Implement the three repositories** to satisfy the interfaces above, mirroring `lib/src/sync/orders_repository.dart`'s `.stream()`-then-join + `.forTest()` shape. Add `OrderMessage` model + barrel exports.

- [ ] **Step 3: Verify + commit**

Run: `cd packages/amuwak_core && flutter analyze && flutter test && cd ../..` → green.

```bash
git add -A packages/amuwak_core
git commit -m "feat(core): add customer orders/messages/profile repositories"
```

---

### Task 3: Scaffold `apps/amuwak_customer`

**Files:**
- Create: `apps/amuwak_customer/` Flutter project (platform folders, `pubspec.yaml`, `lib/main.dart`, `analysis_options.yaml`), font assets declared like the staff `pubspec.yaml:105-117`.
- Modify: root `pubspec.yaml` `workspace:` list to add `apps/amuwak_customer`; `melos.yaml` already globs `packages/**` — add `apps/**` to its `packages:`.

**Interfaces:**
- Produces: a runnable shell that boots Supabase via `AppBootstrap.initialize()` and shows a placeholder home behind `ProviderScope`.

- [ ] **Step 1:** `flutter create --org net.maximusglobal --project-name amuwak_customer apps/amuwak_customer`. Set `pubspec.yaml`: `resolution: workspace`, `environment.sdk: ^3.8.0`, deps `amuwak_core: {path: ../../packages/amuwak_core}`, `flutter_riverpod: ^2.5.0`, `supabase_flutter: ^2.5.0`, `go_router: ^14.0.0`; copy the `flutter: fonts:` Plus Jakarta Sans block and bundle the font files under `apps/amuwak_customer/assets/fonts/`.
- [ ] **Step 2:** Add `apps/amuwak_customer` to root `pubspec.yaml` `workspace:` and `apps/**` to `melos.yaml` `packages:`. Run `flutter pub get` at root → resolves all three packages.
- [ ] **Step 3:** Write `lib/main.dart`: `await AppBootstrap.initialize();` then `runApp(ProviderScope(child: CustomerApp()))` where `CustomerApp` builds `MaterialApp.router(theme: buildAmuwakTheme(), routerConfig: …)` with a single placeholder route. Add a smoke `testWidgets` that pumps `CustomerApp` and finds the placeholder.
- [ ] **Step 4:** Run `cd apps/amuwak_customer && flutter analyze && flutter test && cd ../..` → green. Commit.

```bash
git add -A apps/amuwak_customer pubspec.yaml pubspec.lock melos.yaml
git commit -m "feat(customer): scaffold apps/amuwak_customer in the workspace"
```

---

### Task 4: Auth — go_router redirect, login, signup + link

**Files:**
- Create: `apps/amuwak_customer/lib/src/app/router.dart` (go_router + auth redirect), `lib/src/auth/login_screen.dart`, `lib/src/auth/signup_screen.dart`, `lib/src/auth/customer_session.dart` (providers).
- Test: `apps/amuwak_customer/test/auth/router_redirect_test.dart`, `signup_flow_test.dart`.

**Interfaces:**
- Consumes: `authStateProvider`, `currentUserIdProvider`, `currentRoleProvider`, `AuthService` (core); `CustomerProfileRepository.linkOrCreate` (Task 2).
- Produces: `currentCustomerIdProvider` (resolves the linked `customers.id`, via `CustomerProfileRepository` once `currentRoleProvider == 'customer'`); a router that redirects signed-out users to `/login` and signed-in customers to `/`.

- [ ] **Step 1 (TDD):** Test: when `authStateProvider` has no session, the router redirect resolves to `/login`; when signed in as a customer, to `/`. Run → FAIL.
- [ ] **Step 2:** Implement `router.dart` with `redirect:` reading `currentUserIdProvider`/`currentRoleProvider`. Routes: `/login`, `/signup`, `/` (home), and stubs for `/orders/:id`, `/orders/new`, `/orders/:id/chat`, `/inbox`, `/account` (filled in Stage 2).
- [ ] **Step 3 (TDD):** Test the signup flow with a mocktail `AuthService`/`CustomerProfileRepository`: `signUpWithEmailPassword` then `linkOrCreate(name, phone, email)` is called and returns a customers.id; assert provider state. Run → FAIL → implement `signup_screen.dart` (email, password, name, phone via `isValidEmail` + `ugandaNationalDigits` validation from core) calling `AuthService.signUpWithEmailPassword` (added in Phase A) then `linkOrCreate`, then refreshing the session so the `customer` claim is present. → PASS.
- [ ] **Step 4:** Implement `login_screen.dart` reusing the email/password form pattern. Verify both apps green. Commit.

```bash
git add -A apps/amuwak_customer
git commit -m "feat(customer): go_router auth redirect, login, and signup+link flow"
```

---

## Stage 2 — Screens (expand each into bite-sized steps at execution)

### Task 5: My-orders home (live list)

**Files:** `apps/amuwak_customer/lib/src/orders/my_orders_screen.dart`, `lib/src/orders/providers.dart`; test `test/orders/my_orders_screen_test.dart`.
**Interfaces:** `myOrdersProvider = StreamProvider.autoDispose<List<LaundryOrder>>` watching `CustomerOrdersRepository.watchMine(currentCustomerId)`. UI: active vs history tabs (active = status != completed), each row an `AppCard` showing `orderCode`, status chip (reuse `StatusColors`), `relevantDate` label, and `outstandingUgx`/`totalUgx` via `formatUgx`. `EmptyState` when none. FAB → `/orders/new`.
**Test first:** pump with an overridden `myOrdersProvider` yielding two orders (one active, one completed); assert each lands in the right tab and the status chip text matches. Then implement. **UX:** combine the live list with the per-order timeline (Task 7) so customers aren't left refreshing (NN/g status-tracker guidance).

### Task 6: Place-order wizard + live estimate

**Files:** `lib/src/orders/place_order/` (`place_order_screen.dart` stepper, `estimate_review.dart`), `lib/src/orders/place_order/estimate_provider.dart`; tests for the estimate math wiring + a submit test.
**Interfaces:** `estimateProvider` composes `pricing_settings` (default rate, delivery fee, express flat/pct) + the customer's `customRatePerKgUgx` (via `currentCustomerProvider`) + form inputs into `recomputeTotal(PricingInputs(...))` (core). Submit calls `CustomerOrdersRepository.placeOrder(draft)` building a `LaundryOrder` with `estimatedWeightKg` = the customer's rough estimate (nullable), `finalWeightKg = null`, chosen `serviceType`/`fulfillmentMethod`/`address`/`scheduledFor`/`itemCount`/`notes`/`isExpress`.
**Test first:** given pricing settings + inputs, `estimateProvider` returns the same `OrderTotal` as `recomputeTotal` directly (and `isProvisional == true`); a submit test asserts `placeOrder` is called with `intake_method='customer_app'`. **UX:** the estimate screen shows rate/kg, est. weight × rate, delivery fee, express surcharge, estimated total, and a persistent "final price is set after we weigh your laundry" disclaimer.

### Task 7: Order detail + live tracking

**Files:** `lib/src/orders/order_detail_screen.dart`, plus a `status_timeline.dart` widget; test `order_detail_screen_test.dart`.
**Interfaces:** `orderDetailProvider(orderId) = StreamProvider.autoDispose.family` over `CustomerOrdersRepository.watchById`; `statusEventsProvider(orderId)` over a core status-events read (`.stream().eq('order_id', id)`), rendered as a vertical timeline (past = filled, current = highlighted, upcoming = muted — derive the expected sequence from the order's `intake_method`/`fulfillment_method`). Show proof photos (see Storage note below), and the price breakdown (provisional badge while `finalWeightKg == null`).
**Test first:** pump with an order + a sequence of status events; assert the timeline marks the right current step and shows the provisional badge. **Storage:** customer proof-photo viewing needs a Supabase Storage read path — extend the bucket SELECT policy to own-order photos OR mint signed URLs via a definer RPC; implement the chosen path here (decide in Task 10 hardening if deferred).

### Task 8: Per-order chat (customer side)

**Files:** `lib/src/chat/order_chat_screen.dart`, `lib/src/chat/providers.dart`; test `order_chat_screen_test.dart`.
**Interfaces:** `orderMessagesProvider(orderId) = StreamProvider.autoDispose.family` over `OrderMessagesRepository.watchByOrder`; send via `OrderMessagesRepository.send(orderId, senderKind:'customer', senderId: currentCustomerId, body)`; mark visible inbound messages read on open. Scope the subscription to the single order's channel; dispose on leave (autoDispose).
**Test first:** pump with overridden messages stream; type + send calls `send` with `senderKind:'customer'`; inbound messages render on the left, own on the right.

### Task 9: In-app inbox + staff chat screen + staff "app order" badge

**Files (customer):** `lib/src/inbox/inbox_screen.dart`, `inbox_provider.dart`; test.
**Files (staff):** `lib/src/orders/chat/order_chat_screen.dart` (staff), entry point in `lib/src/orders/order_details_screen.dart`; badge in `lib/src/orders/widgets/order_card.dart`.
**Interfaces:** `inboxProvider` aggregates, across the customer's orders, unread `order_messages` (where `read_at IS NULL` and `sender_kind='staff'`) plus recent status changes, newest first; tapping an item deep-links to `/orders/:id` or `/orders/:id/chat`. Staff chat reuses `OrderMessagesRepository` with `senderKind:'staff'`, `senderId = auth.uid()`. Staff `order_card` shows "Placed by ⟨customerName⟩ via app" when `intakeMethod == 'customer_app'` (read `placed_by_customer_id`/`customerName`).
**Test first (staff):** an order with `intakeMethod=='customer_app'` renders the badge; a staff-sent message persists with `sender_kind='staff'`. **Test first (customer):** an unread staff message appears in the inbox and is replyable.

### Task 10: Hardening

- [ ] **RLS pen-test (manual, against a test project):** sign in as customer B, attempt to read/insert/patch customer A's order and messages via direct PostgREST calls; confirm zero rows / `42501`. (Backs up the pgTAP denied-access tests from Phase B with a real JWT.)
- [ ] **Storage:** finalize customer proof-photo access (bucket policy or signed-URL RPC) and verify a customer can view only their own orders' photos.
- [ ] **Estimate↔final reconciliation:** place an order as a customer, have staff set final weight in the staff app, confirm the customer's price updates live and the provisional disclaimer clears.
- [ ] **Attribution audit:** confirm staff reports/dashboard render the sentinel `created_by` as "Customer App" and surface `placed_by_customer_id`; nothing assumes `created_by` is an active staff member.
- [ ] **CI:** `dart run melos run analyze && dart run melos run test` green across `amuwak_core`, `amuwak_staff`, `amuwak_customer`. Add a `deploy-pwa` workflow variant for the customer app (own base-href + secrets) if a customer PWA is wanted.

---

## Self-Review notes
- **Spec coverage:** registration+link (T4), self-service placement + estimate (T6), live tracking + timeline + proof (T5/T7), per-order chat + reply + inbox (T8/T9), staff chat + app-order attribution badge (T9), no-online-payment "amount due" display (T5/T6/T7), in-app realtime notifications (T9), hardening incl. RLS pen-test + Storage + estimate reconciliation (T10).
- **Reuse:** every screen builds on `amuwak_core` (theme, widgets, motion, pricing, auth, repos); no staff UI copied.
- **Constraint honored:** customers get no status/price mutation path (RLS + UI); estimate flagged provisional; subscriptions scoped + autoDispose.
- **Just-in-time expansion:** Stage-2 tasks define files/interfaces/tests/key-code; their UI steps are expanded to 2–5-min red/green/commit increments at execution, once `amuwak_core` (Stage 1) exists to compile against.

## Final verification (end of Phases C–F)
- `dart run melos run test` → all three packages green; `dart run melos run analyze` clean.
- Manual end-to-end (test project), per the Phase-design verification: register→link, place order (appears in staff queue tagged "Placed by … via app"), staff advance/weigh/proof → customer sees live updates + price finalizes, two-way chat + inbox reply, and customer B cannot see customer A's order.
