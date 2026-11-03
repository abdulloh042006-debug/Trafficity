import 'geo_coordinate_system.dart';

enum RegionReadinessStatus { installedDetailed, updateAvailable, availableForDownload, overviewOnly }

RegionReadinessStatus parseReadinessStatus(String raw) =>
    raw == 'INSTALLED_DETAILED' ? RegionReadinessStatus.installedDetailed : RegionReadinessStatus.overviewOnly;

class LocalizedName {
  final String uz;
  final String ru;
  final String en;
  const LocalizedName({required this.uz, required this.ru, required this.en});
  factory LocalizedName.fromJson(Map<String, dynamic> json) =>
      LocalizedName(uz: json['uz'] as String? ?? '', ru: json['ru'] as String? ?? '', en: json['en'] as String? ?? '');
  String forLang(String lang) => lang == 'uz'
      ? uz
      : lang == 'ru'
      ? ru
      : en;
}

class RegionCatalogEntry {
  final String regionId;
  final String isoCode;
  final String soatoCode;
  final LocalizedName names;

  /// Administrative-center point as listed in the catalog. Approximate; NOT a computed geometric centroid.
  final Wgs84Coord representativePoint;
  final GeoBoundingBox bbox;
  final String architectureProfileId;
  final RegionReadinessStatus defaultReadiness;

  const RegionCatalogEntry({
    required this.regionId,
    required this.isoCode,
    required this.soatoCode,
    required this.names,
    required this.representativePoint,
    required this.bbox,
    required this.architectureProfileId,
    required this.defaultReadiness,
  });

  factory RegionCatalogEntry.fromJson(Map<String, dynamic> json) {
    final Object? rep = json['representativePoint'] ?? json['centroid']; // 'centroid' is the pre-rev.2 key
    final double lat = (json['latitude'] as num?)?.toDouble() ?? ((rep as List)[1] as num).toDouble();
    final double lon = (json['longitude'] as num?)?.toDouble() ?? ((rep as List)[0] as num).toDouble();
    return RegionCatalogEntry(
      regionId: json['regionId'] as String,
      isoCode: json['isoCode'] as String,
      soatoCode: json['soatoCode'] as String? ?? '',
      names: LocalizedName.fromJson(json['names'] as Map<String, dynamic>),
      representativePoint: Wgs84Coord(lon: lon, lat: lat),
      bbox: GeoBoundingBox.fromJson(json['bbox'] as Map<String, dynamic>),
      architectureProfileId: json['architectureProfileId'] as String? ?? 'tashkent_modern_soviet',
      defaultReadiness: parseReadinessStatus(json['defaultReadiness'] as String? ?? 'OVERVIEW_ONLY'),
    );
  }
}
