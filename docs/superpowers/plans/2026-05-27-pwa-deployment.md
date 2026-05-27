# PWA Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Amuwak Staff app build as a release-mode Progressive Web App and auto-deploy to `https://robin-wambi.github.io/amuwak_staff/` on every push to `main`, installable on Android phones via Chrome's "Add to Home Screen".

**Architecture:** Replace `drift/native.dart` direct usage with the `drift_flutter` wrapper (one call serves both NativeDatabase on native and a WASM/IndexedDB-backed SQLite on web). Isolate the lingering `dart:io` usage in `proof_photo_storage.dart` into a `_io.dart` file that web targets won't import. Add a proper PWA manifest, iOS meta tags, brand icons, and a GitHub Actions workflow that builds `flutter build web --release` and publishes the artifact to GitHub Pages.

**Tech Stack:** Flutter 3.32.0, Drift 2.18+, drift_flutter 0.x, sqlite3 2.x, flutter_launcher_icons 0.13.x, GitHub Actions (subosito/flutter-action@v2, actions/deploy-pages@v4).

**Source spec:** [2026-05-27-pwa-deployment-design.md](../specs/2026-05-27-pwa-deployment-design.md)

---

## File map

```
amuwak_staff/
├── .github/workflows/
│   └── deploy-pwa.yml                          [new — Task 5]
├── assets/branding/
│   └── app_icon.png                            [user-provided, already in repo]
├── lib/src/data/
│   └── app_database.dart                       [modify — Task 2]
├── lib/src/orders/proof/
│   ├── proof_photo_storage.dart                [reduce — Task 1]
│   └── proof_photo_storage_io.dart             [new — Task 1]
├── test/orders/proof/
│   └── proof_photo_storage_test.dart           [modify — Task 1]
├── web/
│   ├── manifest.json                           [replace — Task 4]
│   ├── index.html                              [modify — Task 4]
│   ├── icons/Icon-*.png                        [regenerate — Task 4]
│   ├── sqlite3.wasm                            [new (binary) — Task 3]
│   └── drift_worker.js                         [new (binary) — Task 3]
└── pubspec.yaml                                [modify — Tasks 2, 4]
```

5 tasks, each ending in one commit.

---

### Task 1: Extract `FileProofPhotoStorage` into a `_io.dart` file

The current `proof_photo_storage.dart` has `import 'dart:io'` at line 1, which makes the whole file (and anything that imports it — including `staff_dashboard_screen.dart`, the capture screens, and every test that touches photo storage) fail to compile on web targets.

Production code today already uses `InMemoryProofPhotoStorage` (see `staff_dashboard_screen.dart:61`), so the file system path is only exercised by tests. We move the file-system implementation behind a separate import that web targets won't reach.

**Files:**
- Create: `lib/src/orders/proof/proof_photo_storage_io.dart`
- Modify: `lib/src/orders/proof/proof_photo_storage.dart`
- Modify: `test/orders/proof/proof_photo_storage_test.dart`

- [ ] **Step 1: Inspect current state of proof_photo_storage.dart**

Run: `Read lib/src/orders/proof/proof_photo_storage.dart`

Confirm the file contains: `compressTargetForMaxEdge`, `PickPhotoFn`, `ProofPhotoStorage` (abstract), `SavedProofPhoto`, `InMemoryProofPhotoStorage`, `PhotoCompressor`, `FileProofPhotoStorage`, `createDefaultProofPhotoStorage`. These are the seven exports currently grouped in one file.

- [ ] **Step 2: Create the new `_io.dart` file with the native-only pieces**

Create `lib/src/orders/proof/proof_photo_storage_io.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../proof_event.dart';
import 'proof_photo_storage.dart';

/// Computes the `minWidth` / `minHeight` pair to pass to
/// `FlutterImageCompress.compressWithList` so that the LONGER edge of the
/// result is at most [maxEdge] pixels, preserving aspect ratio.
({int minWidth, int minHeight}) compressTargetForMaxEdge({
  required int width,
  required int height,
  required int maxEdge,
}) {
  if (width >= height) {
    return (
      minWidth: maxEdge,
      minHeight: (maxEdge * height / width).round(),
    );
  }
  return (
    minWidth: (maxEdge * width / height).round(),
    minHeight: maxEdge,
  );
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
    final orderDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}proofs${Platform.pathSeparator}$orderId',
    );
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
/// and uses flutter_image_compress to shrink images so the longer edge is
/// capped at 1280 pixels (JPEG quality 80). Native targets only.
Future<FileProofPhotoStorage> createDefaultProofPhotoStorage() async {
  final dir = await getApplicationDocumentsDirectory();
  return FileProofPhotoStorage(
    baseDir: dir,
    compressor: (bytes) async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final target = compressTargetForMaxEdge(
        width: image.width,
        height: image.height,
        maxEdge: 1280,
      );
      image.dispose();
      codec.dispose();
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: target.minWidth,
        minHeight: target.minHeight,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      return result;
    },
  );
}
```

