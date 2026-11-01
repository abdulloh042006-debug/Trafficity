import 'geo_coordinate_system.dart';

class SavedRoadV3 {
  final String id;
  final List<Wgs84Coord> wgs84Polyline;
  final int lanes;
  final String roadClass;

  const SavedRoadV3({
    required this.id,
    required this.wgs84Polyline,
    required this.lanes,
    this.roadClass = 'URBAN_SECONDARY',
  });

  factory SavedRoadV3.fromJson(Map<String, dynamic> json) {
    final pts = (json['wgs84Polyline'] as List<dynamic>)
        .map((p) => Wgs84Coord.fromJson(p))
        .toList();
    return SavedRoadV3(
      id: json['id'] as String,
      wgs84Polyline: pts,
      lanes: (json['lanes'] as num?)?.toInt() ?? 2,
      roadClass: json['roadClass'] as String? ?? 'URBAN_SECONDARY',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'wgs84Polyline': wgs84Polyline.map((p) => p.toJsonList()).toList(),
        'lanes': lanes,
        'roadClass': roadClass,
      };
}

class NationalSaveV3 {
  final int saveFormatVersion;
  final String savedAt;
  final String countryId;
  final String regionId;
  final String districtId;
  final String selectedCityId;
  final String datasetVersion;
  final Wgs84Coord cameraPosition;
  final double cameraZoom;
  final double cameraPitchDegrees;
  final double cameraBearingDegrees;
  final bool is3DMode;
  final List<String> activeMapLayers;
  final List<SavedRoadV3> addedRoads;
  final Map<String, dynamic> legacyPayload;

  const NationalSaveV3({
    this.saveFormatVersion = 3,
    required this.savedAt,
    this.countryId = 'UZ',
    required this.regionId,
    required this.districtId,
    required this.selectedCityId,
    this.datasetVersion = '2026.11.0',
    required this.cameraPosition,
    required this.cameraZoom,
    this.cameraPitchDegrees = 0.0,
    this.cameraBearingDegrees = 0.0,
    this.is3DMode = false,
    required this.activeMapLayers,
    required this.addedRoads,
    this.legacyPayload = const {},
  });

  Map<String, dynamic> toJson() => {
        'saveFormatVersion': saveFormatVersion,
        'savedAt': savedAt,
        'worldContext': {
          'countryId': countryId,
          'regionId': regionId,
          'districtId': districtId,
          'selectedCityId': selectedCityId,
          'datasetVersion': datasetVersion,
        },
        'cameraGeoPose': {
          'lon': cameraPosition.lon,
          'lat': cameraPosition.lat,
          'alt': cameraPosition.alt,
          'zoom': cameraZoom,
          'pitchDegrees': cameraPitchDegrees,
          'bearingDegrees': cameraBearingDegrees,
          'is3DMode': is3DMode,
        },
        'activeMapLayers': activeMapLayers,
        'playerInfrastructure': {
          'addedRoads': addedRoads.map((r) => r.toJson()).toList(),
        },
        'legacyPayload': legacyPayload,
      };

