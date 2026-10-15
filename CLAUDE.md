# RoadFlow City — project state for Claude (read this first)

User: Abdulloh (Uzbek speaker). Reply in Uzbek, short and concrete. Repo: https://github.com/abdulloh042006-debug/Trafficity (public, branch main).
Never store or print tokens. A token was once pasted in chat: it must be revoked; ask for a fresh one only when a push is needed.

## Purpose
Top-down traffic + city simulation for Android, inspired by Trafficity (Steam). Flutter + Flame, custom canvas rendering, microscopic traffic (IDM), lane graph, A* routing. Original assets only.

## Layout (lib/)
- main.dart: UI shell, HUD, bottom toolbar, menu, dialogs, music (audioplayers), error chip (AppErr)
- l10n.dart: UZ/RU/EN phrase table; Uzbek source text, L.t() translates by phrase
- game/road_game.dart: FlameGame; camera (pan/zoom/rotate), pointer tools, snapping, undo/redo, grid tool, save/load (SharedPreferences, 3 slots + autosave), economy tick, ideal city planner, rendering
- game/road_network.dart: nodes/roads topology, connectRoad (auto split/crossings), mergeCloseNodes, roundabout builder
- game/lane_graph.dart: directional lanes (id = roadId*8 + (fwd?0:4) + lane), connectors, building access, A* (findRoute)
- game/traffic_sim.dart: vehicles, spawning, IDM, junction grants (conflict geometry), priority roads, signals, lane changes
- game/signal.dart (fixed/adaptive), traffic_model.dart (Track/Lane/Connector/Vehicle), terrain.dart (biomes), building.dart
- test/network_test.dart (Dart unit tests, never executed), ci/debug.keystore (fixed signing key)

## Key decisions
- Road types: 0 local (1 lane/dir, 40 km/h), 1 arterial (2 lanes, 60), 2 highway (3 lanes, 100, never crosses at grade). Layer 1 = overpass/bridge (no crossing junctions; ends connect = ramps).
- Buildings connect via front point snap (screen-based 34 px radius). Access = nearest lane within 100 units; goals include all lanes of that road.
- Satisfaction = 0.37 access + 0.20 commute + 0.17 flow + 0.07 trip success + 0.11 ecology + 0.08 supply.
- idealCityOnStart = true (road_game.dart): app opens with a generated city; set false for an empty start when the game is finished.
- Coordinates: one toWorld/worldToScreen pair (math verified numerically). "Debug" button shows touch/world/back/dpr.

## Status
IMPLEMENTED AND VERIFIED (user saw it on device, said "all good" up to stage 13): terrain/biomes, camera pan/zoom, straight/curved roads, junction splitting, vehicles + queues, satisfaction + levels, heatmap, roundabout, signals, save/load, language switch.
IMPLEMENTED BUT NOT VERIFIED ON DEVICE (CI compile OK at 9c47e64): ideal city default start, priority junctions (minor road stops/yields), adaptive signal, highway type, lane changing, main menu/settings/map preview, background music, audit fixes (stale waiters, safe split), 2-lane road lane preference fix, estakada/ramps in practice.
INCOMPLETE: production chain (only shop stock/deliveries), ecology is simple, tutorial is 8 steps, tests exist but never run.
NOT IMPLEMENTED: lane add/upgrade tool, stop/yield sign objects, manual signal phase editor, 5000+ vehicles, profiling suite, accessibility beyond colors/text size.
BLOCKED (needs user): GitHub token has no `workflow` scope, so .github/workflows/build-apk.yml (remote still old) must be replaced by the user in the web UI: adds fixed signing (ci/debug.keystore), app name "RoadFlow City", launcher icons step, `flutter test`. Until then APK name is roadflow_city and each build has a new signature (uninstall old app first).

## Known risks
Gridlock cycles possible (no teleport by design; stuck vehicles reroute after 25 s). Performance unmeasured beyond debug fps/sim-ms chip. Lane-change and priority logic are untested at runtime.

## Next steps (priority)
1. Get the user's device feedback on the newest APK (Actions -> latest run -> Artifacts roadflow-apk); fix reported bugs.
2. If asked: lane add/upgrade tool, supply chain depth, profiling.
3. When the game is 100% done: set idealCityOnStart = false.

## How to work (credit rules — the chat history re-reads every turn, so keep turns cheap)
- Do not poll CI in loops. Push, say so, check CI once at the next turn.
- Do not print whole files. Use grep -n and small ranges; patch with Python str.replace + count asserts, batch several changes per push.
- No simulations over ~60 s, no giant outputs. Python tests are fine (user approved); runtime/device tests go to the user's agents as copy-ready prompts.
- Preserve user work; never rewrite history; push to main only fast-forward. Push recipe: clone with token from env, copy project, `git checkout HEAD -- .github`, commit, push, reset remote URL, delete clone.
- Before editing a file section, re-read it (anchors drift). Bracket-balance check after edits.
