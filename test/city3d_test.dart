import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficity/game/road_game.dart';
import 'package:trafficity/game/traffic_model.dart';
import 'package:trafficity/game3d/camera3d.dart';
import 'package:trafficity/game3d/city3d_renderer.dart';
import 'package:trafficity/game3d/city3d_view.dart';
import 'package:trafficity/game3d/city_buildings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = Size(400, 800);

  group('OrbitCamera', () {
    OrbitCamera cam({double yaw = 0, double pitch = 0.8}) =>
        OrbitCamera(targetX: 3200, targetY: 3200, distance: 500, yaw: yaw, pitch: pitch)..update(size);

    test('the target is at the centre of the screen, in front of the camera', () {
      final c = cam();
      final out = Float64List(3);
      expect(c.project(3200, 3200, 0, out), isTrue);
      expect(out[0], closeTo(200, 1e-6));
      expect(out[1], closeTo(400, 1e-6));
      expect(out[2], closeTo(500, 1e-6));
    });

    test('looking north: east is right, north is up, higher is up', () {
      final c = cam();
      final o = Float64List(3);
      c.project(3300, 3200, 0, o);
      expect(o[0], greaterThan(200)); // east
      c.project(3200, 3100, 0, o); // game y decreases to the north
      expect(o[1], lessThan(400));
      c.project(3200, 3200, 50, o);
      expect(o[1], lessThan(400));
    });

    test('yaw follows the 2D map rotation: yaw = pi/2 looks east, so north is to the left', () {
      final c = cam(yaw: 1.5707963267948966);
      final o = Float64List(3);
      c.project(3200, 3100, 0, o); // a point to the north
      expect(o[0], lessThan(200));
    });

    test('groundAt is the inverse of project for ground points', () {
      final c = cam(yaw: 0.7, pitch: 0.6);
      final o = Float64List(3);
      for (final p in const [Offset(3200, 3200), Offset(3150, 3260), Offset(3300, 3100), Offset(3250, 3230)]) {
        expect(c.project(p.dx, p.dy, 0, o), isTrue);
        final g = c.groundAt(Offset(o[0], o[1]))!;
        expect(g.dx, closeTo(p.dx, 1e-6));
        expect(g.dy, closeTo(p.dy, 1e-6));
      }
      expect(c.groundAt(const Offset(200, -5000)), isNull); // above the horizon
    });

    test('points behind the camera are rejected; pitch and distance are clamped', () {
      final c = cam();
      final o = Float64List(3);
      // 300 m behind is still in front of the tilted image plane; 3 km behind is not
      expect(c.project(c.eyeGame.dx, c.eyeGame.dy + 3000, 0, o), isFalse);
      c
        ..pitch = 3
        ..distance = 1e6
        ..update(size);
      expect(c.pitch, OrbitCamera.maxPitch);
      expect(c.distance, OrbitCamera.maxDistance);
    });
  });

  group('triangulate', () {
    double triArea(Float64List x, Float64List y, Int32List t) {
      var s = 0.0;
      for (var i = 0; i < t.length; i += 3) {
        final a = t[i], b = t[i + 1], c = t[i + 2];
        s += ((x[b] - x[a]) * (y[c] - y[a]) - (y[b] - y[a]) * (x[c] - x[a])).abs() / 2;
      }
      return s;
    }

    test('convex and concave polygons in both orientations keep their area', () {
      final shapes = <List<Offset>>[
        const [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)],
        const [Offset(0, 0), Offset(30, 0), Offset(30, 10), Offset(10, 10), Offset(10, 30), Offset(0, 30)], // L
        const [
          Offset(0, 0),
          Offset(40, 0),
          Offset(40, 30),
          Offset(25, 30),
          Offset(25, 10),
          Offset(15, 10),
          Offset(15, 30),
          Offset(0, 30),
        ], // U
      ];
      for (final s in shapes) {
        for (final pts in [s, s.reversed.toList()]) {
          final x = Float64List.fromList([for (final p in pts) p.dx]);
          final y = Float64List.fromList([for (final p in pts) p.dy]);
          final t = triangulate(x, y);
          expect(t.length, (pts.length - 2) * 3);
          expect(triArea(x, y, t), closeTo(polygonArea(pts), 1e-9), reason: '$pts');
        }
      }
    });
  });

  group('CityBuildings', () {
    final bytes = File(CityBuildings.asset).readAsBytesSync();
    final meta = jsonDecode(File('assets/map/tashkent_buildings_meta.json').readAsStringSync()) as Map;
    final city = CityBuildings.decode(ByteData.sublistView(bytes));

    test('decodes the real asset with the counts of its meta file', () {
      expect(city.length, meta['buildingCount']);
      expect(city.start.last, meta['pointCount']);
      for (var i = 0; i < city.length; i += 97) {
        expect(city.heights[i], inInclusiveRange(1.0, 60.0));
        expect(city.vertexCount(i), greaterThanOrEqualTo(3));
        expect(city.roof(i).length, (city.vertexCount(i) - 2) * 3);
      }
    });

    test('the spatial grid finds every building near a point', () {
      final near = city.near(3200, 3200, 300).toSet();
      for (var i = 0; i < city.length; i++) {
        if ((city.cx[i] - 3200).abs() <= 100 && (city.cy[i] - 3200).abs() <= 100) {
          expect(near.contains(i), isTrue);
        }
      }
      expect(near, isNotEmpty);
    });

    test('corrupt files are rejected', () {
      expect(() => CityBuildings.decode(ByteData(8)), throwsFormatException);
      expect(() => CityBuildings.decode(ByteData.sublistView(bytes, 0, bytes.length - 3)), throwsFormatException);
      final extra = Uint8List.fromList([...bytes, 0]);
      expect(() => CityBuildings.decode(ByteData.sublistView(extra)), throwsFormatException);
    });
  });

  group('renderer and view on the real Tashkent game', () {
    late RoadGame game;
    late CityBuildings city;

    Future<void> setUpGame(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        game = RoadGame();
        game.onGameResize(Vector2(size.width, size.height));
        await game.newMap(7, ideal: RoadGame.idealCityOnStart);
        for (var i = 0; i < 400; i++) {
          game.sim.step(0.05);
        }
        city = CityBuildings.decode(await rootBundle.load(CityBuildings.asset));
      });
    }

    testWidgets('a frame has ground, roads, shadows, real buildings, game buildings and vehicles', (tester) async {
      await setUpGame(tester);
      final r = City3DRenderer(game)
        ..syncFrom2D()
        ..city = city;
      final rec = ui.PictureRecorder();
      r.paint(Canvas(rec), size);
      rec.endRecording().dispose();
      final s = r.stats;
      expect(s.groundTris, greaterThan(0));
      expect(s.flatTris, greaterThan(0));
      expect(s.shadowTris, greaterThan(0));
      expect(s.itemTris, greaterThan(0));
      expect(s.cityBuildings, greaterThan(50));
      expect(s.gameBuildings, greaterThan(0));
      expect(s.vehicles, greaterThan(0));
      expect(s.hiddenCityBuildings, greaterThan(0)); // footprints under game roads / buildings are left out
      expect(s.signalPoles, greaterThan(0)); // the ready-made city has signalised junctions
      expect(s.markingTris, greaterThan(0)); // centre lines / lane separators
      expect(s.accidentMarkers, 0);
      // an active accident gets a marker
      final v = game.sim.vehicles.first;
      game.sim.accidentLog.add(Accident(v.track.pointAt(v.s), game.sim.time, game.sim.time + 30, v.id, v.id));
      r.cam
        ..targetX = v.track.pointAt(v.s).dx
        ..targetY = v.track.pointAt(v.s).dy;
      final recA = ui.PictureRecorder();
      r.paint(Canvas(recA), size);
      recA.endRecording().dispose();
      expect(r.stats.accidentMarkers, 1);
      game.sim.accidentLog.clear();
      // every camera pose renders, including looking from below a roof and from straight above
      for (final pose in const [(0.22, 80.0, 0.0), (1.45, 2600.0, 2.0), (0.5, 60.0, -3.0)]) {
        r.cam
          ..pitch = pose.$1
          ..distance = pose.$2
          ..yaw = pose.$3;
        final rec2 = ui.PictureRecorder();
        r.paint(Canvas(rec2), size);
        rec2.endRecording().dispose();
      }
    });

    testWidgets('the view starts where the 2D camera is, gestures move the camera, the close button works', (
      tester,
    ) async {
      await setUpGame(tester);
      game.cam = const Offset(3100, 3150);
      game.rot = 0.4;
      var closed = 0;
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: City3DView(game: game, onClose: () => closed++),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final state = tester.state<City3DViewState>(find.byType(City3DView));
      final cam = state.renderer.cam;
      expect(cam.targetX, 3100);
      expect(cam.targetY, 3150);
      expect(cam.yaw, closeTo(-0.4, 1e-9));
      // one finger: orbit + tilt
      final yaw0 = cam.yaw, pitch0 = cam.pitch;
      await tester.drag(find.byKey(City3DView.viewKey), const Offset(-120, 60));
      await tester.pump(const Duration(milliseconds: 50));
      expect(cam.yaw, isNot(closeTo(yaw0, 1e-6)));
      expect(cam.pitch, greaterThan(pitch0));
      // two fingers apart: zoom in
      final d0 = cam.distance;
      final center = tester.getCenter(find.byKey(City3DView.viewKey));
      final g1 = await tester.startGesture(center - const Offset(40, 0));
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      await g1.moveBy(const Offset(-60, 0));
      await g2.moveBy(const Offset(60, 0));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 50));
      expect(cam.distance, lessThan(d0));
      await tester.tap(find.byKey(City3DView.closeKey));
      expect(closed, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
