# PWA Deployment Design — Amuwak Staff

**Status:** Design approved 2026-05-27.
**Predecessor:** [2026-05-25-new-pickup-form-design.md](./2026-05-25-new-pickup-form-design.md) (PR-B). PWA work builds on the New Pickup feature.

## Goal

Publish a Progressive Web App version of the Amuwak Staff app so the rider can install it from a stable HTTPS URL onto their phone and use it like a native app. Every push to `main` builds a new release and the rider sees it by refreshing.

## What this enables

- Install on Android phone via Chrome "Add to Home Screen"; the app opens fullscreen with the brand status bar, no browser chrome
- Data written through the form lands in Supabase via the same Drift → outbox → SyncOrchestrator pipeline used on Android
- Updates ship by `git push main` → GitHub Actions builds release → GitHub Pages serves it; rider pull-to-refreshes to receive

## Non-goals

- **No hot-reload-on-phone workflow.** Iteration happens on the laptop via `flutter run -d chrome`. Phone testing happens via the deployed prod URL.
- **No iOS Safari install support in v1.** Android Chrome only.
- **No `mobile_scanner` UX improvements for web.** The existing integration's degraded web behavior is accepted; manual entry alternatives are out of scope.
- **No private repository considerations.** Repo is assumed public on GitHub.

## Architecture

```
   Developer laptop                              Rider's phone
   ────────────────                              ──────────────
   flutter run -d chrome                         Visit prod URL once
   (hot reload on desktop)                       "Add to Home Screen"
                                                 PWA installed
   When ready:
   git push main
        │
        ▼
   GitHub Actions:
     dart run drift_dev setup-web
     flutter build web --release
     --base-href "/amuwak_staff/"
     --dart-define SUPABASE_URL/ANON_KEY
        │
        ▼
   actions/deploy-pages@v4
        │
        ▼
   https://robin-wambi.github.io/amuwak_staff/  ◄── new version
                                                         │
                                                         │ pull-to-refresh
                                                         ▼
                                                  Rider sees update
```

## File map

```
amuwak_staff/
├── .github/workflows/
│   └── deploy-pwa.yml                  [new — Section 5]
├── assets/branding/
│   └── app_icon.png                    [user-provided, already saved]
├── lib/src/data/
│   └── app_database.dart               [modify — Section 2]
├── lib/src/orders/proof/
│   └── proof_photo_storage.dart        [modify — Section 4]
├── lib/src/orders/proof/
│   └── proof_photo_storage_web.dart    [new — Section 4]
├── web/
│   ├── manifest.json                   [replace — Section 3]
│   ├── index.html                      [add iOS meta tags — Section 3]
│   ├── icons/Icon-*.png                [replace via flutter_launcher_icons]
│   ├── sqlite3.wasm                    [new asset, downloaded — Section 2]
│   └── drift_worker.js                 [new asset, downloaded — Section 2]
├── pubspec.yaml                        [add deps — Sections 2, 3, 4]
```

---

## Section 2: Drift web setup

**Strategy:** Replace `drift/native.dart` direct usage with the `drift_flutter` wrapper package, which abstracts the per-platform setup. On native, it opens `<docs>/amuwak_staff.sqlite` via `NativeDatabase`. On web, it spawns a SharedWorker running `drift_worker.js`, which loads `sqlite3.wasm` and stores rows in IndexedDB under the database name `amuwak_staff`.

**`pubspec.yaml` changes:**

```yaml
dependencies:
  drift: ^2.18.0
  drift_flutter: ^0.2.0      # NEW — cross-platform wrapper
  sqlite3: ^2.4.0            # NEW — drift_flutter's wasm path needs it
```

`sqlite3_flutter_libs` stays (drift_flutter pulls it in transitively but explicit is clearer).

**`lib/src/data/app_database.dart` change:**

Drop `dart:io`, `path`, `path_provider`. Replace `_openConnection`:

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

