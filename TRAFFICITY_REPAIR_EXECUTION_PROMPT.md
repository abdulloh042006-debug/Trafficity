# TRAFFICITY — Repair Execution Master Prompt

**Purpose:** This file is the single source of truth for repairing, completing, testing, documenting, and packaging the Uzbekistan expansion of the Trafficity application.

**Target repository:** `abdulloh042006-debug/Trafficity`  
**Target working branch:** `codex/uzbekistan-expansion`  
**Current audited commit:** `5f190b92347a5b78a396d8c2fdc5858a79e4fa0c`  
**Main branch:** Do not modify, merge into, rebase onto, or force-push to `main` without explicit owner approval.

---

## 0. CRITICAL EXECUTION RULES

You are being assigned the implementation work now. **Do not assume that any repair task below has already been completed.** Previous messages, claimed terminal results, mock results, and commit descriptions are not proof that the application works.

1. Start by inspecting the actual repository and current branch. Read this entire file first.
2. Work only on `codex/uzbekistan-expansion`. Preserve the existing Trafficity game and its Tashkent functionality.
3. Do not replace working application code with tiny stubs, placeholder implementations, fake checksums, hard-coded success values, empty methods, or code that merely makes a test pass.
4. Do not delete, weaken, skip, rename, or reduce existing tests to hide failures. Fix the implementation or correct genuinely stale test imports without reducing test coverage.
5. A task may be marked **COMPLETED** only after its implementation exists in the repository, the relevant real command has run successfully, and the result has been inspected. A mocked test alone is insufficient for a real integration claim.
6. Never claim that Flutter analysis, Flutter tests, APK build, ZIP generation, or GitHub Actions passed unless the corresponding command/run actually completed with exit code 0.
7. Do not silently continue after a command fails. Record the exact command, exit code, and meaningful error. Fix the cause before proceeding to dependent phases.
8. Preserve all useful functionality. Before editing a file, inspect its current contents and its history. When an implementation was shortened or removed, inspect earlier commits and recover the last complete implementation before rewriting it.
9. Do not invent real-world GIS boundaries, road geometries, city data, coordinates, sources, checksums, package contents, or test evidence.
10. Never expose GitHub tokens or other secrets in source code, logs, browser storage, terminal output, screenshots, reports, or commit messages.
11. Do not force-push. Do not use `git push --force`. Use normal fast-forward pushes only.
12. Keep changes focused and reviewable. Commit after a coherent repair phase, push to the target branch, and continue with the next phase.
13. If a requirement cannot be completed because verified source data, credentials, or a platform dependency is unavailable, implement no fake substitute. Record the blocker under **NOT DONE**, explain what is missing, and leave the application in a truthful state.
14. Do not ask the owner to repeat information already in this file. Make a best effort to complete every feasible task in this run.

## 1. AUDITED BASELINE — FACTS TO RECHECK

The following were observed on commit `5f190b92347a5b78a396d8c2fdc5858a79e4fa0c`. Recheck them against the current branch before changing anything.

### 1.1 Git and CI

- The commit was successfully pushed to `codex/uzbekistan-expansion`.
- GitHub Actions run #15, run ID `41574007338`, for that exact commit completed with **failure**.
- Workflow: `.github/workflows/uzbekistan-release.yml`.
- `flutter pub get` completed.
- The migration command returned exit code 0, but its implementation only counted road records; this was not a successful data migration.
- `flutter analyze` failed with 70 reported issues, including incorrect package imports and undefined game symbols.
- Debug APK build, ZIP packaging, and artifact upload were skipped because the preceding workflow step failed.
- No artifact was uploaded by that run.
- The branch was reported as 15 commits ahead and 4 commits behind `main`. Recheck current refs; do not reconcile this divergence without authorization.

### 1.2 Concrete implementation defects found

