import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'admin_hierarchy.dart';
import 'geo_coordinate_system.dart';
import 'multi_scale_lod_controller.dart';
import 'region_package_manager.dart';

enum WorldLoadState { idle, loading, ready, error }

/// Owns the 14-region Uzbekistan catalog, the active region, its readiness and the level of detail.
///
/// Create it once per screen (it is a [ChangeNotifier]); [initializeFromAssets] is idempotent and safe to await
/// from several places. Notifications after [dispose] are ignored, so late async completions cannot throw.
class UzbekistanWorldController extends ChangeNotifier {
  final NationalCoordinateSystem coordinateSystem = NationalCoordinateSystem();
  final RegionPackageManager packageManager = RegionPackageManager();
  final MultiScaleLodController lodController = MultiScaleLodController();

  static const String catalogAsset = 'assets/world/uzbekistan/region_catalog.json';

  List<RegionCatalogEntry> _regions = [];
  RegionCatalogEntry? _activeRegion;
  WorldLoadState _loadState = WorldLoadState.idle;
  String? _loadError;
  Future<void>? _initFuture;
  bool _disposed = false;

  // last camera input, so the level of detail can be re-evaluated when the region changes
  double _cameraZoom = 0.6;
  bool _is3D = false;

  List<RegionCatalogEntry> get regions => List.unmodifiable(_regions);
  RegionCatalogEntry? get activeRegion => _activeRegion;
  WorldLoadState get loadState => _loadState;
  String? get loadError => _loadError;
  bool get isReady => _loadState == WorldLoadState.ready;
  GeographicalDetailLevel get lodLevel => lodController.activeLevel;

  /// Loads the catalog from the bundled asset once. A failure is recorded in [loadState]/[loadError];
  /// call [retry] to try again.
  Future<void> initializeFromAssets() => _initFuture ??= _initialize();

  Future<void> retry() {
    if (_loadState == WorldLoadState.loading) return _initFuture ?? Future<void>.value();
    _initFuture = null;
    return initializeFromAssets();
  }

  Future<void> _initialize() async {
    _loadState = WorldLoadState.loading;
    _loadError = null;
    _notify();
    try {
      loadFromCatalogJson(await rootBundle.loadString(catalogAsset));
    } catch (e) {
      _loadState = WorldLoadState.error;
      _loadError = e.toString();
      _notify();
    }
  }

  void loadFromCatalogJson(String catalogJson) {
    final map = jsonDecode(catalogJson) as Map<String, dynamic>;
    final regions = (map['regions'] as List)
        .map((e) => RegionCatalogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    if (regions.isEmpty) throw const FormatException('Region catalog contains no regions');
    _regions = regions;
    packageManager.registerKnownRegions(regions.map((r) => r.regionId));
    final defaultId = map['defaultRegionId'] as String?;
    _activeRegion = regions.firstWhere((r) => r.regionId == defaultId, orElse: () => regions.first);
    coordinateSystem.setFloatingOrigin(_activeRegion!.representativePoint);
    _loadState = WorldLoadState.ready;
    _loadError = null;
    _reevaluateLod();
    _notify();
  }

  /// Readiness of [entry] as the package manager sees it (a catalog default never overstates it).
  RegionReadinessStatus readinessOf(RegionCatalogEntry entry) => packageManager.resolveReadiness(entry);

  bool get isActiveDetailed {
    final a = _activeRegion;
    return a != null && readinessOf(a) == RegionReadinessStatus.installedDetailed;
  }

  /// Makes [regionId] the active region and moves the geographic floating origin to its representative point.
  /// Returns false (and changes nothing) for an unknown id.
  bool selectRegion(String regionId) {
    RegionCatalogEntry? found;
    for (final r in _regions) {
      if (r.regionId == regionId) found = r;
    }
    if (found == null) return false;
    _activeRegion = found;
    coordinateSystem.setFloatingOrigin(found.representativePoint);
    _reevaluateLod();
    _notify();
    return true;
  }

  /// Re-selects the region a loaded save belongs to, but only when that region really has a detailed package.
  /// Returns true when the active region now is [regionId]. A tampered save naming an overview-only or unknown
  /// region changes nothing, so a loaded game is never covered by an overview card.
  bool restoreDetailedRegion(String regionId) {
    for (final r in _regions) {
      if (r.regionId != regionId) continue;
      if (readinessOf(r) != RegionReadinessStatus.installedDetailed) return false;
      if (_activeRegion?.regionId == regionId) return true;
      return selectRegion(regionId);
    }
    return false;
  }

  /// Feeds the game camera to the level-of-detail controller; listeners are told only when the level changes.
  GeographicalDetailLevel updateCamera({required double zoom, bool is3D = false}) {
    _cameraZoom = zoom;
    _is3D = is3D;
    final before = lodController.activeLevel;
    final after = _reevaluateLod();
    if (after != before) _notify();
    return after;
  }

  GeographicalDetailLevel _reevaluateLod() => lodController.evaluateFromCamera(
    cameraZoom: _cameraZoom,
    is3DPerspectiveActive: _is3D,
    regionHasDetailedPack: isActiveDetailed,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
