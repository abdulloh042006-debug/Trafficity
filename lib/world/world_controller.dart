import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'admin_hierarchy.dart';
import 'geo_coordinate_system.dart';
import 'multi_scale_lod_controller.dart';
import 'region_package_manager.dart';

class UzbekistanWorldController extends ChangeNotifier {
  final NationalCoordinateSystem coordinateSystem = NationalCoordinateSystem();
  final RegionPackageManager packageManager = RegionPackageManager();
  final MultiScaleLodController lodController = MultiScaleLodController();

  List<RegionCatalogEntry> _regions = [];
  RegionCatalogEntry? _activeRegion;

  List<RegionCatalogEntry> get regions => List.unmodifiable(_regions);
  RegionCatalogEntry? get activeRegion => _activeRegion;

  void loadFromCatalogJson(String catalogJson) {
    final map = jsonDecode(catalogJson) as Map<String, dynamic>;
    _regions = (map['regions'] as List).map((e) => RegionCatalogEntry.fromJson(e as Map<String, dynamic>)).toList();
    _activeRegion = _regions.first;
    notifyListeners();
  }

  void selectRegion(String regionId) {
    _activeRegion = _regions.firstWhere((r) => r.regionId == regionId, orElse: () => _regions.first);
    coordinateSystem.setFloatingOrigin(_activeRegion!.centroid);
    final hasPack = packageManager.resolveReadiness(_activeRegion!) == RegionReadinessStatus.installedDetailed;
    lodController.evaluateFromCamera(cameraZoom: hasPack ? 1.0 : 0.2, is3DPerspectiveActive: false, regionHasDetailedPack: hasPack);
    notifyListeners();
  }
}
