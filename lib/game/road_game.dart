import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui show Image;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'building.dart';
import 'lane_graph.dart';
import 'road_network.dart';
import 'terrain.dart';
import 'traffic_sim.dart';

enum Tool { pan, straight, curve, erase }

class RoadPlan {
  RoadPlan(this.a, this.b, this.c, this.pts, this.length, this.cost, this.error);
  final Offset a, b;
  final Offset? c;
  final List<Offset> pts;
  final double length, cost;
  final String? error;
  bool get valid => error == null;
}

class RoadGame extends FlameGame {
  RoadGame({this.seed = 7});

  static const double startBudget = 3000;
  static const double minRoadLength = 40;
  static const double minZoom = 0.12;
  static const double maxZoom = 3.0;
  static const double _simStep = 0.05;

  int seed;
  late Terrain terrain;
  ui.Image? terrainImage;
  final RoadNetwork net = RoadNetwork();
  final List<Building> buildings = [];
  late LaneGraph graph;
  late TrafficSim sim;

  /// HUD yangilanishi uchun hisoblagich.
  final ValueNotifier<int> hud = ValueNotifier<int>(0);

  bool loading = true;
  double budget = startBudget;
  Tool tool = Tool.pan;
  RoadPlan? currentPlan;
  int noAccess = 0; // yo'lga ulanmagan binolar
  int speed = 1; // 0 pauza, 1, 2, 4

  double _acc = 0;
  double _hudTimer = 0;

  // kamera
  Offset cam = const Offset(1600, 1600);
  double zoom = 0.8;

  // chizish holati: 0 bo'sh, 1 sudrash, 2 egish kutilmoqda, 3 egishni sudrash
  int stage = 0;
  Offset? _a, _b, _c;

  // pointerlar
  final Map<int, Offset> _ptrs = {};
  Offset _downPos = Offset.zero;
  bool _moved = false;
  bool _multi = false;
  double _lastDist = 0;
  Offset _lastMid = Offset.zero;

  @override
  Color backgroundColor() => const Color(0xFFBFD9EE);

  @override
  Future<void> onLoad() async {
    await newMap(seed);
  }

  // ---------------------------------------------------------------- xarita

  Future<void> newMap(int s) async {
    loading = true;
    seed = s;
    stage = 0;
    currentPlan = null;
    hud.value++;
    terrain = Terrain(s);
    terrainImage = await terrain.toImage();
    net.clear();
    graph = LaneGraph(net);
    sim = TrafficSim(graph, buildings, s);
    budget = startBudget;
    _placeBuildings();
    _onNetworkChanged();
    loading = false;
    _notify();
  }

  void _onNetworkChanged() {
    graph.rebuild();
    graph.computeAccess(buildings);
    sim.onGraphChanged();
    noAccess = buildings.where((b) => !graph.access.containsKey(b.id)).length;
  }

