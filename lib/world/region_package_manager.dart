import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'admin_hierarchy.dart';

/// SHA-256 helpers. Digests are always lowercase hexadecimal, exactly 64 characters.
class Sha256Verifier {
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// SHA-256 of [inputBytes] as a 64-character lowercase hex string.
  static String sha256Hex(List<int> inputBytes) => sha256.convert(inputBytes).toString();

  /// Returns the normalised (trimmed, lowercase) digest, or null when it is not a valid SHA-256 hex string.
  static String? normalize(String? digest) {
    if (digest == null) return null;
    final d = digest.trim().toLowerCase();
    return _hex64.hasMatch(d) ? d : null;
  }

  /// Constant-time comparison. Fails closed: invalid or missing digests never match.
  static bool digestsMatch(String? a, String? b) {
    final na = normalize(a);
    final nb = normalize(b);
    if (na == null || nb == null) return false;
    var diff = 0;
    for (var i = 0; i < na.length; i++) {
      diff |= na.codeUnitAt(i) ^ nb.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// True only when [bytes] hash to [expectedDigest].
  static bool verify(List<int> bytes, String? expectedDigest) => digestsMatch(sha256Hex(bytes), expectedDigest);
}

/// Typed failure raised by package validation / lifecycle operations. [code] is stable and machine-readable.
class RegionPackageException implements Exception {
  final String code;
  final String message;
  const RegionPackageException(this.code, this.message);
  @override
  String toString() => 'RegionPackageException($code): $message';
}

/// One file listed in a package manifest.
class PackageFileEntry {
  final String path;
  final int bytes;
  final String sha256;
  final int featureCount;
  const PackageFileEntry({required this.path, required this.bytes, required this.sha256, this.featureCount = 0});
}

/// Region package manifest (schema documented in the repository README).
///
/// `packageSha256` = SHA-256 (UTF-8) of the concatenation, in ascending `path` order, of
/// `"<path>\t<bytes>\t<sha256>\n"` for every entry of `files`. Paths are ASCII-only so that
/// the Dart, Python and JavaScript tools sort them identically.
class RegionPackageManifest {
  static const String manifestFileName = 'manifest.json';
  static final RegExp _versionPattern = RegExp(r'^\d+\.\d+\.\d+$');
  static final RegExp _pathPattern = RegExp(r'^[A-Za-z0-9_./-]+$');

  final String schemaVersion;
  final String packageId;
  final String regionId;
  final String version;
  final String packageSha256;
  final List<PackageFileEntry> files;

  const RegionPackageManifest({
    required this.schemaVersion,
    required this.packageId,
    required this.regionId,
    required this.version,
    required this.packageSha256,
    required this.files,
  });

  static String computePackageDigest(List<PackageFileEntry> files) {
    final sorted = [...files]..sort((a, b) => a.path.compareTo(b.path));
    final sb = StringBuffer();
    for (final f in sorted) {
      sb.write('${f.path}\t${f.bytes}\t${f.sha256}\n');
    }
    return Sha256Verifier.sha256Hex(utf8.encode(sb.toString()));
  }

  static RegionPackageManifest parse(String jsonText) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const RegionPackageException('invalid_manifest', 'Manifest is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RegionPackageException('invalid_manifest', 'Manifest root must be an object');
    }
    final Map<String, dynamic> m = decoded;

    String requireString(String key) {
      final v = m[key];
      if (v is! String || v.isEmpty) {
        throw RegionPackageException('invalid_manifest', 'Manifest field "$key" must be a non-empty string');
      }
      return v;
    }

    final version = requireString('version');
    if (!_versionPattern.hasMatch(version)) {
      throw RegionPackageException('invalid_manifest', 'Manifest version "$version" must look like 1.2.3');
    }
    final rawDigest = m['packageSha256'];
    final digest = Sha256Verifier.normalize(rawDigest is String ? rawDigest : null);
    if (digest == null) {
      throw const RegionPackageException(
        'invalid_manifest',
        'Manifest packageSha256 must be 64 lowercase hex characters',
      );
    }
    final rawFiles = m['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw const RegionPackageException('invalid_manifest', 'Manifest files must be a non-empty list');
    }
    final files = <PackageFileEntry>[];
    final seen = <String>{};
    for (final raw in rawFiles) {
      if (raw is! Map<String, dynamic>) {
        throw const RegionPackageException('invalid_manifest', 'Each manifest file entry must be an object');
      }
      final path = raw['path'];
      final bytes = raw['bytes'];
      final rawFileDigest = raw['sha256'];
      final fileDigest = Sha256Verifier.normalize(rawFileDigest is String ? rawFileDigest : null);
      if (path is! String || !_pathPattern.hasMatch(path) || !RegionPackageManager.isSafeRelativePath(path)) {
        throw RegionPackageException('invalid_manifest', 'Unsafe or invalid manifest file path: $path');
      }
      if (path == manifestFileName) {
        throw const RegionPackageException('invalid_manifest', 'manifest.json must not list itself');
      }
      if (bytes is! int || bytes < 0) {
        throw RegionPackageException('invalid_manifest', 'Invalid byte size for $path');
      }
      if (fileDigest == null) {
        throw RegionPackageException('invalid_manifest', 'Invalid sha256 for $path');
      }
      if (!seen.add(path)) {
        throw RegionPackageException('invalid_manifest', 'Duplicate manifest path: $path');
      }
      final fc = raw['featureCount'];
      files.add(PackageFileEntry(path: path, bytes: bytes, sha256: fileDigest, featureCount: fc is int ? fc : 0));
    }
    return RegionPackageManifest(
      schemaVersion: requireString('schemaVersion'),
      packageId: requireString('packageId'),
      regionId: requireString('regionId'),
      version: version,
      packageSha256: digest,
      files: List.unmodifiable(files),
    );
  }
}

/// Persisted record of an installed region package.
class InstalledPackage {
  final String regionId;
  final String packageId;
  final String version;
  final String packageSha256;
  const InstalledPackage({
    required this.regionId,
    required this.packageId,
    required this.version,
    required this.packageSha256,
  });