- `pubspec.yaml` declares package name `trafficity`, while multiple existing tests import `package:roadflow_city/...`.
- `lib/world/region_package_manager.dart` returns the literal string `verified_sha256` instead of calculating SHA-256.
- `lib/world/geo_coordinate_system.dart` has lost important WGS84-to-Local-ENU and Local-ENU-to-WGS84 conversion functions, ellipsoid scaling, and floating-origin rebasing behavior.
- `lib/world/multi_scale_lod_controller.dart` ignores camera zoom and 3D perspective when choosing detail level.
- `lib/world/national_save_manager.dart` no longer contains the old-save migration adapter and camera-position data.
- `lib/world/road_graph_linker.dart` no longer contains portal registration and cross-chunk boundary logic.
- `tools/map/migrate_tashkent_legacy.py` parses some record shapes but does not convert road coordinates, write migrated road chunks, or update package manifest digests/counts.
- `lib/main.dart` and `lib/game/road_game.dart` do not currently show an integration of the Uzbekistan HUD/controller into the actual game screen.
- The file `Trafficity-Uzbekistan-Complete-Packager.html` was not found at the audited commit.
- `tools/package_release.py` treats a missing Flutter executable as a successful skipped step and does not reliably fail on unsuccessful subcommands.
- The current Node test file contains only a small number of checks. It does not prove full app functionality, real ZIP packaging, or real GitHub API writes.

These are baseline findings, not permission to make assumptions. Inspect the actual current files and repository history.

---

## 2. REQUIRED WORKFLOW — PHASE 0: SAFE START AND REPOSITORY INVENTORY

Before modifying code:

1. Run and record:
   - `git status --short --branch`
   - `git branch --show-current`
   - `git log -8 --oneline --decorate`
   - `git remote -v`
   - `git diff --check`
2. Confirm the current branch is `codex/uzbekistan-expansion`. If not, switch to it safely without discarding uncommitted work.
3. Fetch remote refs and compare the target branch with `origin/main`. Do not merge or rebase.
4. Inspect:
   - `pubspec.yaml`
   - all files under `lib/world/` and `lib/ui/`
   - `lib/main.dart` and `lib/game/road_game.dart`
   - all files under `test/`
   - all Python and Node tooling under `tools/`
   - all workflow files under `.github/workflows/`
   - all JSON, GeoJSON, manifests, and asset references under `assets/world/uzbekistan/`
   - `FILE_MANIFEST.json`
5. Inspect Git history for each shortened or suspicious file. Use commands such as:
   - `git log --all --oneline -- path/to/file`
   - `git show <known-good-commit>:path/to/file`
   - `git diff <known-good-commit>..<current-commit> -- path/to/file`
6. Identify the exact source schema of `assets/map/tashkent_roads.json`. Inspect representative first, middle, and last road entries, including nested arrays and object records. Do not infer a schema from one entry.
7. Create a local inventory of missing, duplicated, unreferenced, and manifest-listed files. Do not change `FILE_MANIFEST.json` until the actual bundle contract is understood.

**Exit criteria:** cleanly understood branch baseline, reproducible list of current failures, and a written inventory. This phase is reconnaissance; do not claim any code repair is complete.

## 3. PHASE 1: REPAIR FLUTTER PACKAGE AND ANALYSIS FAILURES

### 3.1 Correct package imports without reducing coverage

1. Search all Dart files, especially all test files, for stale `package:roadflow_city/` imports.
2. Since the package name is `trafficity`, update valid project imports to `package:trafficity/...` or use correct relative imports.
3. Do not change the package name merely to silence the analyzer unless the entire repository and project identity prove that this is the intended package name.
4. Search for additional stale class names, missing source paths, duplicate declarations, invalid asset paths, and type mismatches.
5. Preserve every existing test scenario and assertion. Do not delete tests or comment them out.

### 3.2 Run the real Dart checks

Run these commands from the repository root and capture their actual output:

