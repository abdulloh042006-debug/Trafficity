import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/world/geo_coordinate_system.dart';

void main() {
  const origin = NationalCoordinateSystem.legacyTashkentOrigin;

  group('WGS84 <-> Local ENU', () {
    test('known Tashkent origin converts to ~zero displacement', () {
      final enu = NationalCoordinateSystem.wgs84ToEnu(origin, origin);
      expect(enu.eastMeters, closeTo(0.0, 1e-6));
      expect(enu.northMeters, closeTo(0.0, 1e-6));
      expect(enu.upMeters, closeTo(0.0, 1e-6));
    });

    test('a point east of the origin has positive east meters', () {
      final p = Wgs84Coord(lon: origin.lon + 0.001, lat: origin.lat, alt: origin.alt);
      final enu = NationalCoordinateSystem.wgs84ToEnu(p, origin);
      expect(enu.eastMeters, greaterThan(0.0));
      // 0.001 deg of longitude at 41.31 N is about 83.7 m.
      expect(enu.eastMeters, closeTo(83.74, 0.2));
      expect(enu.northMeters.abs(), lessThan(0.01));
    });

    test('a point north of the origin has positive north meters', () {
      final p = Wgs84Coord(lon: origin.lon, lat: origin.lat + 0.001, alt: origin.alt);
      final enu = NationalCoordinateSystem.wgs84ToEnu(p, origin);
      expect(enu.northMeters, greaterThan(0.0));
      // 0.001 deg of latitude at 41.31 N is about 111.07 m.
      expect(enu.northMeters, closeTo(111.07, 0.2));
      expect(enu.eastMeters.abs(), lessThan(0.01));
    });

    test('WGS84 -> ENU -> WGS84 round trip stays within 1e-9 deg and 1e-4 m', () {
      const offsets = [
        [0.05, 0.05],
        [-0.05, 0.05],
        [0.05, -0.05],
        [-0.05, -0.05],
        [0.2, 0.0],
        [0.0, -0.2],
      ];
      for (final o in offsets) {
        final p = Wgs84Coord(lon: origin.lon + o[0], lat: origin.lat + o[1], alt: 520.0);
        final enu = NationalCoordinateSystem.wgs84ToEnu(p, origin);
        final back = NationalCoordinateSystem.enuToWgs84(enu, origin);
        expect(back.lon, closeTo(p.lon, 1e-9));
        expect(back.lat, closeTo(p.lat, 1e-9));
        expect(back.alt, closeTo(p.alt, 1e-4));
      }
    });

    test('ENU -> WGS84 -> ENU round trip is exact to micrometres', () {
      const enu = LocalEnuCoord(eastMeters: 1500.0, northMeters: -2500.0, upMeters: 3.0);
      final w = NationalCoordinateSystem.enuToWgs84(enu, origin);
      final back = NationalCoordinateSystem.wgs84ToEnu(w, origin);
      expect(back.eastMeters, closeTo(1500.0, 1e-6));
      expect(back.northMeters, closeTo(-2500.0, 1e-6));
      expect(back.upMeters, closeTo(3.0, 1e-6));
    });

    test('ellipsoid meters-per-degree match published values', () {
      expect(Wgs84Ellipsoid.metersPerDegreeLat(0.0), closeTo(110574.3, 1.0));
      expect(Wgs84Ellipsoid.metersPerDegreeLon(0.0), closeTo(111319.5, 1.0));
      expect(Wgs84Ellipsoid.metersPerDegreeLat(41.311081), closeTo(111059.9, 0.5));
      expect(Wgs84Ellipsoid.metersPerDegreeLon(41.311081), closeTo(83738.4, 0.5));
    });
  });

  group('legacy Tashkent frame and Flame world', () {
    test('legacy centre (3200, 3200) maps to the Tashkent origin', () {
      final w = NationalCoordinateSystem.legacyUnitsToWgs84(3200.0, 3200.0);
      expect(w.lon, closeTo(origin.lon, 1e-9));
      expect(w.lat, closeTo(origin.lat, 1e-9));
    });

    test('legacy axes: +x is east, +y is south', () {
      final east = NationalCoordinateSystem.legacyUnitsToWgs84(3400.0, 3200.0);
      final south = NationalCoordinateSystem.legacyUnitsToWgs84(3200.0, 3400.0);
      expect(east.lon, greaterThan(origin.lon));
      expect(south.lat, lessThan(origin.lat));
    });

    test('legacy points round-trip', () {
      const pts = [
        [3200.0, 3200.0],
        [2379.0, 3952.5],
        [5967.8, 1910.8],
        [10.0, 6390.0],
      ];
      for (final p in pts) {
        final w = NationalCoordinateSystem.legacyUnitsToWgs84(p[0], p[1]);
        // Full double precision: the original 1e-5 requirement is kept for the exact API.
        final exact = NationalCoordinateSystem.wgs84ToLegacyUnitsExact(w);
        expect(exact.x, closeTo(p[0], 1e-5));
        expect(exact.y, closeTo(p[1], 1e-5));
        // Flame Vector2 is float32: its ulp at 6000 is ~4.9e-4, so 1e-3 is the physical limit there.
        final back = NationalCoordinateSystem.wgs84ToLegacyUnits(w);
        expect(back.x, closeTo(p[0], 1e-3));
        expect(back.y, closeTo(p[1], 1e-3));
      }
    });

    test('Flame world negates north (y grows south) and round-trips', () {
      const enu = LocalEnuCoord(eastMeters: 10.0, northMeters: 20.0);
      final v = enu.toFlameWorld();
      expect(v.x, 10.0);
      expect(v.y, -20.0);
      final back = LocalEnuCoord.fromFlameWorld(Vector2(10.0, -20.0));
      expect(back.eastMeters, 10.0);
      expect(back.northMeters, 20.0);
    });
  });

  group('floating origin', () {
    test('below the threshold nothing changes', () {
      final sys = NationalCoordinateSystem();
      final r = sys.rebaseIfNeeded(const LocalEnuCoord(eastMeters: 1500.0, northMeters: 1000.0));
      expect(r, isNull);
      expect(sys.floatingOrigin.lon, origin.lon);
      expect(sys.floatingOrigin.lat, origin.lat);
    });

    test('at or above the threshold rebases and resets local displacement', () {
      final sys = NationalCoordinateSystem();
      const pos = LocalEnuCoord(eastMeters: 1800.0, northMeters: 1200.0);
      final r = sys.rebaseIfNeeded(pos);
      expect(r, isNotNull);
      expect(r!.shift.eastMeters, 1800.0);
      expect(r.shift.northMeters, 1200.0);
      expect(r.newLocalPosition.eastMeters, 0.0);
      expect(r.newLocalPosition.northMeters, 0.0);
      expect(sys.floatingOrigin.lon, r.newOrigin.lon);
      expect(sys.floatingOrigin.lat, r.newOrigin.lat);
      // The new origin is east and north of the old one.
      expect(sys.floatingOrigin.lon, greaterThan(origin.lon));
      expect(sys.floatingOrigin.lat, greaterThan(origin.lat));
      // The old origin is now roughly (-1800, -1200) m away.
      final oldLocal = sys.toLocal(origin);
      expect(oldLocal.eastMeters, closeTo(-1800.0, 1.0));
      expect(oldLocal.northMeters, closeTo(-1200.0, 1.0));
    });

    test('exactly at the threshold rebases', () {
      final sys = NationalCoordinateSystem();
      final r = sys.rebaseIfNeeded(const LocalEnuCoord(eastMeters: 2000.0, northMeters: 0.0));
      expect(r, isNotNull);
    });
  });

  group('validation', () {
    test('invalid WGS84 values are rejected', () {
      expect(() => Wgs84Coord.checked(lon: double.nan, lat: 41.0), throwsA(isA<GeoCoordinateException>()));
      expect(() => Wgs84Coord.checked(lon: 69.0, lat: 91.0), throwsA(isA<GeoCoordinateException>()));
      expect(() => Wgs84Coord.checked(lon: 181.0, lat: 41.0), throwsA(isA<GeoCoordinateException>()));
      expect(
        () => Wgs84Coord.checked(lon: 69.0, lat: 41.0, alt: double.infinity),
        throwsA(isA<GeoCoordinateException>()),
      );
      expect(Wgs84Coord.checked(lon: 69.0, lat: 41.0).isValid, isTrue);
    });

    test('conversions reject invalid input', () {
      const bad = Wgs84Coord(lon: double.nan, lat: 41.0);
      expect(() => NationalCoordinateSystem.wgs84ToEnu(bad, origin), throwsA(isA<GeoCoordinateException>()));
      expect(() => NationalCoordinateSystem.wgs84ToEnu(origin, bad), throwsA(isA<GeoCoordinateException>()));
      expect(
        () =>
            NationalCoordinateSystem.enuToWgs84(const LocalEnuCoord(eastMeters: double.nan, northMeters: 0.0), origin),
        throwsA(isA<GeoCoordinateException>()),
      );
      expect(
        () => NationalCoordinateSystem.legacyUnitsToWgs84(double.infinity, 0.0),
        throwsA(isA<GeoCoordinateException>()),
      );
      expect(() => NationalCoordinateSystem().setFloatingOrigin(bad), throwsA(isA<GeoCoordinateException>()));
      expect(
        () => NationalCoordinateSystem.geodesicDistanceMeters(bad, origin),
        throwsA(isA<GeoCoordinateException>()),
      );
    });
  });

  group('geodesic distance', () {
    test('one degree of latitude on the mean-radius sphere', () {
      final d = NationalCoordinateSystem.geodesicDistanceMeters(
        const Wgs84Coord(lon: 0.0, lat: 0.0),
        const Wgs84Coord(lon: 0.0, lat: 1.0),
      );
      expect(d, closeTo(111195.08, 1.0));
    });

    test('antipodal points hit the clamp and give half the circumference', () {
      final d = NationalCoordinateSystem.geodesicDistanceMeters(
        const Wgs84Coord(lon: 0.0, lat: 0.0),
        const Wgs84Coord(lon: 180.0, lat: 0.0),
      );
      expect(d, closeTo(20015114.4, 5.0));
    });

    test('identical points are zero apart', () {
      expect(NationalCoordinateSystem.geodesicDistanceMeters(origin, origin), 0.0);
    });

    test('Tashkent to Samarkand is plausible (~270 km air distance)', () {
      final d = NationalCoordinateSystem.geodesicDistanceMeters(origin, const Wgs84Coord(lon: 66.9597, lat: 39.6547));
      expect(d, inInclusiveRange(260000.0, 280000.0));
    });
  });
}