  Map<String, dynamic> toJson() => {
    'regionId': regionId,
    'packageId': packageId,
    'version': version,
    'packageSha256': packageSha256,
  };

  static InstalledPackage? tryFromJson(String regionId, Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final packageId = json['packageId'];
    final version = json['version'];
    final digest = json['packageSha256'];
    if (packageId is! String || version is! String || digest is! String) return null;
    return InstalledPackage(regionId: regionId, packageId: packageId, version: version, packageSha256: digest);
  }
}

/// Installs, updates, removes and lists region data packages and resolves region readiness.
///
/// Storage layout under [rootDirectory]:
///   packages/<regionId>/   installed package (manifest.json + files)
///   staging/               temporary extraction area, always cleared on start
///   backup/<regionId>/     previous version kept while an update is being promoted
///   installed_state.json   persisted state (written atomically via temp file + rename)
///
/// Regions in [bundledRegionIds] ship inside the app assets (Tashkent) and are always ready.
/// A manager created without a root directory can only resolve readiness; installs are rejected.
class RegionPackageManager {
  final Directory? _root;
  final Set<String> _bundledRegionIds;
  final Set<String> _knownRegionIds = {};
  Map<String, InstalledPackage> _installed = {};

  /// Test hook: called with a stage name ('extracted', 'promoted'); throwing simulates a crash.
  @visibleForTesting
  Future<void> Function(String stage)? debugFailureHook;

  RegionPackageManager({Set<String> bundledRegionIds = const {'uz_tashkent_city'}})
    : _root = null,
      _bundledRegionIds = bundledRegionIds;

  RegionPackageManager._(this._root, this._bundledRegionIds);

  /// Opens a persistent manager: recovers from incomplete installs and loads the saved state.
  static Future<RegionPackageManager> open({
    required Directory rootDirectory,
    Set<String> bundledRegionIds = const {'uz_tashkent_city'},
    Iterable<String> knownRegionIds = const [],
  }) async {
    final m = RegionPackageManager._(rootDirectory, bundledRegionIds);
    m._knownRegionIds.addAll(knownRegionIds);
    await rootDirectory.create(recursive: true);
    await m._loadState();
    await m._recover();
    return m;
  }