- `flutter pub get`
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test`

If formatting reports changes, run `dart format lib test`, inspect the diff, and rerun all checks.

Fix errors and warnings caused by the expansion. Do not suppress meaningful diagnostics with broad ignores. If an existing legacy warning is unrelated, document it explicitly rather than hiding it.

**Acceptance:** `flutter analyze` exits 0 and the complete existing Flutter test suite exits 0. No tests may be skipped to obtain this result.

## 4. PHASE 2: RESTORE AND COMPLETE THE GEOSPATIAL COORDINATE SYSTEM

File: `lib/world/geo_coordinate_system.dart`

Implement a real coordinate system, not a collection of data classes.

Required behavior:

1. Keep WGS84 coordinates in longitude/latitude order internally where appropriate, and document every JSON coordinate-order convention. GeoJSON uses longitude then latitude.
2. Implement WGS84 ellipsoid constants and latitude-dependent meters-per-degree calculations using the appropriate ellipsoid equations.
3. Implement:
   - WGS84 coordinate to Local ENU conversion.
   - Local ENU coordinate to WGS84 conversion.
   - conversion between Flame world vectors and Local ENU meters.
   - legacy Tashkent local-coordinate conversion compatible with the previous game data.
   - floating-origin updates and threshold-based rebasing.
   - geodesic distance calculation with numeric domain protection.
4. Keep altitude handling consistent.
5. Validate coordinate ranges and reject NaN/infinite values.
6. Ensure the sign convention for screen/world Y is documented and tested. Do not silently invert north/south.
7. Recover prior proven formulas from Git history when possible; independently test them.

Required tests:

- Known Tashkent origin converts to approximately zero local displacement.
- A point east of the origin has positive east meters.
- A point north of the origin has positive north meters.
- WGS84 → ENU → WGS84 round-trip stays within a documented tolerance.
- Legacy Tashkent points round-trip correctly.
- Floating-origin rebasing returns the expected shift and resets local displacement.
- Invalid coordinates are rejected.
- Geodesic distance returns plausible values for known point pairs.

**Acceptance:** all these tests pass, and prior Tashkent map behavior is not broken.

## 5. PHASE 3: IMPLEMENT REAL SHA-256 AND A REAL REGION PACKAGE MANAGER

Primary file: `lib/world/region_package_manager.dart`

### 5.1 SHA-256

1. Remove the fake `verified_sha256` placeholder entirely.
2. Use a maintained, compatible Dart package for SHA-256 (for example, the `crypto` package) or a correct fully tested implementation. Inspect SDK compatibility before selecting a dependency.
3. Add the dependency to `pubspec.yaml` and ensure lockfile consistency if the repository tracks a lockfile.
4. Normalize digest formatting to lowercase hexadecimal, exactly 64 characters.
5. Compare digests safely and fail closed on invalid or missing hashes.

Required known-answer tests:

- SHA-256 of UTF-8 `abc` must equal `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
- SHA-256 of an empty byte sequence must equal `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
- A changed payload must fail verification.
- A correct payload with the correct digest must pass.

### 5.2 Package installation

Implement real package lifecycle behavior:

1. Read and validate a region package manifest.
2. Verify package ID, region ID, version, required files, file sizes, and SHA-256 digests.
3. Download or accept package bytes through an explicit interface; do not hard-code successful installation.
4. Extract ZIP packages using a maintained compatible archive library.
5. Prevent Zip Slip and path traversal:
   - reject absolute paths;
   - reject `..` traversal segments;
   - normalize separators;
   - resolve each destination and verify it remains inside the installation directory;
   - reject symlink entries unless safely supported.
6. Extract to a temporary staging directory, validate all files, then atomically promote it to the installed directory.
7. Never mark a region installed before all validation and extraction steps succeed.
8. Preserve the previous valid installed package if an update fails.
9. Persist installed state across application restarts using an appropriate Flutter-supported storage solution.
10. Support install, update, remove, list installed packages, resolve readiness, and recover from incomplete installation.
11. Keep `OVERVIEW_ONLY` regions as overview-only until a real detailed dataset is installed. Do not pretend the other 13 regions already have playable road data.

Required tests:

- correct archive installs;
- corrupted hash is rejected;
- missing manifest file is rejected;
- path traversal archive is rejected;
- interrupted/failed install does not mark region installed;
- failed update preserves the old version;
- install state survives manager reconstruction;
- removal updates persisted state;
- unknown region IDs are rejected.

**Acceptance:** no fake hash, no in-memory-only success state, and all package lifecycle tests pass.

## 6. PHASE 4: RESTORE LOD, SAVE MIGRATION, AND ROAD GRAPH LINKING

### 6.1 LOD — `lib/world/multi_scale_lod_controller.dart`

Restore meaningful four-level selection:

- Level 1: country overview.
- Level 2: regional view.
- Level 3: detailed city 2D.
- Level 4: detailed urban 3D.

The result must use camera zoom, 3D perspective state, and whether a verified detailed package is installed. Define thresholds in named constants and document them. A region without detailed data must never enter a detailed playable LOD level.

Tests must cover every threshold boundary and all combinations of 2D/3D and installed/not-installed package state.

### 6.2 Save format — `lib/world/national_save_manager.dart`

1. Preserve save format version 3.
2. Store country ID, region ID, camera position in WGS84, and all required version metadata.
3. Restore the legacy v1/v2 save migration adapter.
4. Convert old Tashkent local camera coordinates using the restored coordinate system.
5. Handle missing, malformed, and unknown-version saves safely.
6. Do not overwrite a valid old save until conversion succeeds.

Tests must cover valid legacy saves, missing camera values, malformed input, unknown versions, and v3 serialization/deserialization round-trip.

### 6.3 Road graph linker — `lib/world/road_graph_linker.dart`

Restore portal-based boundary linking:

1. Define a typed portal node with stable portal ID, global road/way ID, WGS84 position, source chunk, and destination chunk.
2. Register and validate portals.
3. Track loaded chunks.
4. Return only active boundary portals where one adjacent chunk is loaded and the other is not.
5. Avoid duplicate portal IDs and invalid self-links.
6. Ensure links use real source data only; do not invent cross-region roads.

Tests must cover chunk load/unload, portal registration, duplicate IDs, and boundary activation.

### 6.4 Architecture profile engine

Preserve the landmark exclusion API and any existing architecture profile behavior. Do not reduce it to a stub. If architecture data is incomplete, distinguish supported profile metadata from unimplemented visuals.

**Acceptance:** all prior behavior is restored or deliberately replaced by an equivalent tested implementation. No API used by existing code is silently removed.

## 7. PHASE 5: REPAIR TASHKENT LEGACY MIGRATION

File: `tools/map/migrate_tashkent_legacy.py`

This script must perform a real, deterministic migration.

### 7.1 Understand input data first

1. Inspect the actual full structure of `assets/map/tashkent_roads.json`.
2. Record the root JSON type, road record shape, point encoding, coordinate units, axis orientation, and any metadata fields.
3. The currently observed input has a root object with a `roads` collection and array-based road entries. Do not assume every entry is a dictionary.
4. Implement explicit parsers for every supported road shape. Reject or report unknown shapes; do not silently discard them.
5. Validate every point for numeric, finite coordinates and plausible ranges.

### 7.2 Coordinate conversion

1. Recover the old Tashkent coordinate origin and conversion convention from repository history and original game code.
2. Convert source road points from the legacy local coordinate system to WGS84 using the restored coordinate conversion implementation or a mathematically equivalent tested Python implementation.
3. Validate axis order and Y direction against known Tashkent anchor points.
4. Preserve stable source road IDs where present; otherwise create deterministic IDs based on stable input identity, not random values.
5. Do not label unverified coordinates as surveyed or verified.

### 7.3 Output package

1. Generate the expected Tashkent package output and chunk data in the documented package layout.
2. Include all valid road geometries, not only a sample of the first 250.
3. Record total source roads, successfully converted roads, skipped/rejected records, and total point count.
4. Generate per-file SHA-256 and byte sizes.
5. Update the Tashkent package manifest with actual output files, digest values, feature counts, coordinate convention, schema version, and attribution.
6. Ensure every referenced file actually exists.
7. Keep the original source `assets/map/tashkent_roads.json` unchanged.
8. Make the script idempotent: running it twice on unchanged input must produce semantically identical output and stable digests.
9. Fail with a nonzero exit code if a required source is absent, no usable roads are converted, or a validation fails.
10. Print a truthful summary; do not say “verified” merely because records were counted.

Required tests:

- fixtures for every real input record shape;
- empty and malformed datasets;
- invalid coordinate values;
- correct known-point conversion;
- all expected roads converted or explicitly rejected with reason;
- digest and file size recalculation;
- idempotency;
- source file unchanged.

**Acceptance:** migration generates real WGS84 road chunks and a valid manifest, and a second run is deterministic.

## 8. PHASE 6: GIS DATA QUALITY AND 14-REGION CATALOG

Files under `assets/world/uzbekistan/`.

1. Validate exactly 14 first-level administrative divisions.
2. Verify that `UZ-TK` (Tashkent City) and `UZ-TO` (Tashkent Region) remain separate.
3. Verify all ISO 3166-2:UZ and SOATO codes against trustworthy sources. Keep source references and verification dates in metadata or documentation.
4. Distinguish:
   - administrative center coordinates;
   - geometric centroids;
   - representative map anchors;
   - bounding boxes.
   Do not call a city-center coordinate a region centroid unless it is actually calculated as one.
5. Validate latitude/longitude ranges, unique IDs/codes, names in Uzbek/Russian/English, and correct coordinate ordering.
6. Inspect the GeoJSON geometry. Current metadata says `verified_bounding_box_envelope_only`. These are envelopes, not true administrative boundary polygons. Preserve that honesty.
7. Do not turn rectangular bounding boxes into claims of accurate regional boundaries.
8. If official or authoritative boundary polygons cannot be sourced and licensed, retain approximate envelopes and label them clearly as approximate.
9. Verify OSM attribution and ODbL obligations for any OSM-derived data.
10. Check that every asset referenced by `pubspec.yaml`, manifests, and code exists and is valid JSON/GeoJSON.
11. Ensure only Tashkent is marked as having detailed playable content unless real datasets for other regions are actually present and validated.

Required tests:

- 14 unique region IDs and ISO codes;
- distinct Tashkent City and Tashkent Region entries;
- all required fields present;
- numeric finite coordinates in valid ranges;
- GeoJSON syntax and feature count;
- each GeoJSON feature ID maps to a catalog record;
- truthful geometry accuracy metadata;
- package readiness is not overstated.

**Acceptance:** data integrity and provenance are documented; no fabricated administrative polygons or road networks.

## 9. PHASE 7: INTEGRATE THE UZBEKISTAN SELECTOR INTO THE REAL GAME

Relevant files: `lib/main.dart`, `lib/game/road_game.dart`, `lib/ui/uzbekistan_hud_button.dart`, `lib/ui/region_selector_overlay.dart`, and world controller files.

1. Understand the existing Flutter/Flame widget tree and HUD composition before adding UI.
2. Integrate a single lifecycle-managed `UzbekistanWorldController` into the actual game screen.
3. Initialize region assets asynchronously and handle loading/error states. Do not call async initialization without handling failure.
4. Add the Uzbekistan selector to the actual visible in-game HUD, not merely create an unused widget class.
5. Ensure opening and closing the selector works and does not block or break existing game controls.
6. Support the existing language choices (Uzbek, Russian, English) through the app's real language state.
7. On region selection:
   - update active region;
   - update geographic origin;
   - resolve package readiness;
   - update LOD safely;
   - show the correct overview/detailed state;
   - communicate selection to the actual game/map layer.
8. For non-Tashkent regions that lack detailed data, show a clear overview-only state. Do not show the Tashkent road map under another region label.
9. Preserve the existing Tashkent game flow, save/load, tutorials, audio, and HUD.
10. Dispose listeners/controllers correctly and prevent setState-after-dispose or duplicate controller instances.

Required tests:

- controller loads all 14 catalog entries;
- selector button appears in the real screen;
- selector opens and closes;
- each region can be selected;
- language labels update;
- Tashkent detailed readiness is retained;
- other regions remain overview-only without real packages;
- existing game widget tests remain passing.

**Acceptance:** the feature is visibly integrated and tested within the real app, without regressions to existing game behavior.

## 10. PHASE 8: REAL CLI AND PACKAGE RELEASE SCRIPT

### 10.1 Node CLI — `tools/uzbekistan_pack_cli.mjs`

Implement and test:

- `list-regions`
- `validate-regions`
- `validate-package <manifest-path>`
- package/bundle validation as needed by the release workflow

Requirements:

1. Validate input arguments and exit with nonzero codes for errors.
2. Resolve paths safely relative to the repository root, not the caller's arbitrary current directory.
3. Validate all 14 records, required keys, uniqueness, ranges, and Tashkent distinction.
4. Validate every required package file exists.
5. Recalculate real SHA-256 digests from actual file bytes.
6. Avoid printing success until all relevant checks pass.

### 10.2 Python release packager — `tools/package_release.py`

1. Remove the behavior that treats missing Flutter binaries as success.
2. Every required command must fail the packaging process on nonzero exit.
3. Use explicit command execution and error handling. Record each command and result.
4. Run migration, Flutter dependency retrieval, formatting verification, analysis, tests, and debug APK build before packaging.
5. Run Node and Python tests too.
6. Verify the APK exists and is non-empty before claiming it was built.
7. Create a deterministic ZIP:
   - stable path ordering;
   - stable file timestamps where practical;
   - no `.git`, build caches, local secrets, or machine-specific files;
   - include all files required to reproduce and run the project;
   - include the intended source and documentation;
   - do not recursively include the ZIP inside itself.
8. Reopen the ZIP after creation and validate its central directory and required file list.
9. Print the SHA-256 digest, byte size, file count, and output location.
10. Exit nonzero on any validation or packaging failure.

Required tests:

- failed Flutter command blocks ZIP creation;
- missing Flutter binary blocks release;
- ZIP contains required files;
- excluded files are absent;
- ZIP opens and validates;
- repeated packaging produces stable contents/digest where deterministic timestamps are used.

## 11. PHASE 9: CREATE THE MISSING BROWSER PACKAGER HTML

Create the file at repository root:

`Trafficity-Uzbekistan-Complete-Packager.html`

This is a required deliverable, not optional documentation.

### 11.1 UI and operation

Create a complete responsive single-page HTML application with:

- clear project title and version;
- dark professional interface with accessible contrast;
- visible repository and target branch;
- package summary;
- validation status;
- ZIP download controls;
- GitHub Direct Push controls;
- progress and result/error messages;
- a visible manifest/file inventory;
- mobile-compatible layout.

### 11.2 Bundle definitions

Use `FILE_MANIFEST.json` as the canonical inventory. Do not maintain a second inconsistent hard-coded file list.

Support exactly the documented bundle modes:

- **Expansion ZIP:** 20 expansion files.
- **Full ZIP:** 23 files (20 expansion + 3 base integration files).

Before bundling, verify each required path exists and its bytes match the expected size and SHA-256 where those fields are defined. Make the self-referential manifest rule explicit so its own digest is not treated as a circular checksum.

Use JSZip (or another maintained browser-compatible ZIP library) to generate a valid downloadable ZIP. Validate that the generated ZIP contains the expected entries and counts. Use deterministic entry ordering.

The page must not label an unvalidated archive as complete.

### 11.3 GitHub Direct Push

Implement the GitHub Direct Push flow using the official Git Database API sequence:

1. Let the owner enter a GitHub fine-grained personal access token explicitly.
2. Show the exact repository and branch before the user confirms.
3. Read the current branch reference and record its SHA.
4. Create required blobs.
5. Create a tree based on the intended base tree.
6. Create a commit with the previous commit as parent.
7. Update the branch reference with a normal non-force update.
8. Never target `main`; target only `codex/uzbekistan-expansion`.
9. Handle a 409/conflict by stopping and asking for a fresh branch state; never silently force.
10. Handle 401/403/404/rate-limit/network failures with safe human-readable errors.
11. Do not print or persist tokens. Do not put tokens in URLs. Keep the token only in page memory for the shortest possible time and clear the input/state after the operation.
12. Warn the user that browser-based token use should be restricted to a repository-scoped fine-grained token and that the token must not be committed.
13. Do not claim a push succeeded until GitHub confirms the updated ref and the new commit can be read back.

### 11.4 HTML verification

Add automated tests or a reproducible test harness for:

- manifest parsing;
- exact 20-file and 23-file bundle modes;
- missing-file rejection;
- digest mismatch rejection;
- generated ZIP contents;
- GitHub API request sequence using mocks;
- conflict behavior;
- token redaction in errors/logs;
- no force update;
- branch target cannot be changed to `main` accidentally.

A mock test validates request construction only. It does not count as a real GitHub push.

## 12. PHASE 10: CI WORKFLOW — MAKE GREEN STATUS MEAN SOMETHING

Update `.github/workflows/uzbekistan-release.yml` to run the full real verification pipeline on pushes to `codex/uzbekistan-expansion` and on manual dispatch.

Required ordered steps:

1. checkout exact commit;
2. set up Python;
3. set up a compatible Java 17 runtime if needed by Android;
4. set up a pinned or stable Flutter SDK compatible with `pubspec.yaml`;
5. set up Node.js compatible with `package.json`;
6. install Flutter dependencies;
7. run formatting verification;
8. run `flutter analyze`;
9. run the complete `flutter test` suite;
10. run `npm test`;
11. run Python unit tests for migration and packaging tools;
12. run CLI region and package validation;
13. run the actual Tashkent migration and validate generated output;
14. build `flutter build apk --debug`;
15. run `tools/package_release.py` in strict mode or the equivalent fully validated release command;
16. validate the ZIP after generation;
17. upload `Trafficity-Uzbekistan-Complete.zip` as a workflow artifact;
18. upload the debug APK as an artifact if appropriate.

Use appropriate dependency caching, but never let a cache substitute for running the checks. Workflow failures must propagate. Do not mark steps continue-on-error just to produce an artifact after failed tests.

**Acceptance:** the exact final commit's GitHub Actions run completes with conclusion `success`; required APK and ZIP artifacts are present and downloadable.

## 13. PHASE 11: MANIFESTS, DOCUMENTATION, AND SCOPE ACCURACY

1. Update `FILE_MANIFEST.json` only after final file contents are stable.
2. Recompute each listed file's real byte size and SHA-256.
3. Validate all listed paths exist and bundle modes have exact counts.
4. Do not count files that are not included, and do not omit required files.
5. Explain which files are expansion-only and which are base integration files.
6. Update README instructions to match actual commands and actual output.
7. Remove claims of completed features if the implementation is not present.
8. State clearly that only the verified Tashkent detailed dataset is playable unless other regional detailed datasets have genuinely been acquired, validated, licensed, and integrated.
9. Explain boundary accuracy honestly: bounding-box envelopes are not real administrative border polygons.
10. Document data sources, capture dates, licenses, attribution, schema versions, and known limitations.
11. Include exact clean-clone setup and verification commands.

## 14. FINAL ACCEPTANCE GATE

Do not mark the project release-ready until every applicable gate below is green:

- [ ] Correct working branch; no unauthorized main changes.
- [ ] No accidental deletion or weakening of original Trafficity tests/features.
- [ ] No stale package imports or unresolved analyzer errors.
- [ ] Dart format check passes.
- [ ] `flutter analyze` exits 0.
- [ ] Full `flutter test` suite exits 0.
- [ ] Real SHA-256 known-answer tests pass.
- [ ] Coordinate conversion and floating-origin tests pass.
- [ ] LOD threshold and readiness tests pass.
- [ ] Save migration tests pass.
- [ ] Road graph portal tests pass.
- [ ] Package install/update/removal/path traversal tests pass.
- [ ] Tashkent migration converts actual data and is idempotent.
- [ ] CLI tests pass.
- [ ] Python migration/package tests pass.
- [ ] `npm test` passes without replacing real checks with mocks.
- [ ] HTML packager exists and its ZIP validation tests pass.
- [ ] GitHub Direct Push mock tests prove safe, non-force request flow.
- [ ] Debug APK builds successfully.
- [ ] Release ZIP is generated and reopened/validated.
- [ ] GitHub Actions for the final commit is green.
- [ ] APK and ZIP artifacts are uploaded and downloadable.
- [ ] Manifest digests/counts match the final repository files.
- [ ] Documentation accurately describes supported and unsupported regions/data.
- [ ] Final code review and `git diff --check` pass.

If any one of these gates fails, report the release as **NOT READY**.

---

## 15. EXECUTION STATUS LEDGER — UPDATE THIS FILE DURING THE WORK

This ledger starts with **no repair tasks completed**. A previous push, a commit title, a local mock, or a claim in chat does not count as a completed repair.

### COMPLETED — VERIFIED

**NONE.**

Move an item here only after the implementation is committed and the relevant real test/command has passed. Each completed entry must include:

- task ID and concise outcome;
- files changed;
- exact command(s) executed;
- actual exit code and test count;
- commit SHA containing the implementation;
- CI run URL/status when applicable.

### NOT DONE — PENDING

- [ ] **P0 — Safe start and inventory:** recheck branch, worktree, history, source data shape, and full repository inventory.
- [ ] **P1 — Flutter package/analyzer:** correct stale package imports and all analyzer errors without deleting or weakening tests.
- [ ] **P2 — Geospatial engine:** restore and test WGS84/ENU conversions, legacy coordinate conversion, and floating-origin rebasing.
- [ ] **P3 — SHA-256 and package manager:** implement real digest calculation, verified ZIP extraction, safe paths, atomic install/update, and persistent state.
- [ ] **P4 — Core modules:** restore camera-aware four-level LOD, legacy save migration, cross-chunk road portals, and architecture profile behavior.
- [ ] **P5 — Tashkent migration:** convert the actual legacy road records to WGS84 chunks, update manifest digests/counts, and prove idempotency.
- [ ] **P6 — GIS data quality:** validate 14 regions, codes, coordinate semantics, GeoJSON limitations, sources, and license metadata.
- [ ] **P7 — Actual app integration:** add the selector/controller to the real game screen and test selection, language, lifecycle, and Tashkent regression behavior.
- [ ] **P8 — CLI and release packager:** make all commands strict, validate outputs, and prevent ZIP creation after failed prerequisite commands.
- [ ] **P9 — Browser HTML packager:** create the missing HTML file, implement 20/23-file ZIP modes and safe GitHub Direct Push, and test it.
- [ ] **P10 — GitHub Actions:** run all real checks, build APK, create ZIP, and upload artifacts.
- [ ] **P11 — Manifest and documentation:** recalculate real digests, validate counts, and correct all unsupported claims.
- [ ] **P12 — Final acceptance:** run the complete release gate, inspect final diff, push normally, and verify the final GitHub Actions run/artifacts.

### BLOCKED

Initially: **NONE KNOWN**. Add a blocker only after the relevant task has been attempted and a concrete missing dependency, unavailable source, or external permission issue has been identified. Include the exact evidence and what is needed to unblock it.

### HOW TO MAINTAIN THIS LEDGER

1. After completing a task, run its tests.
2. If tests pass, commit and push the change to the target branch.
3. Edit this file in the same branch: remove that task's checkbox from **NOT DONE — PENDING** and add a fully evidenced entry under **COMPLETED — VERIFIED**.
4. If implementation is partial or tests fail, leave it under **NOT DONE** and note the partial work/blocker. Do not move it to completed.
5. Recalculate manifest digests after this file changes if this file is part of the declared bundle.
6. At the end of every work session, ensure this ledger agrees with the actual Git tree and test evidence.

---

## 16. REQUIRED FINAL REPORT

At the end, provide a concise but complete report containing:

1. Current branch and final commit SHA.
2. Completed task IDs with changed files.
3. Not-done task IDs and exact reasons.
4. Blockers, if any.
5. Exact commands executed and their real exit codes.
6. Flutter analyzer issue count before and after.
7. Flutter test passed/failed counts.
8. Node/Python test passed/failed counts.
9. Tashkent migration source/converted/rejected road counts.
10. APK path and size.
11. ZIP path, size, SHA-256, and file count.
12. HTML packager path and verified capabilities.
13. GitHub Actions run URL, conclusion, and artifact links.
14. Confirmation that `main` was not modified.

**Do not use phrases such as “all done”, “fully working”, “6/6 passed”, or “release-ready” unless the corresponding evidence above exists. Start with Phase 0 and proceed through the phases in order.**
