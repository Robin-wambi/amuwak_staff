# Online-only mode — ops checklist

The app currently runs **online-only**: repositories read/write Supabase
directly and the offline sync engine is disabled (see the `/* OFFLINE ... */`
blocks in `lib/src/sync/*_repository.dart` and the commit that introduced this
mode). When standing up a new Supabase environment (prod, staging, a dev
project), the following are **hard dependencies** — miss them and the app
appears to work but silently shows stale data.

## 1. Enable the Realtime publication (REQUIRED)

The read repositories use Supabase `.stream(primaryKey: ['id'])`. A stream loads
an initial snapshot via a normal select, but only delivers **live** updates for
tables that are members of the `supabase_realtime` publication. Without this,
the dashboard never reflects an order created/updated in the same session (and
the new-pickup → pickup-capture auto-advance, which waits for the new row to
arrive on the stream, won't fire).

Run once per environment (Supabase Dashboard → Database → Replication, or the
SQL editor):

```sql
alter publication supabase_realtime add table
  public.orders,
  public.customers,
  public.proof_events,
  public.staff,
  public.order_status_events;
```

`alter publication ... add table` errors if a table is already a member, so it
is intentionally **not** baked into a migration (environments that enabled it by
hand would fail). Run it manually and verify with:

```sql
select tablename from pg_publication_tables where pubname = 'supabase_realtime';
```

## 2. Row-Level Security

Reads/writes happen with the signed-in staff member's JWT. RLS must allow
authenticated staff to select/insert/update `orders`, `customers`,
`proof_events`, `order_status_events`, and select `staff`. The `anon` role sees
nothing (verified: REST with the anon key returns `Content-Range: */0`), which
is expected.

## 3. App config

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are passed via `--dart-define` (see
`lib/src/bootstrap/app_config.dart`); CI injects them from GitHub secrets in
`.github/workflows/deploy-pwa.yml`. There is no local `.env` — supply them on
the `flutter run` command line for local runs.

## Re-enabling offline later

The offline engine (Drift + outbox + `SyncOrchestrator`) is preserved, not
deleted: the sync files remain on disk but disconnected, and each repo keeps its
old implementation in a commented `OFFLINE` block. To restore offline, re-wire
`ordersRepositoryProvider` et al. to the `AppDatabase` + `OutboxRepository`,
re-watch `syncLifecycleProvider` in `main.dart`, and restore the bootstrap seed
and the sign-out teardown.