  /// Region IDs the manager accepts packages for (from the catalog). Unknown regions are rejected.
  void registerKnownRegions(Iterable<String> regionIds) {
    _knownRegionIds
      ..clear()
      ..addAll(regionIds);
  }

  List<InstalledPackage> get installedPackages {
    final list = _installed.values.toList()..sort((a, b) => a.regionId.compareTo(b.regionId));
    return List.unmodifiable(list);
  }

  bool isInstalled(String regionId) => _bundledRegionIds.contains(regionId) || _installed.containsKey(regionId);

  InstalledPackage? installedPackage(String regionId) => _installed[regionId];

  /// Directory holding an installed (non-bundled) package, or null.
  Directory? installedDirectory(String regionId) {
    final root = _root;
    if (root == null || !_installed.containsKey(regionId)) return null;
    return Directory(p.join(root.path, 'packages', regionId));
  }

  /// A region is only "installed detailed" when its data is bundled or a validated package is installed.
  /// A catalog default that claims detailed data without a real package never overstates readiness.
  RegionReadinessStatus resolveReadiness(RegionCatalogEntry entry) {
    if (isInstalled(entry.regionId)) return RegionReadinessStatus.installedDetailed;
    return entry.defaultReadiness == RegionReadinessStatus.installedDetailed
        ? RegionReadinessStatus.overviewOnly
        : entry.defaultReadiness;
  }

  /// Instance form of [isSafeRelativePath].
  bool isPathSafe(String relativePath) => isSafeRelativePath(relativePath);

  /// Rejects absolute paths, drive prefixes, NUL bytes, empty/`.`/`..` segments (a trailing slash is allowed).
  static bool isSafeRelativePath(String relativePath) {
    if (relativePath.isEmpty) return false;
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.startsWith('/')) return false;
    if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
    if (normalized.contains('\u0000')) return false;
    final trimmed = normalized.endsWith('/') ? normalized.substring(0, normalized.length - 1) : normalized;
    if (trimmed.isEmpty) return false;
    for (final seg in trimmed.split('/')) {
      if (seg.isEmpty || seg == '.' || seg == '..') return false;
    }
    return true;
  }

  /// True when a ZIP/unix mode marks a symbolic link.
  static bool isSymlinkMode(int mode) => (mode & 0xF000) == 0xA000;

