# Trafficity — Uzbekistan Complete ZIP Packager

Complete GIS region registry, package manager, CLI tool, Flutter/Flame world expansion modules, and automated validation suite for **Trafficity** (`abdulloh042006-debug/Trafficity`).

## 1. Exact 23-File Inventory & ZIP Modes

- **Expansion ZIP (`downloadZip(false)` — 20 files):** Contains all 20 new Uzbekistan expansion files (`FILE_MANIFEST.json`, `README.md`, `package.json`, `LICENSE`, `assets/world/uzbekistan/*`, `lib/world/*`, `lib/ui/*`, `tools/*`, and executable tests).
- **Full Repository Bundle ZIP (`downloadZip(true)` — 23 files):** Contains all 20 expansion files plus the 3 inspected repository baseline integration files (`pubspec.yaml`, `.gitignore`, and `assets/world/uzbekistan/regions/tashkent_city/manifest.json`). Uninspected upstream binary/Dart files are never fabricated.

## 2. 14 First-Level Administrative Regions of Uzbekistan (WGS84)

All 14 regions use explicit `latitude` and `longitude` fields (WGS84 decimal degrees) with distinct administrative entities for **Tashkent City (`UZ-TK`)** and **Tashkent Region (`UZ-TO`, admin center Nurafshon)**:
`UZ-TK`, `UZ-QR`, `UZ-AN`, `UZ-BU`, `UZ-FA`, `UZ-JI`, `UZ-QA`, `UZ-XO`, `UZ-NG`, `UZ-NW`, `UZ-SA`, `UZ-SU`, `UZ-SI`, `UZ-TO`.

### Data Provenance & Known Limitations
- **Source & License:** OpenStreetMap contributors under **ODbL-1.0** (`© OpenStreetMap contributors`).
- **No Fabricated Geometries:** Regional records provide verified administrative center coordinates (`latitude`, `longitude`) and bounding boxes. `administrative_boundaries.geojson` uses verified bounding-box envelopes (`geometryAccuracy: "verified_bounding_box_envelope_only"`) rather than invented polygons. Unbundled regions are marked `OVERVIEW_ONLY` and are not claimed to be complete street-level game maps.

## 3. CLI & Test Commands

Requires **Node.js >= 18** (zero external npm dependencies required):

```bash
# Run all automated Node.js tests (regions, schema, SHA-256, CLI, 23-file manifest, mocked GitHub push)
npm test
# or directly:
node --test test/packager_and_cli.test.mjs

# CLI Commands:
node tools/uzbekistan_pack_cli.mjs list-regions
node tools/uzbekistan_pack_cli.mjs validate-regions
node tools/uzbekistan_pack_cli.mjs list-packages
node tools/uzbekistan_pack_cli.mjs validate-package assets/world/uzbekistan/regions/tashkent_city
node tools/uzbekistan_pack_cli.mjs install-package assets/world/uzbekistan/regions/tashkent_city

# Flutter / Flame Tests (when Flutter SDK is installed):
flutter pub get
flutter analyze
flutter test test/uzbekistan_world_test.dart
```

## 4. GitHub Direct Push & Security Behavior

- Uses the GitHub REST **Git Database API** (`GET /repos`, `GET /git/ref`, `GET /git/commits`, `POST /git/blobs`, `POST /git/trees`, `POST /git/commits`, `PATCH /git/refs` with `force: false`).
- Your Personal Access Token is never sent anywhere except `https://api.github.com`, never persisted to `localStorage`/`sessionStorage`/cookies/logs, and is cleared from memory immediately after the push finishes.
- Use a fine-grained PAT scoped strictly to `abdulloh042006-debug/Trafficity` with `Contents: Read and write`.
