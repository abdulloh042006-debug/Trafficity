import 'dart:math' as math;
import 'package:flame/components.dart';

/// Coordinate conventions used across the Uzbekistan world layer
/// ------------------------------------------------------------
/// * Geographic coordinates are WGS84 degrees stored as longitude, latitude
///   (GeoJSON order). Heights are metres above the WGS84 ellipsoid.
/// * Local ENU: east (+x), north (+y), up (+z), metres, tangent plane at an origin.
/// * Flame world: x grows east, **y grows downward = south** (screen convention).
///   [LocalEnuCoord.toFlameWorld] therefore negates north.
/// * Legacy Tashkent map units: x east, y south (image convention), centre at
///   (3200, 3200). See [LegacyTashkentFrame] for the (unverified) scale.

/// Raised when a coordinate is NaN, infinite, or outside valid ranges.
class GeoCoordinateException implements Exception {
  final String message;
  const GeoCoordinateException(this.message);
  @override
  String toString() => 'GeoCoordinateException: $message';
}

class Wgs84Coord {
  final double lon;
  final double lat;
  final double alt;

  const Wgs84Coord({required this.lon, required this.lat, this.alt = 0.0});
  double get latitude => lat;
  double get longitude => lon;

  /// True when all three components are finite and lon/lat are in range.
  bool get isValid =>
      lon.isFinite && lat.isFinite && alt.isFinite && lon >= -180.0 && lon <= 180.0 && lat >= -90.0 && lat <= 90.0;

  /// Returns a coordinate or throws [GeoCoordinateException] for invalid input.
  factory Wgs84Coord.checked({required double lon, required double lat, double alt = 0.0}) {
    final c = Wgs84Coord(lon: lon, lat: lat, alt: alt);
    if (!c.isValid) {
      throw GeoCoordinateException('Invalid WGS84 coordinate lon=$lon lat=$lat alt=$alt');
    }
    return c;
  }

