# TRAFFICITY — Repair Execution Master Prompt (rev. 2)

**Purpose:** single source of truth for repairing, completing, testing, documenting, and packaging the Uzbekistan expansion of Trafficity.

| Item | Value |
|---|---|
| Repository | `abdulloh042006-debug/Trafficity` (GitHub URLs are case-insensitive; the clone remote is lower-case `trafficity`) |
| Working branch | `codex/uzbekistan-expansion` |
| Protected branch | `main` — never modify, merge into, rebase onto, or force-push without explicit owner approval |
| Baseline re-audited at | commit `a960dfb` ("docs(trafficity): add verified repair execution master prompt"), a single grafted commit |
| Previously audited commit | `5f190b92347a5b78a396d8c2fdc5858a79e4fa0c` (historical; its CI run #15 / ID `41574007338` failed at `flutter analyze` with 70 issues) |
| Owner language | Uzbek. Final report and chat replies to the owner are written in Uzbek. Code, commits, and this file stay in English. |

**Revision note (rev. 2):** rewritten after re-checking every baseline claim against the actual files. Changes: removed claims that no longer match the tree, added the environment/bootstrap section, added the decisions section (so the executor does not stall on ambiguities), fixed the unusable "recover from Git history" instruction (the clone is shallow), documented the real `tashkent_roads.json` schema, defined the missing package/chunk layout, added the blocker protocol for credentials and workflow-file pushes, and added a status vocabulary.

---

## 0. HOW TO USE THIS FILE

1. Read this whole file, then `CLAUDE.md` (project identity, constraints, economy rules), then `UZBEKISTAN_EXPANSION_README.md`.
2. Work phases **P0 → P12 in order**. Each phase has a *Dependencies* line and a *Done when* checklist. Do not start a phase whose dependencies are not green.
3. One coherent phase = one commit (then push, if credentials exist — see §3). Message format: `type(scope): summary` + the attribution trailer required by the session.
4. If budget or time runs out: finish the current phase cleanly (tests green, ledger updated, committed) and stop. A smaller truthful state beats a larger broken one.
5. Priority if you must triage: **P1 (analyzer/tests green) → P3 (real SHA-256) → P2 → P5 → P4 → P7 → P8 → P10 → P6 → P9 → P11 → P12.** Order of *execution* stays P0 → P12 unless a dependency forces otherwise.

### 0.1 Status vocabulary (use exactly these words in the ledger and report)

| Status | Meaning |
|---|---|
| **PASS** | The real command ran in this session and exited 0; output was inspected. |
| **CI-PASS** | The GitHub Actions run for the exact final commit concluded `success`. |
| **FAIL** | The command ran and failed. Record command, exit code, key error. |
| **MOCK-ONLY** | Covered only by mocks/fixtures; proves request construction or logic, not a real integration. |
| **BLOCKED** | A concrete external dependency is missing (credential, network, SDK). Record evidence and what unblocks it. |
| **NOT RUN** | Not attempted or no tool available. Never describe as passed. |

---

## 1. EXECUTION RULES (apply to every phase)

1. Inspect the real repository first. Never assume a task below is already done; previous chat claims, commit titles, and mock results are not evidence.
2. Do not replace working code with stubs, placeholders, fake checksums, hard-coded success values, empty methods, or code that only makes a test pass.
3. Do not delete, skip, comment out, rename-away, or weaken existing tests. Fixing a genuinely stale import is allowed; reducing coverage is not.
4. A task is **COMPLETED** only when its implementation is committed, the relevant real command ran with exit code 0, and the output was inspected. Never claim analyze/test/APK/ZIP/CI success without that.
5. Do not continue silently after a failed command. Record the exact command, exit code, and meaningful error; fix the cause before dependent phases.
6. Do not invent GIS boundaries, road geometry, coordinates, sources, checksums, package contents, or test evidence. If verified data is unavailable, record it under **BLOCKED** or **NOT DONE** and leave the app truthful.
7. Never expose tokens or secrets in code, logs, commits, URLs, reports, or browser storage. Before every push run a secrets scan: `git grep -nE "ghp_|github_pat_|gho_|ghs_|BEGIN (RSA|OPENSSH|PRIVATE) KEY" -- . ':!TRAFFICITY_REPAIR_EXECUTION_PROMPT.md'` over tracked files (this file is excluded because it contains the pattern itself) and the staged diff must return nothing new.
8. No `git push --force` / `--force-with-lease`. Fast-forward pushes only. Do not reconcile divergence with `main`.
9. Keep diffs focused and reviewable. Do not add features the owner did not ask for (`CLAUDE.md`: "ortiqcha yangilik qo'shma").
10. Do not ask the owner to repeat information already in this file or in `CLAUDE.md`. Decisions already made are in §4.
11. `CLAUDE.md` economy rules apply to *how you work* (grep/sed instead of dumping files, short outputs, bounded CI polling: at most 2 checks of ≤60 s each unless the owner asks for more). They never override the verification requirements in this file.
12. Never print or rely on "all done", "fully working", "N/N passed", or "release-ready" unless the evidence for it exists (see §19).

---

## 2. RE-AUDITED BASELINE (commit `a960dfb`) — recheck before editing

Verified by inspection in the revision session. Re-run the check in the right column; if the result differs, believe the repository, not this table.

| # | Finding | How to recheck |
|---|---|---|
| B1 | The clone is **shallow/grafted: exactly 1 commit**. Git history, `git log -- file`, `git show <old>:file`, and the "15 ahead / 4 behind `main`" figure are unavailable. | `git rev-list --count HEAD`, `git rev-parse --is-shallow-repository` |
| B2 | `pubspec.yaml`: package name `trafficity`, `sdk: ^3.11.0`, deps `flame ^1.22.0`, `flame_audio ^2.10.6`, `shared_preferences ^2.3.3`, dev `flutter_test`, `flutter_lints ^6.0.0`. **No** `crypto`, `archive`, `path_provider`, `path`. | `sed -n 1,40p pubspec.yaml` |
| B3 | **12 stale imports** `package:roadflow_city/...` in 4 tests: `test/rail_test.dart`, `test/map_test.dart`, `test/network_test.dart`, `test/rail_game_test.dart`. `test/uzbekistan_world_test.dart` already uses `package:trafficity/...`. | `grep -rn roadflow_city lib test` |
| B4 | `lib/world/region_package_manager.dart` (13 lines): `Sha256Verifier.sha256Hex` returns the literal `'verified_sha256'` for any non-empty input. The existing test only asserts `digest.length == 64`, so it cannot pass today and is too weak to prove SHA-256. | `grep -n verified_sha256 -r lib tools` |
| B5 | Stub-sized world modules: `geo_coordinate_system.dart` (66 lines; defines `LocalEnuCoord` but no WGS84↔ENU conversion, ellipsoid scaling, or rebasing found), `multi_scale_lod_controller.dart` (10), `national_save_manager.dart` (5), `road_graph_linker.dart` (7), `architecture_profile_engine.dart` (5). `admin_hierarchy.dart` (56) and `world_controller.dart` (40) exist. | `wc -l lib/world/*.dart`, read each file |
| B6 | Nothing in `lib/main.dart` or `lib/game/road_game.dart` references `UzbekistanWorldController` or the selector/HUD widgets. | `grep -n "Uzbekistan\|WorldController" lib/main.dart lib/game/road_game.dart` |
| B7 | `tools/map/migrate_tashkent_legacy.py` (53 lines) only counts roads and prints "Verified N roads". It writes no chunks, converts no coordinates, updates no digests. Its `parse_road_points` is written for a shape that does **not** match the real file (see §4.5) and, by inspection, yields zero points for real entries — confirm by running it. | read the script; run it on the real file |
| B8 | `tools/package_release.py`: `allow_missing_binary=True` turns a missing `flutter` into success, and `main()` **ignores every step's return code**, so any failure still produces a ZIP. Its exclusion list does not cover `.env`/`*.pat`/`*.zip` patterns. | read the script |
| B9 | `.github/workflows/uzbekistan-release.yml`: no format check, no Node/`npm test`, no Python tests, no CLI validation, no Android scaffold step, no APK upload, no caching. `flutter analyze` and `flutter test` share one `run:` block. `build-apk.yml` (for `main`) runs `flutter create --platforms=android --org uz.abdulloh .` before building. | read both workflows |
| B10 | `android/` contains **only** `app/src/main/res/mipmap-*/ic_launcher.png`. No Gradle files, no `AndroidManifest.xml`. A bare `flutter build apk` will fail without scaffolding. | `find android -type f` |
| B11 | `Trafficity-Uzbekistan-Complete-Packager.html` does not exist. `tools/uzbekistan_pack_cli.mjs` is 37 lines; `test/packager_and_cli.test.mjs` has 3 tests (catalog, CLI checksum, manifest counts). | `ls`, `wc -l` |
| B12 | `FILE_MANIFEST.json` lists 23 files (20 `expansion` + 3 `base`); every entry except itself currently has a matching size and SHA-256. It does **not** list: `lib/ui/uzbekistan_hud_button.dart`, `test/uzbekistan_world_test.dart`, `tools/package_release.py`, `tools/map/trafficity_ingest.py`, `UZBEKISTAN_EXPANSION_README.md`, either workflow, or the files that P7 must edit (`lib/main.dart`, `lib/game/road_game.dart`). The 3 `base` files are `.gitignore`, `pubspec.yaml`, `assets/world/uzbekistan/regions/tashkent_city/manifest.json`. | run the digest check from §4.6 |
| B13 | Catalog coordinate semantics are mixed: `region_catalog.json` and `world_manifest.json` declare `"coordinateConvention": "latitude, longitude"`, while `centroid` is `[lon, lat]` and `bbox` uses `minLon/minLat/…`. For Tashkent City `centroid` equals the administrative-center point, so it is not a computed centroid. | read `region_catalog.json` |
| B14 | `administrative_boundaries.geojson` declares `"geometryAccuracy": "verified_bounding_box_envelope_only"`. The envelopes are honest about being envelopes, but the word **"verified"** overstates what was checked. | read the GeoJSON header |
| B15 | `CLAUDE.md` describes the project as *RoadFlow City* (Flutter + Flame traffic game; original package name `roadflow_city`) and claims 20 passing tests on `main`. It also states the owner's push token lacks the `workflow` scope, so pushing changes to `.github/workflows/*` can be rejected. | read `CLAUDE.md` |

---

## 3. ENVIRONMENT, CREDENTIALS, AND BLOCKER PROTOCOL

### 3.1 Bootstrap (do this in P0)

1. Check tools: `git --version`, `python3 --version`, `node --version`, `flutter --version`, `dart --version`, `java -version`.
2. If Flutter is missing, install it (per `CLAUDE.md`): `git clone --depth 1 -b stable https://github.com/flutter/flutter.git <scratch>/flutter`, add `flutter/bin` to `PATH`, `export CI=true`. Choose a Flutter release whose bundled Dart satisfies `sdk: ^3.11.0`; if the current stable does not, record it as a finding and do not silently lower the constraint without noting it.
3. Android SDK / Java 17 may be unavailable locally. If `flutter build apk --debug` cannot run locally, mark it **BLOCKED (local)** and rely on CI for that step; do not claim an APK exists.
4. Network is usually proxy-limited. If a download fails, record the exact error and retry once; do not work around the proxy and never disable TLS verification.

### 3.2 Git credentials and CI visibility

- Check whether pushing is possible (`git push --dry-run origin codex/uzbekistan-expansion`). If no credentials exist, **commit locally per phase, do not fake a push**, and at the end export `git bundle create trafficity-uzbekistan.bundle origin/codex/uzbekistan-expansion..HEAD` (or `git format-patch`) and report phases as "committed locally, not pushed".
- CI status for a public repo may be readable without a token (GitHub REST `actions/runs`), but artifact download usually needs auth. Report CI as **CI-PASS** only if you read a `success` conclusion for the exact final SHA; report artifacts as unverified if you could not list them.
- **Workflow-file pushes:** per `CLAUDE.md` the token may lack `workflow` scope. Prepare the workflow change fully; if the push is rejected for that reason, record **BLOCKED** with the exact server message and place the complete YAML in the final report so the owner can paste it. Do not try to bypass the restriction.
- The owner's token was previously exposed in chat. In the final report, remind the owner to revoke it and use a fresh fine-grained token limited to this repository.

---

## 4. DECISIONS ALREADY MADE (do not re-ask the owner)

### 4.1 Package identity
The package name is `trafficity` (pubspec, `uzbekistan_world_test.dart`, repo name). Fix the 12 stale `roadflow_city` imports to `package:trafficity/...` (or correct relative imports). Do not rename the package. Do not delete `CLAUDE.md`; at P11 append a short, truthful "Uzbekistan expansion" status section to it.

### 4.2 Coordinate conventions
- Internally and in every GeoJSON/chunk file: **`[longitude, latitude]`** (GeoJSON order), degrees, WGS84.
- Human-readable catalog fields keep explicit names (`latitude`, `longitude`). Replace the ambiguous `"coordinateConvention": "latitude, longitude"` strings with a statement that names each field and its order, and update the CLI/tests that read them.
- Local ENU: x = east (m), y = north (m), z = up (m). Flame/game world Y grows **downward (south)** in the legacy map (verify, §4.5); the conversion layer must document and test the sign flip explicitly.

### 4.3 Region data honesty
- Only `uz_tashkent_city` is `INSTALLED_DETAILED`. The other 13 stay `OVERVIEW_ONLY`.
- Rename GeoJSON `geometryAccuracy` to a non-overstating value (recommended: `"approximate_bounding_box_envelope"`) and update every reader/test. Rename catalog `centroid` to something truthful (e.g. `representativePoint`) unless it is actually computed as a centroid; keep `adminCenter` coordinates separate from it.
- Do not present rectangles as administrative borders anywhere in UI text or docs.

### 4.4 Region package layout (the previous prompt left this undefined)
```
assets/world/uzbekistan/regions/tashkent_city/
  manifest.json                # package manifest (schemaVersion, packageId, regionId, version, coordinateConvention, attribution, files[])
  chunks/chunk_<ix>_<iy>.json  # road features for one 2000 m ENU grid cell (ix = floor(east/2000), iy = floor(north/2000), relative to the anchor)
```
- `manifest.files[]` entries: `{path, bytes, sha256, featureCount}`; plus top-level `sourceRoadCount`, `convertedRoadCount`, `rejectedRoadCount`, `pointCount`, `coordinateConvention`, `schemaVersion`, `attribution`.
- Define precisely what the package-level `sha256` covers (recommended: SHA-256 of the canonical, key-sorted `files[]` array) and document it; the CLI, Dart manager, and Python migration must compute it identically.
- A road belongs to the chunk of its **midpoint vertex**; geometries are not clipped. Cross-chunk continuity is represented by the portals of P4 built from real shared geometry only.
- Flutter asset directory entries are **not recursive**: list `assets/world/uzbekistan/regions/tashkent_city/` and `.../chunks/` in `pubspec.yaml` (or list files explicitly). Verify with a test that loads each referenced asset.
- Deviation from this layout is allowed only if documented in the manifest and README and all tools agree.

### 4.5 Legacy road data (`assets/map/tashkent_roads.json`) — observed schema
- Root: `{"v": 1, "roads": [...]}` with **2495** entries; every entry is a 4-element list `[cls, layer, oneWay, flatXY]`.
- `cls`: 0 trunk (172), 1 primary (703), 2 secondary (315), 3 tertiary (213), 4 residential (1092). `layer`: 0 ground (2360) / 1 elevated or bridge (135). `oneWay`: 0 (1909) / 1 (586).
- `flatXY`: flat list `[x0, y0, x1, y1, …]` of floats in **game world units**, not degrees. Examples: first `[4,0,0,[2379.0,3952.5,2636.5,4025.6]]`, last `[0,0,0,[5967.8,1910.8,6103.2,1347.0,…]]`. Consumed by `lib/game/real_roads.dart` as `Offset(x, y)`.
- World is 6400×6400 units; the Tashkent basemap is 3200 px at 2 m/px, and the centre `(3200, 3200)` is Amir Temur xiyoboni (`lib/game/terrain.dart`, `real_roads.dart`). Working hypothesis to **verify, not assume**: 1 unit ≈ 1 m, +x east, +y south, origin ≈ `69.279737 E, 41.311081 N` (the constants in the migration script).
- Verification method: pick at least 3 independent, citable Tashkent anchor points (with source and date) and show the converted position lands within a stated tolerance; if sources are unavailable offline, label the conversion **unverified** in the manifest instead of "verified".
- Parse only this shape, plus any other shape you can demonstrate exists in the file (check every entry, not just first/mid/last). Reject-and-report anything else with a reason.
- IDs: `legacy-<source index, 5 digits>-<first 8 hex of sha256 of the canonical record>`; no random values.

### 4.6 `FILE_MANIFEST.json` and the 20 / 23 contract
- The owner-documented contract is two bundle modes: **Expansion = 20 files**, **Full = 23 files (20 + 3 base)**. Keep both counts **unless a required file genuinely cannot be in the list** (see B12). If you must change the list or counts, change them consistently in `FILE_MANIFEST.json`, `package.json` text, CLI, Node tests, HTML packager, README, and report it as an **owner decision** — never silently.
- `FILE_MANIFEST.json` itself is self-referential: it carries no `sizeBytes`/`sha256` for itself; document that rule in the manifest and in code.
- Digest check (re-run after any change to a listed file; it must print nothing but `OK`):
  ```bash
  python3 - <<'E'
  import json, hashlib, os
  m = json.load(open('FILE_MANIFEST.json'))
  bad = []
  for f in m['files']:
      p = f['path']
      if not os.path.exists(p): bad.append((p, 'missing')); continue
      if 'sha256' in f:
          b = open(p, 'rb').read()
          if hashlib.sha256(b).hexdigest() != f['sha256'] or len(b) != f['sizeBytes']:
              bad.append((p, 'mismatch'))
  print(bad or 'OK')
  E
  ```
- This prompt file is **not** part of either bundle unless the owner says so; this avoids a circular digest each time the ledger changes. State that in the manifest.

### 4.7 Tests layout
- Dart: `test/*_test.dart` (run by `flutter test`). Node: `test/*.test.mjs` via `npm test`. Python: `tools/tests/test_*.py`, run with `python3 -m unittest discover -s tools/tests -v`. Record baseline counts for each runner before changing anything, and compare the legacy Flutter count with the "20 tests PASS" claim in `CLAUDE.md` (a mismatch is a finding, not an error to hide).

---

## 5. PHASE P0 — SAFE START AND INVENTORY

*Dependencies:* none. *Output:* a written inventory (local notes or the ledger), no code changes.

1. Record: `git status --short --branch`, `git branch --show-current`, `git log -8 --oneline --decorate`, `git remote -v`, `git rev-list --count HEAD`, `git diff --check`.
2. Confirm the branch is `codex/uzbekistan-expansion`; switch safely without discarding work. Fetch refs read-only. Try a bounded history fetch (`git fetch --depth=1000 origin codex/uzbekistan-expansion`); some policies block `--unshallow`. If history stays unavailable (B1), say so: every "recover from history" step below then means **re-implement from the specification and tests in this file**, and the final report must state that no prior implementation could be consulted.
3. Bootstrap tools (§3.1). Record versions.
4. Inventory (read, do not change): `pubspec.yaml`, `analysis_options.yaml` (does it exist?), all of `lib/world`, `lib/ui`, `lib/main.dart`, `lib/game/road_game.dart`, every test, every script under `tools/`, both workflows, everything under `assets/world/uzbekistan/`, `FILE_MANIFEST.json`.
5. Re-verify §2 table rows B1–B15 and record any differences.
6. Re-inspect `tashkent_roads.json` per §4.5 (all 2495 entries: types, lengths, finite values).
7. Run the baseline once and record real output: `flutter pub get`, `flutter analyze` (issue count), `flutter test` (pass/fail counts), `npm test`, `python3 tools/map/migrate_tashkent_legacy.py`.

**Done when:** inventory + baseline numbers written down; nothing claimed repaired.

---

## 6. PHASE P1 — FLUTTER PACKAGE AND ANALYZER

*Dependencies:* P0.

1. Fix the stale imports (B3) and any other broken paths, duplicate declarations, undefined symbols, invalid asset paths, or type mismatches the analyzer reports. Preserve every test scenario and assertion.
2. Add the dependencies later phases need, with versions compatible with the SDK and with each other: `crypto` (SHA-256), `archive` (ZIP), `path_provider` and `path` (storage and safe paths). Keep `pubspec.lock` consistent if it is tracked. Confirm with `flutter pub get`.
3. Run and record, from the repo root: `flutter pub get`; `dart format --output=none --set-exit-if-changed lib test` (if it reports changes, run `dart format lib test`, inspect the diff, rerun); `flutter analyze`; `flutter test`.
4. Do not hide diagnostics with broad `// ignore` or analyzer excludes. An unrelated legacy warning is documented, not suppressed.

**Done when:** `flutter analyze` exits 0, the full existing suite passes with nothing skipped, the analyzer issue count before/after is recorded, and the test count matches or explains the `CLAUDE.md` baseline.

---

## 7. PHASE P2 — GEOSPATIAL COORDINATE SYSTEM

*Dependencies:* P1. *File:* `lib/world/geo_coordinate_system.dart`.

Implement a real coordinate system, not data classes:

1. WGS84 ellipsoid constants; latitude-dependent meters-per-degree computed from ellipsoid equations.
2. WGS84 → Local ENU and Local ENU → WGS84, with consistent altitude handling.
3. Flame world vector ↔ Local ENU meters, with the Y-sign convention of §4.2 documented in code and tested.
4. Legacy Tashkent local coordinates (§4.5) ↔ WGS84, using the anchor/scale determined and verified in P5/§4.5. Until the anchor is verified, expose the constants as named values with a comment saying "unverified hypothesis", not as truth.
5. Floating-origin update with threshold rebasing (documented named constant; the README states 2000 m) returning the shift and resetting local displacement.
6. Geodesic distance with numeric-domain protection (clamp before `asin`/`acos`).
7. Validation: reject NaN/infinite and out-of-range lon/lat with a typed error.

**Tests:** origin → ~0 m; point east → +east; point north → +north; WGS84→ENU→WGS84 round trip within a documented tolerance; legacy round trip; rebasing shift and reset; invalid inputs rejected; geodesic distance for known pairs (cite the reference value). **Done when:** all pass and the existing Tashkent map behaviour is unchanged.

---

## 8. PHASE P3 — REAL SHA-256 AND REGION PACKAGE MANAGER

*Dependencies:* P1 (dependencies added), P2 only for coordinates in manifests. *File:* `lib/world/region_package_manager.dart` (and new helper files as needed).

### 8.1 SHA-256
Remove `'verified_sha256'` entirely. Use the `crypto` package. Output is lowercase hex, exactly 64 chars; comparison fails closed on missing/invalid hashes. Strengthen `test/uzbekistan_world_test.dart` (do not remove its existing assertion).
Known answers: `"abc"` → `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`; empty → `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`; a changed payload fails; a correct payload with the correct digest passes.

### 8.2 Package lifecycle
- Read/validate a manifest (§4.4): package ID, region ID, version, required files, sizes, SHA-256 per file and for the package.
- Accept bytes through an explicit interface (downloader injected; no hard-coded success). Extract with the `archive` library.
- **Zip Slip protection:** reject absolute paths, `..` segments, drive prefixes, and symlink entries; normalize separators; resolve each destination and verify it stays inside the staging directory.
- Extract into a temporary staging directory, validate everything, then **atomically promote** (rename). Never mark a region installed before all validation succeeds. A failed update leaves the previous valid install intact. Recover from incomplete installs on startup.
- Persist installed state across restarts with a Flutter-supported store (`shared_preferences` is already a dependency, or files under `path_provider`). Support install, update, remove, list, readiness resolution.
- `OVERVIEW_ONLY` regions stay overview-only until a real, validated dataset is installed; unknown region IDs are rejected.

**Tests:** correct archive installs; corrupt hash rejected; missing manifest file rejected; traversal archive rejected; interrupted install not marked installed; failed update preserves old version; state survives manager reconstruction; removal updates persisted state; unknown region rejected. Use an in-memory/temp-dir filesystem so tests do not touch real app storage.

**Done when:** no fake hash remains (`git grep verified_sha256` is empty), nothing is in-memory-only, all lifecycle tests pass.

---

## 9. PHASE P4 — LOD, SAVE MIGRATION, ROAD GRAPH, ARCHITECTURE

*Dependencies:* P2, P3.

**LOD (`multi_scale_lod_controller.dart`).** Four levels: 1 country overview, 2 regional, 3 detailed city 2D, 4 detailed urban 3D. Selection uses camera zoom, 3D-perspective flag, and whether a verified detailed package is installed (the existing method already takes these parameters — make sure they are actually used). Thresholds are named, documented constants. A region without a detailed package never reaches level 3 or 4. Tests: every threshold boundary × {2D, 3D} × {installed, not installed}.

**Saves (`national_save_manager.dart`).** Save format stays version 3: country ID, region ID, WGS84 camera position, all version metadata. Restore the v1/v2 migration adapter; convert old Tashkent local camera coordinates via P2; handle missing/malformed/unknown-version input safely; never overwrite a valid old save before conversion succeeds. Tests: valid legacy, missing camera values, malformed, unknown version, v3 round trip. Do not break the existing 3-slot + auto save logic in `road_game.dart`.

**Road graph (`road_graph_linker.dart`).** Typed portal (stable portal ID, global road/way ID, WGS84 position, source chunk, destination chunk); register/validate; track loaded chunks; return only boundary portals where exactly one adjacent chunk is loaded; reject duplicate IDs and self-links; use real data only. Tests: load/unload, registration, duplicates, activation.

**Architecture profiles.** Keep any landmark-exclusion API and profile behaviour; distinguish supported metadata from unimplemented visuals; do not reduce to a stub.

**Done when:** no API used elsewhere was silently removed (`flutter analyze` proves it) and all new tests pass.

---

## 10. PHASE P5 — TASHKENT MIGRATION (REAL, DETERMINISTIC)

*Dependencies:* P2 (formulas; Python may carry a mathematically equivalent, tested implementation). *File:* `tools/map/migrate_tashkent_legacy.py` + `tools/tests/`.

1. Parse the real schema (§4.5) with an explicit parser; reject unknown shapes with a reason; validate finite numbers and plausible ranges; keep per-reason rejection counts.
2. Verify the unit/axis/origin hypothesis against ≥3 cited anchors (§4.5). Document the result honestly in the manifest (`coordinateVerification`: `verified` only if the anchors were actually checked, otherwise `unverified`).
3. Convert **all** valid roads to WGS84 `[lon, lat]` and write chunks per §4.4. Preserve `cls`, `layer`, `oneWay`, and the deterministic ID. Do not sample (e.g. not "first 250").
4. Write the manifest: real file list with bytes and SHA-256, feature counts, `sourceRoadCount`, `convertedRoadCount`, `rejectedRoadCount`, `pointCount`, schema version, coordinate convention, attribution (`© OpenStreetMap contributors (ODbL-1.0)`).
5. Every referenced file exists; the source `assets/map/tashkent_roads.json` is byte-identical afterwards.
6. Idempotent: two runs on unchanged input give identical bytes and digests (stable key order, stable float formatting, no timestamps in hashed files).
7. Non-zero exit if the source is missing, zero roads converted, or any validation fails. The summary says what was converted/rejected, never "verified" merely because records were counted.

**Tests:** a fixture per real shape; empty/malformed datasets; invalid coordinates; known-point conversion; every road converted or rejected with a reason (counts add up); digest/size recalculation; idempotency; source unchanged.

**Done when:** real chunks + manifest generated, counts add up to 2495, second run is byte-identical, and the Dart/Node validators accept the output.

---

## 11. PHASE P6 — GIS DATA QUALITY AND 14-REGION CATALOG

*Dependencies:* P5 (manifest format), P2. *Files:* `assets/world/uzbekistan/*`.

1. Exactly 14 first-level divisions; `UZ-TK` and `UZ-TO` separate.
2. Verify ISO 3166-2:UZ and SOATO codes against cited sources; store source references and verification dates in metadata or docs. If a code cannot be verified offline, mark it unverified rather than asserting.
3. Distinguish administrative-center point, computed centroid, representative point, and bbox (§4.3). Names in uz/ru/en; finite, in-range coordinates; unique IDs/codes; conventions per §4.2.
4. GeoJSON: keep envelopes labelled approximate (§4.3); never present them as real borders. Every feature ID maps to a catalog record.
5. OSM attribution/ODbL obligations stated wherever OSM-derived data ships (README, package manifests, in-app credits if present).
6. Every asset referenced by `pubspec.yaml`, manifests, or code exists and parses.
7. Only Tashkent is `INSTALLED_DETAILED`.

**Tests:** 14 unique IDs/codes; Tashkent split; required fields; finite in-range coordinates; GeoJSON parses with 14 features mapping to the catalog; accuracy metadata truthful; readiness not overstated. **Done when:** provenance documented, nothing fabricated.

---

## 12. PHASE P7 — INTEGRATE THE SELECTOR INTO THE REAL GAME

*Dependencies:* P2–P4, P6. *Files:* `lib/main.dart`, `lib/game/road_game.dart`, `lib/ui/*`, `lib/world/world_controller.dart`, `lib/l10n.dart`.

1. Study the existing widget tree and HUD (`main.dart` compact panel, bottom toolbar, settings, menu) before adding UI; follow `CLAUDE.md` placement (language/sound/settings live in settings, not the toolbar).
2. One lifecycle-managed `UzbekistanWorldController`: created once, async init with loading and error states, disposed correctly, no duplicate instances, no setState-after-dispose.
3. Add the selector button to the **visible** HUD and open/close the overlay without blocking existing controls (pan, zoom, tools).
4. Use the real language state and extend `L.t` tables for new strings (UZ/RU/EN).
5. On selection: update active region and geographic origin, resolve package readiness, update LOD, show overview/detailed state, and tell the game/map layer.
6. Non-Tashkent regions without a package show an explicit overview-only state. **Never** show the Tashkent road map under another region's label.
7. Preserve Tashkent flow, saves, tutorial, audio, HUD.

**Tests (widget):** controller loads 14 entries; button present on the real screen; open/close; every region selectable; labels follow language; Tashkent stays detailed-ready; others overview-only; all prior game widget tests still pass. **Done when:** the feature is visible in the real app and regression-free.

---

## 13. PHASE P8 — CLI AND RELEASE PACKAGER

*Dependencies:* P3, P5, P6.

### 13.1 `tools/uzbekistan_pack_cli.mjs`
Commands: `list-regions`, `validate-regions`, `validate-package <manifest-path>`, plus bundle validation needed by CI (`validate-bundle --mode expansion|full`). Requirements: validate arguments, non-zero exit on error; resolve paths from the repository root, not the caller's cwd; check 14 records, keys, uniqueness, ranges, Tashkent split; verify every required file exists; **recompute SHA-256 from file bytes** and compare with the manifest; print success only after all checks pass; `validate-package` must verify the package-level digest exactly as defined in §4.4.

### 13.2 `tools/package_release.py`
1. Remove `allow_missing_binary`. A missing required tool is a **failure**.
2. Check every step's return code; any non-zero aborts before ZIP creation. Log each command and result.
3. Order: migration → `flutter pub get` → format check → `flutter analyze` → `flutter test` → `npm test` → Python tests → CLI validation → `flutter build apk --debug` → APK exists and is non-empty → ZIP.
4. Deterministic ZIP: sorted paths, fixed timestamps, fixed permissions, no `.git`, build/cache dirs, `.env`, `*.pat`, `*.zip`, `local.properties`, `__pycache__`, `node_modules`; never include itself.
5. Re-open the ZIP, check the central directory and the required file list, then print SHA-256, size, file count, location. Exit non-zero on any failure.
6. Give it a flag to run steps that cannot work locally (e.g. APK without the Android SDK) as explicit, reported **BLOCKED** instead of silently passing; strict mode (the CI default) treats them as failures.

**Tests:** failed Flutter step blocks the ZIP; missing Flutter blocks release; ZIP contains required files; excluded files absent; ZIP re-opens; repeated packaging gives identical digest.

---

## 14. PHASE P9 — BROWSER PACKAGER `Trafficity-Uzbekistan-Complete-Packager.html`

*Dependencies:* P8. Required deliverable at the repo root. Manifest digests are re-synced in P11 after this file is final.

### 14.1 UI
Responsive single page, dark theme with accessible contrast, mobile-friendly; shows title/version, repository, target branch, package summary, validation status, ZIP controls, GitHub Direct Push controls, progress/results/errors, and the manifest file inventory.

### 14.2 Sources and bundles
- `FILE_MANIFEST.json` is the only inventory; no second hard-coded list.
- A static page cannot read the repo from disk by itself. Support two explicit sources and show which is active: (a) fetch files from the public raw URLs of the target branch, (b) files/folder chosen by the user through the File API (offline).
- Modes: **Expansion ZIP = 20 files**, **Full ZIP = 23 files** (§4.6). Before zipping, verify every required path exists and size/SHA-256 match where defined; the manifest's own digest is exempt by the documented self-reference rule. Deterministic entry order. Never label an unvalidated archive "complete".
- ZIP library: JSZip (or equivalent) **pinned to an exact version with a Subresource Integrity hash**, or inlined. No unpinned CDN.
- Keep logic testable: put the pure logic (manifest parsing, bundle selection, digest checks, GitHub request building) in one module under `tools/` used by the Node tests, and embed the same code in the HTML via a build/sync script; add a test asserting the embedded copy equals the module so they cannot drift.

### 14.3 GitHub Direct Push (official Git Database API)
1. Owner pastes a fine-grained token explicitly. Show exact repository and branch before confirmation. Warn: use a repository-scoped, short-lived token; never commit it.
2. Sequence: read branch ref (record SHA) → create blobs → create tree on the base tree → create commit with the previous commit as parent → update the ref **without force** → read back the ref and the commit.
3. Target is hard-locked to `codex/uzbekistan-expansion`; `main` is rejected in code, and the branch cannot be changed to `main` through the UI.
4. 409/conflict: stop and ask for a fresh state; never retry with force. Handle 401/403/404/rate-limit/network errors with safe messages.
5. Token only in memory for the shortest time, never in URLs, storage, logs, or error text; clear the input afterwards. Redact it from every message.
6. Report success only after GitHub confirms the updated ref and the new commit reads back.

### 14.4 Tests
Manifest parsing; exact 20/23 modes; missing-file rejection; digest-mismatch rejection; ZIP contents; request sequence with mocks; conflict behaviour; token redaction; no force flag anywhere; `main` cannot be targeted. Mock tests are **MOCK-ONLY**; they do not count as a real push.

---

## 15. PHASE P10 — CI WORKFLOW

*Dependencies:* P1–P9. *File:* `.github/workflows/uzbekistan-release.yml` (pushing it may hit the `workflow` scope limit — see §3.2).

Triggers: push to `codex/uzbekistan-expansion` and `workflow_dispatch`. Ordered steps, each failing the job on error (no `continue-on-error` on checks):
1. checkout exact commit; 2. Python; 3. Java 17; 4. Flutter (pinned or stable, compatible with `^3.11.0`); 5. Node (≥18, per `package.json`); 6. **Android scaffold** — `flutter create --platforms=android --org uz.abdulloh .` as in `build-apk.yml` (B10) unless P8/P10 adds a complete `android/` tree; 7. `flutter pub get`; 8. format check; 9. `flutter analyze`; 10. `flutter test`; 11. `npm test`; 12. Python tests; 13. CLI region/package/bundle validation; 14. Tashkent migration + output validation; 15. `flutter build apk --debug`; 16. `tools/package_release.py` in strict mode; 17. re-validate the ZIP; 18. upload `Trafficity-Uzbekistan-Complete.zip`; 19. upload the debug APK.

Use caching for speed but never as a substitute for running a check. Leave `build-apk.yml` (the `main` workflow) untouched unless a change is required and justified.

**Done when:** the exact final commit's run is `success` with both artifacts present — otherwise report **CI not green**, with the failing step and log excerpt.

---

## 16. PHASE P11 — MANIFESTS AND DOCUMENTATION

*Dependencies:* all code phases stable.

1. Recompute size and SHA-256 for every listed file **after** content is final; validate paths and the 20/23 counts; record scope (expansion vs base) with a one-line reason per file.
2. Rewrite `README.md` and `UZBEKISTAN_EXPANSION_README.md` to match real commands and real output; remove claims of unimplemented features; state clearly that **only the Tashkent detailed dataset is playable** and that bounding-box envelopes are not real borders.
3. Document sources, capture dates, licenses/attribution (OSM ODbL), schema versions, known limitations, and the coordinate/verification status from P5.
4. Provide exact clean-clone setup and verification commands (including the Android scaffold step).
5. Append a truthful "Uzbekistan expansion" status section to `CLAUDE.md` (do not delete existing content).

---

## 17. PHASE P12 — FINAL ACCEPTANCE GATE

Release-ready only if **every** applicable box is true with evidence; otherwise report **NOT READY**.

- [ ] Correct branch; `origin/main` SHA is unchanged from the P0 record and no push targeted `main`.
- [ ] No original test or feature deleted or weakened; baseline vs final test counts reported.
- [ ] No stale package imports; `flutter analyze` exit 0 (before/after counts).
- [ ] Format check passes; full `flutter test` exit 0.
- [ ] SHA-256 known-answer tests pass; `verified_sha256` no longer exists.
- [ ] Coordinate, floating-origin, LOD, save-migration, road-portal tests pass.
- [ ] Package install/update/removal/path-traversal tests pass.
- [ ] Tashkent migration converts all valid roads, counts add up to the source, second run is byte-identical, source unchanged.
- [ ] CLI, Python, `npm test` suites pass (no check replaced by a mock).
- [ ] HTML packager exists; ZIP validation tests pass; push flow proven non-force and `main`-proof (**MOCK-ONLY** unless a real push was performed and read back).
- [ ] Selector visible and working in the real game; other regions truthfully overview-only.
- [ ] Debug APK built (CI or local) and non-empty; release ZIP generated, re-opened, validated.
- [ ] CI run for the final commit is `success`; APK and ZIP artifacts present (or reported as not verifiable).
- [ ] Manifest sizes/digests/counts match final files; documentation matches reality.
- [ ] Secrets scan clean; `git diff --check` clean; final diff reviewed.

---

## 18. EXECUTION STATUS LEDGER — UPDATE DURING THE WORK

Starts with **no repair task completed**. A push, commit title, mock, or chat claim does not count.

### COMPLETED — VERIFIED
**NONE.**
Move an item here only after it is committed and its real command passed. Each entry needs: task ID and outcome; files changed; exact commands; exit codes and test counts; commit SHA; CI run URL/status if applicable.

### NOT DONE — PENDING
- [ ] **P0** Safe start, bootstrap, inventory, baseline numbers.
- [ ] **P1** Imports, dependencies, analyzer/format/tests green.
- [ ] **P2** Coordinate system and floating origin.
- [ ] **P3** Real SHA-256 and package manager.
- [ ] **P4** LOD, save migration, road portals, architecture profiles.
- [ ] **P5** Tashkent migration (all roads, chunks, manifest, idempotent).
- [ ] **P6** GIS data quality and honest labelling.
- [ ] **P7** Selector integrated into the real game.
- [ ] **P8** Strict CLI and release packager.
- [ ] **P9** Browser HTML packager with safe Direct Push.
- [ ] **P10** CI workflow green with artifacts.
- [ ] **P11** Manifest, README, and CLAUDE.md accuracy.
- [ ] **P12** Final gate, final push, final CI check.

### BLOCKED
**NONE KNOWN.** Add an entry only after the task was attempted and a concrete missing dependency, source, or permission was identified; include the evidence and what unblocks it. Pre-identified risks to check early: no push credentials; `workflow`-scope rejection; no Flutter/Android SDK locally; no network for anchor verification; shallow history.

### OWNER DECISIONS NEEDED
Add here (do not stop work for them unless a decision is irreversible): any change to the 20/23 file list, relabelled GeoJSON/catalog fields, any scope not covered by §4.

### HOW TO MAINTAIN THE LEDGER
After a task: run its tests → commit → (push if possible) → move it to COMPLETED with evidence in the **same branch**. Partial work or failing tests stay under NOT DONE with a note. At the end of every session the ledger must agree with the Git tree and the test evidence.

---

## 19. REQUIRED FINAL REPORT (write it in Uzbek)

1. Branch and final commit SHA; pushed or local-only.
2. Completed task IDs with changed files; not-done IDs with exact reasons; blockers; owner decisions needed.
3. Every command run with its real exit code.
4. Analyzer issues before/after; Flutter, Node, Python pass/fail counts (and baseline vs final).
5. Tashkent migration: source / converted / rejected road counts and the coordinate-verification status.
6. APK path and size (or BLOCKED reason); ZIP path, size, SHA-256, file count.
7. HTML packager path and verified capabilities (mark mock-only parts).
8. GitHub Actions run URL, conclusion, artifact links (or why unverifiable).
9. Confirmation that `main` was not modified, that no secrets were committed, and a reminder to revoke the previously exposed token.

**Never write "all done", "fully working", "N/N passed", or "release-ready" without the matching evidence. Start with P0 and proceed in order.**
