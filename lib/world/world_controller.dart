import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'admin_hierarchy.dart';
import 'architecture_profile_engine.dart';
import 'geo_coordinate_system.dart';
import 'multi_scale_lod_controller.dart';
import 'region_package_manager.dart';
import 'road_graph_linker.dart';

class UzbekistanWorldController extends ChangeNotifier {
  final NationalCoordinateSystem coordinateSystem;
  final RegionPackageManager packageManager;
  final MultiScaleLodController lodController;
  final RoadGraphLinker roadLinker;
  final ArchitectureProfileEngine architectureEngine;

  List<RegionCatalogEntry> _regions = [];
  List<CityIndexEntry> _cities = [];
  List<RegionBoundaryPolygon> _boundaries = [];
  RegionCatalogEntry? _activeRegion;
  CityIndexEntry? _activeCity;
  bool _isInitialized = false;

  UzbekistanWorldController({
    NationalCoordinateSystem? coordinateSystem,
    RegionPackageManager? packageManager,
    MultiScaleLodController? lodController,
    RoadGraphLinker? roadLinker,
    ArchitectureProfileEngine? architectureEngine,
  })  : coordinateSystem = coordinateSystem ?? NationalCoordinateSystem(),
        packageManager = packageManager ?? RegionPackageManager(),
        lodController = lodController ?? MultiScaleLodController(),
        roadLinker = roadLinker ?? RoadGraphLinker(),
        architectureEngine =
            architectureEngine ?? ArchitectureProfileEngine();

  bool get isInitialized => _isInitialized;
  List<RegionCatalogEntry> get regions => List.unmodifiable(_regions);
  List<CityIndexEntry> get cities => List.unmodifiable(_cities);
  List<RegionBoundaryPolygon> get boundaries => List.unmodifiable(_boundaries);
  RegionCatalogEntry? get activeRegion => _activeRegion;
  CityIndexEntry? get activeCity => _activeCity;

  Future<void> initializeFromAssets() async {
    if (_isInitialized) return;

    final String catalogRaw = await rootBundle
        .loadString('assets/world/uzbekistan/region_catalog.json');
    final String citiesRaw = await rootBundle
        .loadString('assets/world/uzbekistan/cities_index.json');
    final String boundariesRaw = await rootBundle.loadString(
        'assets/world/uzbekistan/administrative_boundaries.geojson');

    loadFromRawJson(
      catalogJson: catalogRaw,
      citiesJson: citiesRaw,
      boundariesGeoJson: boundariesRaw,
    );
  }

  void loadFromRawJson({
    required String catalogJson,
    required String citiesJson,
    required String boundariesGeoJson,
  }) {
    final Map<String, dynamic> catMap =
        jsonDecode(catalogJson) as Map<String, dynamic>;
    final List<dynamic> regList = catMap['regions'] as List<dynamic>;
    _regions = regList
        .map((r) => RegionCatalogEntry.fromJson(r as Map<String, dynamic>))
        .toList();

    final Map<String, dynamic> citMap =
        jsonDecode(citiesJson) as Map<String, dynamic>;
    final List<dynamic> citList = citMap['cities'] as List<dynamic>;
    _cities = citList
        .map((c) => CityIndexEntry.fromJson(c as Map<String, dynamic>))
        .toList();

    _boundaries = _parseBoundariesGeoJson(boundariesGeoJson);

    _activeRegion = _regions.firstWhere(
      (r) => r.regionId == 'uz_tashkent_city',
      orElse: () => _regions.first,
    );
    _activeCity = _cities.firstWhere(
      (c) => c.cityId == 'city_tashkent',
      orElse: () => _cities.first,
    );

    coordinateSystem.setFloatingOrigin(_activeCity!.location);
    _isInitialized = true;
    notifyListeners();
  }

  List<RegionBoundaryPolygon> _parseBoundariesGeoJson(String rawGeoJson) {
    final Map<String, dynamic> geo =
        jsonDecode(rawGeoJson) as Map<String, dynamic>;
    final List<dynamic> features =
        geo['features'] as List<dynamic>? ?? const [];
    final List<RegionBoundaryPolygon> parsed = [];

    for (final f in features) {
      final map = f as Map<String, dynamic>;
      final props = map['properties'] as Map<String, dynamic>? ?? const {};
      final geom = map['geometry'] as Map<String, dynamic>? ?? const {};
      final String type = geom['type'] as String? ?? '';
      final List<List<Wgs84Coord>> rings = [];

      if (type == 'Polygon') {
        final coords = geom['coordinates'] as List<dynamic>;
        for (final ring in coords) {
          rings.add((ring as List<dynamic>)
              .map((pt) => Wgs84Coord(
                    lon: ((pt as List)[0] as num).toDouble(),
                    lat: (pt[1] as num).toDouble(),
                  ))
              .toList());
        }
      }

      parsed.add(
        RegionBoundaryPolygon(
          regionId: props['regionId'] as String? ?? '',
          isoCode: props['isoCode'] as String? ?? '',
          names: LocalizedName(
            uz: props['name_uz'] as String? ?? '',
            ru: props['name_ru'] as String? ?? '',
            en: props['name_en'] as String? ?? '',
          ),
          rings: rings,
        ),
      );
    }
    return parsed;
  }

  void selectRegion(String regionId, {String? cityId}) {
    final targetRegion = _regions.firstWhere(
      (r) => r.regionId == regionId,
      orElse: () => _activeRegion ?? _regions.first,
    );
    _activeRegion = targetRegion;

    final String targetCityId = cityId ?? targetRegion.primaryCityId;
    final matchingCities = _cities.where((c) => c.cityId == targetCityId);
    if (matchingCities.isNotEmpty) {
      _activeCity = matchingCities.first;
      coordinateSystem.setFloatingOrigin(_activeCity!.location);
    } else {
      coordinateSystem.setFloatingOrigin(targetRegion.centroid);
    }

    final bool hasDetailed = packageManager.resolveReadiness(targetRegion) ==
        RegionReadinessStatus.installedDetailed;
    lodController.evaluateFromCamera(
      cameraZoom: hasDetailed ? 1.0 : 0.20,
      is3DPerspectiveActive: false,
      regionHasDetailedPack: hasDetailed,
    );
    notifyListeners();
  }

  RegionCatalogEntry? findRegionAtCoordinate(double lon, double lat) {
    for (final poly in _boundaries) {
      if (poly.containsPoint(lon, lat)) {
        final match = _regions.where((r) => r.regionId == poly.regionId);
        if (match.isNotEmpty) return match.first;
      }
    }
    return null;
  }
}
