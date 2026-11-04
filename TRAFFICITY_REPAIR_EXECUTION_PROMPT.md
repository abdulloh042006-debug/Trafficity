# TRAFFICITY — Repair Execution Master Prompt (rev. 3)

**Purpose:** single source of truth for repairing, completing, testing, documenting, and packaging the Uzbekistan expansion of Trafficity.

| Item | Value |
|---|---|
| Repository | `abdulloh042006-debug/Trafficity` (GitHub URLs are case-insensitive; the clone remote is lower-case `trafficity`) |
| Working branch | `codex/uzbekistan-expansion` (the owner's integration branch). A session bound to another branch (rev. 3 was executed on `ccr-7e104e07-0xa8wr`) keeps that branch a **fast-forward descendant** of the codex tip, so the owner can fast-forward/merge it without conflicts. |
| Protected branch | `main` — never modify, merge into, rebase onto, or force-push without explicit owner approval |
| Baseline at the start of rev. 3 | commit `03a3f77` (tip of `codex/uzbekistan-expansion`: P1, P2, P3, P4, P5, P6 and most of P8 already committed, but the ledger was never updated, `flutter test` had **1 failing test**, the format check failed and 4 phases were untouched) |
| Earlier audits (historical) | rev. 2 audited `a960dfb` (single grafted commit, 70 analyzer issues in CI run #15); history is no longer shallow (see B1) |
| Owner language | Uzbek. Final report and chat replies to the owner are written in Uzbek. Code, commits, and this file stay in English. |

**Revision note (rev. 3):** written after actually executing the plan. Changes: the baseline table (§2) now records what was true at the start of rev. 3 *and* what is true now; new §0.2 lists the pitfalls that cost real time so they are not rediscovered; the CI order of §15 was corrected (the Android scaffold must run **after** the ZIP is built and its generated `test/widget_test.dart` must be removed); the secrets scan (§1.7) is refined because the redaction tests legitimately contain fake tokens; P1/P2/P7/P8/P9 got concrete implementation notes; §18 is a real ledger with evidence (commits, commands, counts) and crossed-out pending items; the final-gate checklist (§17) is ticked only where evidence exists.

**Revision note (rev. 2):** rewritten after re-checking every baseline claim against the actual files. Changes: removed claims that no longer match the tree, added the environment/bootstrap section, added the decisions section (so the executor does not stall on ambiguities), fixed the unusable "recover from Git history" instruction (the clone is shallow), documented the real `tashkent_roads.json` schema, defined the missing package/chunk layout, added the blocker protocol for credentials and workflow-file pushes, and added a status vocabulary.

---

## 0. HOW TO USE THIS FILE

1. Read this whole file, then `CLAUDE.md` (project identity, constraints, economy rules), then `UZBEKISTAN_EXPANSION_README.md`.
2. Work phases **P0 → P12 in order**. Phases already listed under *COMPLETED — VERIFIED* in §18 are not redone: re-run their evidence commands (cheap) and continue with the first item that is still unchecked or crossed-in.  Each phase has a *Dependencies* line and a *Done when* checklist. Do not start a phase whose dependencies are not green.
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
| **PASS (manual)** | Verified by a one-off real run that is not part of CI (for example the HTML packager in headless Chromium). State exactly what was run. |

### 0.2 Pitfalls found while executing (read before you start)

1. **`flutter test` count.** `CLAUDE.md` says 20 tests; those are the original game tests (`network_test` 10, `map_test` 3, `rail_test` 4, `rail_game_test` 3). New suites add to that; compare like with like.
2. **Formatter width.** The game code was written for 120 columns. Without `analysis_options.yaml` containing `formatter: page_width: 120`, `dart format` rewrites ~31 files at 80 columns. Keep that file and format once.
3. **`flutter create .` side effects.** It adds `test/widget_test.dart` (the counter test, which does not compile against this app), `.idea/`, `*.iml`, `.metadata` and the whole `android/` tree. Never run it before building the release ZIP and always delete `test/widget_test.dart` afterwards. The app id becomes `uz.abdulloh.<pubspec name>` = `uz.abdulloh.trafficity` (not the old `...roadflow_city`).
4. **Flame `Vector2` is float32.** Round-trips through it lose ~5e-4 at x ≈ 6000. Provide a double-precision API for data/IO (`wgs84ToLegacyUnitsExact`) and test both.
5. **Widget tests of the real screen.** `audioplayers` opens one platform channel per player id (`xyz.luan/audioplayers/events/<uuid>`); mock them with `defaultBinaryMessenger.allMessagesHandler` returning `StandardMethodCodec().encodeSuccessEnvelope(null)` for every channel that starts with `xyz.luan/audioplayers`. The Flame game ticks forever, so `pumpAndSettle` never returns: pump a fixed number of frames and use `tester.runAsync` for real async work. A `ListView.builder` item that is *built* (cache extent) is not necessarily *on screen*: call `ensureVisible` before `tap`.
6. **`FILE_MANIFEST.json` goes stale.** Any edit (including formatting) of a listed file breaks `npm test`, `validate-bundle` and the release packager. Run `node tools/uzbekistan_pack_cli.mjs update-manifest` after the last edit of every listed file.
7. **Secrets scan false positives.** `test/packager_and_cli.test.mjs`, `tools/packager_core.mjs` and the HTML packager intentionally contain fake tokens or the redaction regex. Scan with the exclusions in §1.7; anything else that matches is real.
8. **CI triggers.** `workflow_dispatch` only works for workflows present on the default branch, so CI evidence for a working branch needs that branch in the `push:` trigger list. Pushing a workflow file worked with the session's credentials; still treat a `workflow`-scope rejection as BLOCKED if it happens.
9. **Android SDK.** A local `flutter build apk` without `ANDROID_HOME` ends with a vague error; the packager now detects it and reports BLOCKED (`--allow-blocked`) or FAIL (strict) *before* running the build.
10. **Shared `main`.** `origin/main` moved during the work (owner's parallel Codex commits). Record its SHA at P0 and re-check at P12; never merge it into the working branch.

---

## 1. EXECUTION RULES (apply to every phase)

1. Inspect the real repository first. Never assume a task below is already done; previous chat claims, commit titles, and mock results are not evidence.
2. Do not replace working code with stubs, placeholders, fake checksums, hard-coded success values, empty methods, or code that only makes a test pass.
3. Do not delete, skip, comment out, rename-away, or weaken existing tests. Fixing a genuinely stale import is allowed; reducing coverage is not.
4. A task is **COMPLETED** only when its implementation is committed, the relevant real command ran with exit code 0, and the output was inspected. Never claim analyze/test/APK/ZIP/CI success without that.
5. Do not continue silently after a failed command. Record the exact command, exit code, and meaningful error; fix the cause before dependent phases.
6. Do not invent GIS boundaries, road geometry, coordinates, sources, checksums, package contents, or test evidence. If verified data is unavailable, record it under **BLOCKED** or **NOT DONE** and leave the app truthful.
7. Never expose tokens or secrets in code, logs, commits, URLs, reports, or browser storage. Before every push run a secrets scan: `git grep -nE "ghp_|github_pat_|gho_|ghs_|BEGIN (RSA|OPENSSH|PRIVATE) KEY" -- . ':!TRAFFICITY_REPAIR_EXECUTION_PROMPT.md'` over tracked files and the staged diff must return nothing new. Exclusions that are known, intentional false positives: this file (contains the pattern), `test/packager_and_cli.test.mjs` (fake tokens for the redaction tests) and `tools/packager_core.mjs` and `Trafficity-Uzbekistan-Complete-Packager.html` (both contain the redaction regex; the page embeds the core). Add `':!test/packager_and_cli.test.mjs' ':!tools/packager_core.mjs' ':!Trafficity-Uzbekistan-Complete-Packager.html'` to the command; any other hit is a finding.
8. No `git push --force` / `--force-with-lease`. Fast-forward pushes only. Do not reconcile divergence with `main`.
9. Keep diffs focused and reviewable. Do not add features the owner did not ask for (`CLAUDE.md`: "ortiqcha yangilik qo'shma").
10. Do not ask the owner to repeat information already in this file or in `CLAUDE.md`. Decisions already made are in §4.
11. `CLAUDE.md` economy rules apply to *how you work* (grep/sed instead of dumping files, short outputs, bounded CI polling: at most 2 checks of ≤60 s each unless the owner asks for more). They never override the verification requirements in this file.
12. Never print or rely on "all done", "fully working", "N/N passed", or "release-ready" unless the evidence for it exists (see §19).

---

## 2. BASELINE FINDINGS — STATE AT REV. 2 AND AT REV. 3

Rev. 2 re-audited `a960dfb`. Rev. 3 re-checked every row against the tree: the right column is the state after the rev. 3 work (evidence in §18). Re-run the check in the *how* column before trusting either.

| # | Finding at rev. 2 | State at rev. 3 | How to recheck |
|---|---|---|---|
| B1 | Shallow clone, 1 commit | **Resolved.** Not shallow: 58+ commits, history readable. | `git rev-list --count HEAD`, `git rev-parse --is-shallow-repository` |
| B2 | No `crypto`/`archive`/`path_provider`/`path` | **Resolved.** `crypto ^3.0.6`, `archive ^3.6.1`, `path ^1.9.0` added. `path_provider` is not needed (the package manager takes an explicit root directory). | `sed -n 1,45p pubspec.yaml` |
| B3 | 12 stale `package:roadflow_city/...` imports | **Resolved** (`e91ed85`). | `grep -rn roadflow_city lib test` (empty) |
| B4 | `Sha256Verifier` returned the literal `verified_sha256` | **Resolved** (`9ea8905`): real SHA-256 via `crypto`; the literal now appears only in negative tests. | `git grep verified_sha256` |
| B5 | Stub-sized world modules | **Resolved.** `geo_coordinate_system` 332 lines, `region_package_manager` 572, `national_save_manager` 146, `road_graph_linker` 85, `multi_scale_lod_controller` 63, `architecture_profile_engine` 36, `world_controller` 130. **But** `national_save_manager`, `road_graph_linker`, `architecture_profile_engine` are unit-tested only and not wired into the game's own save/road/building code (documented, not hidden). | `wc -l lib/world/*.dart` |
| B6 | Nothing in `main.dart`/`road_game.dart` used the selector | **Resolved** in P7 (`3367155`): one controller per screen, HUD button, selector dialog, overview card. | `grep -n "UzbekistanWorldController" lib/main.dart` |
| B7 | Migration script only counted roads | **Resolved** (`565eb1d`): all 2495 roads converted to WGS84 chunks, manifest with digests, deterministic. Coordinate verification: first honestly `unverified`, then `verified_approximate` (see P5b). | `python3 tools/map/migrate_tashkent_legacy.py && git diff --exit-code -- assets` |
| B8 | `package_release.py` ignored failures, `allow_missing_binary` | **Resolved** (`03a3f77`, `797fbcc`): strict, every return code checked, deterministic validated ZIP, missing Android SDK = BLOCKED/FAIL, generated `widget_test.dart` removed. | `python3 -m unittest discover -s tools/tests` |
| B9 | Naive workflow (no checks, no scaffold, no APK upload) | **Resolved** (`f2a474e`): ordered strict workflow, both artifacts uploaded. | read `.github/workflows/uzbekistan-release.yml`; Actions run |
| B10 | `android/` has only launcher icons | **Still true by design.** The project is generated by `flutter create --platforms=android --org uz.abdulloh .` after the ZIP is built; nothing generated is committed. | `find android -type f` |
| B11 | No HTML packager; CLI 37 lines, 3 Node tests | **Resolved.** `Trafficity-Uzbekistan-Complete-Packager.html` + `tools/sync_packager_html.mjs`; CLI 328 lines; 41 Node tests. | `ls`, `npm test` |
| B12 | `FILE_MANIFEST.json` misses files; 42/45 contract | **Resolved for the deliverable bundle.** The manifest is now 42/45 and includes the app wiring, all 16 Tashkent chunks, and the offline packager runtime/UI. The packager's own Node validation test remains included; other test suites and CI workflows stay outside the deliverable bundle. | digest check of §4.6 |
| B13 | Mixed coordinate semantics (`centroid` was the admin center) | **Resolved** (`898fe5b`): `representativePoint`, explicit convention text. | read `region_catalog.json` |
| B14 | GeoJSON `geometryAccuracy` said "verified" | **Resolved**: `approximate_bounding_box_envelope` plus a limitation note. | read the GeoJSON header |
| B15 | `CLAUDE.md` outdated | **Updated** (Uzbekistan section appended, counts corrected). | read `CLAUDE.md` |

---

## 3. ENVIRONMENT, CREDENTIALS, AND BLOCKER PROTOCOL

### 3.1 Bootstrap (do this in P0)

1. Check tools: `git --version`, `python3 --version`, `node --version`, `flutter --version`, `dart --version`, `java -version`.
2. If Flutter is missing, install it (per `CLAUDE.md`): `git clone --depth 1 -b stable https://github.com/flutter/flutter.git <scratch>/flutter`, add `flutter/bin` to `PATH`, `export CI=true`. Choose a Flutter release whose bundled Dart satisfies `sdk: ^3.11.0`; if the current stable does not, record it as a finding and do not silently lower the constraint without noting it.
3. Android SDK / Java 17 may be unavailable locally. If `flutter build apk --debug` cannot run locally, mark it **BLOCKED (local)** and rely on CI for that step; do not claim an APK exists.
4. Network is usually proxy-limited. If a download fails, record the exact error and retry once; do not work around the proxy and never disable TLS verification.

### 3.2 Git credentials and CI visibility

- Check whether pushing is possible (`git push --dry-run origin <your working branch>`). In rev. 3 plain `git push` worked (fast-forward only) and even a workflow-file change was accepted. If no credentials exist, **commit locally per phase, do not fake a push**, and at the end export `git bundle create trafficity-uzbekistan.bundle origin/codex/uzbekistan-expansion..HEAD` (or `git format-patch`) and report phases as "committed locally, not pushed".
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

### 4.6 `FILE_MANIFEST.json` and the 42 / 45 contract
- The owner approved expanding the bundle to include the files required to reproduce the app integration and Tashkent package: **Expansion = 42 files**, **Full = 45 files (42 + 3 base)**. The added entries are `main.dart`, `road_game.dart`, the HUD button, the 16 Tashkent chunks, and the browser packager runtime/UI/sync script. Counts are synchronized in `FILE_MANIFEST.json`, the shared packager core, Node tests, HTML packager, and README. The repair prompt, workflows and test suites are intentionally excluded from downloadable bundles.
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

**Notes from execution:** add `analysis_options.yaml` (`formatter: page_width: 120`, exclude `build/**` and `android/**`) *before* formatting; remove unused imports instead of ignoring them; widget tests that boot the real screen need the audioplayers mock of §0.2.5.

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

**Implementation note:** keep a double-precision API next to every Flame `Vector2` API (§0.2.4).

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
2. Verify the unit/axis/origin hypothesis against ≥3 cited anchors (§4.5). Document the result honestly in the manifest (`coordinateVerification`: `verified_approximate` only if ≥3 anchors within the stated scope were actually compared and all lie inside the stated tolerance; `failed` if the tolerance is exceeded; `unverified` if anchors are missing; never claim survey-grade).
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

**Implementation notes:** the controller must reject unknown region ids (never silently fall back to the first region); notifications after `dispose` must be ignored; a region without a detailed package covers and pauses the game with an *opaque* card so the Tashkent map is never visible under another label; keep the HUD style of `main.dart` (light panel) rather than adding a second visual language.

**Tests (widget):** controller loads 14 entries; button present on the real screen; open/close; every region selectable; labels follow language; Tashkent stays detailed-ready; others overview-only; all prior game widget tests still pass. **Done when:** the feature is visible in the real app and regression-free.

---

## 13. PHASE P8 — CLI AND RELEASE PACKAGER

*Dependencies:* P3, P5, P6.

### 13.1 `tools/uzbekistan_pack_cli.mjs`
Commands: `list-regions`, `validate-regions`, `validate-package <manifest-path>`, plus bundle validation needed by CI (`validate-bundle --mode expansion|full`). Requirements: validate arguments, non-zero exit on error; resolve paths from the repository root, not the caller's cwd; check 14 records, keys, uniqueness, ranges, Tashkent split; verify every required file exists; **recompute SHA-256 from file bytes** and compare with the manifest; print success only after all checks pass; `validate-package` must verify the package-level digest exactly as defined in §4.4.

**Implementation note (rev. 3):** `tools/packager_core.mjs` is the only logic module (no imports; `export` is stripped when it is embedded). `tools/sync_packager_html.mjs --check` is a CI step and `test/packager_html.test.mjs` asserts equality, so the CLI, the page and the tests cannot drift.

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
- Modes: **Expansion ZIP = 52 files**, **Full ZIP = 55 files** (§4.6; 42/45 → 46/49 in P13b → 52/55 in P15). Before zipping, verify every required path exists and size/SHA-256 match where defined; the manifest's own digest is exempt by the documented self-reference rule. Deterministic entry order. Never label an unvalidated archive "complete".
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
Manifest parsing; exact 52/55 modes; missing-file rejection; digest-mismatch rejection; ZIP contents; request sequence with mocks; conflict behaviour; token redaction; no force flag anywhere; `main` cannot be targeted. Mock tests are **MOCK-ONLY**; they do not count as a real push.

---

## 15. PHASE P10 — CI WORKFLOW (corrected in rev. 3)

*Dependencies:* P1–P9. *File:* `.github/workflows/uzbekistan-release.yml` (pushing it may hit the `workflow` scope limit — see §3.2).

Triggers: push to `codex/uzbekistan-expansion` (plus the working branch of the executing session, §0.2.8) and `workflow_dispatch`. Ordered steps, each failing the job on error (no `continue-on-error` on checks):
1. checkout exact commit; 2. Python; 3. Java 17; 4. Flutter (stable, compatible with `^3.11.0`); 5. Node ≥ 18; 6. tool versions; 7. `flutter pub get`; 8. format check; 9. `flutter analyze`; 10. `flutter test`; 11. `npm test`; 12. Python tests; 13. `node tools/sync_packager_html.mjs --check`; 14. CLI region/package/bundle validation; 15. Tashkent migration is reproducible (`git diff --exit-code -- assets/world/uzbekistan assets/map`) and valid; 16. `python3 tools/package_release.py` in strict mode — it builds and re-opens the deterministic ZIP **first**, then creates the Android scaffold (`flutter create --platforms=android --org uz.abdulloh .`, then deletes the generated `test/widget_test.dart`) and builds `flutter build apk --debug`; 17. APK exists and is non-empty; 18. re-validate the ZIP (central directory, sorted unique entries, required and manifest files present, no `.git`/`build`/`*.zip`/`.env`/`local.properties`); 19. upload `Trafficity-Uzbekistan-Complete.zip`; 20. upload the debug APK.

The scaffold is **not** a separate early step (rev. 2 listed it as step 6): generated Android/IDE files would otherwise enter the ZIP and the generated counter test would break analyze and test.

Use caching for speed but never as a substitute for running a check. Leave `build-apk.yml` (the `main` workflow) untouched unless a change is required and justified.

**Done when:** the exact final commit's run is `success` with both artifacts present — otherwise report **CI not green**, with the failing step and log excerpt.

---

## 16. PHASE P11 — MANIFESTS AND DOCUMENTATION

*Dependencies:* all code phases stable.

1. Recompute size and SHA-256 for every listed file **after** content is final; validate paths and the 52/55 counts; record scope (expansion vs base) with a one-line reason per file.
2. Rewrite `README.md` and `UZBEKISTAN_EXPANSION_README.md` to match real commands and real output; remove claims of unimplemented features; state clearly that **only the Tashkent detailed dataset is playable** and that bounding-box envelopes are not real borders.
3. Document sources, capture dates, licenses/attribution (OSM ODbL), schema versions, known limitations, and the coordinate/verification status from P5.
4. Provide exact clean-clone setup and verification commands (including the Android scaffold step).
5. Append a truthful "Uzbekistan expansion" status section to `CLAUDE.md` (do not delete existing content).

---

## 17. PHASE P12 — FINAL ACCEPTANCE GATE

Release-ready only if **every** applicable box is true with evidence; otherwise report **NOT READY**. Boxes are ticked only where §18 holds the evidence.

- [x] Correct branch; `origin/main` unchanged (`ee406fc` at P0 and at the end) and no push targeted `main`. (Work was pushed only to `ccr-7e104e07-0xa8wr`, a fast-forward descendant of the codex tip.)
- [x] No original test or feature deleted or weakened. Baseline 99 tests (98 pass, 1 FAIL) → 112 pass. The 20 original game tests are unchanged apart from formatting. The single changed assertion (`legacy points round-trip`) kept its 1e-5 tolerance on the new double-precision API and added a 1e-3 check for the float32 `Vector2` path.
- [x] No stale package imports; `flutter analyze` exit 0 (1 issue at `03a3f77` → 0).
- [x] Format check exit 0; full `flutter test` exit 0 (151/151 after P15; 112 at the original gate).
- [x] SHA-256 known-answer tests pass; `verified_sha256` exists only in negative tests.
- [x] Coordinate, floating-origin, LOD, save-migration, road-portal tests pass (`geo_coordinate_system_test` 19, `world_core_test` 24).
- [x] Package install/update/removal/path-traversal tests pass (`region_package_manager_test` 35).
- [x] Tashkent migration: 2495 source = 2495 converted + 0 rejected; second run byte-identical (`git diff` clean, CI step "reproducible"); source file unchanged (`sha256 d4faf65d…`).
- [x] CLI, Python, `npm test` suites pass (41 Node, 82 Python after P15; 49 at the original gate); no check replaced by a mock.
- [x] HTML packager exists; ZIP validation tests pass; push flow proven non-force and `main`-proof. **MOCK-ONLY / PASS (manual)**: Chromium run 29/29 with a mocked GitHub API; no real push was performed through the page.
- [x] Selector visible and working in the real game (11 widget tests incl. all 14 regions); other regions overview-only.
- [x] Debug APK built and non-empty: **CI-PASS**. Locally BLOCKED (no Android SDK), but CI runs 41698996726 (`f2a474e`) and 41700238463 (`2e654f5`) built `app-debug.apk` (79 212 058-byte artifact `trafficity-debug-apk`, step "APK exists and is not empty" passed).
- [x] **CI-PASS** for the last code/docs commit `2e654f5`: run [41700238463](https://github.com/abdulloh042006-debug/Trafficity/actions/runs/41700238463) concluded `success`; artifacts `Trafficity-Uzbekistan-Complete` (2 322 635 bytes, sha256 `646488514a2b…`) and `trafficity-debug-apk` (79 212 058 bytes). The ledger-only commit that records this evidence is pushed with `[skip ci]` and changes only this file.
- [x] Manifest sizes/digests/counts match the final files (`validate-bundle` OK in both modes); documentation matches reality.
- [x] Secrets scan clean (only the documented intentional fixtures); `git diff --check` clean.

---

## 18. EXECUTION STATUS LEDGER

Last updated at the end of the rev. 3 execution. A push, commit title, mock, or chat claim does not count; every entry below names the command that ran.

### COMPLETED — VERIFIED

| ID | Outcome | Commits | Evidence (real commands, exit codes) |
|---|---|---|---|
| **P0** | Safe start, bootstrap, inventory, baseline | — | Tools: Flutter 3.47.8, Dart 3.13.7, Node 22.22, Python 3.13, Java 17 (no Android SDK). Baseline at `03a3f77`: `flutter pub get` 0; `flutter analyze` **1 issue**, exit 1; `dart format --set-exit-if-changed` **exit 1** (31/32 files); `flutter test` **98 pass / 1 FAIL**; `npm test` 32/32; Python 45/45. `origin/main` = `ee406fc`. |
| **P1** | Package, imports, analyzer, format | `e91ed85`, `8e11926` | After: `flutter analyze` **No issues**, exit 0; format check exit 0 (`analysis_options.yaml`, width 120); `flutter test` exit 0. Issues: 70 (historical CI #15) → 1 → 0. |
| **P2** | Coordinate system | `a6a42de`, `8e11926` | `geo_coordinate_system_test.dart` 19/19 incl. WGS84↔ENU round trip, legacy frame, Y-sign, floating origin, validation, geodesic. Found and fixed the failing legacy round-trip (float32 `Vector2`): added `wgs84ToLegacyUnitsExact`. Constants stay labelled unverified. |
| **P3** | Real SHA-256, package manager | `9ea8905` | `region_package_manager_test.dart` 35/35: known answers (`abc`, empty), traversal/absolute/drive/symlink, corrupt/missing/extra file, interrupted install, failed update keeps old, crash rollback, persistence, removal, unknown region. `git grep verified_sha256` → only negative tests. New `tashkent_package_real_test.dart` (2): Dart verifies the real Tashkent manifest, package digest and all 16 chunk SHA-256 (cross-implementation proof with Python and Node). |
| **P4** | LOD, save v3 migration, portals, profiles | `01096d6` | `world_core_test.dart` 24/24 (LOD boundaries × 2D/3D × installed/not, v1/v2→v3, malformed/unknown version, portal rules, profile metadata). Not wired into game code (documented). |
| **P5** | Tashkent migration | `565eb1d` | `python3 tools/map/migrate_tashkent_legacy.py` exit 0: source 2495, converted 2495, rejected 0, 6076 points, 16 chunks, packageSha256 `303f1946…`; rerun → `git diff` clean. `coordinateVerification: unverified`. 26 migration tests. |
| **P5b** | Independent coordinate verification | this commit | 79 OSM node positions fetched from `api.openstreetmap.org/api/0.6/nodes.json` on 2026-11-04 (Overpass was unreachable) stored in `tools/map/tashkent_osm_anchors.json`; `migrate_tashkent_legacy.py` recomputes each deviation in the local ENU plane. Result: 21 anchors within 10 km median **17.7 m**, max **23.1 m** (tolerance 30 m) → `verified_approximate`; overall max 70.2 m at 21.8 km (error ≈0.2% of distance); only 2 anchors inside the road extent (Toshkent place node 3.3 m, weir 10.4 m). Axis, unit and origin errors are excluded (flipped y or +100 m shift → `failed` in tests); **not survey-grade**. packageSha256 unchanged (`303f1946…`). 55 Python tests. |
| **P6** | GIS data honesty | `898fe5b` | 14 divisions, `UZ-TK`/`UZ-TO` separate, `representativePoint`, `approximate_bounding_box_envelope`, ISO verified vs statoids (secondary), SOATO unverified. `validate-regions` OK. |
| **P7** | Selector in the real game | `3367155` | `uzbekistan_selector_widget_test.dart` 11/11: controller (idempotent init, unknown region rejected, LOD, notifications, broken catalog), real screen (HUD button, open/close, **all 14 regions selected**, overview card pauses the game and covers the map, back/reopen, Russian labels, dispose safety). Screenshots reviewed. |
| **P7b** | Wiring the remaining modules | this commit | `RoadGame.save()` adds an additive `nat` key (`NationalSaveV3.fromGameState`; outer save stays `v: 2`); `load()` reads it, never fails because of it; `gameRegionId` is the last *detailed* region, so an overview-only selection cannot relabel a Tashkent save; `UzbekistanWorldController.restoreDetailedRegion` (called by the save menu) re-selects only a region with a detailed package. Overview card shows the architecture profile + "no visuals yet". `test/national_wiring_test.dart` 7 tests: envelope round-trip, no invented camera for procedural biomes, additive key, old save without `nat` loads, 4 kinds of broken `nat` load, a well-formed `nat` naming another region is recorded but never adopted (`gameRegionId` stays), overview selection never relabelled, tampered/unknown region refused, profile text. Plus the real-screen test `loading a save from the menu leaves the overview card and returns to the saved region` (mutation-checked: it fails when the restore call in `main.dart` is removed). CI: run [41799584199](https://github.com/abdulloh042006-debug/Trafficity/actions/runs/41799584199) for `c7f9f2e` concluded **success**; artifacts listed: `Trafficity-Uzbekistan-Complete` 2 335 115 bytes, `trafficity-debug-apk` 79 222 191 bytes (not downloaded or installed). Not verified on a device. |
| **P13** | Real 2D map of Uzbekistan (owner screenshot: the selector was only a list and a text card) | this commit | Data: Natural Earth 1:10m admin-1 (public domain) → `assets/world/uzbekistan/region_borders.json` (34 KB, 14 regions, 1815 points, tolerance 0.004° ≈ 440 m) via `tools/map/build_uzbekistan_borders.py` (deterministic: two builds `cmp`-equal). Independent checks: ISO codes match the catalog 14/14; every catalog representative point lies inside its own outline; summed area **449 023 km²** vs. published 448 978 km² (+0.01 %); Tashkent City outline is coarse (240 km², published ≈ 334 km²). Python 13 tests (`test_uzbekistan_borders.py`). Dart: `RegionBorders` (parse/validate/hit test with holes, smallest shape wins) and `UzbekistanMapView` (pan/zoom, tap-to-select, marker for detailed regions with finger-sized target, labels only where they fit and do not collide, crisp at any zoom); wired into the selector (above the unchanged list) and into the overview card (static map, selected region highlighted); broken outlines never break the list. 16 new Flutter tests (hit tests for 14 regions, markers, empty corners, interactive vs static, selector tap, card, broken outlines). PNG renders reviewed (selector, zoom on Tashkent, card). 136 Flutter / 41 Node / 68 Python pass. Not verified on a device. |
| **P13b** | Bundle contract and branch integration | this commit | Another party pushed 11 commits to this branch while P13 was in progress (merge of `main`, 42/45 manifest, packager tests); merged with `git merge` (no history rewrite; one conflict, `FILE_MANIFEST.json` digests, resolved by taking the remote file and running `update-manifest`). The bundle lists the app wiring but not the new map files, so `region_selector_overlay.dart` / `world_controller.dart` in a ZIP would not compile: added `lib/world/region_borders.dart`, `lib/ui/uzbekistan_map_view.dart`, `assets/world/uzbekistan/region_borders.json` and `tools/map/tashkent_osm_anchors.json` → **46 expansion / 49 full** (core constant, HTML text + embedded core, 3 test files, `test_package_release.py`). `validate-bundle` expansion 46 / full 49 OK; `npm test` 41/41; Python 68/68. `lib/l10n.dart` stays outside the list (new strings fall back to the Uzbek key in RU/EN). CI: run [41810160068](https://github.com/abdulloh042006-debug/Trafficity/actions/runs/41810160068) for the merge commit `5ae608e` concluded **success** (CI-PASS for that SHA); artifacts listed: `Trafficity-Uzbekistan-Complete` 2 367 817 bytes, `trafficity-debug-apk` 79 261 205 bytes (not downloaded or installed). Docs-only commits after it carry `[skip ci]`. |
| **P14** | Truck frozen next to Amir Temur xiyoboni (owner's phone screenshot) | this commit | Reproduced headlessly on the default Tashkent city (seed 7): truck V15 on an 18.1 m lane (truck 22 m) kept the hold of the junction behind it — the hold is released only when the rear is 1 m into the lane, impossible on a shorter lane — so it never asked for the next junction, and the held junction blocked the queue behind it. Fix in `traffic_sim.dart`: `_mayAsk` lets a vehicle longer than its lane request the next junction while holding the previous one; `_tryGrant` hands the old hold over; waiter sanitising keeps such vehicles. `test/traffic_short_lane_test.dart` (3; failed before the fix: truck still on the 20 m lane after 120 s). Same seed, 600 s: completed trips 139 → 181 (200 s: 48 → 89). **Not fixed:** general saturation gridlock remains (600 s: 241 of 250 vehicles stopped), see CLAUDE.md 'Ma'lum xavflar'. 139 Flutter tests pass. |
| **P15** | 3D view of Tashkent (owner: "2-variant, soyalar bilan, taxminiy bo'lsa ham") | this commit | `lib/game3d/` software perspective renderer (`OrbitCamera`, near-plane clipping, painter's algorithm per object, `drawVertices` batches): textured basemap ground, roads/rails, decks, 31 908 real footprints, game buildings, cars (body + cabin) and trucks (cab + box), sun shadows in one 30 % layer, haze. Buildings: Microsoft Global ML Building Footprints (ODbL), quadkey 121322232 (789 434 features read, 31 908 kept), projected WGS84 → EPSG:3857 → SVG (`map.wld` + half pixel) → game units; the projection matches all 79 OSM anchors within **0.004 m** (without the half pixel: a constant 3.44 m offset, found and fixed). Heights **estimated** (median 3.2 m, max 38.4 m). Found and fixed while testing: `Offstage` collapsed the screen's Stack to 0×0 (3D view and HUD would have been empty on a phone) → `SizedBox.expand`. Tests: `test/city3d_test.dart` (11), real-screen 3D toggle test, `tools/tests/test_tashkent_buildings.py` (14 incl. OBJ export). PNG renders reviewed (default, close, far, street level, real app screen). Desktop paint time 2–16 ms after the first frame (66 ms incl. caches); **not measured on a phone, not tried on a phone**. Bundle 52/55. `tools/map/export_tashkent_obj.py` (Blender), `docs/GEMINI_3D_PROMPT.md`. |
| **P8** | CLI and strict packager | `898fe5b`, `03a3f77`, `797fbcc` | `validate-regions`, `validate-package`, `validate-bundle --mode expansion|full` OK. `package_release.py --allow-blocked` locally: all checks PASS, ZIP created and validated, APK step **BLOCKED** (SDK); 49 Python tests incl. SDK and scaffold behaviour. |
| **P9** | HTML packager | `797fbcc` | `test/packager_html.test.mjs` 9 tests; `node tools/sync_packager_html.mjs --check` OK. **PASS (manual)**: headless Chromium 29/29 (local-files source, 42/45 validation, tampered/missing file rejected, ZIP re-downloaded and re-opened by Python, mocked GitHub push sequence with `force:false`, parent = previous tip, token only in the Authorization header and cleared, 422 conflict without retry, `main` refused, no CDN). |
| **P10** | CI workflow | `f2a474e`, `2e654f5` | Workflow pushed and accepted. Run [41698996726](https://github.com/abdulloh042006-debug/Trafficity/actions/runs/41698996726) (`f2a474e`) and run [41700238463](https://github.com/abdulloh042006-debug/Trafficity/actions/runs/41700238463) (`2e654f5`) both concluded **success**: format, analyze, `flutter test`, `npm test`, Python tests, HTML sync, CLI validation, reproducible migration, strict packager (ZIP, Android scaffold, debug APK), APK check, ZIP re-validation, both uploads. Artifacts listed via the API for each run (ZIP ≈ 2.3 MB, debug APK 79 212 058 bytes). The artifacts' contents were not downloaded or installed in this session. |
| **P12** | Final gate | `2e654f5` + ledger commit | §17 ticked with the evidence above; `origin/main` re-checked unchanged (`ee406fc`); secrets scan clean with the documented exclusions; `git diff --check` clean. |
| **P11** | Manifest and documentation | this commit | `update-manifest` → `validate-bundle` OK (expansion 42, full 45); `README.md`, `UZBEKISTAN_EXPANSION_README.md`, `CLAUDE.md` rewritten to real behaviour; game history kept in `docs/GAME_STAGES.md`. |

### NOT DONE — PENDING (crossed out = done, see COMPLETED)

- ~~**P0** Safe start, bootstrap, inventory, baseline numbers.~~
- ~~**P1** Imports, dependencies, analyzer/format/tests green.~~
- ~~**P2** Coordinate system and floating origin.~~
- ~~**P3** Real SHA-256 and package manager.~~
- ~~**P4** LOD, save migration, road portals, architecture profiles.~~
- ~~**P5** Tashkent migration (all roads, chunks, manifest, idempotent).~~
- ~~**P6** GIS data quality and honest labelling.~~
- ~~**P7** Selector integrated into the real game.~~
- ~~**P8** Strict CLI and release packager.~~
- ~~**P9** Browser HTML packager with safe Direct Push.~~
- ~~**P10** CI green with both artifacts.~~
- ~~**P11** Manifest, README, and CLAUDE.md accuracy.~~
- ~~**P12** Final gate.~~
- ~~Independent verification of the Tashkent coordinate conversion (P5 step 2).~~ → COMPLETED as **P5b**.
- ~~Wiring `national_save_manager` and `architecture_profile_engine` into the game~~ → COMPLETED as **P7b**.
- [ ] **Playable regions other than Tashkent City** need real map data per region (basemap + roads) built like Tashkent's (`tools/map/build_tashkent*.py` from an OSM export); the repository has none. Ask the owner for OSM exports (e.g. Samarkand, Bukhara).
- ~~**3D**~~ → COMPLETED as **P15** (software perspective renderer, Tashkent only). Still open inside 3D: measured building heights (none in the source), trees, traffic lights, trains, phone performance measurement.
- [ ] Tashkent City view: the territory square (1200 units, grows with level) and roads that extend beyond its edge (owner screenshot) are not diagnosed yet.
- [ ] `road_graph_linker` has no consumer by design (needs a second detailed region); it stays unwired until one exists.

**What is left (as of the last push):**

1. ~~CI for `c7f9f2e` and `7fced4b`~~ — done: runs [41799584199](https://github.com/abdulloh042006-debug/Trafficity/actions/runs/41799584199) and [41799158077](https://github.com/abdulloh042006-debug/Trafficity/actions/runs/41799158077) both **success**. Commit `511b916` (the `load()` fix and the menu-load test): run [41801020928](https://github.com/abdulloh042006-debug/Trafficity/actions/runs/41801020928) concluded **success** (CI-PASS for that exact SHA; later docs-only commits carry `[skip ci]`).
2. Nothing was run on a phone/emulator: the save `nat` key, the region restore after loading and the overview-card profile line are tested headlessly only (`test/national_wiring_test.dart`, `test/uzbekistan_selector_widget_test.dart`).
3. Local APK build stays BLOCKED (no Android SDK here); CI builds it.
4. No in-app region downloader or server; 13 regions stay `OVERVIEW_ONLY`; region borders are bounding-box envelopes; SOATO codes unverified; no profile-specific building visuals (`visualsImplemented: false`).
5. `road_graph_linker` unwired (see above).
6. Owner decisions below (52/55 file list, `main` vs this lineage, token revocation, README role, Android id).

### BLOCKED

- **Local `flutter build apk --debug`** — BLOCKED (local): `No Android SDK found. Try setting the ANDROID_HOME environment variable.` Unblocks with an Android SDK; the same build is **CI-PASS** in GitHub Actions (see P10). The APK was not installed or run on a device.
- ~~Coordinate verification against independent anchors~~ — **unblocked and done as P5b** using 79 OpenStreetMap node positions from the OSM API (`api.openstreetmap.org`; Overpass was unreachable). The `map.wld` georeference was not used (its pixel origin differs by ~3 m from the SVG metadata). Remaining limit: result is `verified_approximate`, **not survey-grade** (anchors are OSM place nodes, only 2 lie inside the road extent).

### OWNER DECISIONS NEEDED

1. **42/45 file list — RESOLVED, then extended to 46/49 (P13b) and 52/55 (P15).** The deliverable bundles now contain the app wiring, all 16 Tashkent chunks, and the offline packager runtime/UI. Workflows, the remaining test suites, release scripts and this repair prompt remain outside the bundle by design; the packager-specific Node validation test is included.
2. **Branches.** The work is on `ccr-7e104e07-0xa8wr`; `codex/uzbekistan-expansion` is kept fast-forwarded to it (no force-push). `main` already contains a different Uzbekistan implementation (`1ae8545`, `ee406fc`) — choose which one wins before merging anything into `main`.
3. **Token.** Revoke the previously exposed token and use a fresh fine-grained one limited to this repository.
4. **README.** On this lineage `README.md` is the packager README; the game's stage log moved to `docs/GAME_STAGES.md`.
5. **Android id.** Builds now use `uz.abdulloh.trafficity` (pubspec name) instead of `uz.abdulloh.roadflow_city`; both can be installed side by side.

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

**Never write "all done", "fully working", "N/N passed", or "release-ready" without the matching evidence. Start with P0 (re-verify the ledger's evidence against the tree) and continue with the first unfinished item.**
