import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadflow_city/game/real_roads.dart';
import 'package:roadflow_city/game/road_game.dart';
import 'package:roadflow_city/game/terrain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RoadGame> make(int biome, {double? world, bool ideal = true}) async {
    final g = RoadGame();
    g.onGameResize(Vector2(900, 600));
    await g.newMap(7, biome: biome, sandbox: false, ideal: ideal, world: world);
    return g;
  }

  testWidgets('Toshkent: markaz quruqlik, daryo/kanalda suv bor, hudud boshida 1200', (tester) async {
    await tester.runAsync(() async {
      final g = await make(Terrain.tashkent);
      expect(g.loadError, isNull);
      expect(g.worldSize, Terrain.bigSize);
      expect(g.cityCenter, const Offset(3200, 3200));
      expect(g.terrain.isWaterAt(g.cityCenter), isFalse);
      var water = 0;
      for (var y = 0; y < 6400; y += 40) {
        for (var x = 0; x < 6400; x += 40) {
          if (g.terrain.isWaterAt(Offset(x + 1.0, y + 1.0))) water++;
        }
      }
      expect(water, greaterThan(100)); // Anhor va boshqa kanallar
      expect(g.terrHalf, RoadGame.terrStart);
      expect(g.inTerritory(const Offset(3200 + 1100, 3200)), isTrue);
      expect(g.inTerritory(const Offset(3200 + 1300, 3200)), isFalse);
      for (final b in g.buildings) {
        expect(g.inTerritory(b.pos), isTrue);
      }
    });
  });

  testWidgets('barcha biomlar 6400 dunyoda yuklanadi, eski 3200 dunyoda hudud butun xarita', (tester) async {
    await tester.runAsync(() async {
      for (final biome in [0, 1, 2, 3]) {
        final g = await make(biome);
        expect(g.loadError, isNull, reason: 'biom $biome');
        expect(g.worldSize, Terrain.bigSize);
        expect(g.buildings, isNotEmpty);
        for (final b in g.buildings) {
          expect(g.terrain.isBuildableAt(b.pos), isTrue, reason: 'biom $biome');
          expect(g.inTerritory(b.pos), isTrue);
        }
      }
      final old = await make(0, world: Terrain.legacySize);
      expect(old.worldSize, Terrain.legacySize);
      expect(old.terrHalf, Terrain.legacySize / 2);
    });
  });

  testWidgets('Toshkent: haqiqiy yo\'llar yuklanadi, binolar ulangan, mashinalar yo\'l topadi', (tester) async {
    await tester.runAsync(() async {
      final all = await RealRoads.load();
      expect(all.length, greaterThan(2000));
      expect(all.every((r) => r.pts.length >= 2), isTrue);
      var shortest = 1e9;
      for (final r in all) {
        var len = 0.0;
        for (var i = 1; i < r.pts.length; i++) {
          len += (r.pts[i] - r.pts[i - 1]).distance;
        }
        if (len < shortest) shortest = len;
      }
      expect(shortest, greaterThan(14)); // juda qisqa bo'lak yo'q (polosasi mashinadan kalta bo'lib qolmasin)

      final g = await make(Terrain.tashkent);
      expect(g.net.roads.length, greaterThan(250)); // boshlang'ich hududdagi haqiqiy ko'chalar
      expect(g.noAccess, 0);
      expect(g.sim.signals, isNotEmpty);
      expect(g.net.roads.values.any((r) => r.oneWay), isTrue); // juft prospektlar bir tomonlama
      expect(g.net.roads.values.any((r) => r.layer == 1), isTrue); // kanal ustidagi ko'priklar
      // asl (tayyor) yo'llar tekin: o'chirilganda mablag' qaytmaydi
      expect(g.net.roads.values.where((r) => r.cost <= 0).length, greaterThan(250));
      g.sim.maxVehicles = 15;
      for (var t = 0.0; t < 200; t += 0.05) {
        g.sim.step(0.05);
      }
      expect(g.sim.failed, 0);
      expect(g.sim.completed, greaterThan(5));

      // hudud kengaysa, yangi halqadagi yo'llar qo'shiladi
      final before = g.net.roads.length;
      expect(g.expandTerritory(2400), isTrue);
      expect(g.net.roads.length, greaterThan(before + 200));
      expect(g.expandTerritory(2000), isFalse);
    });
  });
}
