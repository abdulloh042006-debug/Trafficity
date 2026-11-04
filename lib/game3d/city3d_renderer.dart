import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../game/building.dart';
import '../game/road_game.dart';
import '../game/road_network.dart';
import '../game/traffic_model.dart';
import 'camera3d.dart';
import 'city_buildings.dart';

/// What the last frame contained (tests and the debug line read it).
class City3DStats {
  int groundTris = 0, flatTris = 0, shadowTris = 0, itemTris = 0;
  int cityBuildings = 0, gameBuildings = 0, vehicles = 0, decks = 0, hiddenCityBuildings = 0;
  double paintMs = 0;

  void reset() {
    groundTris = flatTris = shadowTris = itemTris = 0;
    cityBuildings = gameBuildings = vehicles = decks = hiddenCityBuildings = 0;
  }
}

/// Growable triangle list for one `drawVertices` call.
class _Batch {
  _Batch({this.textured = false});
  final bool textured;
  Float32List pos = Float32List(6 * 2048);
  Int32List col = Int32List(3 * 2048);
  Float32List uv = Float32List(0);
  int n = 0; // vertices

  void clear() => n = 0;

  void _grow(int extra) {
    if ((n + extra) * 2 <= pos.length) return;
    var cap = pos.length;
    while ((n + extra) * 2 > cap) {
      cap *= 2;
    }
    pos = Float32List(cap)..setRange(0, n * 2, pos);
    col = Int32List(cap ~/ 2)..setRange(0, n, col);
    if (textured) uv = Float32List(cap)..setRange(0, n * 2, uv);
  }

  void vertex(double x, double y, int c, [double u = 0, double v = 0]) {
    _grow(1);
    pos[n * 2] = x;
    pos[n * 2 + 1] = y;
    col[n] = c;
    if (textured) {
      if (uv.length < pos.length) uv = Float32List(pos.length)..setRange(0, n * 2, uv);
      uv[n * 2] = u;
      uv[n * 2 + 1] = v;
    }
    n++;
  }

  int get triangles => n ~/ 3;

  ui.Vertices? build() {
    if (n == 0) return null;
    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(pos, 0, n * 2),
      colors: textured ? null : Int32List.sublistView(col, 0, n),
      textureCoordinates: textured ? Float32List.sublistView(uv, 0, n * 2) : null,
    );
  }
}

/// Software 3D renderer of the current game state (Tashkent): textured ground, roads, real building footprints with
/// estimated heights, the game's own buildings, vehicles, elevated decks and sun shadows.
///
/// Everything is projected with [OrbitCamera] (true perspective), clipped against the near plane, sorted far to
/// near (painter's algorithm per object) and drawn with a few `drawVertices` calls per frame.
class City3DRenderer {
  City3DRenderer(this.game);

  final RoadGame game;
  CityBuildings? city;
  final OrbitCamera cam = OrbitCamera();
  final City3DStats stats = City3DStats();

  // Sun: azimuth from north, clockwise (225 = south-west, afternoon), elevation above the horizon.
  static const double sunAzimuthDeg = 225, sunElevationDeg = 42;
  static const double deckZ = 7, deckThickness = 1.4, roadZ = 0.12, maxCityBuildings = 4200;
  static const Color sky = Color(0xFF8FB8E0), haze = Color(0xFFDCE5EE), fog = Color(0xFFE6E3DA);
  static const Color asphalt = Color(0xFF6C7178), rail = Color(0xFF5E5650);
  static const Color cityWall = Color(0xFFD5C8BB), cityRoof = Color(0xFFE5DCD2);

  late final double _toSunX, _toSunY, _shadowK;
  bool _sunReady = false;

  final _ground = _Batch(textured: true);
  final _fogB = _Batch(), _flat = _Batch(), _shadow = _Batch(), _items = _Batch();
  final _tmp = Float64List(3);

  // polygon scratch (game space in, camera space clipped out)
  final _px = Float64List(64), _py = Float64List(64), _pz = Float64List(64), _pu = Float64List(64);
  final _pv = Float64List(64);
  final _pc = Int32List(64);
  final _cx = Float64List(80), _cy = Float64List(80), _cz = Float64List(80), _cu = Float64List(80);
  final _cv = Float64List(80);
  final _cc = Int32List(80);
  final _ox = Float64List(80), _oy = Float64List(80), _oz = Float64List(80), _ou = Float64List(80);
  final _ov = Float64List(80);
  final _oc = Int32List(80);

