import 'geo_coordinate_system.dart';

/// Raised when a portal is rejected (duplicate ID, self-link, invalid position, empty IDs).
class PortalException implements Exception {
  final String message;
  const PortalException(this.message);
  @override
  String toString() => 'PortalException: $message';
}

/// A point where a real road crosses a chunk boundary.
///
/// Portals must come from real road geometry that is shared by two chunks; the linker never
/// creates connections on its own.
class PortalNode {
  final String portalId;
  final String globalWayId;
  final Wgs84Coord position;
  final String sourceChunkId;
  final String destinationChunkId;

  const PortalNode({
    required this.portalId,
    required this.globalWayId,
    required this.position,
    required this.sourceChunkId,
    required this.destinationChunkId,
  });
}

/// Tracks which chunks are loaded and which boundary portals are currently active.
///
/// A portal is **active** when exactly one of its two chunks is loaded: vehicles reaching it must
/// continue into a chunk that is not in memory yet. Portals with both chunks loaded are internal
/// links, and portals with neither chunk loaded are irrelevant.
class RoadGraphLinker {
  final Set<String> _loadedChunks = {};
  final Map<String, PortalNode> _portals = {};

  void onChunkLoaded(String chunkId) => _loadedChunks.add(chunkId);
  void onChunkUnloaded(String chunkId) => _loadedChunks.remove(chunkId);
  bool isChunkLoaded(String chunkId) => _loadedChunks.contains(chunkId);
  Set<String> get loadedChunks => Set.unmodifiable(_loadedChunks);

  int get portalCount => _portals.length;
  PortalNode? portalById(String portalId) => _portals[portalId];

  /// Registers a portal. Throws [PortalException] for empty IDs, a duplicate portal ID, a
  /// self-link (source chunk == destination chunk) or an invalid position.
  void registerPortal(PortalNode portal) {
    if (portal.portalId.isEmpty ||
        portal.globalWayId.isEmpty ||
        portal.sourceChunkId.isEmpty ||
        portal.destinationChunkId.isEmpty) {
      throw const PortalException('Portal IDs and chunk IDs must not be empty');
    }
    if (portal.sourceChunkId == portal.destinationChunkId) {
      throw PortalException('Portal ${portal.portalId} links chunk ${portal.sourceChunkId} to itself');
    }
    if (!portal.position.isValid) {
      throw PortalException('Portal ${portal.portalId} has an invalid position');
    }
    if (_portals.containsKey(portal.portalId)) {
      throw PortalException('Duplicate portal id: ${portal.portalId}');
    }
    _portals[portal.portalId] = portal;
  }

  /// Portals with exactly one loaded neighbour chunk, ordered by portal ID for determinism.
  List<PortalNode> activeBoundaryPortals() {
    final active = [
      for (final p in _portals.values)
        if (_loadedChunks.contains(p.sourceChunkId) != _loadedChunks.contains(p.destinationChunkId)) p,
    ]..sort((a, b) => a.portalId.compareTo(b.portalId));
    return List.unmodifiable(active);
  }

  /// The chunk a vehicle must load next when it reaches [portal], or null if the portal is not active.
  String? chunkToLoadFor(PortalNode portal) {
    final srcLoaded = _loadedChunks.contains(portal.sourceChunkId);
    final dstLoaded = _loadedChunks.contains(portal.destinationChunkId);
    if (srcLoaded == dstLoaded) return null;
    return srcLoaded ? portal.destinationChunkId : portal.sourceChunkId;
  }
}
