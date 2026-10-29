
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadflow_city/game/rail.dart';
import 'package:roadflow_city/game/rail_draw.dart';
import 'package:roadflow_city/game/road_game.dart';
import 'package:roadflow_city/game/terrain.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RoadGame> make(int biome) async {
    final g = RoadGame();
    g.onGameResize(Vector2(900, 600));
    await g.newMap(7, biome: biome, sandbox: true, ideal: false);
    g.terrHalf = 2800;
    return g;
  }

  /// Haqiqiy kiritish yo'li: ekran koordinatalarida sudrab chizish.
  void drag(RoadGame g, Offset a, Offset b) {
    g.cam = (a + b) / 2;
    g.zoom = 0.5;
    g.pointerDown(1, g.worldToScreen(a));
    g.pointerMove(1, g.worldToScreen(b));
    g.pointerUp(1);
  }

  void tap(RoadGame g, Offset w) {
    g.cam = w;
    g.pointerDown(1, g.worldToScreen(w));
    g.pointerUp(1);
  }

  Offset? findCanal(RoadGame g) {
    for (var y = 2700.0; y < 4200; y += 20) {
      for (var x = 2100.0; x < 4000; x += 2) {
        final p = Offset(x, y);
        if (g.terrain.isWaterAt(p) &&
            !g.terrain.isWaterAt(Offset(x - 150, y)) &&
            !g.terrain.isWaterAt(Offset(x + 150, y)) &&
            !g.terrain.isWaterAt(Offset(x - 280, y)) &&
            !g.terrain.isWaterAt(Offset(x + 280, y))) {
          return p;
        }
      }
    }
    return null;
  }

  testWidgets('Toshkent: kanal ustiga temir yo\'l ko\'prigi, stansiyalar, poyezd, bekor qilish, saqlash', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final g = await make(Terrain.tashkent);
      final w = findCanal(g)!;
      g.roadLayer = 2; // temir yo'l
      g.tool = Tool.straight;
      final a = Offset(w.dx - 280, w.dy), b = Offset(w.dx + 280, w.dy);
      drag(g, a, b);
      expect(g.railNet.roads.length, 1);
      final an = RailVis.analyze(g.railNet.roads.values.first.pts, 0, g.terrain);
      expect(an.hasBridge, isTrue);
      expect(an.cost, greaterThan(560 * RailConst.costGround)); // ko'prik qimmatroq
      expect(g.net.roads, isEmpty); // oddiy yo'l tarmog'iga tegilmadi

      // ikkita stansiya
      g.tool = Tool.station;
      tap(g, Offset(w.dx - 200, w.dy));
      tap(g, Offset(w.dx + 200, w.dy));
      expect(g.rail.stations.length, 2);
      expect(g.rail.stations.every((s) => s.active), isTrue);
      expect(g.rail.trains.length, 1);
      // juda yaqin stansiya rad etiladi
      tap(g, Offset(w.dx + 250, w.dy));
      expect(g.rail.stations.length, 2);
      // suv ustiga stansiya qo'yib bo'lmaydi
      tap(g, w);
      expect(g.rail.stations.length, 2);

      for (var t = 0.0; t < 90; t += 0.05) {
        g.rail.step(0.05);
      }
      expect(g.rail.trips, greaterThanOrEqualTo(2));

      // bekor qilish / qaytarish
      final budgetNow = g.budget;
      g.undo();
      expect(g.rail.stations.length, 1);
      g.undo();
      expect(g.rail.stations.length, 0);
      g.redo();
      g.redo();
      expect(g.rail.stations.length, 2);
      expect(g.railNet.roads.length, greaterThanOrEqualTo(1));
      expect(g.budget, budgetNow);

      // saqlash va yuklash
      expect(await g.save(slot: 1), isTrue);
      final g2 = RoadGame();
      g2.onGameResize(Vector2(900, 600));
      expect(await g2.load(slot: 1), isTrue);
      expect(g2.rail.stations.length, 2);
      expect(g2.railNet.roads.length, g.railNet.roads.length);
      expect(g2.rail.trains.length, 1);

      // o'chirish asbobi: yo'lni o'chirsa, stansiyalar ham ketadi
      g.tool = Tool.erase;
      tap(g, Offset(w.dx - 270, w.dy)); // chap bo'lak
      tap(g, Offset(w.dx - 100, w.dy)); // o'rta bo'lak (ko'prik)
      tap(g, Offset(w.dx + 270, w.dy)); // o'ng bo'lak
      expect(g.railNet.roads, isEmpty);
      expect(g.rail.stations, isEmpty);
      expect(g.rail.trains, isEmpty);
    });
  });

  testWidgets('Tog\' biomida tunnel: tog\' orqali o\'tadi va qimmatroq', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final g = await make(2);
      // tog'dan o'tuvchi to'g'ri chiziq: uchlari tog'siz va suvsiz, o'rtasida tog' bor
      Offset? a, b;
      for (var y = 2200.0; y < 4200 && a == null; y += 40) {
        for (var x = 2200.0; x < 3000 && a == null; x += 20) {
          final p = Offset(x, y), q = Offset(x + 500, y);
          if (g.terrain.isWaterAt(p) || g.terrain.isWaterAt(q) || g.terrain.isMountainAt(p) || g.terrain.isMountainAt(q)) continue;
          var mt = 0, water = 0;
          for (var s = 0.0; s <= 500; s += 6) {
            final c = Offset(x + s, y);
            if (g.terrain.isMountainAt(c)) mt++;
            if (g.terrain.isWaterAt(c)) water++;
          }
          if (mt >= 12 && water == 0) {
            a = p;
            b = q;
          }
        }
      }
      expect(a, isNotNull, reason: "tog'li chiziq topilmadi");
      g.roadLayer = 2;
      g.tool = Tool.straight;
      drag(g, a!, b!);
      expect(g.railNet.roads.length, 1);
      final an = RailVis.analyze(g.railNet.roads.values.first.pts, 0, g.terrain);
      expect(an.hasTunnel, isTrue);
      expect(an.longestTunnel, greaterThan(60));
      expect(g.railVis.runs.values.first.any((r) => r.cls == RailCls.tunnel), isTrue);
    });
  });

  testWidgets('temir yo\'l binoga tegmaydi va hudud tashqarisiga qurilmaydi; yer osti rejimida bino ostidan o\'tadi', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final g = await make(Terrain.tashkent);
      g.terrHalf = 1200;
      final c = g.worldCenter;
      g.roadLayer = 2;
      g.tool = Tool.straight;
      drag(g, Offset(c.dx + 1100, c.dy + 900), Offset(c.dx + 1500, c.dy + 900)); // hududdan chiqadi
      expect(g.railNet.roads, isEmpty);
      // bino ustidan
      expect(g.buildings, isNotEmpty);
      final b = g.buildings.first;
      Offset? ok;
      for (final d in [const Offset(-150, 0), const Offset(150, 0)]) {
        final p = b.pos + d;
        if (!g.terrain.isWaterAt(p) && g.inTerritory(p, 40)) ok = p;
      }
      expect(ok, isNotNull);
      final dx = (ok!.dx - b.pos.dx).sign;
      drag(g, Offset(b.pos.dx - dx * 150, b.pos.dy), Offset(b.pos.dx + dx * 150, b.pos.dy));
      expect(g.railNet.roads, isEmpty); // yer ustida bino ustidan o'tolmaydi
      g.roadLayer = 3; // yer osti
      drag(g, Offset(b.pos.dx - dx * 150, b.pos.dy), Offset(b.pos.dx + dx * 150, b.pos.dy));
      expect(g.railNet.roads.length, 1);
      expect(g.railNet.roads.values.first.layer, 1);
    });
  });
}
