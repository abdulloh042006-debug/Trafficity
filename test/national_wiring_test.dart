import 'dart:convert';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficity/game/road_game.dart';
import 'package:trafficity/game/terrain.dart';
import 'package:trafficity/l10n.dart';
import 'package:trafficity/ui/region_selector_overlay.dart';
import 'package:trafficity/world/national_save_manager.dart';
import 'package:trafficity/world/world_controller.dart';

const tashkent = 'uz_tashkent_city';

/// The national save envelope, the region restore and the architecture-profile note, wired into the real game.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RoadGame> makeGame({int biome = 0}) async {
    final g = RoadGame();
    g.onGameResize(Vector2(900, 600));
    await g.newMap(7, biome: biome, sandbox: true, ideal: false, realRoads: false);
    return g;
  }

  group('NationalSaveV3.fromGameState', () {
    test('real Tashkent world has a WGS84 camera at the origin; the envelope round-trips', () {
      final s = NationalSaveV3.fromGameState(
        regionId: tashkent,
        biome: Terrain.tashkent,
        worldSize: 6400,
        camX: 3200,
        camY: 3200,
        zoom: 0.8,
      );
      expect(s.cameraPosition!.lon, closeTo(69.279737, 1e-6));
      expect(s.cameraPosition!.lat, closeTo(41.311081, 1e-6));
      expect(s.cameraZoom, 0.8);
      expect(s.migratedFromVersion, NationalSaveV3.currentVersion);
      final back = NationalSaveV3.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.regionId, tashkent);
      expect(back.cameraPosition!.lat, closeTo(s.cameraPosition!.lat, 1e-9));
    });

    test('a procedural biome has no geographic camera (nothing is invented)', () {
      final s = NationalSaveV3.fromGameState(
        regionId: tashkent,
        biome: 1,
        worldSize: 3200,
        camX: 1000,
        camY: 1000,
        zoom: 1,
      );
      expect(s.cameraPosition, isNull);
      expect(s.toJson().containsKey('camera'), isFalse);
    });
  });

  group('RoadGame save/load carries the envelope', () {
    testWidgets('save writes an additive nat key; load restores it; the game save stays v2', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        final g = await makeGame();
        expect(await g.save(slot: 1), isTrue);
        final raw = (await SharedPreferences.getInstance()).getString('save1')!;
        final m = jsonDecode(raw) as Map<String, dynamic>;
        expect(m['v'], 2); // outer format unchanged: older builds still read it
        final nat = m['nat'] as Map<String, dynamic>;
        expect(nat['v'], 3);
        expect(nat['region'], tashkent);
        expect(nat.containsKey('camera'), isFalse); // biome 0 is not the real Tashkent map

        final g2 = await makeGame();
        expect(await g2.load(slot: 1), isTrue);
        expect(g2.loadedNational!.regionId, tashkent);
        expect(g2.loadedNational!.saveFormatVersion, 3);
      });
    });

    testWidgets('an overview-only selection never relabels the game state that is saved', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        final g = await makeGame();
        g.setRegion('uz_samarkand', detailed: false); // player looks at the Samarkand overview card
        expect(g.activeRegionId, 'uz_samarkand');
        expect(g.gameRegionId, tashkent);
        await g.save(slot: 2);
        final m = jsonDecode((await SharedPreferences.getInstance()).getString('save2')!) as Map<String, dynamic>;
        expect((m['nat'] as Map)['region'], tashkent);
      });
    });

    testWidgets('old saves without nat, and saves with a broken nat, still load', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        final g = await makeGame();
        await g.save(slot: 1);
        final sp = await SharedPreferences.getInstance();
        final m = jsonDecode(sp.getString('save1')!) as Map<String, dynamic>;

        final old = Map<String, dynamic>.of(m)..remove('nat');
        await sp.setString('save1', jsonEncode(old));
        final a = await makeGame();
        expect(await a.load(slot: 1), isTrue);
        expect(a.loadedNational, isNull);

        // A well-formed envelope naming another region is data, not an instruction: the game keeps its own region.
        await sp.setString(
          'save1',
          jsonEncode(Map<String, dynamic>.of(m)..['nat'] = {'v': 3, 'region': 'uz_samarkand', 'zoom': 1.0}),
        );
        final t = await makeGame();
        expect(await t.load(slot: 1), isTrue);
        expect(t.loadedNational!.regionId, 'uz_samarkand');
        expect(t.gameRegionId, tashkent);

        for (final broken in <Object?>[
          'garbage',
          {'v': 9, 'region': tashkent},
          {'v': 3},
          {
            'v': 3,
            'region': tashkent,
            'camera': [999, 999],
          },
        ]) {
          await sp.setString('save1', jsonEncode(Map<String, dynamic>.of(m)..['nat'] = broken));
          final b = await makeGame();
          expect(await b.load(slot: 1), isTrue, reason: '$broken');
          expect(b.loadedNational, isNull, reason: '$broken');
        }
      });
    });
  });

  group('UzbekistanWorldController.restoreDetailedRegion', () {
    test('restores Tashkent from another region; refuses unknown and overview-only regions', () async {
      final c = UzbekistanWorldController();
      addTearDown(c.dispose);
      await c.initializeFromAssets();
      expect(c.restoreDetailedRegion('uz_atlantis'), isFalse);
      expect(c.restoreDetailedRegion('uz_samarkand'), isFalse); // a tampered save must not cover the game
      expect(c.activeRegion!.regionId, tashkent);

      c.selectRegion('uz_samarkand');
      expect(c.isActiveDetailed, isFalse);
      expect(c.restoreDetailedRegion(tashkent), isTrue);
      expect(c.activeRegion!.regionId, tashkent);
      expect(c.isActiveDetailed, isTrue);
      expect(c.restoreDetailedRegion(tashkent), isTrue); // already active: no change
    });
  });

  group('architecture profile on the overview card', () {
    testWidgets('shows the profile and says that no profile visuals exist yet', (tester) async {
      L.lang = 2;
      addTearDown(() => L.lang = 0);
      final c = UzbekistanWorldController();
      addTearDown(c.dispose);
      await tester.runAsync(c.initializeFromAssets);
      c.selectRegion('uz_samarkand');
      await tester.pumpWidget(
        MaterialApp(
          home: RegionOverviewCard(
            worldController: c,
            languageCode: 'en',
            onBackToDetailed: () {},
            onOpenSelector: () {},
          ),
        ),
      );
      expect(find.textContaining('Architecture profile: Samarkand Timurid heritage (no visuals yet)'), findsOneWidget);
    });
  });
}
