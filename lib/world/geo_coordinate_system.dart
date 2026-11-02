import 'dart:math' as math;
import 'package:flame/components.dart';

class Wgs84Coord {
  final double lon;
  final double lat;
  final double alt;

  const Wgs84Coord({required this.lon, required this.lat, this.alt = 0.0});

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
      alt: (map['alt'] as num?)?.toDouble() ?? 0.0,
    );
  }

  List<double> toJsonList() => [lon, lat, alt];
}

class LocalEnuCoord {
  final double eastMeters;
  final double northMeters;
  final double upMeters;

  const LocalEnuCoord({required this.eastMeters, required this.northMeters, this.upMeters = 0.0});

  Vector2 toFlameWorld({double pixelsPerMeter = 1.0}) =>
      Vector2(eastMeters * pixelsPerMeter, -northMeters * pixelsPerMeter);

  static LocalEnuCoord fromFlameWorld(Vector2 worldPos, {double pixelsPerMeter = 1.0, double upMeters = 0.0}) =>
      LocalEnuCoord(eastMeters: worldPos.x / pixelsPerMeter, northMeters: -worldPos.y / pixelsPerMeter, upMeters: upMeters);
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

class NationalCoordinateSystem {
  static const double wgs84SemiMajorAxis = 6378137.0;
  static const double wgs84FirstEccentricitySq = 0.00669437999014;
  static const double defaultRebaseThresholdMeters = 2000.0;

  static const Wgs84Coord legacyTashkentOrigin = Wgs84Coord(lon: 69.279737, lat: 41.311081, alt: 475.0);
  static const GeoBoundingBox uzbekistanNationalBbox = GeoBoundingBox(minLon: 55.997, minLat: 37.172, maxLon: 73.132, maxLat: 45.590);

  Wgs84Coord _floatingOrigin;
  double _metersPerDegLon = 85390.0;
  double _metersPerDegLat = 111060.0;
  final double pixelsPerMeter;

  NationalCoordinateSystem({Wgs84Coord? initialOrigin, this.pixelsPerMeter = 1.0})
      : _floatingOrigin = initialOrigin ?? legacyTashkentOrigin {
    _recomputeEllipsoidScale(_floatingOrigin.lat);
  }

  Wgs84Coord get floatingOrigin => _floatingOrigin;

  void _recomputeEllipsoidScale(double latDeg) {
    final double phi = latDeg * math.pi / 180.0;
    final double sinPhi = math.sin(phi);
    final double cosPhi = math.cos(phi);
    final double denom = math.sqrt(1.0 - wgs84FirstEccentricitySq * sinPhi * sinPhi);
    final double primeVerticalRadiusN = wgs84SemiMajorAxis / denom;
    final double meridionalRadiusM = (wgs84SemiMajorAxis * (1.0 - wgs84FirstEccentricitySq)) / (denom * denom * denom);
    _metersPerDegLon = (primeVerticalRadiusN * cosPhi * math.pi) / 180.0;
    _metersPerDegLat = (meridionalRadiusM * math.pi) / 180.0;
  }

  LocalEnuCoord setFloatingOrigin(Wgs84Coord newOrigin) {
    final shift = wgs84ToLocalEnu(newOrigin);
    _floatingOrigin = newOrigin;
    _recomputeEllipsoidScale(_floatingOrigin.lat);
    return shift;
  }

  LocalEnuCoord? checkAndRebaseIfNeeded(Wgs84Coord cameraWgs84, {double thresholdMeters = defaultRebaseThresholdMeters}) {
    final local = wgs84ToLocalEnu(cameraWgs84);
    if (local.eastMeters * local.eastMeters + local.northMeters * local.northMeters > thresholdMeters * thresholdMeters) {
      return setFloatingOrigin(cameraWgs84);
    }
    return null;
  }

  LocalEnuCoord wgs84ToLocalEnu(Wgs84Coord coord) => LocalEnuCoord(
        eastMeters: (coord.lon - _floatingOrigin.lon) * _metersPerDegLon,
        northMeters: (coord.lat - _floatingOrigin.lat) * _metersPerDegLat,
        upMeters: coord.alt - _floatingOrigin.alt,
      );

  Wgs84Coord localEnuToWgs84(LocalEnuCoord metric) => Wgs84Coord(
        lon: _floatingOrigin.lon + (metric.eastMeters / _metersPerDegLon),
        lat: _floatingOrigin.lat + (metric.northMeters / _metersPerDegLat),
        alt: _floatingOrigin.alt + metric.upMeters,
      );

  static double geodesicDistanceMeters(Wgs84Coord a, Wgs84Coord b) {
    const double r = 6371008.8;
    final double dLat = (b.lat - a.lat) * math.pi / 180.0;
    final double dLon = (b.lon - a.lon) * math.pi / 180.0;
    final double lat1 = a.lat * math.pi / 180.0;
    final double lat2 = b.lat * math.pi / 180.0;
    final double h = math.pow(math.sin(dLat * 0.5), 2) + math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon * 0.5), 2);
    return 2.0 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static Wgs84Coord legacyTashkentToWgs84(double x, double y, {double z = 0.0}) =>
      NationalCoordinateSystem().localEnuToWgs84(LocalEnuCoord(eastMeters: x, northMeters: -y, upMeters: z));

  static Vector2 wgs84ToLegacyTashkent(Wgs84Coord coord) =>
      NationalCoordinateSystem().wgs84ToLocalEnu(coord).toFlameWorld();
}
