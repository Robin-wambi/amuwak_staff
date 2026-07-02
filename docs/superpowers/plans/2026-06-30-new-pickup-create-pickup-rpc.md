# New Pickup save failure — fix via rider = manager access (RLS)

## Context

A rider taps **Create pickup** and gets a red error ("Could not save customer: … write did not persist"). Root cause is RLS vs. the rider workflow now that the app writes Supabase directly (online-only). It is **not** caused by test order rows and **not** a migration-apply failure — it reproduces on an empty DB.

The New Pickup flow ([new_pickup_screen.dart](../../../lib/src/orders/new_pickup_screen.dart) `_onSubmit`) does three writes; for a `driver`-role rider the **first** fails:
1. `upsertCustomer` → blocked: `customers_write` ([0007_rls.sql:47-49](../../../supabase/migrations/0007_rls.sql#L47-L49)) allows only `in_shop`/`manager`.
2. `reserveOrderCode` — fine.
3. `upsertOrder` → would also fail: `orders_insert` driver branch ([0010:29-34](../../../supabase/migrations/0010_tighten_orders_rls.sql#L29-L34)) requires `assigned_driver = auth.uid()`, which the client never sets ([supabase_payloads.dart](../../../lib/src/sync/supabase_payloads.dart)).

`in_shop`/`manager` are unaffected, so it only bites the rider/driver tool.

## Decision (user-chosen)

Give the rider **full manager parity, for now**, implemented as the smallest possible change: remap `'driver' -> 'manager'` inside the one helper every RLS policy branches on, `auth_staff_role()`. One migration uniformly grants drivers manager access (write customers, create orders via the manager branch with no `assigned_driver`, see/edit/delete all orders, manage staff, edit pricing). It does **not** touch the JWT `user_role` claim, so the app UI keeps the rider screens — only DB permissions are elevated. Reversible by restoring the original function body.

This fixes New Pickup with **zero client code changes**.

## Implemented

- **`supabase/migrations/0039_rider_manager_access.sql`** — `CREATE OR REPLACE FUNCTION auth_staff_role()` returning `CASE WHEN role = 'driver' THEN 'manager' ELSE role END …`, plus the house-style `REVOKE … FROM public; GRANT … TO authenticated;`.
- **`supabase/tests/0039_rider_manager_access_test.sql`** — pgTAP: a rider can insert a customer; can create a `driver_pickup` order without `assigned_driver`; sees all orders; the created order is attributed to them.
- **Updated existing tests whose driver-restriction assertions invert under the remap** (both run against the final post-0039 schema):
  - [0007_rls_test.sql](../../../supabase/tests/0007_rls_test.sql): "driver sees only own order" → now sees all (count 2); the single-row `order_code` subquery → a deterministic count.
  - [0010_review_fixes_test.sql](../../../supabase/tests/0010_review_fixes_test.sql): "driver cannot reassign" (`throws_ok`) → "rider can reassign" (`lives_ok`). Assertions for the status-pin block and the assigned_driver trigger stay green (manager is equally bound / trigger is role-independent).

### Migration numbering

`0031` exists on `feat/finance-report-payment-tracking`; `0032`–`0038` are reserved for customer-app phase B. To avoid a duplicate-prefix collision (CI guard in `.github/workflows/migrations-lint.yml`) this fix is **`0039`**. If it merges before the 0031–0038 work, reconcile ordering at merge time (renumber or `supabase db push --include-all`).

## Verification

- Docker was unavailable locally, so the pgTAP suite was **not** run here — run it in CI or with Docker up: `supabase db reset` then `supabase test db` → 0039 test passes; 0007 and 0010 tests green; all prior green.
- Manual end-to-end as a rider: open New pickup, fill the form, Create → a real customer + order are written and the flow proceeds to Pickup capture. Confirm an `in_shop`/`manager` user can still create orders.
- `flutter analyze` unaffected (no client changes for this fix).

## Still pending (separate task — the rider's other request)

Field error texts should appear to flag a **forgotten** field on submit, but not scream on a blank form. In [new_pickup_screen.dart](../../../lib/src/orders/new_pickup_screen.dart): wrap fields in a `Form`+`GlobalKey<FormState>` (house convention — see [login_screen.dart](../../../lib/src/auth/login_screen.dart)), switch `AutovalidateMode.always` → `onUserInteraction`, validate on submit so forgotten fields flash their errors; gate the count `errorText` behind a touched flag. Update the three widget tests in [test/orders/new_pickup_screen_test.dart](../../../test/orders/new_pickup_screen_test.dart) (L253-265, L267-280, L334-356) that currently assert always-on errors.
