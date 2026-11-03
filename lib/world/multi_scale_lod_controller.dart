enum GeographicalDetailLevel { level1CountryOverview, level2RegionalView, level3CityView2D, level4DetailedUrban3D }

/// Chooses the level of detail from camera zoom, 3D state and package availability.
///
/// Zoom is the game camera zoom (`RoadGame.minZoom` 0.12 .. `RoadGame.maxZoom` 3.0); larger = closer.
///
/// | condition                                              | level |
/// |--------------------------------------------------------|-------|
/// | zoom < [regionalZoomThreshold]                         | 1 country overview |
/// | zoom < [cityZoomThreshold], or no detailed package     | 2 regional view |
/// | zoom >= [cityZoomThreshold], detailed package, 2D      | 3 city 2D |
/// | zoom >= [urban3dZoomThreshold], detailed package, 3D   | 4 urban 3D |
///
/// A region without a verified detailed package never reaches level 3 or 4.
class MultiScaleLodController {
  /// Below this zoom the whole country is shown.
  static const double regionalZoomThreshold = 0.2;

  /// From this zoom on a region with a detailed package shows its city map.
  static const double cityZoomThreshold = 0.5;

  /// From this zoom on, with the 3D perspective active, the detailed 3D urban view is used.
  static const double urban3dZoomThreshold = 1.2;

  GeographicalDetailLevel _activeLevel = GeographicalDetailLevel.level2RegionalView;
  GeographicalDetailLevel get activeLevel => _activeLevel;

  /// Pure selection without touching controller state.
  static GeographicalDetailLevel levelFor({
    required double cameraZoom,
    required bool is3DPerspectiveActive,
    required bool regionHasDetailedPack,
  }) {
    if (!cameraZoom.isFinite) {
      return regionHasDetailedPack
          ? GeographicalDetailLevel.level3CityView2D
          : GeographicalDetailLevel.level2RegionalView;
    }
    if (cameraZoom < regionalZoomThreshold) return GeographicalDetailLevel.level1CountryOverview;
    if (!regionHasDetailedPack || cameraZoom < cityZoomThreshold) return GeographicalDetailLevel.level2RegionalView;
    if (is3DPerspectiveActive && cameraZoom >= urban3dZoomThreshold)
      return GeographicalDetailLevel.level4DetailedUrban3D;
    return GeographicalDetailLevel.level3CityView2D;
  }

  GeographicalDetailLevel evaluateFromCamera({
    required double cameraZoom,
    required bool is3DPerspectiveActive,
    required bool regionHasDetailedPack,
  }) {
    _activeLevel = levelFor(
      cameraZoom: cameraZoom,
      is3DPerspectiveActive: is3DPerspectiveActive,
      regionHasDetailedPack: regionHasDetailedPack,
    );
    return _activeLevel;
  }

  /// True when the active level shows playable, detailed content.
  bool get isDetailed =>
      _activeLevel == GeographicalDetailLevel.level3CityView2D ||
      _activeLevel == GeographicalDetailLevel.level4DetailedUrban3D;
}