QueryExecutor _openConnection() => driftDatabase(
  name: 'amuwak_staff',
  web: DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  ),
);
```

**Runtime assets (downloaded once via Drift's tooling):**

```powershell
dart run drift_dev setup-web
```

Generates `web/sqlite3.wasm` (~1.3 MB) and `web/drift_worker.js` (~50 KB). Both are checked into git. Re-run when upgrading `drift` major versions.

**What does NOT change:**

- The 12-table schema
- `OrdersRepository`, `CustomersRepository`, `OutboxRepository` — they hold a `QueryExecutor` and don't know which backend serves it
- `OutboxWorker` and `SyncPuller` — they POST/GET against Supabase via `supabase_flutter`, identical on web
- `AppDatabase.forTesting(NativeDatabase.memory())` — existing tests stay native-Drift in-memory

**Multi-tab safety:** the SharedWorker means multiple browser tabs of the same PWA share one SQLite instance — no race conditions even on tablets with split-screen.

**GitHub Pages MIME type:** GitHub Pages serves `.wasm` with `Content-Type: application/wasm` by default (verified 2024+). No workaround needed.

---

## Section 3: PWA manifest + iOS support

**`web/manifest.json` — full replacement:**

```json
{
  "name": "Amuwak Staff",
  "short_name": "Amuwak",
  "description": "On-the-road tool for Amuwak laundry pickup and delivery riders.",
  "start_url": ".",
  "scope": "./",
  "display": "standalone",
  "orientation": "portrait-primary",
  "background_color": "#FFF8F2",
  "theme_color": "#A85A1F",
  "prefer_related_applications": false,
  "icons": [
    { "src": "icons/Icon-192.png",          "sizes": "192x192", "type": "image/png" },
    { "src": "icons/Icon-512.png",          "sizes": "512x512", "type": "image/png" },
    { "src": "icons/Icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icons/Icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

`background_color` and `theme_color` match `amuwakBackground` (#FFF8F2) and `amuwakPrimary` (#A85A1F) in [app_theme.dart](../../../lib/src/shared/widgets/app_theme.dart).

**`web/index.html` — add inside `<head>`:**

```html
<!-- iOS PWA support (best-effort; primary v1 target is Android) -->
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="Amuwak">
<link rel="apple-touch-icon" href="icons/Icon-192.png">
```

**Icons via `flutter_launcher_icons`:**

Add to `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1

flutter_launcher_icons:
  web:
    generate: true
    image_path: "assets/branding/app_icon.png"
    background_color: "#FFF8F2"
    theme_color: "#A85A1F"
```

Run once:

```powershell
dart run flutter_launcher_icons
```

Generates `web/icons/Icon-{192,512,maskable-192,maskable-512}.png` from the user-provided `assets/branding/app_icon.png` (currently 257×257; will upscale to 512 with slight softness — acceptable for v1).

**Service worker:** no code changes. Flutter auto-generates `flutter_service_worker.js` during `flutter build web` with the default `offline-first` strategy. If post-deploy update behaviour becomes a problem in real-world use, we can swap to `--pwa-strategy=none` later.

---

## Section 4: Web-specific code paths

Three places where native APIs need a web alternative; all use `kIsWeb` to gate platform-specific code.

### Place 1: `ProofPhotoStorage` — file-system vs IndexedDB

[lib/src/orders/proof/proof_photo_storage.dart](../../../lib/src/orders/proof/proof_photo_storage.dart) currently writes proof photos via `dart:io` `File` and `path_provider`. Neither works on web.

**Solution:** Add `WebProofPhotoStorage` that stores photos as `Uint8List` blobs in IndexedDB via the `idb_shim` package. Same `ProofPhotoStorage` interface; the factory routes to the right implementation:

```dart
ProofPhotoStorage createProofPhotoStorage() =>
    kIsWeb ? WebProofPhotoStorage() : FileProofPhotoStorage();
```

`InMemoryProofPhotoStorage` (used by tests) stays as-is — it's already platform-agnostic.

Add to `pubspec.yaml`:

```yaml
dependencies:
  idb_shim: ^2.6.1
```

### Place 2: `image_picker` — camera capture differs, but no code change

On native, `image_picker` with `ImageSource.camera` opens a custom camera UI. On web, the same call opens the browser's `<input type="file" capture="environment">` element, which on mobile browsers prompts the OS camera and on desktop opens a file dialog.

**Decision:** no code change. `image_picker` handles the platform difference internally. The existing pickup/delivery capture flows call `XFile.readAsBytes()` to feed `ProofPhotoStorage`, which works identically.

UX consequence: riders on the PWA see the browser's native camera UI, not a custom Flutter screen. Acceptable for v1.

### Place 3: `mobile_scanner` — degraded on web

`mobile_scanner` supports web but slower scanning and no torch/zoom. The existing `BarcodeReader` abstraction returns `Future<String?>` so the data flow is unchanged.

**Decision:** let `mobile_scanner` handle web with its existing limitations. If real-world rider testing shows it's a blocker, revisit with one of:
- (a) Manual entry fallback text field
- (b) Alternative web QR library via JS interop

### Place 4: `path_provider` calls inside `app_database.dart`

Already handled by Section 2's switch to `drift_flutter`. No additional `kIsWeb` guards needed.

---

## Section 5: GitHub Actions deploy pipeline

**`.github/workflows/deploy-pwa.yml`:**

```yaml
name: Deploy PWA to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.32.0

      - run: flutter pub get
      - run: dart run drift_dev setup-web
      - run: flutter build web --release
          --base-href "/amuwak_staff/"
          --dart-define=SUPABASE_URL=${{ secrets.SUPABASE_URL }}
          --dart-define=SUPABASE_ANON_KEY=${{ secrets.SUPABASE_ANON_KEY }}

      - uses: actions/upload-pages-artifact@v3
        with:
          path: build/web

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

**One-time GitHub UI setup:**

1. Repo Settings → Pages → Source: **GitHub Actions**
2. Repo Settings → Secrets and variables → Actions → New repository secret:
   - `SUPABASE_URL` = `https://rrxcsscinwqrxivczrfg.supabase.co`
   - `SUPABASE_ANON_KEY` = `<the JWT>`

**Why `--base-href`?** GitHub Pages serves at `username.github.io/REPO_NAME/`, so every relative URL (`sqlite3.wasm`, `drift_worker.js`, icons) needs the `/amuwak_staff/` prefix or they 404. The flag rewrites `<base href>` in `index.html` accordingly.

**Anon key in CI:** the Supabase anon key is designed to be public (RLS enforces auth server-side). Keeping it in GitHub Secrets is hygiene, not a hard security boundary.

**Deploy cadence:** ~5–7 min first build (downloads Flutter SDK), ~3 min subsequent builds (SDK cached).

**Update visibility on phone:** Flutter's service worker uses offline-first caching by default. After a deploy, the phone sees the old cached version on first refresh but starts fetching the new one in the background; the second refresh activates the new version. If this becomes annoying, switch to `--pwa-strategy=none` in `index.html`.

---

## Section 6: Testing strategy

Four tiers, each gating the next.

### Tier 1 — existing test suite passes (automated)

`flutter test` runs on the Dart VM (native target). After the Section 2 and Section 4 refactors land, all 275 existing tests must still pass — they exercise the native Drift path and `InMemoryProofPhotoStorage`, neither affected by the web additions.

Acceptance: `flutter test` reports 275 passing, no regressions.

### Tier 2 — web build succeeds in CI (automated)

The GitHub Actions workflow runs `dart run drift_dev setup-web` then `flutter build web --release`. Any stray `dart:io` import, missing WASM asset, or web-incompatible type fails the build before deploy starts.

Acceptance: GitHub Actions green check on push to `main`.

### Tier 3 — local Chrome smoke test (manual, ~5 min)

```powershell
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

- [ ] App opens to login screen with no DevTools console errors
- [ ] Sign in succeeds
- [ ] Dashboard renders, seeded orders appear after first sync
- [ ] Tap "New pickup" → form opens
- [ ] Fill all required fields → "Create pickup" → form pops, new card appears
- [ ] Refresh the page → form-created order is still there (IndexedDB persistence)
- [ ] DevTools → Application → IndexedDB → `amuwak_staff` database has rows

### Tier 4 — phone install + functional smoke (manual, ~10 min)

After Tier 3 passes and CI deploys to prod URL:

- [ ] Open prod URL in Chrome on Android phone
- [ ] Three-dot menu → "Add to Home Screen" → confirm install
- [ ] Tap home-screen icon → app opens fullscreen (no URL bar)
- [ ] Status bar shows brand orange (theme_color)
- [ ] Sign in works
- [ ] New Pickup form: validation works, Create button toggles correctly
- [ ] "Use my location" chip: OS permission prompt appears, address fills after grant
- [ ] Schedule for later → Tomorrow morning → chip highlights, "Scheduled for: Tomorrow, 9:00 AM"
- [ ] Submit → form closes → dashboard shows new card with correct timeLabel
- [ ] Close PWA, reopen → state survives (auth + Drift data)
- [ ] Verify in Supabase: `SELECT * FROM orders ORDER BY created_at DESC LIMIT 5;` includes the test pickup

### Tier 5 — update flow validation (manual, ~3 min)

- [ ] Push a trivial visible change to `main`
- [ ] Wait for GitHub Actions to finish (~3 min)
- [ ] On phone: pull-to-refresh the PWA twice
- [ ] Confirm the change is visible after the second refresh

---

## Out of scope (tracked for follow-ups)

- iOS Safari install testing — requires an iPhone, not assumed available
- `mobile_scanner` web UX improvements
- Multi-tab Drift coordination stress testing
- Offline → online sync flake recovery tests (covered by existing OutboxWorker unit tests; web backend uses same outbox code)
- Service-worker update banner with manual "refresh now" affordance
- Custom domain (would replace `username.github.io/amuwak_staff/` with `staff.amuwak.com`)

## Risks and unknowns

- **257×257 icon source upscales to 512:** acceptable for phone home-screen sizes; tablets may show softness. Higher-res source can replace later without code change.
- **GitHub Pages deploy cadence:** ~3 min from push to phone-visible. If real-world iteration shows this is too slow, the laptop hot-reload workflow remains available as a fallback (run `flutter run -d chrome` and develop on the desktop browser).
- **`mobile_scanner` web behavior:** untested by us; may require manual-entry fallback if rider testing surfaces problems.
- **Service worker stickiness:** Flutter's default offline-first strategy can hold old versions on iOS Safari. v1 targets Android only, so this is deferred.
- **Anon key exposure:** by design, public. RLS policies must be correctly set up server-side. Pre-existing concern unchanged by PWA work.

## Source spec references

- [Drift web platform docs](https://drift.simonbinder.eu/platforms/web/)
- [Flutter hot reload docs](https://docs.flutter.dev/tools/hot-reload)
- [Flutter web FAQ](https://docs.flutter.dev/platform-integration/web/faq)
- [actions/deploy-pages](https://github.com/actions/deploy-pages)
