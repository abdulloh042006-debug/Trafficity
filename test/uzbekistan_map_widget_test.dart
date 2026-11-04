import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/ui/region_selector_overlay.dart';
import 'package:trafficity/ui/uzbekistan_map_view.dart';
import 'package:trafficity/world/region_borders.dart';
import 'package:trafficity/world/world_controller.dart';

const tashkent = 'uz_tashkent_city';

void main() {
  final borders = RegionBorders.fromJson(File('assets/world/uzbekistan/region_borders.json').readAsStringSync());
  final catalog = jsonDecode(File('assets/world/uzbekistan/region_catalog.json').readAsStringSync()) as Map;
  final infos = [
    for (final r in (catalog['regions'] as List).cast<Map<String, dynamic>>())
      MapRegionInfo(
        id: r['regionId'] as String,
        name: (r['names'] as Map)['uz'] as String,
        anchor: Offset(
          ((r['representativePoint'] as List)[0] as num).toDouble(),
          ((r['representativePoint'] as List)[1] as num).toDouble(),
        ),
        detailed: r['regionId'] == tashkent,
      ),
  ];
  MapRegionInfo info(String id) => infos.firstWhere((i) => i.id == id);

  Widget host({ValueChanged<String>? onTap, String? active}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: UzbekistanMapView(borders: borders, regions: infos, activeRegionId: active, onRegionTap: onTap),
        ),
      ),
    ),
  );

  Offset pxOf(WidgetTester tester, String regionId) {
    final fit = MapFit.of(borders.bounds, tester.getSize(find.byKey(UzbekistanMapView.mapKey)));
    final a = info(regionId).anchor;
    return tester.getTopLeft(find.byKey(UzbekistanMapView.mapKey)) + fit.toPx(a.dx, a.dy);
  }

  group('MapFit', () {
    test('fits the country inside the padding and round-trips lon/lat', () {
      const size = Size(400, 300);
      final fit = MapFit.of(borders.bounds, size);
      // lon/lat bounds keep the minimum latitude in `top`: (left, bottom) = north-west, (right, top) = south-east
      final nw = fit.toPx(borders.bounds.left, borders.bounds.bottom);
      final se = fit.toPx(borders.bounds.right, borders.bounds.top);
      for (final p in [nw, se]) {
        expect(p.dx, inInclusiveRange(MapFit.padding - 0.01, size.width - MapFit.padding + 0.01));
        expect(p.dy, inInclusiveRange(MapFit.padding - 0.01, size.height - MapFit.padding + 0.01));
      }
      expect(se.dx, greaterThan(nw.dx)); // east is right
      expect(se.dy, greaterThan(nw.dy)); // south is down
      final ll = fit.toLonLat(fit.toPx(66.96, 39.65));
      expect(ll.dx, closeTo(66.96, 1e-9));
      expect(ll.dy, closeTo(39.65, 1e-9));
    });
  });

  group('UzbekistanMapView', () {
    testWidgets('tapping inside a region reports exactly that region', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(host(onTap: taps.add));
      for (final id in [
        'uz_samarkand',
        'uz_bukhara',
        'uz_fergana',
        'uz_khorezm',
        'uz_karakalpakstan',
        'uz_surkhandarya',
      ]) {
        await tester.tapAt(pxOf(tester, id));
        await tester.pump();
        expect(taps.last, id);
      }
      expect(taps.length, 6);
    });

    testWidgets('the marker of the detailed region wins over the province under it', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(host(onTap: taps.add));
      await tester.tapAt(pxOf(tester, tashkent));
      await tester.pump();
      expect(taps, [tashkent]);
      // a finger-sized margin around the marker still counts; the province under the margin does not steal it
      await tester.tapAt(pxOf(tester, tashkent) + const Offset(8, 8));
      await tester.pump();
      expect(taps, [tashkent, tashkent]);
    });

    testWidgets('tapping the sea or the empty corner selects nothing', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(host(onTap: taps.add));
      final origin = tester.getTopLeft(find.byKey(UzbekistanMapView.mapKey));
      await tester.tapAt(origin + const Offset(4, 4));
      await tester.tapAt(origin + const Offset(395, 295));
      await tester.pump();
      expect(taps, isEmpty);
    });

    testWidgets('interactive map pans/zooms; a map without a callback is a static picture', (tester) async {
      await tester.pumpWidget(host(onTap: (_) {}));
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.pumpWidget(host());
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byKey(UzbekistanMapView.mapKey), findsOneWidget);
    });

    testWidgets('renders every active region without errors', (tester) async {
      for (final i in infos) {
        await tester.pumpWidget(host(onTap: (_) {}, active: i.id));
        expect(tester.takeException(), isNull, reason: i.id);
      }
    });
  });

  group('inside the selector and the overview card', () {
    Future<UzbekistanWorldController> loaded(WidgetTester tester) async {
      final c = UzbekistanWorldController();
      addTearDown(c.dispose);
      await tester.runAsync(c.initializeFromAssets);
      expect(c.borders, isNotNull);
      expect(c.bordersError, isNull);
      return c;
    }

    testWidgets('tapping the map in the selector confirms that region', (tester) async {
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      final c = await loaded(tester);
      final confirmed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UzbekistanRegionSelectorOverlay(
              worldController: c,
              onRegionConfirmed: (r) => confirmed.add(r.regionId),
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(UzbekistanMapView.mapKey), findsOneWidget);
      await tester.tapAt(pxOf(tester, 'uz_navoi'));
      await tester.pump();
      expect(confirmed, ['uz_navoi']);
      // the list is still there and its keys are unchanged
      expect(find.byKey(UzbekistanRegionSelectorOverlay.listKey), findsOneWidget);
    });

    testWidgets('the overview card shows the country map with the selected region', (tester) async {
      final c = await loaded(tester);
      c.selectRegion('uz_samarkand');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegionOverviewCard(worldController: c, onBackToDetailed: () {}, onOpenSelector: () {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(RegionOverviewCard.miniMapKey), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing); // static picture on the card
      expect(find.byType(Icon), findsWidgets); // buttons keep their icons
    });

    testWidgets('broken outlines never break the region list', (tester) async {
      final c = UzbekistanWorldController();
      addTearDown(c.dispose);
      c.loadFromCatalogJson(File('assets/world/uzbekistan/region_catalog.json').readAsStringSync());
      expect(() => c.loadBordersJson('{"schema":"x"}'), throwsFormatException);
      expect(c.borders, isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UzbekistanRegionSelectorOverlay(worldController: c, onRegionConfirmed: (_) {}, onClose: () {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(UzbekistanMapView.mapKey), findsNothing);
      expect(find.byKey(UzbekistanRegionSelectorOverlay.listKey), findsOneWidget);
    });
  });
}
