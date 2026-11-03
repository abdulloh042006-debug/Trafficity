import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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
  bool _isInitialized = false;

  List<RegionCatalogEntry> get regions => List.unmodifiable(_regions);
  RegionCatalogEntry? get activeRegion => _activeRegion;

  Future<void> initializeFromAssets() async {
    if (_isInitialized) return;
    final raw = await rootBundle.loadString('assets/world/uzbekistan/region_catalog.json');
    loadFromCatalogJson(raw);
    _isInitialized = true;
  }

  void loadFromCatalogJson(String catalogJson) {
    final map = jsonDecode(catalogJson) as Map<String, dynamic>;
    _regions = (map['regions'] as List).map((e) => RegionCatalogEntry.fromJson(e as Map<String, dynamic>)).toList();
    _activeRegion = _regions.first;
    notifyListeners();
  }

  void selectRegion(String regionId) {
    _activeRegion = _regions.firstWhere((r) => r.regionId == regionId, orElse: () => _regions.first);
    coordinateSystem.setFloatingOrigin(_activeRegion!.centroid);
    notifyListeners();
  }
}