  factory NationalSaveV3.fromJson(Map<String, dynamic> json) {
    final ctx = json['worldContext'] as Map<String, dynamic>? ?? const {};
    final cam = json['cameraGeoPose'] as Map<String, dynamic>? ?? const {};
    final infra =
        json['playerInfrastructure'] as Map<String, dynamic>? ?? const {};
    final roadsList = infra['addedRoads'] as List<dynamic>? ?? const [];

    return NationalSaveV3(
      saveFormatVersion: (json['saveFormatVersion'] as num?)?.toInt() ?? 3,
      savedAt: json['savedAt'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
      countryId: ctx['countryId'] as String? ?? 'UZ',
      regionId: ctx['regionId'] as String? ?? 'uz_tashkent_city',
      districtId: ctx['districtId'] as String? ?? 'UZ-TK',
      selectedCityId: ctx['selectedCityId'] as String? ?? 'city_tashkent',
      datasetVersion: ctx['datasetVersion'] as String? ?? '2026.11.0',
      cameraPosition: Wgs84Coord(
        lon: (cam['lon'] as num?)?.toDouble() ??
            NationalCoordinateSystem.legacyTashkentOrigin.lon,
        lat: (cam['lat'] as num?)?.toDouble() ??
            NationalCoordinateSystem.legacyTashkentOrigin.lat,
        alt: (cam['alt'] as num?)?.toDouble() ?? 475.0,
      ),
      cameraZoom: (cam['zoom'] as num?)?.toDouble() ?? 1.0,
      cameraPitchDegrees: (cam['pitchDegrees'] as num?)?.toDouble() ?? 0.0,
      cameraBearingDegrees: (cam['bearingDegrees'] as num?)?.toDouble() ?? 0.0,
      is3DMode: cam['is3DMode'] as bool? ?? false,
      activeMapLayers: (json['activeMapLayers'] as List<dynamic>? ??
              const [
                'roads',
                'buildings',
                'signals',
                'parks',
                'waterways',
                'metro',
              ])
          .map((e) => e.toString())
          .toList(),
      addedRoads: roadsList
          .map((r) => SavedRoadV3.fromJson(r as Map<String, dynamic>))
          .toList(),
      legacyPayload:
          json['legacyPayload'] as Map<String, dynamic>? ?? const {},
    );
  }
}

class SaveMigrationAdapter {
  static NationalSaveV3 migrateAnySaveToV3(Map<String, dynamic> rawSave) {
    final int version = (rawSave['saveFormatVersion'] as num?)?.toInt() ??
        (rawSave['version'] as num?)?.toInt() ??
        1;

    if (version >= 3 && rawSave.containsKey('worldContext')) {
      return NationalSaveV3.fromJson(rawSave);
    }

    final double camX = (rawSave['camX'] as num?)?.toDouble() ??
        (rawSave['camera'] is Map
            ? ((rawSave['camera']['x'] as num?)?.toDouble() ?? 0.0)
            : 0.0);
    final double camY = (rawSave['camY'] as num?)?.toDouble() ??
        (rawSave['camera'] is Map
            ? ((rawSave['camera']['y'] as num?)?.toDouble() ?? 0.0)
            : 0.0);
    final double zoom = (rawSave['zoom'] as num?)?.toDouble() ??
        (rawSave['camera'] is Map
            ? ((rawSave['camera']['zoom'] as num?)?.toDouble() ?? 1.0)
            : 1.0);

    final Wgs84Coord wgsCam =
        NationalCoordinateSystem.legacyTashkentToWgs84(camX, camY);

    final List<SavedRoadV3> migratedRoads = [];
    final dynamic rawRoads = rawSave['roads'] ?? rawSave['customRoads'];
    if (rawRoads is List) {
      int idx = 0;
      for (final r in rawRoads) {
        if (r is Map<String, dynamic>) {
          final List<Wgs84Coord> poly = [];
          if (r['points'] is List) {
            for (final pt in (r['points'] as List)) {
              if (pt is Map) {
                poly.add(NationalCoordinateSystem.legacyTashkentToWgs84(
                  (pt['x'] as num).toDouble(),
                  (pt['y'] as num).toDouble(),
                ));
              } else if (pt is List && pt.length >= 2) {
                poly.add(NationalCoordinateSystem.legacyTashkentToWgs84(
                  (pt[0] as num).toDouble(),
                  (pt[1] as num).toDouble(),
                ));
              }
            }
          } else if (r.containsKey('x1') && r.containsKey('y1')) {
            poly.add(NationalCoordinateSystem.legacyTashkentToWgs84(
              (r['x1'] as num).toDouble(),
              (r['y1'] as num).toDouble(),
            ));
            poly.add(NationalCoordinateSystem.legacyTashkentToWgs84(
              (r['x2'] as num).toDouble(),
              (r['y2'] as num).toDouble(),
            ));
          }
          migratedRoads.add(
            SavedRoadV3(
              id: r['id']?.toString() ?? 'legacy_road_${idx++}',
              wgs84Polyline: poly,
              lanes: (r['lanes'] as num?)?.toInt() ?? 2,
            ),
          );
        }
      }
    }

    return NationalSaveV3(
      saveFormatVersion: 3,
      savedAt: rawSave['savedAt'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
      countryId: 'UZ',
      regionId: 'uz_tashkent_city',
      districtId: 'UZ-TK',
      selectedCityId: 'city_tashkent',
      datasetVersion: '2026.11.0-migrated-v$version',
      cameraPosition: wgsCam,
      cameraZoom: zoom,
      is3DMode:
          (rawSave['is3D'] as bool?) ?? (rawSave['deck3D'] as bool?) ?? false,
      activeMapLayers: const [
        'roads',
        'buildings',
        'signals',
        'parks',
        'waterways',
        'metro',
      ],
      addedRoads: migratedRoads,
      legacyPayload: Map<String, dynamic>.from(rawSave),
    );
  }
}
