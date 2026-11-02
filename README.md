# Trafficity — Uzbekistan Complete ZIP Packager

Complete 14-region Uzbekistan GIS expansion, Region Package Manager, CLI, and automated verification suite for `abdulloh042006-debug/Trafficity`.

## Canonical 23-File Inventory
- **Expansion Bundle (`downloadZip(false)`):** 20 expansion files.
- **Base Repository Bundle:** 3 baseline integration files (`pubspec.yaml`, `.gitignore`, `assets/world/uzbekistan/regions/tashkent_city/manifest.json`).
- **Full Bundle (`downloadZip(true)`):** All 23 files (20 Expansion + 3 Base).

## CLI & Test Commands
```bash
npm test
node tools/uzbekistan_pack_cli.mjs list-regions
node tools/uzbekistan_pack_cli.mjs validate-regions
node tools/uzbekistan_pack_cli.mjs validate-package assets/world/uzbekistan/regions/tashkent_city/manifest.json
flutter test test/uzbekistan_world_test.dart
```

## Data Provenance & Honesty Guardrails
- All 14 first-level administrative divisions of Uzbekistan use explicit `latitude` and `longitude` (WGS84) coordinates.
- `UZ-TK` (Tashkent City) and `UZ-TO` (Tashkent Region, center Nurafshon) are distinct administrative entities.
- `administrative_boundaries.geojson` uses verified bounding-box envelopes (`verified_bounding_box_envelope_only`) rather than fabricated polygons.
