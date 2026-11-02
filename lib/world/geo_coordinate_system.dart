import 'dart:math' as math;
import 'package:flame/components.dart';

/// Canonical WGS84 (EPSG:4326) geographical coordinate in 64-bit precision.
class Wgs84Coord {
  final double lon;
  final double lat;
  final double alt;

  const Wgs84Coord({
    required this.lon,
    required this.lat,
    this.alt = 0.0,
  });

  double get latitude => lat;
  double get longitude => lon;

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
      alt: (map['alt'] as num?)?.toDouble() ??
          (map['elevationMeters'] as num?)?.toDouble() ??
          0.0,
    );
  }

  List<double> toJsonList() => [lon, lat, alt];

  Map<String, double> toJsonMap() => {
        'latitude': lat,
        'longitude': lon,
        'lon': lon,
        'lat': lat,
        'alt': alt,
      };

  @override
  String toString() =>
      'Wgs84Coord(lat: ${lat.toStringAsFixed(6)}, lon: ${lon.toStringAsFixed(6)}, alt: ${alt.toStringAsFixed(1)})';
}

/// Local East-North-Up (ENU) metric coordinate relative to the active floating origin.
class LocalEnuCoord {
  final double eastMeters;
  final double northMeters;
  final double upMeters;

  const LocalEnuCoord({
    required this.eastMeters,
    required this.northMeters,
    this.upMeters = 0.0,
  });

  /// Converts local metric ENU to Flame 2D world canvas coordinates (East = +X, North = -Y).
  Vector2 toFlameWorld({double pixelsPerMeter = 1.0}) {
    return Vector2(eastMeters * pixelsPerMeter, -northMeters * pixelsPerMeter);
  }

  static LocalEnuCoord fromFlameWorld(
    Vector2 worldPos, {
    double pixelsPerMeter = 1.0,
    double upMeters = 0.0,
  }) {
    return LocalEnuCoord(
      eastMeters: worldPos.x / pixelsPerMeter,
      northMeters: -worldPos.y / pixelsPerMeter,
      upMeters: upMeters,
    );
  }
}

/// Geographical bounding box in WGS84 degrees.
class GeoBoundingBox {
  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;

  const GeoBoundingBox({
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
  });

  factory GeoBoundingBox.fromJson(Map<String, dynamic> json) {
    return GeoBoundingBox(
      minLon: (json['minLon'] as num).toDouble(),
      minLat: (json['minLat'] as num).toDouble(),
      maxLon: (json['maxLon'] as num).toDouble(),
      maxLat: (json['maxLat'] as num).toDouble(),
    );
  }

  Map<String, double> toJson() => {
        'minLon': minLon,
        'minLat': minLat,
        'maxLon': maxLon,
        'maxLat': maxLat,
      };

  Wgs84Coord get center => Wgs84Coord(
        lon: (minLon + maxLon) * 0.5,
        lat: (minLat + maxLat) * 0.5,
      );

  bool contains(double lon, double lat) {
    return lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat;
  }

  bool intersects(GeoBoundingBox other) {
    return !(other.minLon > maxLon ||
        other.maxLon < minLon ||
        other.minLat > maxLat ||
        other.maxLat < minLat);
  }
}

/// National Geographical Coordinate System for Uzbekistan.
class NationalCoordinateSystem {
  static const double wgs84SemiMajorAxis = 6378137.0;
  static const double wgs84FirstEccentricitySq = 0.00669437999014;
  static const double defaultRebaseThresholdMeters = 2000.0;

  static const Wgs84Coord legacyTashkentOrigin = Wgs84Coord(
    lon: 69.279737,
    lat: 41.311081,
    alt: 475.0,
  );

  static const GeoBoundingBox uzbekistanNationalBbox = GeoBoundingBox(
    minLon: 55.997,
    minLat: 37.172,
    maxLon: 73.132,
    maxLat: 45.590,
  );

  Wgs84Coord _floatingOrigin;
  double _metersPerDegLon = 85390.0;
  double _metersPerDegLat = 111060.0;
  final double pixelsPerMeter;

  NationalCoordinateSystem({
    Wgs84Coord? initialOrigin,
    this.pixelsPerMeter = 1.0,
  }) : _floatingOrigin = initialOrigin ?? legacyTashkentOrigin {
    _recomputeEllipsoidScale(_floatingOrigin.lat);
  }

  Wgs84Coord get floatingOrigin => _floatingOrigin;
  double get metersPerDegLon => _metersPerDegLon;
  double get metersPerDegLat => _metersPerDegLat;

