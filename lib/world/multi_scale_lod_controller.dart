enum GeographicalDetailLevel {
  level1CountryOverview,
  level2RegionalView,
  level3CityView2D,
  level4DetailedUrban3D,
}

class MultiScaleLodController {
  GeographicalDetailLevel _activeLevel = GeographicalDetailLevel.level3CityView2D;
  GeographicalDetailLevel get activeLevel => _activeLevel;

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
}