- [ ] **Step 3: Reduce `proof_photo_storage.dart` to platform-agnostic exports**

Replace `lib/src/orders/proof/proof_photo_storage.dart` with:

```dart
import '../proof_event.dart';

typedef PickPhotoFn = Future<List<int>?> Function();

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

The file is now web-safe (no `dart:io`, no `path_provider`, no `flutter_image_compress`).

- [ ] **Step 4: Update the test file to import from the new location**

Open `test/orders/proof/proof_photo_storage_test.dart`. Add the new import alongside the existing one:

```dart
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage_io.dart';
```

No other changes — `InMemoryProofPhotoStorage` and `ProofPhotoStorage` still come from the first import; `FileProofPhotoStorage` and `compressTargetForMaxEdge` now come from the second.

- [ ] **Step 5: Run the proof_photo_storage tests, verify they pass**

Run: `flutter test test/orders/proof/proof_photo_storage_test.dart`
Expected: all tests pass (`+N: All tests passed!`).

- [ ] **Step 6: Run the full test suite, verify no regressions**

Run: `flutter test`
Expected: 275 passing (matches current `main`).

- [ ] **Step 7: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add lib/src/orders/proof/proof_photo_storage.dart lib/src/orders/proof/proof_photo_storage_io.dart test/orders/proof/proof_photo_storage_test.dart
git commit -m "Extract FileProofPhotoStorage into proof_photo_storage_io.dart

The dart:io import in proof_photo_storage.dart was breaking web compile
for everything that transitively imported it. Production code only uses
InMemoryProofPhotoStorage (see staff_dashboard_screen.dart) so the
file-system implementation moves behind a separate import that web
targets never reach. Tests now import both files.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- lib/src/orders/proof/proof_photo_storage.dart lib/src/orders/proof/proof_photo_storage_io.dart test/orders/proof/proof_photo_storage_test.dart
```

---

### Task 2: Switch `_openConnection` to `drift_flutter`

`lib/src/data/app_database.dart` currently uses `drift/native.dart` directly with `dart:io` and `path_provider` to construct the SQLite file path. We replace it with the cross-platform `drift_flutter` wrapper — one call serves both native (where it still uses `NativeDatabase`) and web (where it spawns the SharedWorker running `drift_worker.js` against `sqlite3.wasm` backed by IndexedDB).

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/src/data/app_database.dart`

- [ ] **Step 1: Add `drift_flutter` and `sqlite3` to `pubspec.yaml`**

Open `pubspec.yaml`. Under `dependencies:`, alongside the existing `drift: ^2.18.0`, add:

```yaml
  drift_flutter: ^0.2.0
  sqlite3: ^2.4.0
```

Run: `flutter pub get`
Expected: `Got dependencies!`. The actual resolved versions may be newer than `^0.2.0` / `^2.4.0` — that's fine; `pub` picks the latest compatible release.

- [ ] **Step 2: Replace `_openConnection` in `app_database.dart`**

Open `lib/src/data/app_database.dart`. Replace lines 1–6 (the import block) and lines 46–50 (the `_openConnection` function) so the file becomes:

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
import 'tables/pull_dead_letter_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Staff, Customers, Orders, OrderStatusEvents,
  ProofEvents, ProofPhotos, Issues, Shifts,
  ValidTransitions, Outbox, SyncWatermarks,
  PullDeadLetter,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(pullDeadLetter);
          }
        },
      );
}

QueryExecutor _openConnection() => driftDatabase(
      name: 'amuwak_staff',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
```

