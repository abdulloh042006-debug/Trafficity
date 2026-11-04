import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficity/game/road_game.dart';
import 'package:trafficity/l10n.dart';
import 'package:trafficity/main.dart';
import 'package:trafficity/ui/region_selector_overlay.dart';
import 'package:trafficity/ui/uzbekistan_hud_button.dart';
import 'package:trafficity/world/multi_scale_lod_controller.dart';
import 'package:trafficity/world/world_controller.dart';

const tashkent = 'uz_tashkent_city';

/// audioplayers opens platform channels (one per player id) that do not exist in `flutter test`.
/// Answer every audioplayers call with a null success so the real screen can be built; all other channels
/// keep their normal handlers.
void mockPlatform() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.allMessagesHandler = (channel, handler, message) async {
    if (channel.startsWith('xyz.luan/audioplayers')) {
      return const StandardMethodCodec().encodeSuccessEnvelope(null);
    }
    return handler?.call(message);
  };
  addTearDown(() => messenger.allMessagesHandler = null);
}

/// Boots the real app; the main menu is closed so the HUD and the game are interactive.
Future<void> bootGame(WidgetTester tester, {int lang = 0}) async {
  SharedPreferences.setMockInitialValues({'lang': lang});
  mockPlatform();
  L.lang = lang;
  tester.view.physicalSize = const Size(1080, 2160);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const RoadFlowApp());
  await settle(tester, 12);
  await tester.tap(find.text(lang == 1 ? 'Продолжить' : 'Davom etish'));
  await tester.pump(const Duration(milliseconds: 100));
  await settle(tester, 6);
}

