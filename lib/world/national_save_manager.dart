import 'geo_coordinate_system.dart';

class NationalSaveV3 {
  final int saveFormatVersion;
  final String countryId;
  final String regionId;
  final Wgs84Coord cameraPosition;

  const NationalSaveV3({
    this.saveFormatVersion = 3,
    this.countryId = 'UZ',
    required this.regionId,
    required this.cameraPosition,
  });
}

class SaveMigrationAdapter {
  static NationalSaveV3 migrateAnySaveToV3(Map<String, dynamic> rawSave) {
    final double camX = (rawSave['camX'] as num?)?.toDouble() ?? 0.0;
    final double camY = (rawSave['camY'] as num?)?.toDouble() ?? 0.0;
    return NationalSaveV3(
      regionId: 'uz_tashkent_city',
      cameraPosition: NationalCoordinateSystem.legacyTashkentToWgs84(camX, camY),
    );
  }
}
