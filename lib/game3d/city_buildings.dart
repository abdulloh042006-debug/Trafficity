import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

/// Real building footprints of the Tashkent map for the 3D view (`assets/map/tashkent_buildings.bin`).
///
/// Source: Microsoft Global ML Building Footprints (ODbL-1.0), projected with the same chain as the game map
/// (see `tools/map/build_tashkent_buildings.py`). Heights are ESTIMATED from footprint area and shape: the source
/// has no heights for Uzbekistan.
class CityBuildings {
  static const String asset = 'assets/map/tashkent_buildings.bin';
  static const String attribution = 'Building footprints © Microsoft (ODbL) · Map © OpenStreetMap contributors';
  static const double cellSize = 200;
  static const double quant = 4;

  final Float32List xs, ys; // every footprint vertex, game units
  final Int32List start; // building i owns vertices start[i] .. start[i + 1] - 1
  final Float32List heights; // metres (estimated)
  final Float32List cx, cy, area; // centroid and area of every footprint
  final double world;
  final int gridN;
  final List<Int32List> _grid;
  final List<Int32List?> _roofCache;

  CityBuildings._(
    this.xs,
    this.ys,
    this.start,
    this.heights,
    this.cx,
    this.cy,
    this.area,
    this.world,
    this.gridN,
    this._grid,
  ) : _roofCache = List<Int32List?>.filled(heights.length, null);

  int get length => heights.length;
  int vertexCount(int i) => start[i + 1] - start[i];

  static Future<CityBuildings>? _loading;

  /// Loads and decodes the bundled asset once per process.
  static Future<CityBuildings> load() =>
      _loading ??= rootBundle.load(asset).then((d) => CityBuildings.decode(d)).catchError((Object e) {
        _loading = null; // allow a retry
        throw e;
      });

  /// Throws [FormatException] for anything that is not a valid, complete building file.
  factory CityBuildings.decode(ByteData data, {double world = 6400}) {
    if (data.lengthInBytes < 8 ||
        data.getUint8(0) != 0x54 ||
        data.getUint8(1) != 0x4B ||
        data.getUint8(2) != 0x42 ||
        data.getUint8(3) != 0x31) {
      throw const FormatException('buildings: bad magic');
    }
    final count = data.getUint32(4, Endian.little);
    var off = 8;
    final starts = Int32List(count + 1);
    final heights = Float32List(count);
    // first pass: sizes
    var total = 0;
    for (var i = 0; i < count; i++) {
      if (off + 2 > data.lengthInBytes) throw const FormatException('buildings: truncated');
      final n = data.getUint8(off);
      if (n < 3) throw const FormatException('buildings: polygon with fewer than 3 points');
      starts[i] = total;
      heights[i] = data.getUint8(off + 1) / 2;
      total += n;
      off += 2 + n * 4;
    }
    if (off != data.lengthInBytes) throw const FormatException('buildings: size mismatch');
    starts[count] = total;
    final xs = Float32List(total), ys = Float32List(total);
    final cx = Float32List(count), cy = Float32List(count), area = Float32List(count);
    off = 8;
    var k = 0;
    for (var i = 0; i < count; i++) {
      final n = data.getUint8(off);
      off += 2;
      var sx = 0.0, sy = 0.0;
      for (var j = 0; j < n; j++) {
        final x = data.getUint16(off, Endian.little) / quant, y = data.getUint16(off + 2, Endian.little) / quant;
        if (x > world || y > world) throw const FormatException('buildings: point outside the world');
        xs[k + j] = x;
        ys[k + j] = y;
        sx += x;
        sy += y;
        off += 4;
      }
      cx[i] = sx / n;
      cy[i] = sy / n;
      var a = 0.0;
      for (var j = 0; j < n; j++) {
        final j2 = (j + 1) % n;
        a += xs[k + j] * ys[k + j2] - xs[k + j2] * ys[k + j];
      }
      area[i] = a / 2; // signed: the sign gives the orientation
      k += n;
    }
    final gridN = (world / cellSize).ceil();
    final buckets = List<List<int>>.generate(gridN * gridN, (_) => <int>[]);
    for (var i = 0; i < count; i++) {
      final gx = (cx[i] / cellSize).floor().clamp(0, gridN - 1);
      final gy = (cy[i] / cellSize).floor().clamp(0, gridN - 1);
      buckets[gy * gridN + gx].add(i);
    }
    return CityBuildings._(xs, ys, starts, heights, cx, cy, area, world, gridN, [
      for (final b in buckets) Int32List.fromList(b),
    ]);
  }

