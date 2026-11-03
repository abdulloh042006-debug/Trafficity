import 'geo_coordinate_system.dart';

/// Raised for saves that cannot be read. [code]: `malformed`, `unknown_version`, `missing_field`.
class SaveFormatException implements Exception {
  final String code;
  final String message;
  const SaveFormatException(this.code, this.message);
  @override
  String toString() => 'SaveFormatException($code): $message';
}

/// National save envelope, format version 3.
///
/// Carries only the geographic identity of a save (country, region, camera in WGS84) and version
/// metadata. Gameplay payload (roads, buildings, ...) stays in the game's own save map.
class NationalSaveV3 {
  static const int currentVersion = 3;
  static const String defaultCountryId = 'UZ';

  final int saveFormatVersion;
  final String countryId;
  final String regionId;

  /// Camera centre in WGS84, or null when the save has no geographic meaning (see [fromLegacy]).
  final Wgs84Coord? cameraPosition;
  final double cameraZoom;

  /// Format version this save was originally written in (1 or 2 for migrated legacy saves).
  final int migratedFromVersion;

  const NationalSaveV3({
    this.saveFormatVersion = currentVersion,
    this.countryId = defaultCountryId,
    required this.regionId,
    this.cameraPosition,
    this.cameraZoom = 1.0,
    this.migratedFromVersion = currentVersion,
  });

  Map<String, dynamic> toJson() => {
        'v': saveFormatVersion,
        'country': countryId,
        'region': regionId,
        if (cameraPosition != null) 'camera': [cameraPosition!.lon, cameraPosition!.lat],
        'zoom': cameraZoom,
        'migratedFrom': migratedFromVersion,
      };

  /// Reads a v3 save. Throws [SaveFormatException] for anything else or for invalid values.
  factory NationalSaveV3.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const SaveFormatException('malformed', 'Save root must be an object');
    }
    final v = json['v'];
    if (v is! int) throw const SaveFormatException('malformed', 'Save has no integer version');
    if (v != currentVersion) throw SaveFormatException('unknown_version', 'Not a v3 save: v=$v');
    final region = json['region'];
    if (region is! String || region.isEmpty) {
      throw const SaveFormatException('missing_field', 'region is required');
    }
    final country = json['country'];
    Wgs84Coord? camera;
    final rawCam = json['camera'];
    if (rawCam != null) {
      if (rawCam is! List || rawCam.length < 2 || rawCam[0] is! num || rawCam[1] is! num) {
        throw const SaveFormatException('malformed', 'camera must be [lon, lat]');
      }
      camera = Wgs84Coord(lon: (rawCam[0] as num).toDouble(), lat: (rawCam[1] as num).toDouble());
      if (!camera.isValid) throw const SaveFormatException('malformed', 'camera is not a valid WGS84 position');
    }
    final zoom = json['zoom'];
    final migrated = json['migratedFrom'];
    return NationalSaveV3(
      countryId: country is String && country.isNotEmpty ? country : defaultCountryId,
      regionId: region,
      cameraPosition: camera,
      cameraZoom: zoom is num && zoom.isFinite ? zoom.toDouble() : 1.0,
      migratedFromVersion: migrated is int ? migrated : currentVersion,
    );
  }

  /// Biome id of the real Tashkent map in legacy saves (`Terrain.tashkent`).
  static const int legacyTashkentBiome = 4;

  /// World size (units) of the Tashkent map whose centre (3200, 3200) is the Tashkent origin.
  static const double legacyTashkentWorldSize = 6400.0;

  /// Migrates a legacy v1/v2 game save (`{'v': 1|2, 'biome':…, 'ws':…, 'cam':[x,y], 'zoom':…}`).
  ///
  /// Only real-Tashkent saves (biome 4, 6400-unit world) have a geographic camera; procedural
  /// biomes have no real-world position, so [cameraPosition] stays null instead of inventing one.
  /// The input map is never modified.
  factory NationalSaveV3.fromLegacy(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const SaveFormatException('malformed', 'Legacy save root must be an object');
    }
    final v = json['v'];
    if (v != 1 && v != 2) {
      throw SaveFormatException('unknown_version', 'Unsupported legacy save version: $v');
    }
    final biome = (json['biome'] as num?)?.toInt() ?? 0;
    final ws = (json['ws'] as num?)?.toDouble() ?? (biome == legacyTashkentBiome ? legacyTashkentWorldSize : 3200.0);
    final zoomRaw = json['zoom'];
    final zoom = zoomRaw is num && zoomRaw.isFinite ? zoomRaw.toDouble() : 1.0;

    Wgs84Coord? camera;
    final cam = json['cam'];
    if (biome == legacyTashkentBiome && ws == legacyTashkentWorldSize && cam is List && cam.length >= 2) {
      final x = cam[0];
      final y = cam[1];
      if (x is num && y is num && x.isFinite && y.isFinite) {
        camera = NationalCoordinateSystem.legacyUnitsToWgs84(x.toDouble(), y.toDouble());
      }
    }
    return NationalSaveV3(
      regionId: 'uz_tashkent_city',
      cameraPosition: camera,
      cameraZoom: zoom,
      migratedFromVersion: v as int,
    );
  }

  /// Reads any supported save (v3, or legacy v1/v2) and returns it as v3.
  static NationalSaveV3 parseAny(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const SaveFormatException('malformed', 'Save root must be an object');
    }
    final v = json['v'];
    if (v == currentVersion) return NationalSaveV3.fromJson(json);
    if (v == 1 || v == 2) return NationalSaveV3.fromLegacy(json);
    throw SaveFormatException('unknown_version', 'Unknown save version: $v');
  }
}

/// Decides which stored value to keep. A legacy save is only replaced after its v3 form
/// has been produced successfully; on any failure the original string is kept untouched.
class NationalSaveMigrator {
  /// Returns the migrated v3 JSON map, or null when [rawLegacy] cannot be migrated (caller keeps the original).
  static Map<String, dynamic>? tryMigrate(Object? decodedLegacy) {
    try {
      return NationalSaveV3.parseAny(decodedLegacy).toJson();
    } on SaveFormatException {
      return null;
    }
  }
}
