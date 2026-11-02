class ArchitectureProfileEngine {
  final Set<String> _excludedFootprintIds = {};

  void registerLandmarkExclusions(Iterable<String> footprintIds) => _excludedFootprintIds.addAll(footprintIds);

  bool isFootprintExcluded(String footprintId) => _excludedFootprintIds.contains(footprintId);
}
