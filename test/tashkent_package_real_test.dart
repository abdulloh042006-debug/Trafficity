import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/world/region_package_manager.dart';

/// The bundled Tashkent package is produced by the Python migration and validated by the Node CLI; this test makes
/// the Dart implementation verify the very same bytes, so all three digest implementations are proven to agree.
void main() {
  const dir = 'assets/world/uzbekistan/regions/tashkent_city';

  test('Dart parses the real Tashkent manifest and the package digest matches the one written by Python', () {
    final text = File('$dir/manifest.json').readAsStringSync();
    final manifest = RegionPackageManifest.parse(text);
    expect(manifest.regionId, 'uz_tashkent_city');
    expect(manifest.files.length, 16);
    expect(RegionPackageManifest.computePackageDigest(manifest.files), manifest.packageSha256);
    final raw = jsonDecode(text) as Map<String, dynamic>;
    expect(raw['sourceRoadCount'], 2495);
    expect(raw['convertedRoadCount'], 2495);
    expect(raw['rejectedRoadCount'], 0);
  });

  test('every chunk file listed in the real manifest exists with the recorded size, SHA-256 and feature count', () {
    final manifest = RegionPackageManifest.parse(File('$dir/manifest.json').readAsStringSync());
    var features = 0;
    for (final f in manifest.files) {
      final file = File('$dir/${f.path}');
      expect(file.existsSync(), isTrue, reason: f.path);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, f.bytes, reason: f.path);
      expect(Sha256Verifier.verify(bytes, f.sha256), isTrue, reason: f.path);
      final chunk = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final roads = (chunk['features'] ?? chunk['roads']) as List;
      expect(roads.length, f.featureCount, reason: f.path);
      features += roads.length;
    }
    expect(features, 2495);
  });
}
