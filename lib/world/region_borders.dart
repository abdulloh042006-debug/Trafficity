import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// Outline of one first-level division: polygons of rings (first ring = outer, others = holes) in
/// longitude/latitude, stored as `Offset(lon, lat)`.
class RegionBorderShape {
  final String regionId;
  final String isoCode;
  final List<List<List<Offset>>> polygons;

  /// Bounding box in lon/lat (left = min lon, top = min lat).
  final Rect bounds;

  /// Approximate area in square degrees (outer rings minus holes); only used to rank overlapping shapes.
  final double areaDeg2;

  RegionBorderShape._(this.regionId, this.isoCode, this.polygons, this.bounds, this.areaDeg2);

  factory RegionBorderShape.build(String regionId, String isoCode, List<List<List<Offset>>> polygons) {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    var area = 0.0;
    for (final poly in polygons) {
      for (var i = 0; i < poly.length; i++) {
        final a = _ringArea(poly[i]).abs();
        area += i == 0 ? a : -a;
        for (final p in poly[i]) {
          minX = math.min(minX, p.dx);
          maxX = math.max(maxX, p.dx);
          minY = math.min(minY, p.dy);
          maxY = math.max(maxY, p.dy);
        }
      }
    }
    return RegionBorderShape._(regionId, isoCode, polygons, Rect.fromLTRB(minX, minY, maxX, maxY), area);
  }

  static double _ringArea(List<Offset> ring) {
    var s = 0.0;
    for (var i = 0; i + 1 < ring.length; i++) {
      s += ring[i].dx * ring[i + 1].dy - ring[i + 1].dx * ring[i].dy;
    }
    return s / 2;
  }

  static bool _inRing(double x, double y, List<Offset> ring) {
    var c = false;
    for (var i = 0; i + 1 < ring.length; i++) {
      final a = ring[i], b = ring[i + 1];
      if ((a.dy > y) != (b.dy > y) && x < (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy) + a.dx) c = !c;
    }
    return c;
  }

  /// Even-odd test over every ring of every polygon (so holes are respected).
  bool contains(double lon, double lat) {
    if (lon < bounds.left || lon > bounds.right || lat < bounds.top || lat > bounds.bottom) return false;
    for (final poly in polygons) {
      var inside = false;
      for (final ring in poly) {
        if (_inRing(lon, lat, ring)) inside = !inside;
      }
      if (inside) return true;
    }
    return false;
  }
}

/// The 14 generalised region outlines (`assets/world/uzbekistan/region_borders.json`, Natural Earth, public
/// domain). They are cartographic outlines for drawing and tapping, **not** legal or surveyed borders.
class RegionBorders {
  static const String schema = 'trafficity-region-borders/1';

  /// Latitude used to scale longitude into the drawing plane (the country spans 37-45 N).
  static const double referenceLatitude = 41.3;

  final List<RegionBorderShape> shapes;
  final Rect bounds; // lon/lat
  final String notice;

  RegionBorders._(this.shapes, this.bounds, this.notice);

  static double get _kx => math.cos(referenceLatitude * math.pi / 180);

  /// lon/lat -> drawing plane (x east, y down = south), equirectangular around [referenceLatitude].
  static Offset project(double lon, double lat) => Offset(lon * _kx, -lat);

  /// Inverse of [project].
  static Offset unproject(Offset p) => Offset(p.dx / _kx, -p.dy);

  /// Throws [FormatException] for anything that is not a valid border document.
  factory RegionBorders.fromJson(String text) {
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      throw const FormatException('region borders: not JSON');
    }
    if (root is! Map<String, dynamic> || root['schema'] != schema) {
      throw const FormatException('region borders: wrong schema');
    }
    final regions = root['regions'];
    if (regions is! Map<String, dynamic> || regions.isEmpty) {
      throw const FormatException('region borders: no regions');
    }
    final shapes = <RegionBorderShape>[];
    for (final id in regions.keys.toList()..sort()) {
      final r = regions[id];
      if (r is! Map<String, dynamic> || r['polygons'] is! List || (r['polygons'] as List).isEmpty) {
        throw FormatException('region borders: $id has no polygons');
      }
      final polys = <List<List<Offset>>>[];
      for (final poly in r['polygons'] as List) {
        if (poly is! List || poly.isEmpty) throw FormatException('region borders: $id has an empty polygon');
        final rings = <List<Offset>>[];
        for (final ring in poly) {
          if (ring is! List || ring.length < 4) throw FormatException('region borders: $id has a short ring');
          final pts = <Offset>[];
          for (final p in ring) {
            if (p is! List || p.length < 2 || p[0] is! num || p[1] is! num) {
              throw FormatException('region borders: $id has a bad point');
            }
            final lon = (p[0] as num).toDouble(), lat = (p[1] as num).toDouble();
            if (!lon.isFinite || !lat.isFinite || lat.abs() > 90 || lon.abs() > 180) {
              throw FormatException('region borders: $id has an out-of-range point');
            }
            pts.add(Offset(lon, lat));
          }
          if (pts.first != pts.last) throw FormatException('region borders: $id has an open ring');
          rings.add(pts);
        }
        polys.add(rings);
      }
      shapes.add(RegionBorderShape.build(id, (r['isoCode'] as String?) ?? '', polys));
    }
    var b = shapes.first.bounds;
    for (final s in shapes.skip(1)) {
      b = b.expandToInclude(s.bounds);
    }
    return RegionBorders._(shapes, b, (root['notice'] as String?) ?? '');
  }

  RegionBorderShape? shapeOf(String regionId) {
    for (final s in shapes) {
      if (s.regionId == regionId) return s;
    }
    return null;
  }

  /// Region id at [lon]/[lat]; where outlines overlap (a city inside its province) the smallest one wins.
  /// Null outside every outline.
  String? hitTest(double lon, double lat) {
    RegionBorderShape? best;
    for (final s in shapes) {
      if (s.contains(lon, lat) && (best == null || s.areaDeg2 < best.areaDeg2)) best = s;
    }
    return best?.regionId;
  }
}