  bool _landDisk(Offset p, double r) {
    if (!terrain.isBuildableAt(p)) return false;
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * 2 * pi;
      if (!terrain.isBuildableAt(p + Offset(cos(a), sin(a)) * r)) return false;
    }
    return true;
  }

  void _placeBuildings() {
    final rnd = Random(seed);
    buildings.clear();

    Offset? center;
    for (var i = 0; i < 4000 && center == null; i++) {
      final p = Offset(800 + rnd.nextDouble() * 1600, 800 + rnd.nextDouble() * 1600);
      if (_landDisk(p, 300)) center = p;
    }
    center ??= const Offset(1600, 1600);
    cam = center;
    zoom = 0.9;

    const houseRoofs = [Color(0xFFC9694F), Color(0xFF7FA66B), Color(0xFFD9A441), Color(0xFF8C6E5D)];
    const shopRoofs = [Color(0xFF5B8DD6), Color(0xFF4F7FC4)];
    const factoryRoofs = [Color(0xFF9A9DA3), Color(0xFF8B8F96)];

    var id = 1;
    void place(BuildingType type, int count, Size size, List<Color> roofs) {
      for (var k = 0; k < count; k++) {
        for (var t = 0; t < 300; t++) {
          final ang = rnd.nextDouble() * 2 * pi;
          final dist = sqrt(rnd.nextDouble()) * 420;
          final p = center! + Offset(cos(ang), sin(ang)) * dist;
          final r = size.longestSide / 2 + 8;
          if (!terrain.isBuildableAt(p)) continue;
          if (!terrain.isBuildableAt(p + Offset(r, 0)) ||
              !terrain.isBuildableAt(p + Offset(-r, 0)) ||
              !terrain.isBuildableAt(p + Offset(0, r)) ||
              !terrain.isBuildableAt(p + Offset(0, -r))) {
            continue;
          }
          if (buildings.any((b) => (b.pos - p).distance < 90)) continue;
          buildings.add(Building(
            id: id++,
            type: type,
            pos: p,
            angle: rnd.nextInt(4) * pi / 2 + (rnd.nextDouble() - 0.5) * 0.3,
            size: size,
            roof: roofs[rnd.nextInt(roofs.length)],
          ));
          break;
        }
      }
    }

    place(BuildingType.house, 14, const Size(34, 26), houseRoofs);
    place(BuildingType.shop, 4, const Size(52, 34), shopRoofs);
    place(BuildingType.factory, 2, const Size(70, 46), factoryRoofs);
  }

  // ---------------------------------------------------------- saqlash/yuklash

  Future<bool> save({bool auto = false}) async {
    if (loading) return false;
    try {
      final sp = await SharedPreferences.getInstance();
      final key = auto ? 'autosave' : 'save1';
      final old = sp.getString(key);
      if (old != null) await sp.setString('${key}_prev', old);
      final data = jsonEncode({
        'v': 1,
        'seed': seed,
        'budget': budget,
        'cam': [cam.dx, cam.dy],
        'zoom': zoom,
        'roads': [
          for (final r in net.roads.values)
            [for (final p in r.pts) ...[p.dx, p.dy]]
        ],
      });
      await sp.setString(key, data);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> load() async {
    final SharedPreferences sp;
    try {
      sp = await SharedPreferences.getInstance();
    } catch (_) {
      return false;
    }
    for (final key in ['save1', 'save1_prev', 'autosave', 'autosave_prev']) {
      final raw = sp.getString(key);
      if (raw == null) continue;
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['v'] != 1) continue;
        final s = m['seed'] as int;
        final bud = (m['budget'] as num).toDouble();
        final c = (m['cam'] as List).map((e) => (e as num).toDouble()).toList();
        final z = (m['zoom'] as num).toDouble();
        final roads = <List<Offset>>[];
        for (final r in m['roads'] as List) {
          final f = (r as List).map((e) => (e as num).toDouble()).toList();
          if (f.length < 4 || f.length.isOdd) throw const FormatException('road');
          roads.add([for (var i = 0; i < f.length; i += 2) Offset(f[i], f[i + 1])]);
        }
        await newMap(s);
        for (final pts in roads) {
          net.addRoadPts(pts);
        }
        budget = bud;
        cam = Offset(c[0], c[1]);
        zoom = z.clamp(minZoom, maxZoom).toDouble();
        _onNetworkChanged();
        _notify();
        return true;
      } catch (_) {
        continue; // buzilgan fayl: oldingi zaxira nusxaga o'tamiz
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- kamera

  Offset toWorld(Offset s) =>
      Offset((s.dx - size.x / 2) / zoom + cam.dx, (s.dy - size.y / 2) / zoom + cam.dy);

  void _clampCam() {
    cam = Offset(
      cam.dx.clamp(0.0, Terrain.worldSize).toDouble(),
      cam.dy.clamp(0.0, Terrain.worldSize).toDouble(),
    );
  }

  void wheel(Offset pos, double dy) {
    final before = toWorld(pos);
    zoom = (zoom * exp(-dy * 0.0015)).clamp(minZoom, maxZoom).toDouble();
    cam = before - Offset((pos.dx - size.x / 2) / zoom, (pos.dy - size.y / 2) / zoom);
    _clampCam();
  }

  void _initPinch() {
    final p = _ptrs.values.take(2).toList();
    _lastMid = (p[0] + p[1]) / 2;
    _lastDist = (p[0] - p[1]).distance;
  }

  void _pinch() {
    final p = _ptrs.values.take(2).toList();
    final mid = (p[0] + p[1]) / 2;
    final dist = (p[0] - p[1]).distance;
    if (_lastDist > 0 && dist > 0) {
      final before = toWorld(_lastMid);
      zoom = (zoom * dist / _lastDist).clamp(minZoom, maxZoom).toDouble();
      cam = before - Offset((mid.dx - size.x / 2) / zoom, (mid.dy - size.y / 2) / zoom);
    }
    _lastMid = mid;
    _lastDist = dist;
    _clampCam();
  }

  // ------------------------------------------------------------- boshqaruv

  void setTool(Tool t) {
    tool = t;
    stage = 0;
    _notify();
  }

  void cancel() {
    stage = 0;
    _notify();
  }

  void cycleSpeed() {
    speed = speed == 1 ? 2 : (speed == 2 ? 4 : (speed == 4 ? 0 : 1));
    hud.value++;
  }

  Offset _snap(Offset w) {
    final n = net.nodeNear(w, 26 / zoom + 6);
    if (n != null) return n.pos;
    final h = net.nearestRoadPoint(w, 16 / zoom + 6);
    return h?.point ?? w;
  }

  void pointerDown(int id, Offset pos) {
    if (loading) return;
    _ptrs[id] = pos;
    if (_ptrs.length >= 2) {
      _multi = true;
      if (stage == 1) stage = 0;
      if (stage == 3) stage = 2;
      _initPinch();
      _notify();
      return;
    }
    _multi = false;
    _downPos = pos;
    _moved = false;
    final w = toWorld(pos);
    switch (tool) {
      case Tool.straight:
        stage = 1;
        _a = _snap(w);
        _b = _a;
        break;
      case Tool.curve:
        if (stage == 2) {
          stage = 3;
          _c = w;
        } else {
          stage = 1;
          _a = _snap(w);
          _b = _a;
        }
        break;
      default:
        break;
    }
    _notify();
  }

  void pointerMove(int id, Offset pos) {
    final prev = _ptrs[id];
    if (prev == null) return;
    _ptrs[id] = pos;
    if (_ptrs.length >= 2) {
      _pinch();
      return;
    }
    if (_multi) return;
    if ((pos - _downPos).distance > 8) _moved = true;
    switch (tool) {
      case Tool.pan:
        cam -= (pos - prev) / zoom;
        _clampCam();
        break;
      case Tool.straight:
      case Tool.curve:
        if (stage == 1) {
          _b = _snap(toWorld(pos));
        } else if (stage == 3) {
          _c = toWorld(pos);
        }
        break;
      case Tool.erase:
        break;
    }
    _notify();
  }

  void pointerUp(int id) {
    final pos = _ptrs.remove(id);
    if (pos == null) return;
    if (_multi) {
      if (_ptrs.isEmpty) _multi = false;
      return;
    }
    switch (tool) {
      case Tool.erase:
        if (!_moved) _eraseAt(toWorld(pos));
        break;
      case Tool.straight:
        if (stage == 1) {
          final p = currentPlan;
          if (p != null && p.valid) _commit(p);
          stage = 0;
        }
        break;
      case Tool.curve:
        if (stage == 1) {
          if (_moved && (_b! - _a!).distance >= minRoadLength) {
            stage = 2;
            _c = (_a! + _b!) / 2;
          } else {
            stage = 0;
          }
        } else if (stage == 3) {
          final p = currentPlan;
          if (p != null && p.valid) {
            _commit(p);
            stage = 0;
          } else {
            stage = 2;
          }
        }
        break;
      case Tool.pan:
        break;
    }
    _notify();
  }

  void _eraseAt(Offset w) {
    final r = net.roadNear(w, 14 / zoom + 8);
    if (r == null) return;
    budget += r.cost; // to'liq qaytarish
    net.removeRoad(r.id);
    _onNetworkChanged();
  }

  void _commit(RoadPlan p) {
    net.connectRoad(p.pts);
    budget -= p.cost;
    _onNetworkChanged();
  }

  // -------------------------------------------------------------- yo'l rejasi

  bool _tooSharp(Offset a, Offset b, Offset c) {
    final va = a - c, vb = b - c;
    final la = va.distance, lb = vb.distance;
    if (la < 1 || lb < 1) return true;
    final cosA = ((va.dx * vb.dx + va.dy * vb.dy) / (la * lb)).clamp(-1.0, 1.0).toDouble();
    return acos(cosA) < 0.9; // ~52 daraja
  }

  RoadPlan _buildPlan(Offset a, Offset b, Offset? c) {
    final pts = RoadNetwork.sample(a, b, c);
    final len = RoadNetwork.polyLength(pts);
    final cost = len * RoadNetwork.costPerUnit;
    String? err;
    if (len < minRoadLength) {
      err = "Juda qisqa";
    } else if (c != null && _tooSharp(a, b, c)) {
      err = "Burchak juda keskin";
    } else if (pts.any(terrain.isWaterAt)) {
      err = "Suv ustiga yo'l qurib bo'lmaydi";
    } else if (buildings.any((bd) => pts.any((p) => (p - bd.pos).distance < bd.radius))) {
      err = "Yo'l binoga tegmoqda";
    } else if (cost > budget) {
      err = "Mablag' yetarli emas";
    }
    return RoadPlan(a, b, c, pts, len, cost, err);
  }

  RoadPlan? _computePlan() {
    if (stage == 0 || _a == null || _b == null) return null;
    if (stage == 1) return _buildPlan(_a!, _b!, null);
    return _buildPlan(_a!, _b!, _c ?? (_a! + _b!) / 2);
  }

  void _notify() {
    currentPlan = _computePlan();
    hud.value++;
  }

  // ----------------------------------------------------------------- yangilash

  @override
  void update(double dt) {
    super.update(dt);
    if (loading) return;
    if (speed > 0) {
      _acc += min(dt, 0.1) * speed;
      var n = 0;
      while (_acc >= _simStep && n < 10) {
        sim.step(_simStep);
        _acc -= _simStep;
        n++;
      }
      if (_acc > _simStep) _acc = 0; // qurilma ulgurmasa, tezlikni pasaytiramiz
    }
    _hudTimer += dt;
    if (_hudTimer > 0.3) {
      _hudTimer = 0;
      hud.value++;
    }
  }

  // ----------------------------------------------------------------- chizish

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (loading || terrainImage == null) return;

    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(zoom);
    canvas.translate(-cam.dx, -cam.dy);

    _drawTerrain(canvas);
    _drawRoads(canvas);
    for (final b in buildings) {
      b.draw(canvas);
    }
    _drawVehicles(canvas);
    _drawPreview(canvas);

    canvas.restore();
  }

  void _drawTerrain(Canvas canvas) {
    final img = terrainImage!;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      const Rect.fromLTWH(0, 0, Terrain.worldSize, Terrain.worldSize),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  Path _pathOf(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    return path;
  }

  void _drawRoads(Canvas canvas) {
    if (net.roads.isEmpty) return;
    const w = RoadNetwork.roadWidth;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w + 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF4A4D52);
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFDADCDF);
    final center = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xCCD9B85A);

    final paths = [for (final r in net.roads.values) _pathOf(r.pts)];
    for (final p in paths) {
      canvas.drawPath(p, border);
    }
    for (final p in paths) {
      canvas.drawPath(p, fill);
    }
    for (final p in paths) {
      canvas.drawPath(p, center);
    }
    final junction = Paint()..color = const Color(0xFFDADCDF);
    for (final n in net.nodes.values) {
      if (n.roads.length >= 3) canvas.drawCircle(n.pos, w * 0.7, junction);
    }
  }

  void _drawVehicles(Canvas canvas) {
    final k = max(1.0, 3.0 / (4.4 * zoom)); // uzoqdan ham ko'rinishi uchun
    final paint = Paint();
    final glass = Paint()..color = const Color(0x55000000);
    for (final v in sim.vehicles) {
      final p = v.track.pointAt(v.s);
      final d = v.track.dirAt(v.s);
      final c = p - d * (v.length * k / 2);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(atan2(d.dy, d.dx));
      final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: v.length * k, height: v.width * k),
        Radius.circular(1.5 * k),
      );
      paint.color = v.color;
      canvas.drawRRect(body, paint);
      canvas.drawRect(
        Rect.fromLTWH(v.length * k * 0.12, -v.width * k * 0.35, v.length * k * 0.2, v.width * k * 0.7),
        glass,
      );
      canvas.restore();
    }
  }

  void _drawPreview(Canvas canvas) {
    final plan = currentPlan;
    if (plan == null) return;
    final color = plan.valid ? const Color(0xAA29C5D6) : const Color(0xAAE0524A);
    canvas.drawPath(
      _pathOf(plan.pts),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = RoadNetwork.roadWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    final dot = Paint()..color = const Color(0xFF1B8FA0);
    canvas.drawCircle(plan.a, 5, dot);
    canvas.drawCircle(plan.b, 5, dot);
    if (plan.c != null && stage >= 2) {
      canvas.drawCircle(plan.c!, 6, Paint()..color = const Color(0xFFF2A33A));
    }
  }
}