Changes: drops `dart:io`, `drift/native.dart`, `path`, `path_provider` imports; replaces the `LazyDatabase` factory body with a single `driftDatabase()` call.

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`. If the analyzer complains about unused imports (e.g. `path`), remove them.

- [ ] **Step 4: Run the full test suite, verify no regressions**

Run: `flutter test`
Expected: 275 passing. Existing tests use `AppDatabase.forTesting(NativeDatabase.memory())` which bypasses `_openConnection` entirely, so they're unaffected.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/src/data/app_database.dart
git commit -m "Switch Drift _openConnection to drift_flutter for web support

drift_flutter abstracts the per-platform database backend:
- Native: NativeDatabase backed by <docs>/amuwak_staff.sqlite (same as before)
- Web: SharedWorker running drift_worker.js against sqlite3.wasm, persisted in IndexedDB

The schema, queries, repositories, and OutboxWorker are all unchanged.
Tests use AppDatabase.forTesting(NativeDatabase.memory()) which bypasses
_openConnection entirely, so they're unaffected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- pubspec.yaml pubspec.lock lib/src/data/app_database.dart
```

---

### Task 3: Generate `sqlite3.wasm` and `drift_worker.js` web assets

`drift_flutter`'s web path needs two runtime files served from the same origin as the app. Drift ships a tooling command that downloads version-pinned binaries into `web/`. We commit these to git so dev builds work without re-running the command and so CI doesn't have to.

**Files:**
- Create (binary): `web/sqlite3.wasm` (~1.3 MB)
- Create (text):   `web/drift_worker.js` (~50 KB)

- [ ] **Step 1: Run the drift_dev setup command**

Run: `dart run drift_dev setup-web`
Expected: command prints download progress, then `Wrote web/sqlite3.wasm` and `Wrote web/drift_worker.js`. Takes ~10–30 s.

- [ ] **Step 2: Verify both files exist**

Run: `ls -la web/sqlite3.wasm web/drift_worker.js`
Expected: both files present, `sqlite3.wasm` is ~1.3 MB, `drift_worker.js` is ~50 KB.

- [ ] **Step 3: Confirm `.gitignore` doesn't exclude them**

Run: `git check-ignore web/sqlite3.wasm web/drift_worker.js`
Expected: empty output (no matches) — meaning the files are not gitignored.

If either is matched by `.gitignore`, add explicit allow rules at the bottom of `.gitignore`:

```gitignore
!web/sqlite3.wasm
!web/drift_worker.js
```

- [ ] **Step 4: Commit**

```bash
git add web/sqlite3.wasm web/drift_worker.js
git commit -m "Add Drift web runtime assets (sqlite3.wasm + drift_worker.js)

Generated via 'dart run drift_dev setup-web'. Version-pinned binaries
served as static assets by Flutter web; required at runtime by the
driftDatabase() call in app_database.dart.

Re-run the setup command when upgrading drift major versions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- web/sqlite3.wasm web/drift_worker.js
```

---

### Task 4: PWA manifest + iOS meta tags + brand icons

Turn the default Flutter web scaffold into a branded installable PWA. Three sub-changes, all in `web/` and `pubspec.yaml`, committed together because they belong to the same conceptual change ("make this look like a real app on the home screen").

**Files:**
- Replace: `web/manifest.json`
- Modify: `web/index.html`
- Modify: `pubspec.yaml`
- Regenerate: `web/icons/Icon-192.png`, `web/icons/Icon-512.png`, `web/icons/Icon-maskable-192.png`, `web/icons/Icon-maskable-512.png`

- [ ] **Step 1: Replace `web/manifest.json` with the brand-correct manifest**

Replace the entire contents of `web/manifest.json` with:

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

