import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/world/region_package_manager.dart';
import 'package:trafficity/world/world_controller.dart';

void main() {
  test('14 Uzbekistan regions load and verify SHA-256 package integrity', () {
    final raw = File('assets/world/uzbekistan/region_catalog.json').readAsStringSync();
    final ctrl = UzbekistanWorldController()..loadFromCatalogJson(raw);
    expect(ctrl.regions.length, equals(14));

    final bytes = utf8.encode(raw);
    final digest = Sha256Verifier.sha256Hex(bytes);
    expect(digest.length, equals(64));
  });
}