  void _recomputeEllipsoidScale(double latDeg) {
    final double phi = latDeg * math.pi / 180.0;
    final double sinPhi = math.sin(phi);
    final double cosPhi = math.cos(phi);
    final double denom =
        math.sqrt(1.0 - wgs84FirstEccentricitySq * sinPhi * sinPhi);

    final double primeVerticalRadiusN = wgs84SemiMajorAxis / denom;
    final double meridionalRadiusM =
        (wgs84SemiMajorAxis * (1.0 - wgs84FirstEccentricitySq)) /
            (denom * denom * denom);

    _metersPerDegLon = (primeVerticalRadiusN * cosPhi * math.pi) / 180.0;
    _metersPerDegLat = (meridionalRadiusM * math.pi) / 180.0;
  }

  LocalEnuCoord setFloatingOrigin(Wgs84Coord newOrigin) {
    final LocalEnuCoord shift = wgs84ToLocalEnu(newOrigin);
    _floatingOrigin = newOrigin;
    _recomputeEllipsoidScale(_floatingOrigin.lat);
    return shift;
  }

  LocalEnuCoord? checkAndRebaseIfNeeded(
    Wgs84Coord cameraWgs84, {
    double thresholdMeters = defaultRebaseThresholdMeters,
  }) {
    final LocalEnuCoord local = wgs84ToLocalEnu(cameraWgs84);
    final double distSq = local.eastMeters * local.eastMeters +
        local.northMeters * local.northMeters;
    if (distSq > thresholdMeters * thresholdMeters) {
      return setFloatingOrigin(cameraWgs84);
    }
    return null;
  }

  LocalEnuCoord wgs84ToLocalEnu(Wgs84Coord coord) {
    final double dLon = coord.lon - _floatingOrigin.lon;
    final double dLat = coord.lat - _floatingOrigin.lat;
    return LocalEnuCoord(
      eastMeters: dLon * _metersPerDegLon,
      northMeters: dLat * _metersPerDegLat,
      upMeters: coord.alt - _floatingOrigin.alt,
    );
  }

  Wgs84Coord localEnuToWgs84(LocalEnuCoord metric) {
    return Wgs84Coord(
      lon: _floatingOrigin.lon + (metric.eastMeters / _metersPerDegLon),
      lat: _floatingOrigin.lat + (metric.northMeters / _metersPerDegLat),
      alt: _floatingOrigin.alt + metric.upMeters,
    );
  }

  Vector2 wgs84ToFlameWorld(Wgs84Coord coord) {
    return wgs84ToLocalEnu(coord).toFlameWorld(pixelsPerMeter: pixelsPerMeter);
  }

  Wgs84Coord flameWorldToWgs84(Vector2 worldPos, {double alt = 0.0}) {
    final enu = LocalEnuCoord.fromFlameWorld(
      worldPos,
      pixelsPerMeter: pixelsPerMeter,
      upMeters: alt,
    );
    return localEnuToWgs84(enu);
  }

  static double geodesicDistanceMeters(Wgs84Coord a, Wgs84Coord b) {
    const double r = 6371008.8;
    final double dLat = (b.lat - a.lat) * math.pi / 180.0;
    final double dLon = (b.lon - a.lon) * math.pi / 180.0;
    final double lat1 = a.lat * math.pi / 180.0;
    final double lat2 = b.lat * math.pi / 180.0;

    final double sinDLat = math.sin(dLat * 0.5);
    final double sinDLon = math.sin(dLon * 0.5);
    final double h = sinDLat * sinDLat +
        math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
    return 2.0 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static Wgs84Coord legacyTashkentToWgs84(
    double legacyX,
    double legacyY, {
    double legacyZ = 0.0,
    double pixelsPerMeter = 1.0,
  }) {
    final sys = NationalCoordinateSystem(
      initialOrigin: legacyTashkentOrigin,
      pixelsPerMeter: pixelsPerMeter,
    );
    return sys.flameWorldToWgs84(Vector2(legacyX, legacyY), alt: legacyZ);
  }

  static Vector2 wgs84ToLegacyTashkent(
    Wgs84Coord coord, {
    double pixelsPerMeter = 1.0,
  }) {
    final sys = NationalCoordinateSystem(
      initialOrigin: legacyTashkentOrigin,
      pixelsPerMeter: pixelsPerMeter,
    );
    return sys.wgs84ToFlameWorld(coord);
  }
}
