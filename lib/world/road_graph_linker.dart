import 'geo_coordinate_system.dart';

enum RoadFunctionalClass {
  nationalHighway,
  regionalHighway,
  intercityConnector,
  urbanPrimary,
  urbanSecondary,
  localMahalla,
}

class StitchPortalNode {
  final String portalId;
  final String globalWayId;
  final String roadDesignation;
  final Wgs84Coord wgs84Position;
  final String fromRegionId;
  final String fromChunkId;
  final String toRegionId;
  final String toChunkId;
  final int laneCount;
  final double headingDegrees;
  final String structureType;

  const StitchPortalNode({
    required this.portalId,
    required this.globalWayId,
    required this.roadDesignation,
    required this.wgs84Position,
    required this.fromRegionId,
    required this.fromChunkId,
    required this.toRegionId,
    required this.toChunkId,
    required this.laneCount,
    required this.headingDegrees,
    this.structureType = 'SURFACE',
  });

  factory StitchPortalNode.fromJson(Map<String, dynamic> json) {
    return StitchPortalNode(
      portalId: json['portalId'] as String,
      globalWayId: json['globalWayId'] as String,
      roadDesignation: json['roadDesignation'] as String? ?? 'M39',
      wgs84Position: Wgs84Coord.fromJson(json['wgs84Position']),
      fromRegionId: json['fromRegionId'] as String,
      fromChunkId: json['fromChunkId'] as String,
      toRegionId: json['toRegionId'] as String,
      toChunkId: json['toChunkId'] as String,
      laneCount: (json['laneCount'] as num?)?.toInt() ?? 4,
      headingDegrees: (json['headingDegrees'] as num?)?.toDouble() ?? 0.0,
      structureType: json['structureType'] as String? ?? 'SURFACE',
    );
  }
}

class CrossRegionSegment {
  final String segmentId;
  final String globalWayId;
  final String regionId;
  final String chunkId;
  String startNodeId;
  String endNodeId;
  final List<Wgs84Coord> geometry;
  final int lanes;

  CrossRegionSegment({
    required this.segmentId,
    required this.globalWayId,
    required this.regionId,
    required this.chunkId,
    required this.startNodeId,
    required this.endNodeId,
    required this.geometry,
    this.lanes = 2,
  });
}

class RoadGraphLinker {
  final Map<String, StitchPortalNode> _portals = {};
  final Map<String, CrossRegionSegment> _segments = {};
  final Set<String> _loadedChunks = {};

  void registerPortals(Iterable<StitchPortalNode> portals) {
    for (final p in portals) {
      _portals[p.portalId] = p;
    }
  }

  void onChunkLoaded(String chunkId, List<CrossRegionSegment> segments) {
    _loadedChunks.add(chunkId);
    for (final seg in segments) {
      if (!_segments.containsKey(seg.segmentId)) {
        _segments[seg.segmentId] = seg;
      }
    }
    _relinkSharedPortals();
  }

  void onChunkUnloaded(String chunkId) {
    _loadedChunks.remove(chunkId);
    _segments.removeWhere((_, seg) => seg.chunkId == chunkId);
  }

  void _relinkSharedPortals() {
    for (final portal in _portals.values) {
      final bool bothLoaded = _loadedChunks.contains(portal.fromChunkId) &&
          _loadedChunks.contains(portal.toChunkId);
      if (!bothLoaded) continue;

      for (final seg in _segments.values) {
        if (seg.globalWayId == portal.globalWayId) {
          if (seg.chunkId == portal.fromChunkId &&
              NationalCoordinateSystem.geodesicDistanceMeters(
                    seg.geometry.last,
                    portal.wgs84Position,
                  ) <
                  5.0) {
            seg.endNodeId = portal.portalId;
          } else if (seg.chunkId == portal.toChunkId &&
              NationalCoordinateSystem.geodesicDistanceMeters(
                    seg.geometry.first,
                    portal.wgs84Position,
                  ) <
                  5.0) {
            seg.startNodeId = portal.portalId;
          }
        }
      }
    }
  }

  List<StitchPortalNode> getActiveBoundaryReservoirs() {
    final List<StitchPortalNode> result = [];
    for (final portal in _portals.values) {
      final bool fromLoaded = _loadedChunks.contains(portal.fromChunkId);
      final bool toLoaded = _loadedChunks.contains(portal.toChunkId);
      if (fromLoaded != toLoaded) {
        result.add(portal);
      }
    }
    return result;
  }

  int get activeSegmentCount => _segments.length;
}
