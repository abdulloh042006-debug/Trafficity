import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/world/architecture_profile_engine.dart';
import 'package:trafficity/world/geo_coordinate_system.dart';
import 'package:trafficity/world/multi_scale_lod_controller.dart';
import 'package:trafficity/world/national_save_manager.dart';
import 'package:trafficity/world/road_graph_linker.dart';

GeographicalDetailLevel lod(double zoom, {bool is3d = false, bool pack = true}) =>
    MultiScaleLodController.levelFor(cameraZoom: zoom, is3DPerspectiveActive: is3d, regionHasDetailedPack: pack);

void main() {
  group('LOD', () {
    test('threshold constants are ordered and inside the game zoom range 0.12..3.0', () {
      expect(MultiScaleLodController.regionalZoomThreshold, lessThan(MultiScaleLodController.cityZoomThreshold));
      expect(MultiScaleLodController.cityZoomThreshold, lessThan(MultiScaleLodController.urban3dZoomThreshold));
      expect(MultiScaleLodController.regionalZoomThreshold, greaterThan(0.12));
      expect(MultiScaleLodController.urban3dZoomThreshold, lessThan(3.0));
    });

    test('with a detailed package: boundaries in 2D', () {
      expect(lod(0.12), GeographicalDetailLevel.level1CountryOverview);
      expect(lod(0.1999), GeographicalDetailLevel.level1CountryOverview);
      expect(lod(0.2), GeographicalDetailLevel.level2RegionalView);
      expect(lod(0.4999), GeographicalDetailLevel.level2RegionalView);
      expect(lod(0.5), GeographicalDetailLevel.level3CityView2D);
      expect(lod(1.2), GeographicalDetailLevel.level3CityView2D);
      expect(lod(3.0), GeographicalDetailLevel.level3CityView2D);
    });

    test('with a detailed package: boundaries in 3D', () {
      expect(lod(0.1999, is3d: true), GeographicalDetailLevel.level1CountryOverview);
      expect(lod(0.4999, is3d: true), GeographicalDetailLevel.level2RegionalView);
      expect(lod(0.5, is3d: true), GeographicalDetailLevel.level3CityView2D);
      expect(lod(1.1999, is3d: true), GeographicalDetailLevel.level3CityView2D);
      expect(lod(1.2, is3d: true), GeographicalDetailLevel.level4DetailedUrban3D);
      expect(lod(3.0, is3d: true), GeographicalDetailLevel.level4DetailedUrban3D);
    });

    test('without a detailed package the region never reaches level 3 or 4', () {
      for (final z in [0.12, 0.2, 0.5, 0.8, 1.2, 2.0, 3.0]) {
        for (final is3d in [false, true]) {
          final level = lod(z, is3d: is3d, pack: false);
          expect(
            level == GeographicalDetailLevel.level1CountryOverview || level == GeographicalDetailLevel.level2RegionalView,
            isTrue,
            reason: 'zoom=$z 3d=$is3d gave $level',
          );
        }
      }
      expect(lod(0.1, pack: false), GeographicalDetailLevel.level1CountryOverview);
      expect(lod(2.0, is3d: true, pack: false), GeographicalDetailLevel.level2RegionalView);
    });

    test('non-finite zoom falls back safely', () {
      expect(lod(double.nan), GeographicalDetailLevel.level3CityView2D);
      expect(lod(double.nan, pack: false), GeographicalDetailLevel.level2RegionalView);
    });

    test('controller stores the evaluated level and reports detail', () {
      final c = MultiScaleLodController();
      expect(c.activeLevel, GeographicalDetailLevel.level2RegionalView);
      c.evaluateFromCamera(cameraZoom: 2.0, is3DPerspectiveActive: true, regionHasDetailedPack: true);
      expect(c.activeLevel, GeographicalDetailLevel.level4DetailedUrban3D);
      expect(c.isDetailed, isTrue);
      c.evaluateFromCamera(cameraZoom: 2.0, is3DPerspectiveActive: true, regionHasDetailedPack: false);
      expect(c.isDetailed, isFalse);
    });
  });

  group('national save v3', () {
    test('v3 serialisation round trip keeps region, camera and zoom', () {
      const save = NationalSaveV3(
        regionId: 'uz_samarkand',
        cameraPosition: Wgs84Coord(lon: 66.9597, lat: 39.6547),
        cameraZoom: 0.75,
        migratedFromVersion: 2,
      );
      final json = save.toJson();
      expect(json['v'], 3);
      expect(json['camera'], [66.9597, 39.6547]);
      final back = NationalSaveV3.fromJson(json);
      expect(back.saveFormatVersion, 3);
      expect(back.countryId, 'UZ');
      expect(back.regionId, 'uz_samarkand');
      expect(back.cameraPosition!.lon, 66.9597);
      expect(back.cameraPosition!.lat, 39.6547);
      expect(back.cameraZoom, 0.75);
      expect(back.migratedFromVersion, 2);
    });

    test('a v3 save without a camera round-trips with a null camera', () {
      final back = NationalSaveV3.fromJson(const NationalSaveV3(regionId: 'uz_bukhara').toJson());
      expect(back.cameraPosition, isNull);
    });

    test('legacy v2 Tashkent save: centre camera becomes the Tashkent origin', () {
      final legacy = {'v': 2, 'seed': 1, 'budget': 10.0, 'biome': 4, 'ws': 6400.0, 'cam': [3200.0, 3200.0], 'zoom': 0.9};
      final save = NationalSaveV3.fromLegacy(legacy);
      expect(save.regionId, 'uz_tashkent_city');
      expect(save.migratedFromVersion, 2);
      expect(save.cameraZoom, 0.9);
      expect(save.cameraPosition!.lon, closeTo(NationalCoordinateSystem.legacyTashkentOrigin.lon, 1e-9));
      expect(save.cameraPosition!.lat, closeTo(NationalCoordinateSystem.legacyTashkentOrigin.lat, 1e-9));
    });

    test('legacy v1 Tashkent save: a camera east and south of centre converts with the right signs', () {
      final legacy = {'v': 1, 'biome': 4, 'cam': [3400.0, 3400.0], 'zoom': 1.0};
      final save = NationalSaveV3.fromLegacy(legacy);
      expect(save.migratedFromVersion, 1);
      expect(save.cameraPosition!.lon, greaterThan(NationalCoordinateSystem.legacyTashkentOrigin.lon));
      expect(save.cameraPosition!.lat, lessThan(NationalCoordinateSystem.legacyTashkentOrigin.lat));
    });

    test('legacy procedural-biome save gets no invented geographic camera', () {
      final save = NationalSaveV3.fromLegacy({'v': 2, 'biome': 1, 'ws': 3200.0, 'cam': [100.0, 200.0], 'zoom': 1.0});
      expect(save.cameraPosition, isNull);
      expect(save.regionId, 'uz_tashkent_city');
    });

    test('missing camera values are tolerated; non-finite camera values are ignored', () {
      expect(NationalSaveV3.fromLegacy({'v': 2, 'biome': 4}).cameraPosition, isNull);
      expect(NationalSaveV3.fromLegacy({'v': 2, 'biome': 4, 'cam': [double.nan, 1.0]}).cameraPosition, isNull);
      expect(NationalSaveV3.fromLegacy({'v': 2, 'biome': 4, 'cam': [1.0]}).cameraPosition, isNull);
      expect(NationalSaveV3.fromLegacy({'v': 2, 'biome': 4, 'cam': 'x'}).cameraPosition, isNull);
    });

    test('the legacy input map is not modified', () {
      final legacy = {'v': 2, 'biome': 4, 'cam': [3200.0, 3200.0], 'zoom': 1.0};
      NationalSaveV3.fromLegacy(legacy);
      expect(legacy['v'], 2);
      expect(legacy['cam'], [3200.0, 3200.0]);
    });

    test('malformed input is rejected with a typed error', () {
      expect(() => NationalSaveV3.fromJson('nope'), throwsA(isA<SaveFormatException>()));
      expect(() => NationalSaveV3.fromJson({'v': 3}), throwsA(isA<SaveFormatException>().having((e) => e.code, 'code', 'missing_field')));
      expect(() => NationalSaveV3.fromJson({'v': 3, 'region': 'uz_x', 'camera': [1]}), throwsA(isA<SaveFormatException>()));
      expect(() => NationalSaveV3.fromJson({'v': 3, 'region': 'uz_x', 'camera': [999.0, 0.0]}), throwsA(isA<SaveFormatException>()));
      expect(() => NationalSaveV3.fromLegacy(null), throwsA(isA<SaveFormatException>()));
      expect(() => NationalSaveV3.parseAny(<String, dynamic>{}), throwsA(isA<SaveFormatException>()));
    });

    test('unknown versions are rejected', () {
      for (final v in [0, 4, 99, -1]) {
        expect(
          () => NationalSaveV3.parseAny({'v': v}),
          throwsA(isA<SaveFormatException>().having((e) => e.code, 'code', 'unknown_version')),
          reason: 'v=$v',
        );
      }
      expect(() => NationalSaveV3.fromLegacy({'v': 3}), throwsA(isA<SaveFormatException>()));
    });

    test('parseAny dispatches v1, v2 and v3', () {
      expect(NationalSaveV3.parseAny({'v': 1, 'biome': 4, 'cam': [3200.0, 3200.0]}).migratedFromVersion, 1);
      expect(NationalSaveV3.parseAny({'v': 2, 'biome': 4, 'cam': [3200.0, 3200.0]}).migratedFromVersion, 2);
      expect(NationalSaveV3.parseAny({'v': 3, 'region': 'uz_bukhara'}).regionId, 'uz_bukhara');
    });

    test('migrator returns null (caller keeps the old save) when migration fails', () {
      expect(NationalSaveMigrator.tryMigrate({'v': 99}), isNull);
      expect(NationalSaveMigrator.tryMigrate('garbage'), isNull);
      final ok = NationalSaveMigrator.tryMigrate({'v': 2, 'biome': 4, 'cam': [3200.0, 3200.0]});
      expect(ok, isNotNull);
      expect(ok!['v'], 3);
    });
  });

  group('road graph linker', () {
    const wgs = Wgs84Coord(lon: 69.3, lat: 41.3);
    PortalNode portal(String id, String a, String b, {Wgs84Coord pos = wgs}) =>
        PortalNode(portalId: id, globalWayId: 'way_$id', position: pos, sourceChunkId: a, destinationChunkId: b);

    test('chunk load and unload are tracked', () {
      final l = RoadGraphLinker();
      expect(l.isChunkLoaded('c0'), isFalse);
      l.onChunkLoaded('c0');
      expect(l.isChunkLoaded('c0'), isTrue);
      l.onChunkUnloaded('c0');
      expect(l.isChunkLoaded('c0'), isFalse);
    });

    test('portal registration and lookup', () {
      final l = RoadGraphLinker()..registerPortal(portal('p1', 'c0', 'c1'));
      expect(l.portalCount, 1);
      expect(l.portalById('p1')!.globalWayId, 'way_p1');
      expect(l.portalById('nope'), isNull);
    });

    test('duplicate IDs, self-links, empty IDs and invalid positions are rejected', () {
      final l = RoadGraphLinker()..registerPortal(portal('p1', 'c0', 'c1'));
      expect(() => l.registerPortal(portal('p1', 'c1', 'c2')), throwsA(isA<PortalException>()));
      expect(() => l.registerPortal(portal('p2', 'c0', 'c0')), throwsA(isA<PortalException>()));
      expect(() => l.registerPortal(portal('', 'c0', 'c1')), throwsA(isA<PortalException>()));
      expect(
        () => l.registerPortal(portal('p3', 'c0', 'c1', pos: const Wgs84Coord(lon: double.nan, lat: 0))),
        throwsA(isA<PortalException>()),
      );
      expect(l.portalCount, 1);
    });

    test('boundary portals activate only when exactly one neighbouring chunk is loaded', () {
      final l = RoadGraphLinker()
        ..registerPortal(portal('p_a', 'c0', 'c1'))
        ..registerPortal(portal('p_b', 'c1', 'c2'))
        ..registerPortal(portal('p_c', 'c5', 'c6'));
      expect(l.activeBoundaryPortals(), isEmpty); // nothing loaded

      l.onChunkLoaded('c1');
      expect(l.activeBoundaryPortals().map((p) => p.portalId), ['p_a', 'p_b']);

      l.onChunkLoaded('c0');
      expect(l.activeBoundaryPortals().map((p) => p.portalId), ['p_b']); // p_a is now internal

      l.onChunkLoaded('c2');
      expect(l.activeBoundaryPortals(), isEmpty);

      l.onChunkUnloaded('c2');
      expect(l.activeBoundaryPortals().map((p) => p.portalId), ['p_b']);
    });

    test('chunkToLoadFor names the missing neighbour', () {
      final l = RoadGraphLinker();
      final p = portal('p1', 'c0', 'c1');
      l.registerPortal(p);
      expect(l.chunkToLoadFor(p), isNull);
      l.onChunkLoaded('c0');
      expect(l.chunkToLoadFor(p), 'c1');
      l.onChunkUnloaded('c0');
      l.onChunkLoaded('c1');
      expect(l.chunkToLoadFor(p), 'c0');
      l.onChunkLoaded('c0');
      expect(l.chunkToLoadFor(p), isNull);
    });
  });

  group('architecture profiles', () {
    test('landmark exclusion API still works', () {
      final e = ArchitectureProfileEngine()..registerLandmarkExclusions(['a', 'b']);
      expect(e.isFootprintExcluded('a'), isTrue);
      expect(e.isFootprintExcluded('z'), isFalse);
    });

    test('profile metadata is truthful: known ids resolve, visuals are not claimed', () {
      final e = ArchitectureProfileEngine();
      expect(e.profileFor('tashkent_modern_soviet'), isNotNull);
      expect(e.profileFor('does_not_exist'), isNull);
      for (final id in ArchitectureProfileEngine.supportedProfiles.keys) {
        expect(e.hasProfileVisuals(id), isFalse, reason: id);
      }
      expect(e.hasProfileVisuals('does_not_exist'), isFalse);
    });
  });
}
