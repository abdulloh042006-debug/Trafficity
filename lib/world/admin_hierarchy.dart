import 'geo_coordinate_system.dart';

enum AdminLevel {
  country,
  firstLevelAdmin,
  secondLevelAdmin,
  settlement,
}

enum FirstLevelAdminType {
  autonomousRepublic,
  region,
  capitalCity,
}

enum RegionReadinessStatus {
  installedDetailed,
  updateAvailable,
  availableForDownload,
  overviewOnly,
}

RegionReadinessStatus parseReadinessStatus(String raw) {
  switch (raw) {
    case 'INSTALLED_DETAILED':
      return RegionReadinessStatus.installedDetailed;
    case 'UPDATE_AVAILABLE':
      return RegionReadinessStatus.updateAvailable;
    case 'AVAILABLE_FOR_DOWNLOAD':
      return RegionReadinessStatus.availableForDownload;
    case 'OVERVIEW_ONLY':
    default:
      return RegionReadinessStatus.overviewOnly;
  }
}

String readinessStatusToString(RegionReadinessStatus status) {
  switch (status) {
    case RegionReadinessStatus.installedDetailed:
      return 'INSTALLED_DETAILED';
    case RegionReadinessStatus.updateAvailable:
      return 'UPDATE_AVAILABLE';
    case RegionReadinessStatus.availableForDownload:
      return 'AVAILABLE_FOR_DOWNLOAD';
    case RegionReadinessStatus.overviewOnly:
      return 'OVERVIEW_ONLY';
  }
}

class LocalizedName {
  final String uz;
  final String ru;
  final String en;

  const LocalizedName({
    required this.uz,
    required this.ru,
    required this.en,
  });

  factory LocalizedName.fromJson(Map<String, dynamic> json) {
    return LocalizedName(
      uz: json['uz'] as String? ?? '',
      ru: json['ru'] as String? ?? '',
      en: json['en'] as String? ?? '',
    );
  }

  Map<String, String> toJson() => {
        'uz': uz,
        'ru': ru,
        'en': en,
      };

  String forLang(String langCode) {
    switch (langCode.toLowerCase()) {
      case 'uz':
        return uz;
      case 'ru':
        return ru;
      default:
        return en;
    }
  }
}

class RegionCatalogEntry {
  final String regionId;
  final String isoCode;
  final String soatoCode;
  final FirstLevelAdminType adminType;
  final LocalizedName names;
  final String primaryCityId;
  final List<String> supportedCities;
  final Wgs84Coord centroid;
  final GeoBoundingBox bbox;
  final String architectureProfileId;
  final String manifestPath;
  final List<int> availableDetailLevels;
  final RegionReadinessStatus defaultReadiness;
  final int estimatedDownloadBytes;

  const RegionCatalogEntry({
    required this.regionId,
    required this.isoCode,
    required this.soatoCode,
    required this.adminType,
    required this.names,
    required this.primaryCityId,
    required this.supportedCities,
    required this.centroid,
    required this.bbox,
    required this.architectureProfileId,
    required this.manifestPath,
    required this.availableDetailLevels,
    required this.defaultReadiness,
    this.estimatedDownloadBytes = 0,
  });

  factory RegionCatalogEntry.fromJson(Map<String, dynamic> json) {
    final String rawType = json['adminType'] as String? ?? 'REGION';
    final FirstLevelAdminType parsedType = rawType == 'AUTONOMOUS_REPUBLIC'
        ? FirstLevelAdminType.autonomousRepublic
        : rawType == 'CAPITAL_CITY'
            ? FirstLevelAdminType.capitalCity
            : FirstLevelAdminType.region;

    final List<dynamic> cList = json['centroid'] as List<dynamic>;
    return RegionCatalogEntry(
      regionId: json['regionId'] as String,
      isoCode: json['isoCode'] as String,
      soatoCode: json['soatoCode'] as String? ?? '',
      adminType: parsedType,
      names: LocalizedName.fromJson(json['names'] as Map<String, dynamic>),
      primaryCityId: json['primaryCityId'] as String,
      supportedCities: (json['supportedCities'] as List<dynamic>? ??
              [json['primaryCityId']])
          .map((e) => e.toString())
          .toList(),
      centroid: Wgs84Coord(
        lon: (cList[0] as num).toDouble(),
        lat: (cList[1] as num).toDouble(),
      ),
      bbox: GeoBoundingBox.fromJson(json['bbox'] as Map<String, dynamic>),
      architectureProfileId:
          json['architectureProfileId'] as String? ?? 'tashkent_modern_soviet',
      manifestPath: json['manifestPath'] as String,
      availableDetailLevels:
          (json['availableDetailLevels'] as List<dynamic>? ?? [1, 2])
              .map((e) => (e as num).toInt())
              .toList(),
      defaultReadiness: parseReadinessStatus(
          json['defaultReadiness'] as String? ?? 'OVERVIEW_ONLY'),
      estimatedDownloadBytes:
          (json['estimatedDownloadBytes'] as num?)?.toInt() ?? 0,
    );
  }

  bool get hasDetailedPlayablePack =>
      defaultReadiness == RegionReadinessStatus.installedDetailed &&
      availableDetailLevels.contains(3);
}

class CityIndexEntry {
  final String cityId;
  final String regionId;
  final String isoCode;
  final LocalizedName names;
  final Wgs84Coord location;
  final int population;
  final bool isRegionalCapital;
  final bool hasDetailedPack;
  final String architectureProfileId;

  const CityIndexEntry({
    required this.cityId,
    required this.regionId,
    required this.isoCode,
    required this.names,
    required this.location,
    required this.population,
    required this.isRegionalCapital,
    required this.hasDetailedPack,
    required this.architectureProfileId,
  });

  factory CityIndexEntry.fromJson(Map<String, dynamic> json) {
    final coords = json['coordinates'] as List<dynamic>;
    return CityIndexEntry(
      cityId: json['cityId'] as String,
      regionId: json['regionId'] as String,
      isoCode: json['isoCode'] as String,
      names: LocalizedName.fromJson(json['names'] as Map<String, dynamic>),
      location: Wgs84Coord(
        lon: (coords[0] as num).toDouble(),
        lat: (coords[1] as num).toDouble(),
        alt: coords.length > 2 ? (coords[2] as num).toDouble() : 450.0,
      ),
      population: (json['population'] as num?)?.toInt() ?? 0,
      isRegionalCapital: json['isRegionalCapital'] as bool? ?? false,
      hasDetailedPack: json['hasDetailedPack'] as bool? ?? false,
      architectureProfileId:
          json['architectureProfileId'] as String? ?? 'tashkent_modern_soviet',
    );
  }
}

class RegionBoundaryPolygon {
  final String regionId;
  final String isoCode;
  final LocalizedName names;
  final List<List<Wgs84Coord>> rings;

  const RegionBoundaryPolygon({
    required this.regionId,
    required this.isoCode,
    required this.names,
    required this.rings,
  });

  bool containsPoint(double lon, double lat) {
    for (final ring in rings) {
      if (_ringContains(ring, lon, lat)) {
        return true;
      }
    }
    return false;
  }

  static bool _ringContains(List<Wgs84Coord> ring, double lon, double lat) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final double xi = ring[i].lon, yi = ring[i].lat;
      final double xj = ring[j].lon, yj = ring[j].lat;

      final bool intersect = ((yi > lat) != (yj > lat)) &&
          (lon <
              (xj - xi) *
                      (lat - yi) /
                      ((yj - yi) == 0 ? 1e-12 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