  static int compareVersions(String a, String b) {
    final pa = a.split('.').map(int.parse).toList();
    final pb = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final c = pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  Directory _requireRoot() {
    final root = _root;
    if (root == null) {
      throw const RegionPackageException('storage_unavailable', 'This manager has no storage directory');
    }
    return root;
  }

  /// Validates [zipBytes] completely (paths, manifest, sizes, digests) and returns the manifest.
  /// Nothing is written to disk.
  RegionPackageManifest validateArchive(Uint8List zipBytes) => _validate(zipBytes).manifest;

  ({RegionPackageManifest manifest, Map<String, List<int>> entries}) _validate(Uint8List zipBytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const RegionPackageException('invalid_archive', 'Package is not a readable ZIP archive');
    }
    final entries = <String, List<int>>{};
    for (final f in archive.files) {
      final name = f.name.replaceAll('\\', '/');
      if (!isSafeRelativePath(name)) {
        throw RegionPackageException('unsafe_path', 'Unsafe path in archive: ${f.name}');
      }
      if (isSymlinkMode(f.mode)) {
        throw RegionPackageException('symlink_entry', 'Symbolic links are not allowed: ${f.name}');
      }
      if (!f.isFile) continue;
      if (entries.containsKey(name)) {
        throw RegionPackageException('duplicate_entry', 'Duplicate archive entry: $name');
      }
      entries[name] = f.content as List<int>;
    }
    final manifestBytes = entries[RegionPackageManifest.manifestFileName];
    if (manifestBytes == null) {
      throw const RegionPackageException('missing_manifest', 'Archive has no manifest.json');
    }
    String manifestText;
    try {
      manifestText = utf8.decode(manifestBytes);
    } on FormatException {
      throw const RegionPackageException('invalid_manifest', 'manifest.json is not valid UTF-8');
    }
    final manifest = RegionPackageManifest.parse(manifestText);
    if (!_knownRegionIds.contains(manifest.regionId)) {
      throw RegionPackageException('unknown_region', 'Unknown region id: ${manifest.regionId}');
    }
    final listed = <String>{RegionPackageManifest.manifestFileName};
    for (final f in manifest.files) {
      listed.add(f.path);
      final data = entries[f.path];
      if (data == null) {
        throw RegionPackageException('missing_file', 'Listed file is missing from the archive: ${f.path}');
      }
      if (data.length != f.bytes) {
        throw RegionPackageException('size_mismatch', 'Size mismatch for ${f.path}: ${data.length} != ${f.bytes}');
      }
      if (!Sha256Verifier.verify(data, f.sha256)) {
        throw RegionPackageException('hash_mismatch', 'SHA-256 mismatch for ${f.path}');
      }
    }
    for (final name in entries.keys) {
      if (!listed.contains(name)) {
        throw RegionPackageException('unlisted_file', 'Archive contains a file not listed in the manifest: $name');
      }
    }
    if (!Sha256Verifier.digestsMatch(
      RegionPackageManifest.computePackageDigest(manifest.files),
      manifest.packageSha256,
    )) {
      throw const RegionPackageException('package_hash_mismatch', 'Package digest does not match the file list');
    }
    return (manifest: manifest, entries: entries);
  }

