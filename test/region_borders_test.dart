import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/world/region_borders.dart';

String ring(List<List<double>> pts) => jsonEncode(pts);

String doc(Map<String, Object?> regions, {String schema = RegionBorders.schema}) =>
    jsonEncode({'schema': schema, 'notice': 'n', 'regions': regions});

Map<String, Object?> square(double x, double y, double s, {List<List<double>>? hole}) => {
  'isoCode': 'UZ-X',
  'polygons': [
    [
      [
        [x, y],
        [x + s, y],
        [x + s, y + s],
        [x, y + s],
        [x, y],
      ],
      if (hole != null) hole,
    ],
  ],
};

void main() {
  final realText = File('assets/world/uzbekistan/region_borders.json').readAsStringSync();
  final catalog = jsonDecode(File('assets/world/uzbekistan/region_catalog.json').readAsStringSync()) as Map;
  final regions = (catalog['regions'] as List).cast<Map<String, dynamic>>();

  group('real outlines (assets/world/uzbekistan/region_borders.json)', () {
    final b = RegionBorders.fromJson(realText);

    test('14 regions, exactly the catalog ids, inside the Uzbekistan extent', () {
      expect(b.shapes.map((s) => s.regionId).toSet(), regions.map((r) => r['regionId']).toSet());
      expect(b.shapes.length, 14);
      expect(b.bounds.left, inInclusiveRange(55.9, 57.0)); // west of Karakalpakstan
      expect(b.bounds.right, inInclusiveRange(72.0, 73.2)); // east of Andijan
      expect(b.bounds.top, inInclusiveRange(37.1, 38.0)); // south of Surkhandarya
      expect(b.bounds.bottom, inInclusiveRange(44.0, 45.6)); // north of Karakalpakstan
      expect(b.notice, contains('not legal'));
    });

    test('every catalog representative point hits its own region (a city beats its province)', () {
      for (final r in regions) {
        final rp = r['representativePoint'] as List;
        expect(
          b.hitTest((rp[0] as num).toDouble(), (rp[1] as num).toDouble()),
          r['regionId'],
          reason: '${r['regionId']}',
        );
      }
    });

    test('points outside the country hit nothing', () {
      expect(b.hitTest(0, 0), isNull);
      expect(b.hitTest(60.0, 50.0), isNull); // Kazakhstan
      expect(b.hitTest(70.0, 35.0), isNull); // Afghanistan
      expect(b.hitTest(74.5, 41.0), isNull); // Kyrgyzstan
    });

    test('known places fall in the right region', () {
      expect(b.hitTest(66.96, 39.65), 'uz_samarkand');
      expect(b.hitTest(64.42, 39.77), 'uz_bukhara');
      expect(b.hitTest(71.78, 40.38), 'uz_fergana');
      expect(b.hitTest(60.63, 41.55), 'uz_khorezm');
      expect(b.hitTest(69.28, 41.31), 'uz_tashkent_city');
    });
  });

  group('projection', () {
    test('project/unproject round trip and axis directions', () {
      final p = RegionBorders.project(69.28, 41.31);
      final back = RegionBorders.unproject(p);
      expect(back.dx, closeTo(69.28, 1e-9));
      expect(back.dy, closeTo(41.31, 1e-9));
      // east is +x, north is -y (screen convention)
      expect(RegionBorders.project(70, 41).dx, greaterThan(RegionBorders.project(69, 41).dx));
      expect(RegionBorders.project(69, 42).dy, lessThan(RegionBorders.project(69, 41).dy));
    });
  });

  group('parsing and hit testing of synthetic documents', () {
    test('holes are respected and the smallest overlapping shape wins', () {
      final b = RegionBorders.fromJson(
        doc({
          'big': square(
            0,
            0,
            10,
            hole: [
              [3, 3],
              [3, 6],
              [6, 6],
              [6, 3],
              [3, 3],
            ],
          ),
          'small': square(4, 4, 1),
        }),
      );
      expect(b.hitTest(1, 1), 'big');
      expect(b.hitTest(3.5, 3.5), isNull); // in the hole of 'big', outside 'small'
      expect(b.hitTest(4.5, 4.5), 'small'); // inside the hole and inside 'small'
      expect(b.hitTest(11, 1), isNull);
    });

    test('invalid documents are rejected with FormatException', () {
      expect(() => RegionBorders.fromJson('not json'), throwsFormatException);
      expect(() => RegionBorders.fromJson(doc({'a': square(0, 0, 1)}, schema: 'other/1')), throwsFormatException);
      expect(() => RegionBorders.fromJson(doc({})), throwsFormatException);
      expect(
        () => RegionBorders.fromJson(
          doc({
            'a': {'isoCode': 'x', 'polygons': []},
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => RegionBorders.fromJson(
          doc({
            'a': {
              'polygons': [
                [
                  [
                    [0, 0],
                    [1, 0],
                    [1, 1],
                    [0, 0.5],
                  ], // open ring
                ],
              ],
            },
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => RegionBorders.fromJson(
          doc({
            'a': {
              'polygons': [
                [
                  [
                    [0, 0],
                    [1, 0],
                    [0, 0],
                  ], // too short
                ],
              ],
            },
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => RegionBorders.fromJson(
          doc({
            'a': {
              'polygons': [
                [
                  [
                    [0, 0],
                    [1, 0],
                    [1, 95],
                    [0, 0],
                  ], // latitude out of range
                ],
              ],
            },
          }),
        ),
        throwsFormatException,
      );
    });
  });
}
