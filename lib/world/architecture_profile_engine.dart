import 'dart:ui';
import 'geo_coordinate_system.dart';

enum BuildingGenerationMode {
  verifiedLandmarkModel,
  proceduralEstimatedBuilding,
}

class VerifiedLandmarkDescriptor {
  final String landmarkId;
  final Map<String, String> names;
  final Wgs84Coord wgs84Anchor;
  final double heightMeters;
  final String styleTag;
  final Color primaryColor;
  final Color accentDomeColor;
  final List<String> footprintExclusionIds;

  const VerifiedLandmarkDescriptor({
    required this.landmarkId,
    required this.names,
    required this.wgs84Anchor,
    required this.heightMeters,
    required this.styleTag,
    required this.primaryColor,
    required this.accentDomeColor,
    this.footprintExclusionIds = const [],
  });

  factory VerifiedLandmarkDescriptor.fromJson(Map<String, dynamic> json) {
    return VerifiedLandmarkDescriptor(
      landmarkId: json['landmarkId'] as String,
      names: Map<String, String>.from(json['names'] as Map),
      wgs84Anchor: Wgs84Coord.fromJson(json['wgs84Anchor']),
      heightMeters: (json['heightMeters'] as num?)?.toDouble() ?? 30.0,
      styleTag: json['styleTag'] as String? ?? 'TIMURID_MONUMENT',
      primaryColor:
          _parseHexColor(json['primaryColorHex'] as String? ?? '#D8B88C'),
      accentDomeColor:
          _parseHexColor(json['accentColorHex'] as String? ?? '#1B8A99'),
      footprintExclusionIds:
          (json['footprintExclusionPolygonIds'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
    );
  }
}

class CityArchitectureProfile {
  final String profileId;
  final String cityOrRegionName;
  final double historicZoneMaxHeightMeters;
  final double modernZoneDefaultHeightMeters;
  final List<Color> facadePalette;
  final Color roofAndDomeAccentColor;
  final bool pedestrianOnlyHistoricCore;

  const CityArchitectureProfile({
    required this.profileId,
    required this.cityOrRegionName,
    required this.historicZoneMaxHeightMeters,
    required this.modernZoneDefaultHeightMeters,
    required this.facadePalette,
    required this.roofAndDomeAccentColor,
    this.pedestrianOnlyHistoricCore = false,
  });

  factory CityArchitectureProfile.fromJson(Map<String, dynamic> json) {
    final paletteRaw = json['facadePalette'] as List<dynamic>? ??
        ['#D8B88C', '#C9A374', '#E4D1B5'];
    return CityArchitectureProfile(
      profileId: json['profileId'] as String,
      cityOrRegionName: json['cityOrRegionName'] as String? ?? '',
      historicZoneMaxHeightMeters:
          (json['historicZoneMaxHeightMeters'] as num?)?.toDouble() ?? 12.0,
      modernZoneDefaultHeightMeters:
          (json['modernZoneDefaultHeightMeters'] as num?)?.toDouble() ?? 18.0,
      facadePalette:
          paletteRaw.map((hex) => _parseHexColor(hex.toString())).toList(),
      roofAndDomeAccentColor:
          _parseHexColor(json['roofAccentHex'] as String? ?? '#1B8A99'),
      pedestrianOnlyHistoricCore:
          json['pedestrianOnlyHistoricCore'] as bool? ?? false,
    );
  }
}

class ResolvedBuildingStyle {
  final String buildingId;
  final BuildingGenerationMode generationMode;
  final String inspectionBadge;
  final double heightMeters;
  final Color wallColor;
  final Color roofColor;
  final bool hasTraditionalDome;

  const ResolvedBuildingStyle({
    required this.buildingId,
    required this.generationMode,
    required this.inspectionBadge,
    required this.heightMeters,
    required this.wallColor,
    required this.roofColor,
    this.hasTraditionalDome = false,
  });
}

class ArchitectureProfileEngine {
  final Map<String, CityArchitectureProfile> _profiles = {
    'tashkent_modern_soviet': const CityArchitectureProfile(
      profileId: 'tashkent_modern_soviet',
      cityOrRegionName: 'Tashkent',
      historicZoneMaxHeightMeters: 14.0,
      modernZoneDefaultHeightMeters: 24.0,
      facadePalette: [
        Color(0xFFD9D2C5),
        Color(0xFFC7BFA8),
        Color(0xFF9FB4C7),
        Color(0xFFE2C9A0),
      ],
      roofAndDomeAccentColor: Color(0xFF1F8A9C),
    ),
    'samarkand_timurid_heritage': const CityArchitectureProfile(
      profileId: 'samarkand_timurid_heritage',
      cityOrRegionName: 'Samarkand',
      historicZoneMaxHeightMeters: 9.5,
      modernZoneDefaultHeightMeters: 15.0,
      facadePalette: [
        Color(0xFFD8B88C),
        Color(0xFFC9A374),
        Color(0xFFE4D1B5),
      ],
      roofAndDomeAccentColor: Color(0xFF1B8A99),
    ),
    'bukhara_historic_oasis': const CityArchitectureProfile(
      profileId: 'bukhara_historic_oasis',
      cityOrRegionName: 'Bukhara',
      historicZoneMaxHeightMeters: 8.5,
      modernZoneDefaultHeightMeters: 14.0,
      facadePalette: [
        Color(0xFFD4B283),
        Color(0xFFC29E6B),
        Color(0xFFDEC39B),
      ],
      roofAndDomeAccentColor: Color(0xFF237A8C),
    ),
    'khiva_ichan_kala': const CityArchitectureProfile(
      profileId: 'khiva_ichan_kala',
      cityOrRegionName: 'Khiva / Khorezm',
      historicZoneMaxHeightMeters: 7.5,
      modernZoneDefaultHeightMeters: 12.0,
      facadePalette: [
        Color(0xFFCFA872),
        Color(0xFFBF9660),
        Color(0xFFDAB98B),
      ],
      roofAndDomeAccentColor: Color(0xFF1A96A8),
      pedestrianOnlyHistoricCore: true,
    ),
    'fergana_valley_urban': const CityArchitectureProfile(
      profileId: 'fergana_valley_urban',
      cityOrRegionName: 'Andijan / Fergana / Namangan',
      historicZoneMaxHeightMeters: 11.0,
      modernZoneDefaultHeightMeters: 18.0,
      facadePalette: [
        Color(0xFFDCD6C8),
        Color(0xFFC8C2B2),
        Color(0xFFB5C4B1),
      ],
      roofAndDomeAccentColor: Color(0xFF3E6B5C),
    ),
    'karakalpak_steppe_modern': const CityArchitectureProfile(
      profileId: 'karakalpak_steppe_modern',
      cityOrRegionName: 'Nukus / Karakalpakstan',
      historicZoneMaxHeightMeters: 10.0,
      modernZoneDefaultHeightMeters: 16.0,
      facadePalette: [
        Color(0xFFDFCFB6),
        Color(0xFFC9B79C),
        Color(0xFFB8C2CC),
      ],
      roofAndDomeAccentColor: Color(0xFF2B6F8E),
    ),
  };

  final Set<String> _excludedFootprintIds = {};
  final Map<String, VerifiedLandmarkDescriptor> _landmarks = {};

  void registerLandmarks(Iterable<VerifiedLandmarkDescriptor> landmarks) {
    _excludedFootprintIds.clear();
    _landmarks.clear();
    for (final lm in landmarks) {
      _landmarks[lm.landmarkId] = lm;
      _excludedFootprintIds.addAll(lm.footprintExclusionIds);
    }
  }

  CityArchitectureProfile getProfile(String profileId) {
    return _profiles[profileId] ?? _profiles['tashkent_modern_soviet']!;
  }

  ResolvedBuildingStyle? resolveFootprint({
    required String footprintId,
    required String profileId,
    double? osmHeightMeters,
    int? osmLevels,
    bool isHistoricZone = false,
  }) {
    if (_excludedFootprintIds.contains(footprintId)) {
      return null;
    }

    final profile = getProfile(profileId);
    final double rawHeight = osmHeightMeters ??
        (osmLevels != null
            ? osmLevels * 3.2
            : profile.modernZoneDefaultHeightMeters);
    final double clampedHeight = isHistoricZone
        ? (rawHeight > profile.historicZoneMaxHeightMeters
            ? profile.historicZoneMaxHeightMeters
            : rawHeight)
        : rawHeight;

    final int hash = footprintId.codeUnits.fold<int>(
        2166136261, (prev, elem) => ((prev ^ elem) * 16777619) & 0x7fffffff);
    final Color wallColor =
        profile.facadePalette[hash % profile.facadePalette.length];

    return ResolvedBuildingStyle(
      buildingId: footprintId,
      generationMode: BuildingGenerationMode.proceduralEstimatedBuilding,
      inspectionBadge: osmHeightMeters != null
          ? 'Procedural Building (OSM Height: ${clampedHeight.toStringAsFixed(1)}m)'
          : 'Procedural Estimated Building (${profile.profileId})',
      heightMeters: clampedHeight,
      wallColor: wallColor,
      roofColor: profile.roofAndDomeAccentColor,
      hasTraditionalDome: isHistoricZone && (hash % 7 == 0),
    );
  }
}

Color _parseHexColor(String hexString) {
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
  buffer.write(hexString.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