  factory Wgs84Coord.fromJson(dynamic json) {
    if (json is List) {
      return Wgs84Coord(
        lon: (json[0] as num).toDouble(),
        lat: (json[1] as num).toDouble(),
        alt: json.length > 2 ? (json[2] as num).toDouble() : 0.0,
      );
    }
    final map = json as Map<String, dynamic>;
    return Wgs84Coord(
      lon: ((map['longitude'] ?? map['lon']) as num).toDouble(),
      lat: ((map['latitude'] ?? map['lat']) as num).toDouble(),
      alt: (map['alt'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// GeoJSON position `[lon, lat]` (plus altitude only when non-zero).
  List<double> toGeoJson() => alt == 0.0 ? [lon, lat] : [lon, lat, alt];
}

class LocalEnuCoord {
  final double eastMeters;
  final double northMeters;
  final double upMeters;
  const LocalEnuCoord({required this.eastMeters, required this.northMeters, this.upMeters = 0.0});

  bool get isFinite => eastMeters.isFinite && northMeters.isFinite && upMeters.isFinite;

  /// Horizontal distance from the origin in metres.
  double get horizontalMeters => math.sqrt(eastMeters * eastMeters + northMeters * northMeters);

  /// Flame world vector. Flame's y axis points down (south), so north is negated.
  Vector2 toFlameWorld({double pixelsPerMeter = 1.0}) =>
      Vector2(eastMeters * pixelsPerMeter, -northMeters * pixelsPerMeter);

  /// Inverse of [toFlameWorld].
  static LocalEnuCoord fromFlameWorld(Vector2 world, {double pixelsPerMeter = 1.0, double upMeters = 0.0}) =>
      LocalEnuCoord(
        eastMeters: world.x / pixelsPerMeter,
        northMeters: -world.y / pixelsPerMeter,
        upMeters: upMeters,
      );
}

class GeoBoundingBox {
  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;
  const GeoBoundingBox({required this.minLon, required this.minLat, required this.maxLon, required this.maxLat});
  factory GeoBoundingBox.fromJson(Map<String, dynamic> json) => GeoBoundingBox(
        minLon: (json['minLon'] as num).toDouble(),
        minLat: (json['minLat'] as num).toDouble(),
        maxLon: (json['maxLon'] as num).toDouble(),
        maxLat: (json['maxLat'] as num).toDouble(),
      );
}

/// WGS84 ellipsoid constants and derived per-degree lengths.
class Wgs84Ellipsoid {
  /// Semi-major axis (metres).
  static const double a = 6378137.0;

  /// Flattening.
  static const double f = 1.0 / 298.257223563;

  /// First eccentricity squared.
  static const double e2 = f * (2.0 - f);

  static double _rad(double deg) => deg * math.pi / 180.0;

  /// Length of one degree of latitude (metres) at [latDeg]; meridional radius of curvature.
  static double metersPerDegreeLat(double latDeg) {
    final s = math.sin(_rad(latDeg));
    final w = 1.0 - e2 * s * s;
    final m = a * (1.0 - e2) / (w * math.sqrt(w));
    return m * math.pi / 180.0;
  }

  /// Length of one degree of longitude (metres) at [latDeg]; prime-vertical radius times cos(lat).
  static double metersPerDegreeLon(double latDeg) {
    final phi = _rad(latDeg);
    final s = math.sin(phi);
    final n = a / math.sqrt(1.0 - e2 * s * s);
    return n * math.cos(phi) * math.pi / 180.0;
  }
}

/// Earth-centred Earth-fixed vector (metres).
class _Ecef {
  final double x;
  final double y;
  final double z;
  const _Ecef(this.x, this.y, this.z);
}

/// Legacy Tashkent map frame (units of the original RoadFlow City world).
///
/// x = east, y = south, centre (3200, 3200) = Amir Temur xiyoboni.
/// [metersPerUnit] is **an unverified hypothesis**: the basemap is 3200 px at 2 m/px
/// over a 6400-unit world (=> 1 m per unit) but no surveyed anchor points have been
/// checked against it yet. The migration manifest reports this as `unverified`.
class LegacyTashkentFrame {
  static const double worldCenter = 3200.0;
  static const double metersPerUnit = 1.0;

  static LocalEnuCoord unitsToEnu(double x, double y) =>
      LocalEnuCoord(eastMeters: (x - worldCenter) * metersPerUnit, northMeters: -(y - worldCenter) * metersPerUnit);

  static Vector2 enuToUnits(LocalEnuCoord enu) =>
      Vector2(worldCenter + enu.eastMeters / metersPerUnit, worldCenter - enu.northMeters / metersPerUnit);
}

/// Result of a floating-origin rebase.
class FloatingOriginRebase {
  /// The new WGS84 origin.
  final Wgs84Coord newOrigin;

  /// Displacement of the new origin relative to the old one, in the old ENU frame.
  final LocalEnuCoord shift;

  /// The rebased position expressed relative to [newOrigin] (zero after a rebase).
  final LocalEnuCoord newLocalPosition;
  const FloatingOriginRebase({required this.newOrigin, required this.shift, required this.newLocalPosition});
}

class NationalCoordinateSystem {
  static const Wgs84Coord legacyTashkentOrigin = Wgs84Coord(lon: 69.279737, lat: 41.311081, alt: 475.0);
  static const GeoBoundingBox uzbekistanNationalBbox =
      GeoBoundingBox(minLon: 55.997, minLat: 37.172, maxLon: 73.132, maxLat: 45.590);

  /// Horizontal distance from the floating origin after which the origin is rebased.
  static const double rebaseThresholdMeters = 2000.0;

  /// Mean Earth radius used for geodesic (haversine) distance, metres.
  static const double meanEarthRadiusMeters = 6371008.8;

  Wgs84Coord _floatingOrigin = legacyTashkentOrigin;
  Wgs84Coord get floatingOrigin => _floatingOrigin;

  void setFloatingOrigin(Wgs84Coord newOrigin) {
    _requireValid(newOrigin);
    _floatingOrigin = newOrigin;
  }

  static void _requireValid(Wgs84Coord c) {
    if (!c.isValid) {
      throw GeoCoordinateException('Invalid WGS84 coordinate lon=${c.lon} lat=${c.lat} alt=${c.alt}');
    }
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
  static double _deg(double rad) => rad * 180.0 / math.pi;

  static _Ecef _geodeticToEcef(Wgs84Coord c) {
    final phi = _rad(c.lat);
    final lam = _rad(c.lon);
    final sinPhi = math.sin(phi);
    final cosPhi = math.cos(phi);
    final n = Wgs84Ellipsoid.a / math.sqrt(1.0 - Wgs84Ellipsoid.e2 * sinPhi * sinPhi);
    return _Ecef(
      (n + c.alt) * cosPhi * math.cos(lam),
      (n + c.alt) * cosPhi * math.sin(lam),
      (n * (1.0 - Wgs84Ellipsoid.e2) + c.alt) * sinPhi,
    );
  }

  static Wgs84Coord _ecefToGeodetic(_Ecef p) {
    final lon = math.atan2(p.y, p.x);
    final r = math.sqrt(p.x * p.x + p.y * p.y);
    const e2 = Wgs84Ellipsoid.e2;
    double lat = math.atan2(p.z, r * (1.0 - e2));
    double alt = 0.0;
    for (var i = 0; i < 12; i++) {
      final sinLat = math.sin(lat);
      final n = Wgs84Ellipsoid.a / math.sqrt(1.0 - e2 * sinLat * sinLat);
      final cosLat = math.cos(lat);
      if (cosLat.abs() > 1e-9) {
        alt = r / cosLat - n;
      } else {
        alt = p.z.abs() / sinLat.abs() - n * (1.0 - e2);
      }
      lat = math.atan2(p.z, r * (1.0 - e2 * n / (n + alt)));
    }
    return Wgs84Coord(lon: _deg(lon), lat: _deg(lat), alt: alt);
  }

  /// WGS84 point -> Local ENU metres relative to [origin].
  static LocalEnuCoord wgs84ToEnu(Wgs84Coord point, Wgs84Coord origin) {
    _requireValid(point);
    _requireValid(origin);
    final p = _geodeticToEcef(point);
    final o = _geodeticToEcef(origin);
    final dx = p.x - o.x;
    final dy = p.y - o.y;
    final dz = p.z - o.z;
    final phi = _rad(origin.lat);
    final lam = _rad(origin.lon);
    final sinPhi = math.sin(phi);
    final cosPhi = math.cos(phi);
    final sinLam = math.sin(lam);
    final cosLam = math.cos(lam);
    return LocalEnuCoord(
      eastMeters: -sinLam * dx + cosLam * dy,
      northMeters: -sinPhi * cosLam * dx - sinPhi * sinLam * dy + cosPhi * dz,
      upMeters: cosPhi * cosLam * dx + cosPhi * sinLam * dy + sinPhi * dz,
    );
  }

  /// Local ENU metres relative to [origin] -> WGS84 point.
  static Wgs84Coord enuToWgs84(LocalEnuCoord enu, Wgs84Coord origin) {
    _requireValid(origin);
    if (!enu.isFinite) {
      throw GeoCoordinateException('Invalid ENU coordinate e=${enu.eastMeters} n=${enu.northMeters} u=${enu.upMeters}');
    }
    final o = _geodeticToEcef(origin);
    final phi = _rad(origin.lat);
    final lam = _rad(origin.lon);
    final sinPhi = math.sin(phi);
    final cosPhi = math.cos(phi);
    final sinLam = math.sin(lam);
    final cosLam = math.cos(lam);
    final dx = -sinLam * enu.eastMeters - sinPhi * cosLam * enu.northMeters + cosPhi * cosLam * enu.upMeters;
    final dy = cosLam * enu.eastMeters - sinPhi * sinLam * enu.northMeters + cosPhi * sinLam * enu.upMeters;
    final dz = cosPhi * enu.northMeters + sinPhi * enu.upMeters;
    final result = _ecefToGeodetic(_Ecef(o.x + dx, o.y + dy, o.z + dz));
    _requireValid(result);
    return result;
  }

  /// Legacy Tashkent map units (x east, y south) -> WGS84, using [legacyTashkentOrigin].
  static Wgs84Coord legacyUnitsToWgs84(double x, double y) {
    if (!x.isFinite || !y.isFinite) {
      throw GeoCoordinateException('Invalid legacy coordinate x=$x y=$y');
    }
    return enuToWgs84(LegacyTashkentFrame.unitsToEnu(x, y), legacyTashkentOrigin);
  }

  /// WGS84 -> legacy Tashkent map units.
  static Vector2 wgs84ToLegacyUnits(Wgs84Coord point) =>
      LegacyTashkentFrame.enuToUnits(wgs84ToEnu(point, legacyTashkentOrigin));

  /// Position of [point] relative to the current floating origin.
  LocalEnuCoord toLocal(Wgs84Coord point) => wgs84ToEnu(point, _floatingOrigin);

  /// WGS84 position of a local coordinate expressed relative to the current floating origin.
  Wgs84Coord fromLocal(LocalEnuCoord local) => enuToWgs84(local, _floatingOrigin);

  /// If [localPosition] is at least [rebaseThresholdMeters] away horizontally from the floating
  /// origin, moves the origin onto that position and returns the shift; otherwise returns null.
  FloatingOriginRebase? rebaseIfNeeded(LocalEnuCoord localPosition, {double thresholdMeters = rebaseThresholdMeters}) {
    if (!localPosition.isFinite) {
      throw GeoCoordinateException('Invalid local position for rebase');
    }
    if (localPosition.horizontalMeters < thresholdMeters) return null;
    final newOrigin = enuToWgs84(localPosition, _floatingOrigin);
    _floatingOrigin = newOrigin;
    return FloatingOriginRebase(
      newOrigin: newOrigin,
      shift: localPosition,
      newLocalPosition: const LocalEnuCoord(eastMeters: 0.0, northMeters: 0.0, upMeters: 0.0),
    );
  }

  /// Great-circle (haversine) distance in metres on a sphere of [meanEarthRadiusMeters].
  /// Accurate to roughly 0.5% compared with the ellipsoid. Throws for invalid input.
  static double geodesicDistanceMeters(Wgs84Coord a, Wgs84Coord b) {
    _requireValid(a);
    _requireValid(b);
    final dLat = _rad(b.lat - a.lat);
    final dLon = _rad(b.lon - a.lon);
    final sLat = math.sin(dLat * 0.5);
    final sLon = math.sin(dLon * 0.5);
    final h = sLat * sLat + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * sLon * sLon;
    final clamped = h < 0.0 ? 0.0 : (h > 1.0 ? 1.0 : h);
    return 2.0 * meanEarthRadiusMeters * math.asin(math.sqrt(clamped));
  }
}
