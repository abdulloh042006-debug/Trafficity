import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/world/admin_hierarchy.dart';
import 'package:trafficity/world/architecture_profile_engine.dart';
import 'package:trafficity/world/geo_coordinate_system.dart';
import 'package:trafficity/world/multi_scale_lod_controller.dart';
import 'package:trafficity/world/national_save_manager.dart';
import 'package:trafficity/world/region_package_manager.dart';
import 'package:trafficity/world/road_graph_linker.dart';
import 'package:trafficity/world/world_controller.dart';

void main() {
  group('1. National Geographical Coordinate System & Floating Origin', () {
    test('Round-trip WGS84 <-> Local ENU is accurate across Uzbekistan', () {
      const samarkandRegistan = Wgs84Coord(
        lon: 66.974973,
        lat: 39.654808,
        alt: 702.0,
      );
      final coordSys =
          NationalCoordinateSystem(initialOrigin: samarkandRegistan);

      const testPoint = Wgs84Coord(
        lon: 66.985120,
        lat: 39.662150,
        alt: 710.0,
      );
      final enu = coordSys.wgs84ToLocalEnu(testPoint);
      final roundTrip = coordSys.localEnuToWgs84(enu);

      expect(roundTrip.lon, closeTo(testPoint.lon, 1e-7));
      expect(roundTrip.lat, closeTo(testPoint.lat, 1e-7));
      expect(roundTrip.alt, closeTo(testPoint.alt, 1e-3));
    });

    test('Floating origin rebases when camera moves beyond 2000m threshold', () {
      final coordSys = NationalCoordinateSystem();
      const distantCamera =
          Wgs84Coord(lon: 69.320000, lat: 41.340000, alt: 480.0);

      final shift = coordSys.checkAndRebaseIfNeeded(distantCamera);
      expect(shift, isNotNull);
      expect(coordSys.floatingOrigin.lon, closeTo(distantCamera.lon, 1e-7));
      expect(coordSys.floatingOrigin.lat, closeTo(distantCamera.lat, 1e-7));
    });

    test('Legacy Tashkent coordinates transform cleanly to and from WGS84', () {
      final wgs =
          NationalCoordinateSystem.legacyTashkentToWgs84(1250.0, -840.0);
      final backToLegacy = NationalCoordinateSystem.wgs84ToLegacyTashkent(wgs);

      expect(backToLegacy.x, closeTo(1250.0, 1e-3));
      expect(backToLegacy.y, closeTo(-840.0, 1e-3));
    });
  });

  group('2. Uzbekistan 14-Region Catalog & Honesty Guardrails', () {
    late UzbekistanWorldController controller;

    setUp(() {
      final catalogJson =
          File('assets/world/uzbekistan/region_catalog.json').readAsStringSync();
      final citiesJson =
          File('assets/world/uzbekistan/cities_index.json').readAsStringSync();
      final boundariesJson =
          File('assets/world/uzbekistan/administrative_boundaries.geojson')
              .readAsStringSync();

      controller = UzbekistanWorldController();
      controller.loadFromRawJson(
        catalogJson: catalogJson,
        citiesJson: citiesJson,
        boundariesGeoJson: boundariesJson,
      );
    });

    test('Catalog contains all 14 first-level administrative divisions', () {
      expect(controller.regions.length, equals(14));
    });

    test('Tashkent City is INSTALLED_DETAILED while unbuilt regions are OVERVIEW_ONLY', () {
      final tashkent = controller.regions
          .firstWhere((r) => r.regionId == 'uz_tashkent_city');
      final samarkand =
          controller.regions.firstWhere((r) => r.regionId == 'uz_samarkand');

      expect(tashkent.hasDetailedPlayablePack, isTrue);
      expect(
          samarkand.defaultReadiness, equals(RegionReadinessStatus.overviewOnly));
      expect(samarkand.hasDetailedPlayablePack, isFalse);

      controller.selectRegion('uz_samarkand');
      expect(
        controller.lodController.activeLevel,
        equals(GeographicalDetailLevel.level2RegionalView),
      );
    });
  });

  group('3. Cross-Boundary Road Stitching & Architecture Profiles', () {
    test('RoadGraphLinker stitches segments across chunk borders', () {
      final linker = RoadGraphLinker();
      const portalPos = Wgs84Coord(lon: 68.7840, lat: 40.4890);
      linker.registerPortals([
        const StitchPortalNode(
          portalId: 'uz:portal:m39:syrdarya_jizzakh',
          globalWayId: 'uz:road:way:m39',
          roadDesignation: 'M39',
          wgs84Position: portalPos,
          fromRegionId: 'uz_syrdarya',
          fromChunkId: 'chunk_syr_1',
          toRegionId: 'uz_jizzakh',
          toChunkId: 'chunk_jiz_1',
          laneCount: 4,
          headingDegrees: 215.0,
        ),
      ]);

      linker.onChunkLoaded('chunk_syr_1', [
        CrossRegionSegment(
          segmentId: 'seg_1',
          globalWayId: 'uz:road:way:m39',
          regionId: 'uz_syrdarya',
          chunkId: 'chunk_syr_1',
          startNodeId: 'n_start',
          endNodeId: 'n_temp_end',
          geometry: [const Wgs84Coord(lon: 68.80, lat: 40.50), portalPos],
        ),
      ]);

      expect(linker.getActiveBoundaryReservoirs().length, equals(1));

      linker.onChunkLoaded('chunk_jiz_1', [
        CrossRegionSegment(
          segmentId: 'seg_2',
          globalWayId: 'uz:road:way:m39',
          regionId: 'uz_jizzakh',
          chunkId: 'chunk_jiz_1',
          startNodeId: 'n_temp_start',
          endNodeId: 'n_end',
          geometry: [portalPos, const Wgs84Coord(lon: 68.75, lat: 40.45)],
        ),
      ]);

      expect(linker.getActiveBoundaryReservoirs(), isEmpty);
    });

    test('ArchitectureProfileEngine suppresses footprints for landmarks', () {
      final engine = ArchitectureProfileEngine();
      engine.registerLandmarks([
        VerifiedLandmarkDescriptor.fromJson({
          'landmarkId': 'lm_registan',
          'names': {'uz': 'Registon', 'ru': 'Регистан', 'en': 'Registan'},
          'wgs84Anchor': [66.975, 39.654, 702.0],
          'heightMeters': 36.0,
          'footprintExclusionPolygonIds': ['fp_ulugbek_madrasa'],
        }),
      ]);

      final excluded = engine.resolveFootprint(
        footprintId: 'fp_ulugbek_madrasa',
        profileId: 'samarkand_timurid_heritage',
      );
      expect(excluded, isNull);
    });
  });

  group('4. Legacy Save v1/v2 -> National Save v3 Migration', () {
    test('Migrates legacy Tashkent save to v3 with canonical WGS84 coordinates', () {
      final legacyV1Save = <String, dynamic>{
        'version': 1,
        'camX': 500.0,
        'camY': -300.0,
        'zoom': 1.25,
        'roads': [
          {
            'id': 'r_legacy_1',
            'x1': 0.0,
            'y1': 0.0,
            'x2': 100.0,
            'y2': -100.0,
            'lanes': 4,
          }
        ],
      };

      final v3 = SaveMigrationAdapter.migrateAnySaveToV3(legacyV1Save);
      expect(v3.saveFormatVersion, equals(3));
      expect(v3.countryId, equals('UZ'));
      expect(v3.regionId, equals('uz_tashkent_city'));
      expect(v3.addedRoads.length, equals(1));
    });
  });

  group('5. SHA-256 Package Integrity Verifier', () {
    test('Verifies valid SHA-256 digest', () {
      final mgr = RegionPackageManager();
      final bytes = utf8.encode('{"regionId":"uz_samarkand","roads":[]}');
      final expectedHash = Sha256Verifier.sha256Hex(bytes);

      final ok = mgr.verifyAndInstallPackageBytes(
        regionId: 'uz_samarkand',
        packageId: 'pkg_uz_samarkand_l3',
        datasetVersion: '2026.11.0',
        payloadBytes: bytes,
        expectedSha256: expectedHash,
      );
      expect(ok, isTrue);
    });
  });
}
