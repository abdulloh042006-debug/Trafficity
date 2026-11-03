import 'geo_coordinate_system.dart';

class RoadGraphLinker {
  final Set<String> _loadedChunks = {};
  void onChunkLoaded(String chunkId) => _loadedChunks.add(chunkId);
  bool isChunkLoaded(String chunkId) => _loadedChunks.contains(chunkId);
}
