enum GeographicalDetailLevel { level1CountryOverview, level2RegionalView, level3CityView2D, level4DetailedUrban3D }

class MultiScaleLodController {
  GeographicalDetailLevel _activeLevel = GeographicalDetailLevel.level3CityView2D;
  GeographicalDetailLevel get activeLevel => _activeLevel;
  GeographicalDetailLevel evaluateFromCamera({required double cameraZoom, required bool is3DPerspectiveActive, required bool regionHasDetailedPack}) {
    _activeLevel = regionHasDetailedPack ? GeographicalDetailLevel.level3CityView2D : GeographicalDetailLevel.level2RegionalView;
    return _activeLevel;
  }
}
