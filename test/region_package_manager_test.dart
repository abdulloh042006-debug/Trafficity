import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/world/admin_hierarchy.dart';
import 'package:trafficity/world/geo_coordinate_system.dart';
import 'package:trafficity/world/region_package_manager.dart';

const _known = ['uz_tashkent_city', 'uz_samarkand', 'uz_bukhara'];

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

/// Builds a package ZIP. [mutate] can corrupt the result for negative tests.
Uint8List _buildZip({
  String regionId = 'uz_samarkand',
  String version = '1.0.0',
  Map<String, String>? files,
  String? overridePackageSha,
  Map<String, String>? extraEntries,
  bool omitManifest = false,
  bool omitListedFile = false,
  String? tamperPath,
}) {
  final payload = files ?? {'chunks/chunk_0_0.json': '{"roads":[1,2,3]}', 'data/readme.txt': 'hello'};
  final entries = [
    for (final e in payload.entries)
      PackageFileEntry(
        path: e.key,
        bytes: utf8.encode(e.value).length,
        sha256: Sha256Verifier.sha256Hex(utf8.encode(e.value)),
        featureCount: 1,
      ),
  ];
  final manifest = {
    'schemaVersion': '3.0.0',
    'packageId': 'pkg_$regionId',
    'regionId': regionId,
    'version': version,
    'packageSha256': overridePackageSha ?? RegionPackageManifest.computePackageDigest(entries),
    'files': [
      for (final f in entries) {'path': f.path, 'bytes': f.bytes, 'sha256': f.sha256, 'featureCount': f.featureCount},
    ],
  };
  final archive = Archive();
  if (!omitManifest) {
    final mb = _utf8(jsonEncode(manifest));
    archive.addFile(ArchiveFile('manifest.json', mb.length, mb));
  }
  var skipped = false;
  for (final e in payload.entries) {
    if (omitListedFile && !skipped) {
      skipped = true;
      continue;
    }
    final text = e.key == tamperPath ? '${e.value}-tampered' : e.value;
    final b = _utf8(text);
    archive.addFile(ArchiveFile(e.key, b.length, b));
  }
  for (final e in (extraEntries ?? <String, String>{}).entries) {
    final b = _utf8(e.value);
    archive.addFile(ArchiveFile(e.key, b.length, b));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

RegionCatalogEntry _entry(String id, RegionReadinessStatus readiness) => RegionCatalogEntry(
      regionId: id,
      isoCode: 'UZ-XX',
      soatoCode: '0000',
      names: const LocalizedName(uz: 'x', ru: 'x', en: 'x'),
      centroid: const Wgs84Coord(lon: 66.9, lat: 39.6),
      bbox: const GeoBoundingBox(minLon: 66.0, minLat: 39.0, maxLon: 68.0, maxLat: 40.0),
      architectureProfileId: 'p',
      defaultReadiness: readiness,
    );

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('trafficity_pkg_test_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<RegionPackageManager> openManager() => RegionPackageManager.open(rootDirectory: root, knownRegionIds: _known);

  group('SHA-256', () {
    test('known answer: "abc"', () {
      expect(
        Sha256Verifier.sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('known answer: empty input', () {
      expect(
        Sha256Verifier.sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('digest is lowercase hex of exactly 64 characters and never the old placeholder', () {
      final d = Sha256Verifier.sha256Hex(utf8.encode('anything'));
      expect(d.length, 64);
      expect(d, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(d, isNot('verified_sha256'));
    });

    test('a changed payload fails verification, the correct payload passes', () {
      const good = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      expect(Sha256Verifier.verify(utf8.encode('abc'), good), isTrue);
      expect(Sha256Verifier.verify(utf8.encode('abd'), good), isFalse);
      expect(Sha256Verifier.verify(utf8.encode('abc'), good.toUpperCase()), isTrue);
    });

    test('invalid or missing digests fail closed', () {
      expect(Sha256Verifier.verify(utf8.encode('abc'), null), isFalse);
      expect(Sha256Verifier.verify(utf8.encode('abc'), ''), isFalse);
      expect(Sha256Verifier.verify(utf8.encode('abc'), 'verified_sha256'), isFalse);
      expect(Sha256Verifier.normalize('abc'), isNull);
    });
  });

  group('path safety', () {
    test('rejects traversal, absolute and drive paths', () {
      for (final bad in ['../evil', 'a/../../evil', '/etc/passwd', r'C:\win', 'C:/win', 'a//b', './a', '', 'a/\u0000b', r'..\evil']) {
        expect(RegionPackageManager.isSafeRelativePath(bad), isFalse, reason: bad);
      }
    });

    test('accepts normal relative paths', () {
      for (final ok in ['manifest.json', 'chunks/chunk_0_0.json', 'a/b/c.txt', 'dir/']) {
        expect(RegionPackageManager.isSafeRelativePath(ok), isTrue, reason: ok);
      }
    });

    test('symbolic-link mode bits are recognised', () {
      expect(RegionPackageManager.isSymlinkMode(0xA1FF), isTrue);
      expect(RegionPackageManager.isSymlinkMode(0x81A4), isFalse);
    });
  });

  group('install lifecycle', () {
    test('a correct archive installs and is persisted', () async {
      final m = await openManager();
      final rec = await m.installFromZip(_buildZip());
      expect(rec.regionId, 'uz_samarkand');
      expect(rec.version, '1.0.0');
      expect(m.isInstalled('uz_samarkand'), isTrue);
      final dir = m.installedDirectory('uz_samarkand')!;
      expect(File('${dir.path}/chunks/chunk_0_0.json').readAsStringSync(), '{"roads":[1,2,3]}');
      expect(File('${dir.path}/manifest.json').existsSync(), isTrue);
    });

    test('install state survives manager reconstruction', () async {
      final m = await openManager();
      await m.installFromZip(_buildZip());
      final again = await openManager();
      expect(again.isInstalled('uz_samarkand'), isTrue);
      expect(again.installedPackage('uz_samarkand')!.version, '1.0.0');
    });

    test('a corrupted payload hash is rejected and nothing is installed', () async {
      final m = await openManager();
      await expectLater(
        m.installFromZip(_buildZip(tamperPath: 'data/readme.txt')),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', anyOf('hash_mismatch', 'size_mismatch'))),
      );
      expect(m.isInstalled('uz_samarkand'), isFalse);
    });

    test('a wrong package digest is rejected', () async {
      final m = await openManager();
      await expectLater(
        m.installFromZip(_buildZip(overridePackageSha: 'a' * 64)),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'package_hash_mismatch')),
      );
      expect(m.isInstalled('uz_samarkand'), isFalse);
    });

    test('a manifest-listed file missing from the archive is rejected', () async {
      final m = await openManager();
      await expectLater(
        m.installFromZip(_buildZip(omitListedFile: true)),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'missing_file')),
      );
      expect(m.isInstalled('uz_samarkand'), isFalse);
    });

    test('an archive without manifest.json is rejected', () async {
      final m = await openManager();
      await expectLater(
        m.installFromZip(_buildZip(omitManifest: true)),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'missing_manifest')),
      );
    });

    test('an unlisted extra file is rejected', () async {
      final m = await openManager();
      await expectLater(
        m.installFromZip(_buildZip(extraEntries: {'extra.bin': 'x'})),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'unlisted_file')),
      );
    });

    test('a path traversal archive is rejected and nothing escapes the install root', () async {
      final m = await openManager();
      final sentinel = File('${root.parent.path}/trafficity_evil_${root.path.hashCode}.txt');
      await expectLater(
        m.installFromZip(_buildZip(extraEntries: {'../${sentinel.uri.pathSegments.last}': 'pwned'})),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'unsafe_path')),
      );
      expect(sentinel.existsSync(), isFalse);
      expect(m.isInstalled('uz_samarkand'), isFalse);
    });

    test('an absolute path entry is rejected', () async {
      final m = await openManager();
      await expectLater(
        m.installFromZip(_buildZip(extraEntries: {'/tmp/trafficity_abs.txt': 'x'})),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'unsafe_path')),
      );
    });

    test('unknown region ids are rejected', () async {
      final m = await openManager();
      await expectLater(
        m.installFromZip(_buildZip(regionId: 'uz_atlantis')),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'unknown_region')),
      );
    });

    test('garbage bytes are rejected as an invalid archive', () async {
      final m = await openManager();
      await expectLater(
        m.installFromZip(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'invalid_archive')),
      );
    });

    test('bundled Tashkent cannot be replaced through the manager', () async {
      final m = await openManager();
      await expectLater(
        m.installFromZip(_buildZip(regionId: 'uz_tashkent_city')),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'bundled_region')),
      );
    });

    test('an interrupted install does not mark the region installed and is cleaned on restart', () async {
      final m = await openManager();
      m.debugFailureHook = (stage) async {
        if (stage == 'extracted') throw StateError('simulated crash');
      };
      await expectLater(m.installFromZip(_buildZip()), throwsA(isA<StateError>()));
      expect(m.isInstalled('uz_samarkand'), isFalse);
      final again = await openManager();
      expect(again.isInstalled('uz_samarkand'), isFalse);
      expect(Directory('${root.path}/staging').existsSync(), isFalse);
    });

    test('a crash after promotion on a fresh install leaves nothing installed', () async {
      final m = await openManager();
      m.debugFailureHook = (stage) async {
        if (stage == 'promoted') throw StateError('simulated crash');
      };
      await expectLater(m.installFromZip(_buildZip()), throwsA(isA<StateError>()));
      expect(m.isInstalled('uz_samarkand'), isFalse);
      expect(Directory('${root.path}/packages/uz_samarkand').existsSync(), isFalse);
    });

    test('an update installs the new version', () async {
      final m = await openManager();
      await m.installFromZip(_buildZip());
      final rec = await m.installFromZip(_buildZip(version: '1.1.0', files: {'chunks/chunk_0_0.json': '{"roads":[9]}'}));
      expect(rec.version, '1.1.0');
      final dir = m.installedDirectory('uz_samarkand')!;
      expect(File('${dir.path}/chunks/chunk_0_0.json').readAsStringSync(), '{"roads":[9]}');
      expect(File('${dir.path}/data/readme.txt').existsSync(), isFalse);
      expect(Directory('${root.path}/backup/uz_samarkand').existsSync(), isFalse);
    });

    test('a failed update (invalid new package) preserves the old version', () async {
      final m = await openManager();
      await m.installFromZip(_buildZip());
      await expectLater(
        m.installFromZip(_buildZip(version: '1.1.0', tamperPath: 'data/readme.txt')),
        throwsA(isA<RegionPackageException>()),
      );
      expect(m.installedPackage('uz_samarkand')!.version, '1.0.0');
      final dir = m.installedDirectory('uz_samarkand')!;
      expect(File('${dir.path}/data/readme.txt').readAsStringSync(), 'hello');
    });

    test('a crash during promotion of an update rolls back to the old version', () async {
      final m = await openManager();
      await m.installFromZip(_buildZip());
      m.debugFailureHook = (stage) async {
        if (stage == 'promoted') throw StateError('simulated crash');
      };
      await expectLater(
        m.installFromZip(_buildZip(version: '1.1.0', files: {'chunks/chunk_0_0.json': '{"roads":[9]}'})),
        throwsA(isA<StateError>()),
      );
      expect(m.installedPackage('uz_samarkand')!.version, '1.0.0');
      final dir = m.installedDirectory('uz_samarkand')!;
      expect(File('${dir.path}/chunks/chunk_0_0.json').readAsStringSync(), '{"roads":[1,2,3]}');
      final again = await openManager();
      expect(again.installedPackage('uz_samarkand')!.version, '1.0.0');
    });

    test('same version and downgrades are rejected', () async {
      final m = await openManager();
      await m.installFromZip(_buildZip(version: '2.0.0'));
      await expectLater(
        m.installFromZip(_buildZip(version: '2.0.0')),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'already_installed')),
      );
      await expectLater(
        m.installFromZip(_buildZip(version: '1.9.9')),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'downgrade_rejected')),
      );
    });

    test('removal updates persisted state and deletes files', () async {
      final m = await openManager();
      await m.installFromZip(_buildZip());
      await m.removeRegion('uz_samarkand');
      expect(m.isInstalled('uz_samarkand'), isFalse);
      expect(Directory('${root.path}/packages/uz_samarkand').existsSync(), isFalse);
      final again = await openManager();
      expect(again.isInstalled('uz_samarkand'), isFalse);
    });

    test('removing an unknown or bundled region is rejected', () async {
      final m = await openManager();
      await expectLater(
        m.removeRegion('uz_bukhara'),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'not_installed')),
      );
      await expectLater(
        m.removeRegion('uz_tashkent_city'),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'bundled_region')),
      );
    });

    test('a package directory deleted behind the manager is dropped from state on restart', () async {
      final m = await openManager();
      await m.installFromZip(_buildZip());
      Directory('${root.path}/packages/uz_samarkand').deleteSync(recursive: true);
      final again = await openManager();
      expect(again.isInstalled('uz_samarkand'), isFalse);
    });

    test('a manager without storage rejects installs', () async {
      final m = RegionPackageManager();
      m.registerKnownRegions(_known);
      await expectLater(
        m.installFromZip(_buildZip()),
        throwsA(isA<RegionPackageException>().having((e) => e.code, 'code', 'storage_unavailable')),
      );
    });
  });

  group('readiness', () {
    test('Tashkent is bundled and ready; other regions stay overview-only', () async {
      final m = RegionPackageManager();
      expect(m.resolveReadiness(_entry('uz_tashkent_city', RegionReadinessStatus.installedDetailed)), RegionReadinessStatus.installedDetailed);
      expect(m.resolveReadiness(_entry('uz_samarkand', RegionReadinessStatus.overviewOnly)), RegionReadinessStatus.overviewOnly);
    });

    test('a catalog default that claims detailed data without a package is not trusted', () {
      final m = RegionPackageManager();
      expect(m.resolveReadiness(_entry('uz_bukhara', RegionReadinessStatus.installedDetailed)), RegionReadinessStatus.overviewOnly);
    });

    test('an installed package makes the region detailed', () async {
      final m = await openManager();
      await m.installFromZip(_buildZip());
      expect(m.resolveReadiness(_entry('uz_samarkand', RegionReadinessStatus.overviewOnly)), RegionReadinessStatus.installedDetailed);
    });
  });

  group('manifest parsing', () {
    test('package digest is order independent and covers path, size and hash', () {
      const a = PackageFileEntry(path: 'a.json', bytes: 1, sha256: 'aa');
      const b = PackageFileEntry(path: 'b.json', bytes: 2, sha256: 'bb');
      expect(RegionPackageManifest.computePackageDigest([a, b]), RegionPackageManifest.computePackageDigest([b, a]));
      const a2 = PackageFileEntry(path: 'a.json', bytes: 9, sha256: 'aa');
      expect(RegionPackageManifest.computePackageDigest([a, b]), isNot(RegionPackageManifest.computePackageDigest([a2, b])));
    });

    test('malformed manifests are rejected with a typed error', () {
      for (final bad in ['not json', '[]', '{}', '{"version":"1.0","files":[]}']) {
        expect(() => RegionPackageManifest.parse(bad), throwsA(isA<RegionPackageException>()), reason: bad);
      }
    });
  });
}