  /// Installs a new package or updates an existing one. The region is marked installed only after
  /// every validation and extraction step succeeded; a failed update keeps the previous version.
  Future<InstalledPackage> installFromZip(Uint8List zipBytes) async {
    final root = _requireRoot();
    final validated = _validate(zipBytes);
    final manifest = validated.manifest;
    final regionId = manifest.regionId;
    if (_bundledRegionIds.contains(regionId)) {
      throw RegionPackageException('bundled_region', 'Region $regionId is bundled with the app and cannot be replaced');
    }
    final existing = _installed[regionId];
    if (existing != null) {
      final c = compareVersions(manifest.version, existing.version);
      if (c == 0) {
        throw RegionPackageException(
          'already_installed',
          'Version ${manifest.version} of $regionId is already installed',
        );
      }
      if (c < 0) {
        throw RegionPackageException(
          'downgrade_rejected',
          'Refusing to downgrade $regionId from ${existing.version} to ${manifest.version}',
        );
      }
    }

    final stagingRoot = Directory(p.join(root.path, 'staging'));
    final staging = Directory(p.join(stagingRoot.path, '$regionId-${DateTime.now().microsecondsSinceEpoch}'));
    try {
      await staging.create(recursive: true);
      for (final entry in validated.entries.entries) {
        final dest = p.normalize(p.join(staging.path, entry.key));
        if (!p.isWithin(staging.path, dest)) {
          throw RegionPackageException('unsafe_path', 'Path escapes the installation directory: ${entry.key}');
        }
        final file = File(dest);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
      await debugFailureHook?.call('extracted');
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }

    final packagesDir = Directory(p.join(root.path, 'packages'));
    await packagesDir.create(recursive: true);
    final target = Directory(p.join(packagesDir.path, regionId));
    final backup = Directory(p.join(root.path, 'backup', regionId));
    final hadOld = await target.exists();
    if (hadOld) {
      await backup.parent.create(recursive: true);
      if (await backup.exists()) await backup.delete(recursive: true);
      await target.rename(backup.path);
    }
    final record = InstalledPackage(
      regionId: regionId,
      packageId: manifest.packageId,
      version: manifest.version,
      packageSha256: manifest.packageSha256,
    );
    try {
      await staging.rename(target.path);
      await debugFailureHook?.call('promoted');
      final next = Map<String, InstalledPackage>.of(_installed)..[regionId] = record;
      await _writeState(next);
      _installed = next;
    } catch (_) {
      if (await target.exists()) await target.delete(recursive: true);
      if (hadOld) await backup.rename(target.path);
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
    if (hadOld && await backup.exists()) await backup.delete(recursive: true);
    return record;
  }

  /// Removes an installed package and persists the new state first, then deletes its files.
  Future<void> removeRegion(String regionId) async {
    final root = _requireRoot();
    if (_bundledRegionIds.contains(regionId)) {
      throw RegionPackageException('bundled_region', 'Region $regionId is bundled with the app and cannot be removed');
    }
    if (!_installed.containsKey(regionId)) {
      throw RegionPackageException('not_installed', 'Region $regionId is not installed');
    }
    final next = Map<String, InstalledPackage>.of(_installed)..remove(regionId);
    await _writeState(next);
    _installed = next;
    final dir = Directory(p.join(root.path, 'packages', regionId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  File get _stateFile => File(p.join(_requireRoot().path, 'installed_state.json'));

  Future<void> _writeState(Map<String, InstalledPackage> state) async {
    final root = _requireRoot();
    final payload = jsonEncode({
      'schemaVersion': 1,
      'installed': {for (final e in state.entries) e.key: e.value.toJson()},
    });
    final tmp = File(p.join(root.path, 'installed_state.json.tmp'));
    await tmp.writeAsString(payload, flush: true);
    await tmp.rename(_stateFile.path);
  }

  Future<void> _loadState() async {
    final file = _stateFile;
    if (!await file.exists()) {
      _installed = {};
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      final installed = (decoded is Map<String, dynamic>) ? decoded['installed'] : null;
      final result = <String, InstalledPackage>{};
      if (installed is Map<String, dynamic>) {
        for (final e in installed.entries) {
          final rec = InstalledPackage.tryFromJson(e.key, e.value);
          if (rec != null) result[e.key] = rec;
        }
      }
      _installed = result;
    } on FormatException {
      // Corrupt state is never trusted: keep the evidence and start with nothing installed.
      await file.rename('${file.path}.corrupt');
      _installed = {};
    }
  }

  Future<String?> _readManifestVersion(Directory dir) async {
    try {
      final f = File(p.join(dir.path, RegionPackageManifest.manifestFileName));
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map<String, dynamic> && decoded['version'] is String) {
        return decoded['version'] as String;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Cleans up after an interrupted install/update and reconciles disk with the saved state.
  Future<void> _recover() async {
    final root = _requireRoot();
    final staging = Directory(p.join(root.path, 'staging'));
    if (await staging.exists()) await staging.delete(recursive: true);

    final packages = Directory(p.join(root.path, 'packages'));
    final backupRoot = Directory(p.join(root.path, 'backup'));
    if (await backupRoot.exists()) {
      final backups = await backupRoot.list().toList();
      for (final ent in backups) {
        if (ent is! Directory) continue;
        final regionId = p.basename(ent.path);
        final target = Directory(p.join(packages.path, regionId));
        final stateVersion = _installed[regionId]?.version;
        final dirVersion = await _readManifestVersion(target);
        if (stateVersion != null && dirVersion == stateVersion) {
          await ent.delete(recursive: true); // promotion had completed
        } else {
          if (await target.exists()) await target.delete(recursive: true);
          await ent.rename(target.path); // roll back to the previous version
        }
      }
    }

    var changed = false;
    if (await packages.exists()) {
      final dirs = await packages.list().toList();
      for (final ent in dirs) {
        if (ent is! Directory) continue;
        if (!_installed.containsKey(p.basename(ent.path))) {
          await ent.delete(recursive: true); // orphan of an interrupted install
        }
      }
    }
    final next = Map<String, InstalledPackage>.of(_installed);
    for (final rec in _installed.values) {
      final dirVersion = await _readManifestVersion(Directory(p.join(packages.path, rec.regionId)));
      if (dirVersion != rec.version) {
        next.remove(rec.regionId);
        changed = true;
      }
    }
    if (changed) {
      await _writeState(next);
      _installed = next;
    }
  }
}
