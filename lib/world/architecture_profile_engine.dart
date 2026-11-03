class ArchitectureProfileEngine {
  final Set<String> _excludedFootprintIds = {};
  void registerLandmarkExclusions(Iterable<String> ids) => _excludedFootprintIds.addAll(ids);
  bool isFootprintExcluded(String id) => _excludedFootprintIds.contains(id);
}
