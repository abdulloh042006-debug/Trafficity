# Trafficity — Uzbekistan multi-region expansion

Flutter + Flame traffic and railway game (package `trafficity`) with a real map of **Tashkent City** (OpenStreetMap),
plus the groundwork for a 14-region Uzbekistan platform: region catalog, region selector in the HUD, WGS84 coordinate
system, transactional region packages, a Node CLI and a browser packager.

## What is real, what is not

| Area | State |
|---|---|
| Playable map | **Only Tashkent City** has a detailed dataset (2495 real OSM roads, converted to WGS84 chunks). |
| Other 13 divisions | `OVERVIEW_ONLY`: the selector shows an overview card and pauses the game. **No** road map is ever shown under another region's name. |
| Region borders | The GeoJSON shapes are **approximate bounding-box envelopes**, not administrative borders. They are never presented as borders. |
| Codes | ISO 3166-2:UZ codes were checked against a secondary source (statoids.com, 2026-11-03). **SOATO codes are unverified.** |
| Tashkent coordinate conversion | Status `verified_approximate`: origin (Amir Temur xiyoboni, 41.311081 N 69.279737 E), axes and 1 m/unit scale were compared with 79 independent OpenStreetMap node positions (`tools/map/tashkent_osm_anchors.json`, OSM API, 2026-11-04). 21 anchors within 10 km: median 17.7 m, max 23.1 m (tolerance 30 m); the error grows about 0.2% with distance (70 m at ~22 km). Only 2 anchors lie inside the road extent (3.3 m and 10.4 m). **Not survey-grade**: the anchors are OSM place nodes, not control points. |
| Region package manager | Install / update / remove / recover is implemented and tested (SHA-256, Zip-Slip protection, atomic promote). There is **no in-app downloader or server**: no region besides Tashkent can be installed from the UI. |
| `national_save_manager` | **Wired (additive).** `RoadGame.save()` writes a `nat` envelope (country, region, WGS84 camera only for the real Tashkent world, zoom) next to the unchanged v2 game save; `load()` reads it, ignores a missing/invalid one, and the save menu re-selects the stored region only if it has a detailed package. The region saved is the one the game state belongs to, never an overview-only selection. |
| `architecture_profile_engine` | **Wired as metadata only.** The overview card shows the region's profile with "no visuals yet" (`visualsImplemented: false`); there are no profile-specific building visuals. |
| `road_graph_linker` | **Not wired, on purpose.** It links road portals between two *detailed* regions; only Tashkent City has a detailed package, so no consumer exists. Unit-tested only. |
| Level of detail | `MultiScaleLodController` selects a level from zoom/3D/package state and the selector displays it. There is no chunk streaming and no 3D renderer. |

## Layout

```
lib/game/         game: roads, lanes, traffic, rail, terrain, real Tashkent roads
lib/world/        coordinates (WGS84/ENU), catalog, LOD, package manager, save v3, portals, world controller
lib/ui/           region selector dialog, overview card, HUD button
assets/map/       Tashkent basemap, water mask, legacy road file (game units)
assets/world/uzbekistan/   catalog, cities index, envelopes, regions/tashkent_city (manifest + 16 chunks)
tools/            migration (Python), CLI + packager core (Node), release packager (Python), HTML sync
test/             Flutter tests (*_test.dart) and Node tests (*.test.mjs); Python tests in tools/tests/
```

## Clean-clone setup and verification

Requirements: Flutter stable whose Dart satisfies `^3.11.0`, Node >= 18, Python >= 3.11. For the APK also Java 17 and the
Android SDK (`ANDROID_HOME`). The repository ships only launcher icons under `android/`, so the Android project is
generated (never committed) with `flutter create --platforms=android --org uz.abdulloh .`; delete the generated
`test/widget_test.dart` afterwards. `tools/package_release.py` does both automatically after it has built the ZIP.

```bash
git clone https://github.com/abdulloh042006-debug/Trafficity.git && cd Trafficity
git checkout <branch>

flutter pub get
dart format --output=none --set-exit-if-changed lib test     # formatter width is 120 (analysis_options.yaml)
flutter analyze
flutter test
npm test                                                     # CLI, packager core, HTML packager
python3 -m unittest discover -s tools/tests -v
node tools/sync_packager_html.mjs --check                    # HTML packager embeds the current core
node tools/uzbekistan_pack_cli.mjs validate-regions
node tools/uzbekistan_pack_cli.mjs validate-package assets/world/uzbekistan/regions/tashkent_city/manifest.json
node tools/uzbekistan_pack_cli.mjs validate-bundle --mode expansion   # and --mode full
python3 tools/map/migrate_tashkent_legacy.py && git diff --exit-code -- assets/world assets/map   # reproducible

python3 tools/package_release.py                # strict: checks -> ZIP -> Android scaffold -> debug APK
python3 tools/package_release.py --allow-blocked # local run without Android SDK: step is BLOCKED, never "release ready"
```

Reference result of this revision (see `TRAFFICITY_REPAIR_EXECUTION_PROMPT.md`, section 18 for evidence): analyzer
clean, format check clean, 120 Flutter tests (20 of them are the original game tests), 41 Node tests, 55 Python tests.

## Region data format

`assets/world/uzbekistan/regions/tashkent_city/manifest.json` lists every chunk with `path`, `bytes`, `sha256`,
`featureCount`. Chunks are 2000 m ENU grid cells (`ix = floor(east/2000)`, `iy = floor(north/2000)`) around the anchor;
a road belongs to the cell of its midpoint vertex. Coordinates are `[longitude, latitude]` (GeoJSON order, WGS84).
The package digest is the SHA-256 of the canonical, key-sorted `files[]` array; the Dart manager, the Node CLI and the
Python migration compute it identically (cross-checked by tests). The migration is deterministic: two runs give identical bytes.

## Bundles and the browser packager

`FILE_MANIFEST.json` lists 23 files: **Expansion = 20**, **Full = 20 + 3 base**. `Trafficity-Uzbekistan-Complete-Packager.html`
validates them (size and SHA-256), builds a deterministic ZIP and can push the verified files with the GitHub Git
Database API. The push target is locked to `codex/uzbekistan-expansion`, is never forced, rejects `main`/`master`,
and the token is used once and cleared. The HTML embeds `tools/packager_core.mjs`; run `node tools/sync_packager_html.mjs`
after editing the core.

## CI

`.github/workflows/uzbekistan-release.yml` runs every check above in order, then the strict release packager, and
uploads `Trafficity-Uzbekistan-Complete.zip` and the debug APK. `build-apk.yml` (release APK for `main`) is separate.

## Data sources and licence

Road and map data: © OpenStreetMap contributors, ODbL-1.0. Code: MIT (see `LICENSE`).
Earlier game history (stages 1-22): [docs/GAME_STAGES.md](docs/GAME_STAGES.md).
