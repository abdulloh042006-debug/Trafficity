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
}

class LocalEnuCoord {
  final double eastMeters;
  final double northMeters;
  final double upMeters;
  const LocalEnuCoord({required this.eastMeters, required this.northMeters, this.upMeters = 0.0});
  Vector2 toFlameWorld({double pixelsPerMeter = 1.0}) =>
      Vector2(eastMeters * pixelsPerMeter, -northMeters * pixelsPerMeter);
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
  static const Wgs84Coord legacyTashkentOrigin = Wgs84Coord(lon: 69.279737, lat: 41.311081, alt: 475.0);
  static const GeoBoundingBox uzbekistanNationalBbox = GeoBoundingBox(minLon: 55.997, minLat: 37.172, maxLon: 73.132, maxLat: 45.590);
  Wgs84Coord _floatingOrigin = legacyTashkentOrigin;
  Wgs84Coord get floatingOrigin => _floatingOrigin;
  void setFloatingOrigin(Wgs84Coord newOrigin) => _floatingOrigin = newOrigin;
  static double geodesicDistanceMeters(Wgs84Coord a, Wgs84Coord b) {
    const double r = 6371008.8;
    final double dLat = (b.lat - a.lat) * math.pi / 180.0;
    final double dLon = (b.lon - a.lon) * math.pi / 180.0;
    final double h = math.pow(math.sin(dLat * 0.5), 2) + math.cos(a.lat * math.pi / 180.0) * math.cos(b.lat * math.pi / 180.0) * math.pow(math.sin(dLon * 0.5), 2);
    return 2.0 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }
}