/// The game ticks forever (Flame loop) so `pumpAndSettle` never returns: pump a fixed number of frames while
/// letting real async work (asset loading, terrain isolate) finish.
Future<void> settle(WidgetTester tester, [int rounds = 5]) async {
  await tester.runAsync(() async {
    for (var i = 0; i < rounds; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}

Future<void> frames(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

dynamic screen(WidgetTester tester) => tester.state(find.byType(GameScreen));

Future<void> openSelector(WidgetTester tester) async {
  await tester.tap(find.byKey(UzbekistanHudButton.buttonKey));
  await frames(tester);
  expect(find.byKey(UzbekistanRegionSelectorOverlay.listKey), findsOneWidget);
}

Future<void> tapRegion(WidgetTester tester, String regionId) async {
  final tile = find.byKey(UzbekistanRegionSelectorOverlay.tileKey(regionId));
  await tester.scrollUntilVisible(
    tile,
    120,
    scrollable: find.descendant(
      of: find.byKey(UzbekistanRegionSelectorOverlay.listKey),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.ensureVisible(tile); // built (cache extent) is not the same as on screen
  await frames(tester, 2);
  await tester.tap(tile);
  await frames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UzbekistanWorldController', () {
    test('loads the 14-region catalog once, Tashkent active and detailed', () async {
      final c = UzbekistanWorldController();
      addTearDown(c.dispose);
      expect(c.loadState, WorldLoadState.idle);
      final a = c.initializeFromAssets();
      final b = c.initializeFromAssets();
      expect(identical(a, b), isTrue); // idempotent: one load
      await a;
      expect(c.loadState, WorldLoadState.ready);
      expect(c.regions.length, 14);
      expect(c.activeRegion!.regionId, tashkent);
      expect(c.isActiveDetailed, isTrue);
      expect(c.regions.where((r) => c.readinessOf(r).name == 'installedDetailed').map((r) => r.regionId), [tashkent]);
    });

    test('unknown region is rejected and changes nothing; known region moves the floating origin', () async {
      final c = UzbekistanWorldController();
      addTearDown(c.dispose);
      await c.initializeFromAssets();
      expect(c.selectRegion('uz_atlantis'), isFalse);
      expect(c.activeRegion!.regionId, tashkent);
      expect(c.selectRegion('uz_samarkand'), isTrue);
      final r = c.activeRegion!;
      expect(c.coordinateSystem.floatingOrigin.lon, r.representativePoint.lon);
      expect(c.coordinateSystem.floatingOrigin.lat, r.representativePoint.lat);
      expect(c.isActiveDetailed, isFalse);
    });

    test('LOD follows zoom, and an overview-only region never reaches level 3 or 4', () async {
      final c = UzbekistanWorldController();
      addTearDown(c.dispose);
      await c.initializeFromAssets();
      expect(c.updateCamera(zoom: 0.1), GeographicalDetailLevel.level1CountryOverview);
      expect(c.updateCamera(zoom: 0.8), GeographicalDetailLevel.level3CityView2D);
      expect(c.updateCamera(zoom: 2.0, is3D: true), GeographicalDetailLevel.level4DetailedUrban3D);
      c.selectRegion('uz_bukhara');
      expect(c.lodLevel, GeographicalDetailLevel.level2RegionalView);
      expect(c.updateCamera(zoom: 3.0, is3D: true), GeographicalDetailLevel.level2RegionalView);
    });

    test('listeners are notified on level changes only, and not after dispose', () async {
      final c = UzbekistanWorldController();
      await c.initializeFromAssets();
      var n = 0;
      c.addListener(() => n++);
      c.updateCamera(zoom: 0.8);
      final base = n;
      c.updateCamera(zoom: 0.9); // same level: no notification
      expect(n, base);
      c.updateCamera(zoom: 0.1); // level changes
      expect(n, base + 1);
      c.dispose();
      expect(() => c.selectRegion('uz_samarkand'), returnsNormally); // guarded notify
    });

    test('a broken or empty catalog is reported, not swallowed', () {
      final c = UzbekistanWorldController();
      addTearDown(c.dispose);
      expect(() => c.loadFromCatalogJson('not json'), throwsFormatException);
      expect(() => c.loadFromCatalogJson('{"regions": []}'), throwsFormatException);
    });
  });

  group('selector inside the real game', () {
    testWidgets('the HUD shows the region button with the active region name', (tester) async {
      await bootGame(tester);
      expect(find.byKey(UzbekistanHudButton.buttonKey), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(UzbekistanHudButton.buttonKey), matching: find.text('Toshkent shahri')),
        findsOneWidget,
      );
      // existing HUD is intact
      expect(find.textContaining("Mablag'"), findsWidgets);
      expect(find.text('Menyu'), findsOneWidget);
    });

    testWidgets('opens with all 14 regions and closes; the game stays usable', (tester) async {
      await bootGame(tester);
      await openSelector(tester);
      final world = screen(tester).world as UzbekistanWorldController;
      expect(world.regions.length, 14);
      expect(find.byKey(UzbekistanRegionSelectorOverlay.tileKey(tashkent)), findsOneWidget);
      await tester.tap(find.byKey(UzbekistanRegionSelectorOverlay.closeKey));
      await frames(tester);
      expect(find.byKey(UzbekistanRegionSelectorOverlay.listKey), findsNothing);
      expect(screen(tester).game.menuOpen, isFalse); // still running
      expect(find.byKey(RegionOverviewCard.cardKey), findsNothing);
    });

    testWidgets('every one of the 14 regions can be selected; only Tashkent stays detailed', (tester) async {
      await bootGame(tester);
      final world = screen(tester).world as UzbekistanWorldController;
      final ids = world.regions.map((r) => r.regionId).toList();
      expect(ids.length, 14);
      for (final id in ids) {
        await openSelector(tester);
        await tapRegion(tester, id);
        expect(world.activeRegion!.regionId, id, reason: id);
        expect(find.byKey(UzbekistanRegionSelectorOverlay.listKey), findsNothing, reason: id);
        final overview = find.byKey(RegionOverviewCard.cardKey);
        if (id == tashkent) {
          expect(overview, findsNothing);
          expect(screen(tester).game.menuOpen, isFalse);
          expect(screen(tester).game.regionDetailed, isTrue);
        } else {
          expect(overview, findsOneWidget, reason: id);
          expect(screen(tester).game.menuOpen, isTrue, reason: 'game is paused behind the overview card');
          expect(screen(tester).game.regionDetailed, isFalse);
          expect(screen(tester).game.activeRegionId, id);
          // the card names the selected region and says it is overview-only
          expect(find.text(world.activeRegion!.names.uz), findsWidgets);
          expect(find.textContaining("Faqat umumiy ko'rinish"), findsWidgets);
          await tester.tap(find.byKey(RegionOverviewCard.backKey)); // back to the playable map
          await frames(tester);
          expect(find.byKey(RegionOverviewCard.cardKey), findsNothing);
          expect(world.activeRegion!.regionId, tashkent);
          expect(screen(tester).game.menuOpen, isFalse);
        }
      }
    });

    testWidgets('loading a save from the menu leaves the overview card and returns to the saved region', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      late String raw;
      await tester.runAsync(() async {
        final g = RoadGame();
        g.onGameResize(Vector2(900, 600));
        await g.newMap(7, biome: 0, sandbox: true, ideal: false, realRoads: false);
        await g.save(slot: 1);
        raw = (await SharedPreferences.getInstance()).getString('save1')!;
      });
      SharedPreferences.setMockInitialValues({'lang': 0, 'save1': raw});
      mockPlatform();
      L.lang = 0;
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const RoadFlowApp());
      await settle(tester, 12);

      final world = screen(tester).world as UzbekistanWorldController;
      expect(world.selectRegion('uz_samarkand'), isTrue); // the player was looking at an overview-only region
      await frames(tester);
      expect(find.byKey(RegionOverviewCard.cardKey), findsOneWidget);

      await tester.tap(find.text("Saqlangan o'yinlar"));
      await settle(tester, 3);
      await tester.tap(find.byTooltip('Yuklash').at(1)); // slot 1
      await settle(tester, 12);

      expect(world.activeRegion!.regionId, tashkent);
      expect(find.byKey(RegionOverviewCard.cardKey), findsNothing);
      expect(screen(tester).game.regionDetailed, isTrue);
      expect(screen(tester).game.loadedNational.regionId, tashkent);
      expect(screen(tester).game.menuOpen, isFalse);
    });

    testWidgets('overview card can reopen the selector', (tester) async {
      await bootGame(tester);
      await openSelector(tester);
      await tapRegion(tester, 'uz_khorezm');
      expect(find.byKey(RegionOverviewCard.cardKey), findsOneWidget);
      await tester.tap(find.byKey(RegionOverviewCard.regionsKey));
      await frames(tester);
      expect(find.byKey(UzbekistanRegionSelectorOverlay.listKey), findsOneWidget);
      await tapRegion(tester, tashkent);
      expect(find.byKey(RegionOverviewCard.cardKey), findsNothing);
    });

    testWidgets('labels follow the language (ru)', (tester) async {
      await bootGame(tester, lang: 1);
      expect(
        find.descendant(of: find.byKey(UzbekistanHudButton.buttonKey), matching: find.text('г. Ташкент')),
        findsOneWidget,
      );
      await openSelector(tester);
      expect(find.text('Регионы Узбекистана'), findsOneWidget);
      await tapRegion(tester, 'uz_samarkand');
      expect(find.text('Самаркандская область'), findsWidgets);
      expect(find.textContaining('Только общий обзор'), findsWidgets);
      L.lang = 0;
    });

    testWidgets('disposing the screen removes listeners: no errors after it is gone', (tester) async {
      await bootGame(tester);
      final world = screen(tester).world as UzbekistanWorldController;
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester);
      expect(tester.takeException(), isNull);
      // the controller was disposed with the screen; late calls must not throw
      expect(() => world.selectRegion('uz_samarkand'), returnsNormally);
    });
  });
}