  // city building visibility (0 unknown, 1 shown, 2 hidden under a game road or building)
  Int8List? _cityState;
  int _signature = -1;
  final Map<int, List<int>> _segGrid = {}; // cell -> road segment indices
  final List<double> _segs = []; // x1, y1, x2, y2, halfWidth
  static const double _segCell = 64;

  /// Points the camera at the 2D view (same centre, same map rotation).
  void syncFrom2D() {
    cam
      ..targetX = game.cam.dx
      ..targetY = game.cam.dy
      ..yaw = -game.rot
      ..distance = (520 / game.zoom).clamp(220.0, 1600.0).toDouble()
      ..pitch = 0.78;
  }

  void _initSun() {
    if (_sunReady) return;
    final az = sunAzimuthDeg * math.pi / 180, el = sunElevationDeg * math.pi / 180;
    // horizontal direction towards the sun in game coordinates (x east, y south)
    _toSunX = math.sin(az);
    _toSunY = -math.cos(az);
    _shadowK = 1 / math.tan(el);
    _sunReady = true;
  }

  double get drawRadius => (cam.distance * 2.6).clamp(900.0, 2600.0).toDouble();

  void paint(Canvas canvas, Size size) {
    final sw = Stopwatch()..start();
    _initSun();
    stats.reset();
    cam.update(size);
    final r = drawRadius;
    _paintSky(canvas, size);
    _buildGround(r);
    final img = game.terrainImage;
    final gv = _ground.build();
    if (gv != null && img != null) {
      final paint = Paint()
        ..shader = ImageShader(img, TileMode.clamp, TileMode.clamp, Float64List.fromList(_identity))
        ..filterQuality = FilterQuality.medium;
      canvas.drawVertices(gv, BlendMode.srcOver, paint);
    }
    final fv = _fogB.build();
    if (fv != null) canvas.drawVertices(fv, BlendMode.dst, Paint());
    stats.groundTris = _ground.triangles + _fogB.triangles;

    _buildFlat(r);
    final flv = _flat.build();
    if (flv != null) canvas.drawVertices(flv, BlendMode.dst, Paint());
    stats.flatTris = _flat.triangles;

    final items = _collect(r, size);
    _shadow.clear();
    for (final it in items) {
      _shadowOf(it);
    }
    final shv = _shadow.build();
    if (shv != null) {
      canvas.saveLayer(Offset.zero & size, Paint()..color = const Color(0x4D000000));
      canvas.drawVertices(shv, BlendMode.dst, Paint());
      canvas.restore();
    }
    stats.shadowTris = _shadow.triangles;

    _items.clear();
    for (final it in items) {
      _emitItem(it, r);
    }
    final iv = _items.build();
    if (iv != null) canvas.drawVertices(iv, BlendMode.dst, Paint());
    stats.itemTris = _items.triangles;
    _paintHaze(canvas, size, r);
    stats.paintMs = sw.elapsedMicroseconds / 1000;
  }

  static const _identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

  // ------------------------------------------------------------------ sky, haze