  /// Indices of buildings whose centroid lies within the square [x - r, x + r] x [y - r, y + r] (grid cells).
  Iterable<int> near(double x, double y, double r) sync* {
    final g0x = ((x - r) / cellSize).floor().clamp(0, gridN - 1),
        g1x = ((x + r) / cellSize).floor().clamp(0, gridN - 1);
    final g0y = ((y - r) / cellSize).floor().clamp(0, gridN - 1),
        g1y = ((y + r) / cellSize).floor().clamp(0, gridN - 1);
    for (var gy = g0y; gy <= g1y; gy++) {
      for (var gx = g0x; gx <= g1x; gx++) {
        yield* _grid[gy * gridN + gx];
      }
    }
  }

  /// Footprint of building [i] as offsets (allocates; for tests and tools).
  List<Offset> footprint(int i) => [for (var j = start[i]; j < start[i + 1]; j++) Offset(xs[j], ys[j])];

  /// Triangle indices (relative to the building's first vertex) of the roof / footprint, cached.
  Int32List roof(int i) {
    final cached = _roofCache[i];
    if (cached != null) return cached;
    final s = start[i], n = start[i + 1] - s;
    final px = Float64List(n), py = Float64List(n);
    for (var j = 0; j < n; j++) {
      px[j] = xs[s + j];
      py[j] = ys[s + j];
    }
    return _roofCache[i] = triangulate(px, py);
  }
}

/// Ear-clipping triangulation of a simple polygon (either orientation). Returns vertex index triples; falls back to
/// a fan when the polygon is degenerate, so it always returns n - 2 triangles for n >= 3.
Int32List triangulate(Float64List x, Float64List y) {
  final n = x.length;
  if (n < 3) return Int32List(0);
  var a = 0.0;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    a += x[i] * y[j] - x[j] * y[i];
  }
  final sign = a >= 0 ? 1.0 : -1.0;
  final idx = List<int>.generate(n, (i) => i);
  final out = <int>[];
  var guard = 0;
  while (idx.length > 3 && guard < n * n) {
    guard++;
    var clipped = false;
    for (var k = 0; k < idx.length; k++) {
      final i0 = idx[(k + idx.length - 1) % idx.length], i1 = idx[k], i2 = idx[(k + 1) % idx.length];
      final cross = (x[i1] - x[i0]) * (y[i2] - y[i0]) - (y[i1] - y[i0]) * (x[i2] - x[i0]);
      if (cross * sign <= 1e-9) continue; // reflex or flat corner
      var inside = false;
      for (final p in idx) {
        if (p == i0 || p == i1 || p == i2) continue;
        if (_inTri(x[p], y[p], x[i0], y[i0], x[i1], y[i1], x[i2], y[i2], sign)) {
          inside = true;
          break;
        }
      }
      if (inside) continue;
      out
        ..add(i0)
        ..add(i1)
        ..add(i2);
      idx.removeAt(k);
      clipped = true;
      break;
    }
    if (!clipped) break; // degenerate: finish with a fan
  }
  for (var k = 1; k + 1 < idx.length; k++) {
    out
      ..add(idx[0])
      ..add(idx[k])
      ..add(idx[k + 1]);
  }
  return Int32List.fromList(out);
}

bool _inTri(double px, double py, double ax, double ay, double bx, double by, double cx, double cy, double sign) {
  double side(double x1, double y1, double x2, double y2) => ((x2 - x1) * (py - y1) - (y2 - y1) * (px - x1)) * sign;
  return side(ax, ay, bx, by) >= 0 && side(bx, by, cx, cy) >= 0 && side(cx, cy, ax, ay) >= 0;
}

/// Area of a polygon from flat coordinate lists (absolute value).
double polygonArea(List<Offset> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return (a / 2).abs();
}
