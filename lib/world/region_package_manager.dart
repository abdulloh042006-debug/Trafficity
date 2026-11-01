import 'dart:convert';
import 'dart:typed_data';
import 'admin_hierarchy.dart';

enum PackageInstallState {
  notInstalled,
  downloading,
  verifying,
  installed,
  updateAvailable,
  corrupted,
  overviewOnly,
}

class RegionPackageDescriptor {
  final String packageId;
  final String regionId;
  final String tier;
  final String datasetVersion;
  final int downloadSizeBytes;
  final String sha256;
  final List<String> featureLayers;
  final List<int> detailLevels;

  const RegionPackageDescriptor({
    required this.packageId,
    required this.regionId,
    required this.tier,
    required this.datasetVersion,
    required this.downloadSizeBytes,
    required this.sha256,
    required this.featureLayers,
    required this.detailLevels,
  });

  factory RegionPackageDescriptor.fromJson(Map<String, dynamic> json) {
    return RegionPackageDescriptor(
      packageId: json['packageId'] as String,
      regionId: json['regionId'] as String,
      tier: json['tier'] as String? ?? 'city_detail',
      datasetVersion: json['datasetVersion'] as String? ?? '2026.11.0',
      downloadSizeBytes: (json['downloadSizeBytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String? ?? '',
      featureLayers: (json['featureLayers'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      detailLevels: (json['detailLevels'] as List<dynamic>? ?? const [1, 2])
          .map((e) => (e as num).toInt())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'packageId': packageId,
        'regionId': regionId,
        'tier': tier,
        'datasetVersion': datasetVersion,
        'downloadSizeBytes': downloadSizeBytes,
        'sha256': sha256,
        'featureLayers': featureLayers,
        'detailLevels': detailLevels,
      };
}

class LocalPackageRecord {
  final String packageId;
  final String regionId;
  final String datasetVersion;
  final int sizeBytes;
  final String sha256;
  final DateTime installedAt;
  DateTime lastAccessedAt;
  bool pinnedOffline;
  PackageInstallState state;

  LocalPackageRecord({
    required this.packageId,
    required this.regionId,
    required this.datasetVersion,
    required this.sizeBytes,
    required this.sha256,
    required this.installedAt,
    required this.lastAccessedAt,
    this.pinnedOffline = true,
    this.state = PackageInstallState.installed,
  });

  factory LocalPackageRecord.fromJson(Map<String, dynamic> json) {
    return LocalPackageRecord(
      packageId: json['packageId'] as String,
      regionId: json['regionId'] as String,
      datasetVersion: json['datasetVersion'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      sha256: json['sha256'] as String,
      installedAt: DateTime.parse(json['installedAt'] as String),
      lastAccessedAt: DateTime.parse(json['lastAccessedAt'] as String),
      pinnedOffline: json['pinnedOffline'] as bool? ?? true,
      state: PackageInstallState.values.firstWhere(
        (e) => e.name == (json['state'] as String? ?? 'installed'),
        orElse: () => PackageInstallState.installed,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'packageId': packageId,
        'regionId': regionId,
        'datasetVersion': datasetVersion,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'installedAt': installedAt.toIso8601String(),
        'lastAccessedAt': lastAccessedAt.toIso8601String(),
        'pinnedOffline': pinnedOffline,
        'state': state.name,
      };
}

class Sha256Verifier {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _rotr(int x, int n) =>
      ((x & 0xffffffff) >>> n) | ((x << (32 - n)) & 0xffffffff);

  static String sha256Hex(List<int> inputBytes) {
    int h0 = 0x6a09e667;
    int h1 = 0xbb67ae85;
    int h2 = 0x3c6ef372;
    int h3 = 0xa54ff53a;
    int h4 = 0x510e527f;
    int h5 = 0x9b05688c;
    int h6 = 0x1f83d9ab;
    int h7 = 0x5be0cd19;

    final int bitLen = inputBytes.length * 8;
    final List<int> padded = List<int>.from(inputBytes)..add(0x80);
    while ((padded.length % 64) != 56) {
      padded.add(0x00);
    }
    final bd = ByteData(8)..setUint64(0, bitLen, Endian.big);
    for (int i = 0; i < 8; i++) {
      padded.add(bd.getUint8(i));
    }

    final List<int> w = List<int>.filled(64, 0);
    final chunkData = ByteData.sublistView(Uint8List.fromList(padded));

    for (int offset = 0; offset < padded.length; offset += 64) {
      for (int i = 0; i < 16; i++) {
        w[i] = chunkData.getUint32(offset + i * 4, Endian.big);
      }
      for (int i = 16; i < 64; i++) {
        final int s0 =
            _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final int s1 =
            _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      int a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

      for (int i = 0; i < 64; i++) {
        final int s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final int ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final int temp1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
        final int s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final int maj = (a & b) ^ (a & c) ^ (b & c);
        final int temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    return [h0, h1, h2, h3, h4, h5, h6, h7]
        .map((v) => v.toRadixString(16).padLeft(8, '0'))
        .join();
  }
}

class RegionPackageManager {
  final Map<String, LocalPackageRecord> _installedByRegionId = {};
  final Map<String, double> _downloadProgressByRegionId = {};

  RegionPackageManager() {
    _installedByRegionId['uz_tashkent_city'] = LocalPackageRecord(
      packageId: 'pkg_uz_tashkent_city_l3_l4',
      regionId: 'uz_tashkent_city',
      datasetVersion: '2026.11.0',
      sizeBytes: 1859500,
      sha256: 'bundled_verified_tashkent_city',
      installedAt: DateTime.utc(2026, 11, 1),
      lastAccessedAt: DateTime.utc(2026, 11, 1),
      pinnedOffline: true,
      state: PackageInstallState.installed,
    );
  }

  void restoreFromJsonString(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) return;
    try {
      final list = jsonDecode(rawJson) as List<dynamic>;
      for (final item in list) {
        final rec = LocalPackageRecord.fromJson(item as Map<String, dynamic>);
        _installedByRegionId[rec.regionId] = rec;
      }
    } catch (_) {}
  }

  String exportToJsonString() {
    final list = _installedByRegionId.values.map((e) => e.toJson()).toList();
    return jsonEncode(list);
  }

  RegionReadinessStatus resolveReadiness(RegionCatalogEntry entry) {
    final local = _installedByRegionId[entry.regionId];
    if (local != null && local.state == PackageInstallState.installed) {
      return RegionReadinessStatus.installedDetailed;
    }
    return entry.defaultReadiness;
  }

  double getDownloadProgress(String regionId) =>
      _downloadProgressByRegionId[regionId] ?? 0.0;

  bool isDetailedRegionInstalled(String regionId) {
    final rec = _installedByRegionId[regionId];
    return rec != null && rec.state == PackageInstallState.installed;
  }

  bool verifyAndInstallPackageBytes({
    required String regionId,
    required String packageId,
    required String datasetVersion,
    required List<int> payloadBytes,
    required String expectedSha256,
  }) {
    final actualHash = Sha256Verifier.sha256Hex(payloadBytes);
    if (actualHash.toLowerCase() != expectedSha256.toLowerCase()) {
      _installedByRegionId[regionId] = LocalPackageRecord(
        packageId: packageId,
        regionId: regionId,
        datasetVersion: datasetVersion,
        sizeBytes: payloadBytes.length,
        sha256: actualHash,
        installedAt: DateTime.now().toUtc(),
        lastAccessedAt: DateTime.now().toUtc(),
        state: PackageInstallState.corrupted,
      );
      return false;
    }

    _installedByRegionId[regionId] = LocalPackageRecord(
      packageId: packageId,
      regionId: regionId,
      datasetVersion: datasetVersion,
      sizeBytes: payloadBytes.length,
      sha256: actualHash,
      installedAt: DateTime.now().toUtc(),
      lastAccessedAt: DateTime.now().toUtc(),
      pinnedOffline: true,
      state: PackageInstallState.installed,
    );
    return true;
  }

  bool removeRegionPackage(String regionId) {
    if (regionId == 'uz_tashkent_city') return false;
    return _installedByRegionId.remove(regionId) != null;
  }

  List<LocalPackageRecord> get installedPackages =>
      _installedByRegionId.values.toList(growable: false);
}
