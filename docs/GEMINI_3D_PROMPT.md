# Gemini (yoki boshqa AI) uchun 3D prompt — Trafficity / RoadFlow City

> Quyidagi chiziqdan pastdagi hammasini nusxa olib Gemini'ga bering. Prompt inglizcha, chunki texnik
> talablar shunda aniqroq tushuniladi; javobni o'zbekcha so'rash mumkin.

---

You are working on **RoadFlow City / Trafficity**, an Android top-down road-building and traffic simulation game
written in **Flutter + Flame** (Dart 3.13, Flutter 3.47). Repository: `https://github.com/abdulloh042006-debug/Trafficity`,
working branch `ccr-7e104e07-0xa8wr` (mirror: `codex/uzbekistan-expansion`). Do **not** push to or merge into `main`.
Read `CLAUDE.md` in the repository root first: it is the single source of truth (architecture, constants, known risks).

## What already exists (do not rebuild it from scratch)

A working **software 3D view** of the real Tashkent map, opened with the **"3D"** button in the bottom toolbar
(Tashkent biome only). Files:

- `lib/game3d/camera3d.dart` — `OrbitCamera`: true perspective (fov 50°), orbit/tilt/zoom, `project`, `groundAt`.
  Game coordinates: x east, y south, 1 unit ≈ 1 m, z = height in metres; centre (3200, 3200) = Amir Temur xiyoboni.
- `lib/game3d/city3d_renderer.dart` — `City3DRenderer`: textured ground (the 2D basemap `game.terrainImage`), roads
  and rails as ribbons, real buildings, the game's own buildings, cars/trucks (body + cabin), elevated decks,
  sun shadows (azimuth 225°, elevation 42°, drawn in one translucent layer), distance haze, near-plane clipping,
  painter's algorithm per object, a few `Canvas.drawVertices` calls per frame, stats in `City3DStats`.
- `lib/game3d/city3d_view.dart` — full-screen widget: 1 finger orbit + tilt, 2 fingers zoom/pan/turn, "2D xarita" button.
  The 2D game keeps simulating underneath (`Offstage` inside `SizedBox.expand` in `lib/main.dart`).
- `lib/game3d/city_buildings.dart` — decoder of `assets/map/tashkent_buildings.bin` (31 908 footprints, 0.25 m
  quantisation, spatial grid, ear-clipping roofs).
- Data: `tools/map/build_tashkent_buildings.py` builds the binary from **Microsoft Global ML Building Footprints
  (ODbL)**, quadkey 121322232, projected with the **same chain as the game map** (WGS84 → EPSG:3857 → SVG units via
  `map.wld` + half-pixel → game units; checked against 79 OSM anchors, max error 0.004 m). **Heights are estimated**
  from footprint area and elongation (the source has no heights for Uzbekistan) — see `estimate_height`.
- `tools/map/export_tashkent_obj.py` — exports the same city as OBJ + MTL + basemap texture for **Blender**.
- Tests: `test/city3d_test.dart`, `tools/tests/test_tashkent_buildings.py`, the 3D toggle test in
  `test/uzbekistan_selector_widget_test.dart`.

## Your task (pick the items you can finish completely; one item = one commit)

1. **Better heights**: where OpenStreetMap has `building:levels` / `height` for a footprint (match by overlap ≥ 50 %),
   use it (3.2 m per level); keep the estimate elsewhere and record per building whether the height is
   `osm` or `estimated` in the meta file. Data access must be reproducible (script + source + date + checksum).
2. **Roofs and facades**: flat roofs with a darker parapet edge; a procedural window pattern on walls
   (horizontal bands every 3.2 m) without per-frame allocations.
3. **Trees** in parks/green areas (from the basemap green colour or OSM landuse), as low-poly cones/cylinders with shadows.
4. **Traffic lights** at signalised junctions (`game.sim.signals`) as small poles with the current colour.
5. **Trains and stations** (`game.rail`, `game.railNet`) in 3D.
6. **Performance**: measure frame time (`City3DStats.paintMs`) at distances 160 / 700 / 1600 m; keep ≤ 16 ms on a
   mid-range phone (report what you measured and where); reuse buffers, cull by frustum, LOD small buildings.
7. Optional, only if it stays stable on Android: GPU 3D (`flutter_scene` or similar). Keep the software renderer as
   the fallback and do not add native dependencies without a written reason.
8. Optional **Blender** deliverable: a `bpy` script that imports `build/tashkent_3d/tashkent.obj`, assigns the colours
   below, adds a sun lamp (azimuth 225°, elevation 42°) and renders a 1920×1080 image. Do not commit generated files.

## Colours (keep the 3D look close to the 2D game)

Building walls `#D5C8BB`, roofs `#E5DCD2` (±5 % per building), asphalt `#6C7178`, rails `#5E5650`,
unbuilt territory fog `#E6E3DA`, sky `#8FB8E0` → horizon haze `#DCE5EE`, shadow = black at 30 % alpha,
game buildings use their 2D roof colour (`Building.roof`) with walls at 80 %, vehicles use `Vehicle.color`.

## Rules (mandatory)

- Before every push: `flutter pub get && dart format --output=none --set-exit-if-changed lib test && flutter analyze &&
  flutter test && npm test && python3 -m unittest discover -s tools/tests`. All green, or say exactly what failed.
- After changing any file listed in `FILE_MANIFEST.json`, run `node tools/sync_packager_html.mjs` (if the packager
  core changed) and then `node tools/uzbekistan_pack_cli.mjs update-manifest`; new runtime files must be added to the
  bundle lists, otherwise the bundle ZIP does not compile.
- Honesty: never call estimated heights "real"; keep the attribution
  `Building footprints © Microsoft (ODbL) · Map © OpenStreetMap contributors` visible in the 3D view.
- No secrets in code or docs. No force-push. Short Uzbek summary at the end: what was done, what was not verified
  (the owner tests on a phone), next step.