  void _paintSky(Canvas canvas, Size size) {
    final hy = cam.horizonY.clamp(-size.height, size.height * 2).toDouble();
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, math.min(0, hy - size.height)), Offset(0, math.max(1, hy)), [
          sky,
          haze,
        ]),
    );
  }

  void _paintHaze(Canvas canvas, Size size, double r) {
    // soft band where the drawn ground ends, so the edge of the visible disc melts into the sky
    final ahead = _tmp;
    final ok = cam.project(
      cam.targetX + math.sin(cam.yaw) * r * 0.92,
      cam.targetY - math.cos(cam.yaw) * r * 0.92,
      0,
      ahead,
    );
    final edge = ok ? ahead[1] : cam.horizonY;
    final top = math.min(cam.horizonY, edge) - 6, bottom = edge + size.height * 0.10;
    if (bottom <= 0 || top >= size.height) return;
    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, bottom),
      Paint()..shader = ui.Gradient.linear(Offset(0, top), Offset(0, bottom), [haze, haze.withValues(alpha: 0)]),
    );
  }

  // ------------------------------------------------------------------ polygons

  /// Clips the polygon in `_px/_py/_pz` (+ colours/uv) against the near plane and appends it as a fan to [b].
  /// Returns the number of triangles added.
  int _poly(_Batch b, int n) {
    if (n < 3) return 0;
    var anyIn = false, allIn = true;
    for (var i = 0; i < n; i++) {
      cam.toCamera(_px[i], _py[i], _pz[i], _tmp);
      _cx[i] = _tmp[0];
      _cy[i] = _tmp[1];
      _cz[i] = _tmp[2];
      _cu[i] = _pu[i];
      _cv[i] = _pv[i];
      _cc[i] = _pc[i];
      if (_tmp[2] >= OrbitCamera.near) {
        anyIn = true;
      } else {
        allIn = false;
      }
    }
    if (!anyIn) return 0;
    var m = n;
    Float64List sx = _cx, sy = _cy, sz = _cz, su = _cu, sv = _cv;
    Int32List sc = _cc;
    if (!allIn) {
      m = 0;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final zi = _cz[i], zj = _cz[j];
        final inI = zi >= OrbitCamera.near, inJ = zj >= OrbitCamera.near;
        if (inI) {
          _ox[m] = _cx[i];
          _oy[m] = _cy[i];
          _oz[m] = zi;
          _ou[m] = _cu[i];
          _ov[m] = _cv[i];
          _oc[m] = _cc[i];
          m++;
        }
        if (inI != inJ) {
          final t = (OrbitCamera.near - zi) / (zj - zi);
          _ox[m] = _cx[i] + (_cx[j] - _cx[i]) * t;
          _oy[m] = _cy[i] + (_cy[j] - _cy[i]) * t;
          _oz[m] = OrbitCamera.near;
          _ou[m] = _cu[i] + (_cu[j] - _cu[i]) * t;
          _ov[m] = _cv[i] + (_cv[j] - _cv[i]) * t;
          _oc[m] = t < 0.5 ? _cc[i] : _cc[j];
          m++;
        }
      }
      if (m < 3) return 0;
      sx = _ox;
      sy = _oy;
      sz = _oz;
      su = _ou;
      sv = _ov;
      sc = _oc;
    }
    final f = cam.focal, ccx = cam.cx, ccy = cam.cy;
    final x0 = ccx + sx[0] / sz[0] * f, y0 = ccy - sy[0] / sz[0] * f;
    var xa = ccx + sx[1] / sz[1] * f, ya = ccy - sy[1] / sz[1] * f;
    for (var i = 2; i < m; i++) {
      final xb = ccx + sx[i] / sz[i] * f, yb = ccy - sy[i] / sz[i] * f;
      b.vertex(x0, y0, sc[0], su[0], sv[0]);
      b.vertex(xa, ya, sc[i - 1], su[i - 1], sv[i - 1]);
      b.vertex(xb, yb, sc[i], su[i], sv[i]);
      xa = xb;
      ya = yb;
    }
    return m - 2;
  }

  void _setP(int i, double x, double y, double z, int c, [double u = 0, double v = 0]) {
    _px[i] = x;
    _py[i] = y;
    _pz[i] = z;
    _pc[i] = c;
    _pu[i] = u;
    _pv[i] = v;
  }

  // ------------------------------------------------------------------ ground

  void _buildGround(double r) {
    _ground.clear();
    _fogB.clear();
    final w = game.worldSize;
    final x0 = math.max(0.0, cam.targetX - r), x1 = math.min(w, cam.targetX + r);
    final y0 = math.max(0.0, cam.targetY - r), y1 = math.min(w, cam.targetY + r);
    if (x1 <= x0 || y1 <= y0) return;
    final c = game.worldCenter, th = game.terrHalf;
    List<double> lines(double a, double b, double t0, double t1) {
      const steps = 18;
      final s = <double>{for (var i = 0; i <= steps; i++) a + (b - a) * i / steps};
      if (t0 > a && t0 < b) s.add(t0);
      if (t1 > a && t1 < b) s.add(t1);
      return s.toList()..sort();
    }

    final xs = lines(x0, x1, c.dx - th, c.dx + th), ys = lines(y0, y1, c.dy - th, c.dy + th);
    final img = game.terrainImage;
    final k = img == null ? 0.0 : img.width / w;
    final fogC = fog.toARGB32();
    for (var j = 0; j + 1 < ys.length; j++) {
      for (var i = 0; i + 1 < xs.length; i++) {
        final ax = xs[i], bx = xs[i + 1], ay = ys[j], by = ys[j + 1];
        final mx = (ax + bx) / 2, my = (ay + by) / 2;
        final inside = img != null && (mx - c.dx).abs() <= th && (my - c.dy).abs() <= th;
        _setP(0, ax, ay, 0, fogC, ax * k, ay * k);
        _setP(1, bx, ay, 0, fogC, bx * k, ay * k);
        _setP(2, bx, by, 0, fogC, bx * k, by * k);
        _setP(3, ax, by, 0, fogC, ax * k, by * k);
        _poly(inside ? _ground : _fogB, 4);
      }
    }
  }

  // ------------------------------------------------------------------ roads and rails (flat)

  void _ribbon(_Batch b, Offset a, Offset c, double half, double z, int color) {
    final dx = c.dx - a.dx, dy = c.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return;
    final ux = dx / len, uy = dy / len, nx = -uy * half, ny = ux * half;
    final ext = half * 0.55; // overlap at bends so the joints have no gaps
    final ax = a.dx - ux * ext, ay = a.dy - uy * ext, cx = c.dx + ux * ext, cy = c.dy + uy * ext;
    _setP(0, ax + nx, ay + ny, z, color);
    _setP(1, cx + nx, cy + ny, z, color);
    _setP(2, cx - nx, cy - ny, z, color);
    _setP(3, ax - nx, ay - ny, z, color);
    _poly(b, 4);
  }

  bool _near(Offset p, double r) {
    final dx = p.dx - cam.targetX, dy = p.dy - cam.targetY;
    return dx * dx + dy * dy <= r * r;
  }

  void _buildFlat(double r) {
    _flat.clear();
    final rc = rail.toARGB32(), ac = asphalt.toARGB32();
    for (final road in game.railNet.roads.values) {
      if (road.layer != 0) continue; // tunnels are underground
      for (var i = 0; i + 1 < road.pts.length; i++) {
        if (!_near(road.pts[i], r)) continue;
        _ribbon(_flat, road.pts[i], road.pts[i + 1], 3.2, roadZ * 0.5, rc);
      }
    }
    for (final road in game.net.roads.values) {
      if (road.layer != 0) continue; // elevated decks are 3D items
      final half = RoadNetwork.roadWidth * (road.type + 1) / 2;
      for (var i = 0; i + 1 < road.pts.length; i++) {
        if (!_near(road.pts[i], r) && !_near(road.pts[i + 1], r)) continue;
        _ribbon(_flat, road.pts[i], road.pts[i + 1], half, roadZ, ac);
      }
    }
  }

  // ------------------------------------------------------------------ items

  List<_Item> _collect(double r, Size size) {
    final out = <_Item>[];
    final eye = cam.eyeGame;
    final city = this.city;
    if (city != null) {
      _ensureVisibility(city);
      final st = _cityState!;
      final cand = <_Item>[];
      for (final i in city.near(cam.targetX, cam.targetY, r)) {
        final x = city.cx[i], y = city.cy[i];
        final dx = x - cam.targetX, dy = y - cam.targetY;
        if (dx * dx + dy * dy > r * r) continue;
        if (!game.inTerritory(Offset(x, y))) continue;
        final ed = math.sqrt((x - eye.dx) * (x - eye.dx) + (y - eye.dy) * (y - eye.dy));
        if (city.area[i].abs() < 60 && ed > 900) continue; // small houses only near the camera
        if (st[i] == 0) st[i] = _hiddenUnderGame(city, i) ? 2 : 1;
        if (st[i] == 2) {
          stats.hiddenCityBuildings++;
          continue;
        }
        final h = city.heights[i];
        if (!cam.project(x, y, h * 0.5, _tmp)) continue;
        if (_tmp[0] < -size.width * 0.6 || _tmp[0] > size.width * 1.6 || _tmp[1] > size.height * 1.6) continue;
        cand.add(_Item(_Kind.city, i, _tmp[2]));
      }
      if (cand.length > maxCityBuildings) {
        cand.sort((a, b) => a.depth.compareTo(b.depth));
        cand.removeRange(maxCityBuildings.toInt(), cand.length);
      }
      out.addAll(cand);
      stats.cityBuildings = cand.length;
    }
    for (var i = 0; i < game.buildings.length; i++) {
      final b = game.buildings[i];
      if (!_near(b.pos, r)) continue;
      out.add(_Item(_Kind.building, i, cam.depthOf(b.pos.dx, b.pos.dy, 4)));
      stats.gameBuildings++;
    }
    final vs = game.sim.vehicles;
    for (var i = 0; i < vs.length; i++) {
      final v = vs[i];
      if (v.removed) continue;
      final p = v.track.pointAt(math.max(0.0, v.s - v.length / 2));
      if (!_near(p, r)) continue;
      out.add(_Item(_Kind.vehicle, i, cam.depthOf(p.dx, p.dy, 1.5)));
      stats.vehicles++;
    }
    for (final road in game.net.roads.values) {
      if (road.layer != 1) continue;
      for (var i = 0; i + 1 < road.pts.length; i++) {
        final a = road.pts[i], b = road.pts[i + 1];
        if (!_near(a, r)) continue;
        out.add(_Item(_Kind.deck, road.id * 4096 + i, cam.depthOf((a.dx + b.dx) / 2, (a.dy + b.dy) / 2, deckZ)));
        stats.decks++;
      }
    }
    out.sort((a, b) => b.depth.compareTo(a.depth)); // far first
    return out;
  }

  /// A real building that sits under a game road or a game building is hidden (the game objects win).
  bool _hiddenUnderGame(CityBuildings city, int i) {
    for (final b in game.buildings) {
      if (b.containsPoint(Offset(city.cx[i], city.cy[i]), 4)) return true;
    }
    for (var j = city.start[i]; j < city.start[i + 1]; j++) {
      final x = city.xs[j], y = city.ys[j];
      final key = _cellKey(x, y);
      final segs = _segGrid[key];
      if (segs == null) continue;
      for (final s in segs) {
        final o = s * 5;
        if (_distSeg(x, y, _segs[o], _segs[o + 1], _segs[o + 2], _segs[o + 3]) < _segs[o + 4] + 0.5) return true;
      }
    }
    return false;
  }

  static int _cellKey(double x, double y) => (y ~/ _segCell) * 1000 + (x ~/ _segCell);

  void _ensureVisibility(CityBuildings city) {
    var sig = game.net.roads.length * 1000003 + game.buildings.length * 7919 + game.terrHalf.round();
    for (final r in game.net.roads.values) {
      sig = (sig * 31 + r.id) & 0x3FFFFFFF;
    }
    if (_cityState != null && sig == _signature) return;
    _signature = sig;
    _cityState = Int8List(city.length);
    _segGrid.clear();
    _segs.clear();
    for (final road in game.net.roads.values) {
      final half = RoadNetwork.roadWidth * (road.type + 1) / 2;
      for (var i = 0; i + 1 < road.pts.length; i++) {
        final a = road.pts[i], b = road.pts[i + 1];
        final idx = _segs.length ~/ 5;
        _segs.addAll([a.dx, a.dy, b.dx, b.dy, half]);
        final pad = half + 1;
        final x0 = (math.min(a.dx, b.dx) - pad) ~/ _segCell, x1 = (math.max(a.dx, b.dx) + pad) ~/ _segCell;
        final y0 = (math.min(a.dy, b.dy) - pad) ~/ _segCell, y1 = (math.max(a.dy, b.dy) + pad) ~/ _segCell;
        for (var gy = y0; gy <= y1; gy++) {
          for (var gx = x0; gx <= x1; gx++) {
            _segGrid.putIfAbsent(gy * 1000 + gx, () => []).add(idx);
          }
        }
      }
    }
  }

  static double _distSeg(double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax, dy = by - ay;
    final l2 = dx * dx + dy * dy;
    var t = l2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / l2;
    t = t.clamp(0.0, 1.0);
    final qx = ax + dx * t - px, qy = ay + dy * t - py;
    return math.sqrt(qx * qx + qy * qy);
  }

  // ------------------------------------------------------------------ item geometry

  /// Footprint of an item into `_fx/_fy` (game coordinates), returns its vertex count, its height and base z.
  final _fx = Float64List(260), _fy = Float64List(260);
  double _h = 0, _z0 = 0;
  int _wall = 0, _roof = 0;
  Int32List? _roofTris;

  int _footprint(_Item it) {
    _roofTris = null;
    switch (it.kind) {
      case _Kind.city:
        final city = this.city!;
        final s = city.start[it.index], n = city.start[it.index + 1] - s;
        for (var j = 0; j < n; j++) {
          _fx[j] = city.xs[s + j];
          _fy[j] = city.ys[s + j];
        }
        _h = city.heights[it.index];
        _z0 = 0;
        final t = _hash(city.cx[it.index], city.cy[it.index]);
        _wall = _tint(cityWall, 0.94 + 0.10 * t);
        _roof = _tint(cityRoof, 0.95 + 0.08 * t);
        _roofTris = city.roof(it.index);
        return n;
      case _Kind.building:
        final b = game.buildings[it.index];
        _rect(b.pos, b.angle, b.size.width / 2, b.size.height / 2);
        _h = b.type == BuildingType.factory ? 11 : (b.type == BuildingType.shop ? 6.5 : 7.5);
        _z0 = 0;
        _roof = b.roof.toARGB32();
        _wall = _tint(b.roof, 0.80);
        return 4;
      case _Kind.vehicle:
        final v = game.sim.vehicles[it.index];
        final front = v.track.pointAt(v.s), back = v.track.pointAt(math.max(0.0, v.s - v.length));
        var dx = front.dx - back.dx, dy = front.dy - back.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        final angle = len < 1e-3 ? 0.0 : math.atan2(dy, dx);
        final c = v.track.pointAt(math.max(0.0, v.s - v.length / 2));
        // the 2D sprite is drawn along the lane; rectangle half sizes: length along, width across
        final ca = math.cos(angle), sa = math.sin(angle);
        final hl = v.length / 2, hw = v.width / 2;
        dx = ca;
        dy = sa;
        _fx[0] = c.dx + dx * hl - dy * hw;
        _fy[0] = c.dy + dy * hl + dx * hw;
        _fx[1] = c.dx - dx * hl - dy * hw;
        _fy[1] = c.dy - dy * hl + dx * hw;
        _fx[2] = c.dx - dx * hl + dy * hw;
        _fy[2] = c.dy - dy * hl - dx * hw;
        _fx[3] = c.dx + dx * hl + dy * hw;
        _fy[3] = c.dy + dy * hl - dx * hw;
        _h = v.type == VType.truck ? 4.6 : 2.7; // overall height (shadow)
        _z0 = _layerOf(v.track) == 1 ? deckZ : roadZ;
        _wall = _tint(v.color, 0.82);
        _roof = v.color.toARGB32();
        return 4;
      case _Kind.deck:
        final road = game.net.roads[it.index ~/ 4096]!;
        final i = it.index % 4096;
        final a = road.pts[i], b = road.pts[i + 1];
        final half = RoadNetwork.roadWidth * (road.type + 1) / 2;
        final dx = b.dx - a.dx, dy = b.dy - a.dy;
        final len = math.max(1e-6, math.sqrt(dx * dx + dy * dy));
        final ux = dx / len, uy = dy / len, nx = -uy * half, ny = ux * half, e = half * 0.55;
        _fx[0] = a.dx - ux * e + nx;
        _fy[0] = a.dy - uy * e + ny;
        _fx[1] = b.dx + ux * e + nx;
        _fy[1] = b.dy + uy * e + ny;
        _fx[2] = b.dx + ux * e - nx;
        _fy[2] = b.dy + uy * e - ny;
        _fx[3] = a.dx - ux * e - nx;
        _fy[3] = a.dy - uy * e - ny;
        _h = deckThickness;
        _z0 = deckZ - deckThickness;
        _roof = asphalt.toARGB32();
        _wall = const Color(0xFF575B61).toARGB32();
        return 4;
    }
  }

  int _layerOf(Track t) {
    if (t is Lane) return game.net.roads[t.roadId]?.layer ?? 0;
    if (t is Connector) return game.net.roads[t.from.roadId]?.layer ?? 0;
    return 0;
  }

  void _rect(Offset c, double angle, double hx, double hy) {
    final ca = math.cos(angle), sa = math.sin(angle);
    const corners = [
      [-1.0, -1.0],
      [1.0, -1.0],
      [1.0, 1.0],
      [-1.0, 1.0],
    ];
    for (var k = 0; k < 4; k++) {
      final lx = corners[k][0] * hx, ly = corners[k][1] * hy;
      _fx[k] = c.dx + lx * ca - ly * sa;
      _fy[k] = c.dy + lx * sa + ly * ca;
    }
  }

  void _shadowOf(_Item it) {
    final n = _footprint(it);
    final top = _z0 + _h;
    final ox = -_toSunX * _shadowK * top, oy = -_toSunY * _shadowK * top;
    const z = roadZ + 0.03;
    const c = 0xFF000000;
    // the shadow of a prism = its footprint swept along the sun direction: every edge sweeps a quad
    for (var j = 0; j < n; j++) {
      final k = (j + 1) % n;
      _setP(0, _fx[j], _fy[j], z, c);
      _setP(1, _fx[k], _fy[k], z, c);
      _setP(2, _fx[k] + ox, _fy[k] + oy, z, c);
      _setP(3, _fx[j] + ox, _fy[j] + oy, z, c);
      _poly(_shadow, 4);
    }
    // plus the far cap (the roof outline on the ground); triangulated when it is not a rectangle
    final tris = _roofTris;
    if (tris == null) {
      for (var j = 0; j < n; j++) {
        _setP(j, _fx[j] + ox, _fy[j] + oy, z, c);
      }
      _poly(_shadow, n);
    } else {
      for (var t = 0; t + 2 < tris.length; t += 3) {
        for (var q = 0; q < 3; q++) {
          _setP(q, _fx[tris[t + q]] + ox, _fy[tris[t + q]] + oy, z, c);
        }
        _poly(_shadow, 3);
      }
    }
  }

  void _emitItem(_Item it, double r) {
    final fogT = ((it.depth - r * 0.6) / (r * 0.4)).clamp(0.0, 1.0) * 0.85;
    if (it.kind == _Kind.vehicle) {
      _emitVehicle(game.sim.vehicles[it.index], fogT);
      return;
    }
    final n = _footprint(it);
    _emitPrism(n, _z0, _z0 + _h, _wall, _roof, _roofTris, fogT);
  }

  /// Car: low body + glass cabin; truck: cab at the front + taller cargo box.
  void _emitVehicle(Vehicle v, double fogT) {
    final front = v.track.pointAt(v.s), back = v.track.pointAt(math.max(0.0, v.s - v.length));
    final dx = front.dx - back.dx, dy = front.dy - back.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final ca = len < 1e-3 ? 1.0 : dx / len, sa = len < 1e-3 ? 0.0 : dy / len;
    final c = v.track.pointAt(math.max(0.0, v.s - v.length / 2));
    final z0 = _layerOf(v.track) == 1 ? deckZ : roadZ;
    final l = v.length, w = v.width;
    final body = v.color, glass = const Color(0xFF34404B).toARGB32();
    if (v.type == VType.truck) {
      _box(c.dx + ca * l * 0.39, c.dy + sa * l * 0.39, ca, sa, l * 0.11, w * 0.47);
      _emitPrism(4, z0, z0 + 3.2, _tint(const Color(0xFF8B3A2E), 0.85), const Color(0xFFB5523F).toARGB32(), null, fogT);
      _box(c.dx - ca * l * 0.12, c.dy - sa * l * 0.12, ca, sa, l * 0.38, w * 0.5);
      _emitPrism(4, z0, z0 + 4.6, _tint(body, 0.84), body.toARGB32(), null, fogT);
    } else {
      _box(c.dx, c.dy, ca, sa, l * 0.5, w * 0.5);
      _emitPrism(4, z0, z0 + 1.5, _tint(body, 0.82), body.toARGB32(), null, fogT);
      _box(c.dx - ca * l * 0.06, c.dy - sa * l * 0.06, ca, sa, l * 0.27, w * 0.43);
      _emitPrism(4, z0 + 1.5, z0 + 2.7, glass, _tint(body, 1.04), null, fogT);
    }
  }

  /// Rotated rectangle (centre, direction cos/sin, half length, half width) into `_fx/_fy`.
  void _box(double cx, double cy, double ca, double sa, double hl, double hw) {
    _fx[0] = cx + ca * hl - sa * hw;
    _fy[0] = cy + sa * hl + ca * hw;
    _fx[1] = cx - ca * hl - sa * hw;
    _fy[1] = cy - sa * hl + ca * hw;
    _fx[2] = cx - ca * hl + sa * hw;
    _fy[2] = cy - sa * hl - ca * hw;
    _fx[3] = cx + ca * hl + sa * hw;
    _fy[3] = cy + sa * hl - ca * hw;
  }

  void _emitPrism(int n, double z0, double top, int wallArgb, int roofArgb, Int32List? tris, double fogT) {
    final eye = cam.eyeGame;
    final eh = cam.eyeHeight;
    // orientation of the footprint: outward normal of edge (a -> b) is sign * (dy, -dx)
    var area = 0.0;
    for (var j = 0; j < n; j++) {
      final k = (j + 1) % n;
      area += _fx[j] * _fy[k] - _fx[k] * _fy[j];
    }
    final sign = area >= 0 ? 1.0 : -1.0;
    for (var j = 0; j < n; j++) {
      final k = (j + 1) % n;
      final dx = _fx[k] - _fx[j], dy = _fy[k] - _fy[j];
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;
      final nx = sign * dy / len, ny = sign * -dx / len;
      // back-face culling: only walls that face the eye
      if ((eye.dx - _fx[j]) * nx + (eye.dy - _fy[j]) * ny <= 0) continue;
      final lit = 0.62 + 0.38 * math.max(0.0, nx * _toSunX + ny * _toSunY);
      final cTop = _fogged(_tint(Color(wallArgb), lit), fogT);
      final cBottom = _fogged(_tint(Color(wallArgb), lit * 0.86), fogT); // a little darker at the foot
      _setP(0, _fx[j], _fy[j], z0, cBottom);
      _setP(1, _fx[k], _fy[k], z0, cBottom);
      _setP(2, _fx[k], _fy[k], top, cTop);
      _setP(3, _fx[j], _fy[j], top, cTop);
      _poly(_items, 4);
    }
    if (eh < top) return; // the roof is not visible from below
    final rc = _fogged(roofArgb, fogT);
    if (tris == null) {
      for (var j = 0; j < n; j++) {
        _setP(j, _fx[j], _fy[j], top, rc);
      }
      _poly(_items, n);
    } else {
      for (var t = 0; t + 2 < tris.length; t += 3) {
        for (var q = 0; q < 3; q++) {
          _setP(q, _fx[tris[t + q]], _fy[tris[t + q]], top, rc);
        }
        _poly(_items, 3);
      }
    }
  }

  // ------------------------------------------------------------------ colours

  static int _tint(Color c, double k) {
    final r = (c.r * 255 * k).round().clamp(0, 255), g = (c.g * 255 * k).round().clamp(0, 255);
    final b = (c.b * 255 * k).round().clamp(0, 255);
    return 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  static int _fogged(int argb, double t) {
    if (t <= 0) return argb;
    final hr = (haze.r * 255).round(), hg = (haze.g * 255).round(), hb = (haze.b * 255).round();
    final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    return 0xFF000000 |
        ((r + (hr - r) * t).round() << 16) |
        ((g + (hg - g) * t).round() << 8) |
        (b + (hb - b) * t).round();
  }

  static double _hash(double x, double y) {
    var h = ((x * 4).round() * 73856093) ^ ((y * 4).round() * 19349663);
    h &= 0xFFFFFFFF;
    h ^= h >> 16;
    h = (h * 0x45d9f3b) & 0xFFFFFFFF;
    h ^= h >> 16;
    return h / 4294967296.0;
  }
}

enum _Kind { city, building, vehicle, deck }

class _Item {
  _Item(this.kind, this.index, this.depth);
  final _Kind kind;
  final int index;
  final double depth;
}