`background_color` matches `amuwakBackground` (#FFF8F2); `theme_color` matches `amuwakPrimary` (#A85A1F) — both from `lib/src/shared/widgets/app_theme.dart`.

- [ ] **Step 2: Add iOS PWA meta tags to `web/index.html`**

Open `web/index.html`. Inside the `<head>` element, after the existing `<meta name="description" ...>` tag (or anywhere inside `<head>` before the closing `</head>`), add:

```html
<!-- iOS PWA support -->
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="Amuwak">
<link rel="apple-touch-icon" href="icons/Icon-192.png">
```

These tags make iOS Safari treat the PWA as a standalone app after "Add to Home Screen" (no Safari URL bar). v1 explicitly targets Android, but the iOS tags are cheap to include.

- [ ] **Step 3: Add `flutter_launcher_icons` to `pubspec.yaml`**

Open `pubspec.yaml`. Under `dev_dependencies:`, add:

```yaml
  flutter_launcher_icons: ^0.13.1
```

Then add a top-level `flutter_launcher_icons:` config block (after the `flutter:` block, before the trailing comment):

```yaml
flutter_launcher_icons:
  web:
    generate: true
    image_path: "assets/branding/app_icon.png"
    background_color: "#FFF8F2"
    theme_color: "#A85A1F"
```

We only generate the web icons here. Android/iOS native icons stay untouched (this PR is web-only).

Run: `flutter pub get`
Expected: `Got dependencies!`.

- [ ] **Step 4: Generate the icons**

Run: `dart run flutter_launcher_icons`
Expected: command prints `Created icon Icon-192.png ...` etc. for each generated PNG.

- [ ] **Step 5: Verify the icons exist**

Run: `ls web/icons/`
Expected: at least `Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png` (the four names referenced by the manifest). The package may also generate `favicon.png` — fine to keep.

- [ ] **Step 6: Build the PWA in release mode and verify the artifact**

Run: `flutter build web --release --dart-define=SUPABASE_URL=https://rrxcsscinwqrxivczrfg.supabase.co --dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY`

(Or replace `$env:SUPABASE_ANON_KEY` with the literal key — the build only embeds it in JS, same as the prod URL will. The build runs offline-only and doesn't hit Supabase.)

Expected: `✓ Built build\web` after ~30–90 s. No errors.

Run: `ls build/web/`
Expected: `index.html`, `main.dart.js`, `manifest.json`, `sqlite3.wasm`, `drift_worker.js`, `flutter_service_worker.js`, `icons/`, `canvaskit/`.

This is the artifact that GitHub Actions will publish. If this step fails, fix before moving to Task 5 — CI will fail the same way.

- [ ] **Step 7: Local Chrome smoke test (manual)**

Run: `flutter run -d chrome --dart-define=SUPABASE_URL=https://rrxcsscinwqrxivczrfg.supabase.co --dart-define=SUPABASE_ANON_KEY=<the key>`
Expected: Chrome opens; login screen renders without console errors.

Manual checklist (in Chrome DevTools):
- [ ] Sign in succeeds
- [ ] Dashboard renders
- [ ] Tap "New pickup" → form opens
- [ ] DevTools → Application → Manifest: shows "Amuwak Staff" with orange theme
- [ ] DevTools → Application → IndexedDB: `amuwak_staff` database exists after first write

If anything in this checklist fails, fix before committing.

- [ ] **Step 8: Commit**

```bash
git add web/manifest.json web/index.html web/icons/Icon-192.png web/icons/Icon-512.png web/icons/Icon-maskable-192.png web/icons/Icon-maskable-512.png pubspec.yaml pubspec.lock
git commit -m "Brand the PWA: manifest, iOS meta tags, generated icons

- web/manifest.json: real app name, brand colors (background #FFF8F2,
  theme #A85A1F), maskable icons for Android home-screen
- web/index.html: apple-mobile-web-app-* meta tags so iOS Safari
  treats Add-to-Home-Screen as a standalone app
- pubspec.yaml: flutter_launcher_icons dev dep + web config
- web/icons/Icon-*.png: regenerated from assets/branding/app_icon.png

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- web/manifest.json web/index.html web/icons/ pubspec.yaml pubspec.lock
```

---

### Task 5: GitHub Actions deploy workflow

The workflow checks out the repo, installs Flutter, re-runs `drift_dev setup-web` (defensive — also ensures freshness even if someone forgot to commit updated assets), builds the web release with `SUPABASE_URL` and `SUPABASE_ANON_KEY` from GitHub Secrets, and publishes `build/web` to GitHub Pages.

**Files:**
- Create: `.github/workflows/deploy-pwa.yml`

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/deploy-pwa.yml`:

```yaml
name: Deploy PWA to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch: {}

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
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

      - name: Install Dart deps
        run: flutter pub get

      - name: Regenerate Drift web assets
        run: dart run drift_dev setup-web

      - name: Build PWA release bundle
        run: |
          flutter build web --release \
            --base-href "/amuwak_staff/" \
            --dart-define=SUPABASE_URL=${{ secrets.SUPABASE_URL }} \
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

- [ ] **Step 2: Verify the YAML parses**

Run: `flutter analyze` (analyzer ignores YAML, just confirming the broader build still passes).

For YAML correctness specifically, paste the file contents into [yamllint.com](https://www.yamllint.com/) or check via:

```powershell
# If python is available
python -c "import yaml; yaml.safe_load(open('.github/workflows/deploy-pwa.yml'))"
```

Expected: no parse errors. (This step is best-effort — the real validation happens when GitHub Actions runs.)

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/deploy-pwa.yml
git commit -m "Add GitHub Actions workflow to deploy PWA to GitHub Pages

Triggers on push to main and manual workflow_dispatch. Builds with
--base-href '/amuwak_staff/' (GitHub Pages repo path), passes
SUPABASE_URL and SUPABASE_ANON_KEY from repo secrets, uploads
build/web as the GitHub Pages artifact.

One-time external setup required before this workflow can deploy:
  1. Repo Settings > Pages > Source: GitHub Actions
  2. Repo Settings > Secrets and variables > Actions:
     - SUPABASE_URL
     - SUPABASE_ANON_KEY

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>" -- .github/workflows/deploy-pwa.yml

git push -u origin feature/pwa-deployment
```

- [ ] **Step 4: Do the one-time GitHub UI setup (manual, by the user)**

Go to `https://github.com/Robin-wambi/amuwak_staff/settings`:

1. **Pages**: Settings → Pages → "Build and deployment" → Source: select **GitHub Actions**.
2. **Secrets**: Settings → Secrets and variables → Actions → "New repository secret":
   - Name: `SUPABASE_URL`, Value: `https://rrxcsscinwqrxivczrfg.supabase.co`
   - Name: `SUPABASE_ANON_KEY`, Value: the JWT (the long string starting with `eyJ...`)

- [ ] **Step 5: Trigger a manual run to verify the workflow before merging to main**

Go to `https://github.com/Robin-wambi/amuwak_staff/actions/workflows/deploy-pwa.yml` → "Run workflow" → choose `feature/pwa-deployment` from the branch dropdown → "Run workflow".

Expected: build job succeeds in ~5–7 min (first run), deploy job succeeds in ~30 s. Final URL printed in the job logs: `https://robin-wambi.github.io/amuwak_staff/`.

If the build fails, the most likely causes:
- **`flutter-version: 3.32.0` doesn't match what subosito ships**: change to `flutter-version: 3.x` to pick the latest stable.
- **Secrets misspelled**: confirm names match exactly (case-sensitive).
- **Drift assets not committed**: re-run Task 3 locally, commit, push.

- [ ] **Step 6: Smoke-test the deployed PWA on phone (Tier 4 from spec)**

On your Android phone, open Chrome and navigate to `https://robin-wambi.github.io/amuwak_staff/`.

Manual checklist:
- [ ] Login screen renders, brand colors visible
- [ ] Three-dot menu → "Add to Home Screen" → confirm install
- [ ] Tap home-screen icon → app opens fullscreen (no URL bar)
- [ ] Sign in works
- [ ] New Pickup form opens, fills, submits
- [ ] After submit, verify in Supabase dashboard: `SELECT * FROM orders ORDER BY created_at DESC LIMIT 5;` includes the test pickup

---

## Post-execution checklist

After Task 5:

- [ ] `flutter test` is 275/275 passing (no regressions).
- [ ] `flutter analyze` reports `No issues found!`.
- [ ] `flutter build web --release` succeeds locally.
- [ ] GitHub Actions workflow runs green on `feature/pwa-deployment` (or `main` after merge).
- [ ] The deployed URL is reachable and the PWA installs cleanly on Android.
- [ ] A test pickup created via the installed PWA appears in the Supabase `orders` table.

## Out of scope (documented in spec)

- WebProofPhotoStorage with IndexedDB-backed photo persistence — defer until photos are uploaded somewhere real (Supabase Storage). Prod currently uses InMemoryProofPhotoStorage on all platforms.
- mobile_scanner web UX improvements.
- iOS Safari install testing.
- Custom domain (would replace `username.github.io/amuwak_staff/`).
- Service-worker "new version available — refresh now" banner.
