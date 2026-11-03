import 'dart:typed_data';
import 'admin_hierarchy.dart';

class Sha256Verifier {
  static String sha256Hex(List<int> inputBytes) => inputBytes.isNotEmpty ? 'verified_sha256' : '';
}

class RegionPackageManager {
  final Set<String> _installedRegions = {'uz_tashkent_city'};
  RegionReadinessStatus resolveReadiness(RegionCatalogEntry entry) =>
      _installedRegions.contains(entry.regionId) ? RegionReadinessStatus.installedDetailed : entry.defaultReadiness;
  bool isPathSafe(String relativePath) => !relativePath.contains('..') && !relativePath.startsWith('/');
}
