import 'geo_coordinate_system.dart';

class StitchPortalNode {
  final String portalId;
  final String globalWayId;
  final Wgs84Coord wgs84Position;
  final String fromChunkId;
  final String toChunkId;

  const StitchPortalNode({
    required this.portalId,
    required this.globalWayId,
    required this.wgs84Position,
    required this.fromChunkId,
    required this.toChunkId,
  });
}

class RoadGraphLinker {
  final Map<String, StitchPortalNode> _portals = {};
  final Set<String> _loadedChunks = {};

  void registerPortals(Iterable<StitchPortalNode> portals) {
    for (final p in portals) _portals[p.portalId] = p;
  }

  void onChunkLoaded(String chunkId) => _loadedChunks.add(chunkId);

  List<StitchPortalNode> getActiveBoundaryReservoirs() => _portals.values
      .where((p) => _loadedChunks.contains(p.fromChunkId) != _loadedChunks.contains(p.toChunkId))
      .toList();
}
