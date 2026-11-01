import 'geo_coordinate_system.dart';

enum GeographicalDetailLevel {
  level1CountryOverview,
  level2RegionalView,
  level3CityView2D,
  level4DetailedUrban3D,
}

extension GeographicalDetailLevelExt on GeographicalDetailLevel {
  int get numericLevel {
    switch (this) {
      case GeographicalDetailLevel.level1CountryOverview:
        return 1;
      case GeographicalDetailLevel.level2RegionalView:
        return 2;
      case GeographicalDetailLevel.level3CityView2D:
        return 3;
      case GeographicalDetailLevel.level4DetailedUrban3D:
        return 4;
    }
  }

  String label(String lang) {
    switch (this) {
      case GeographicalDetailLevel.level1CountryOverview:
        return lang == 'uz'
            ? '1-daraja: Butun Oʻzbekiston'
            : lang == 'ru'
                ? 'Уровень 1: Весь Узбекистан'
                : 'Level 1: Uzbekistan Overview';
      case GeographicalDetailLevel.level2RegionalView:
        return lang == 'uz'
            ? '2-daraja: Viloyat koʻrinishi'
            : lang == 'ru'
                ? 'Уровень 2: Региональный вид'
                : 'Level 2: Regional View';
      case GeographicalDetailLevel.level3CityView2D:
        return lang == 'uz'
            ? '3-daraja: Shahar 2D xaritasi'
            : lang == 'ru'
                ? 'Уровень 3: Городской 2D вид'
                : 'Level 3: City 2D View';
      case GeographicalDetailLevel.level4DetailedUrban3D:
        return lang == 'uz'
            ? '4-daraja: Batafsil 3D shahar'
            : lang == 'ru'
                ? 'Уровень 4: Детальный 3D город'
                : 'Level 4: Detailed 3D Urban';
    }
  }
}

class SpatialChunkDescriptor {
  final String chunkId;
  final String regionId;
  final int lod;
  final Wgs84Coord center;
  final GeoBoundingBox bbox;
  final double radiusMeters;
  final String assetPath;

  const SpatialChunkDescriptor({
    required this.chunkId,
    required this.regionId,
    required this.lod,
    required this.center,
    required this.bbox,
    required this.radiusMeters,
    required this.assetPath,
  });

  factory SpatialChunkDescriptor.fromJson(Map<String, dynamic> json) {
    final centerList = json['center'] as List<dynamic>;
    return SpatialChunkDescriptor(
      chunkId: json['chunkId'] as String,
      regionId: json['regionId'] as String,
      lod: (json['lod'] as num).toInt(),
      center: Wgs84Coord(
        lon: (centerList[0] as num).toDouble(),
        lat: (centerList[1] as num).toDouble(),
      ),
      bbox: GeoBoundingBox.fromJson(json['bbox'] as Map<String, dynamic>),
      radiusMeters: (json['radiusMeters'] as num).toDouble(),
      assetPath: json['assetPath'] as String,
    );
  }
}

class ChunkStreamingDelta {
  final List<SpatialChunkDescriptor> toLoad;
  final List<String> toUnload;

  const ChunkStreamingDelta({
    required this.toLoad,
    required this.toUnload,
  });
}

class MultiScaleLodController {
  static const double lod4ActiveRadiusMeters = 2500.0;
  static const double lod3RingRadiusMeters = 12000.0;
  static const double lod2RegionalRadiusMeters = 65000.0;

  final Set<String> _loadedChunkIds = {};
  GeographicalDetailLevel _activeLevel =
      GeographicalDetailLevel.level3CityView2D;

  GeographicalDetailLevel get activeLevel => _activeLevel;
  Set<String> get loadedChunkIds => Set.unmodifiable(_loadedChunkIds);

  GeographicalDetailLevel evaluateFromCamera({
    required double cameraZoom,
    required bool is3DPerspectiveActive,
    required bool regionHasDetailedPack,
  }) {
    if (cameraZoom < 0.08) {
      _activeLevel = GeographicalDetailLevel.level1CountryOverview;
    } else if (cameraZoom < 0.28 || !regionHasDetailedPack) {
      _activeLevel = GeographicalDetailLevel.level2RegionalView;
    } else if (is3DPerspectiveActive && cameraZoom >= 0.85) {
      _activeLevel = GeographicalDetailLevel.level4DetailedUrban3D;
    } else {
      _activeLevel = GeographicalDetailLevel.level3CityView2D;
    }
    return _activeLevel;
  }

  ChunkStreamingDelta updateStreamingChunks({
    required Wgs84Coord cameraWgs84,
    required List<SpatialChunkDescriptor> availableChunks,
  }) {
    if (_activeLevel == GeographicalDetailLevel.level1CountryOverview) {
      final toUnload = _loadedChunkIds.toList();
      _loadedChunkIds.clear();
      return ChunkStreamingDelta(toLoad: const [], toUnload: toUnload);
    }

    final Set<String> desired = {};
    final List<SpatialChunkDescriptor> toLoad = [];

    for (final chunk in availableChunks) {
      final double dist = NationalCoordinateSystem.geodesicDistanceMeters(
            cameraWgs84,
            chunk.center,
          ) -
          chunk.radiusMeters;
      final double clampedDist = dist < 0.0 ? 0.0 : dist;

      bool shouldLoad = false;
      if (_activeLevel == GeographicalDetailLevel.level2RegionalView) {
        shouldLoad = chunk.lod <= 2 && clampedDist <= lod2RegionalRadiusMeters;
      } else if (_activeLevel == GeographicalDetailLevel.level3CityView2D) {
        shouldLoad = chunk.lod == 3 && clampedDist <= lod3RingRadiusMeters;
      } else if (_activeLevel == GeographicalDetailLevel.level4DetailedUrban3D) {
        shouldLoad = (chunk.lod == 4 && clampedDist <= lod4ActiveRadiusMeters) ||
            (chunk.lod == 3 && clampedDist <= lod3RingRadiusMeters);
      }

      if (shouldLoad) {
        desired.add(chunk.chunkId);
        if (!_loadedChunkIds.contains(chunk.chunkId)) {
          _loadedChunkIds.add(chunk.chunkId);
          toLoad.add(chunk);
        }
      }
    }

    final List<String> toUnload = [];
    for (final existingId in _loadedChunkIds.toList()) {
      if (!desired.contains(existingId)) {
        _loadedChunkIds.remove(existingId);
        toUnload.add(existingId);
      }
    }

    return ChunkStreamingDelta(toLoad: toLoad, toUnload: toUnload);
  }
}
