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
import 'signal.dart';
import 'terrain.dart';
import 'traffic_model.dart';
import 'traffic_sim.dart';

enum Tool { pan, straight, curve, signal, roundabout, erase, building, inspect }

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
  String loadStatus = "Yuklanmoqda...";
  String? loadError;
  double budget = startBudget;
  Tool tool = Tool.pan;
  RoadPlan? currentPlan;
  int noAccess = 0; // yo'lga ulanmagan binolar
  int speed = 1; // 0 pauza, 1, 2, 4
  bool heat = false; // tirbandlik xaritasi

  // shahar darajasi va mamnuniyat
  static const int maxLevel = 12;
  static const double levelNeedSeconds = 20;
  int level = 1;
  double satisfaction = 50;
  double levelTimer = 0;
  String satNote = "";
  int _tripsAtLevel = 0;
  double _econTimer = 0;
  int _nextBuildingId = 1;
  Offset cityCenter = const Offset(1600, 1600);
  double get satTarget => min(85.0, 55 + 3.0 * level + (difficulty - 1) * 5);

  // o'yin sozlamalari
  int biome = 0; // 0 tekislik, 1 daryo deltasi, 2 tog' vodiysi, 3 orollar
  int difficulty = 1; // 0 oson, 1 oddiy, 2 qiyin
  bool sandbox = false;
  int roadType = 0; // 0 oddiy, 1 katta yo'l
  int buildType = 0; // sandbox: 0 uy, 1 do'kon, 2 zavod
  double demand = 1.0; // sandbox: talab ko'paytmasi
  Vehicle? selected;

  // ekologiya: zavod ifloslanishi + transport shovqini
  double env = 1.0; // 1 = toza va tinch
  bool showEnv = false;
  final Map<int, double> envExpo = {}; // uy id -> ekologik yuk 0..1

  // koordinata tekshiruvi (debug)
  bool debug = false;
  Offset? _lastTouch;
  Offset? lastGlobal;
  double dpr = 1;
  Size widgetSize = Size.zero;

  // grafiklar (chegaralangan tarix)
  final List<double> histVeh = [];
  final List<double> histSat = [];
  final List<double> histTrip = [];
  final List<double> histCong = [];
  double _histT = 0;
  bool showCharts = false;

  // xarita aylantirish (ikki barmoq bilan burash)
  double rot = 0;
  double _twist = 0;
  bool _rotating = false;
  double _lastAng = 0;
  Offset? _dragScreen; // chizish paytida barmoq joyi (chetga yetganda xarita suriladi)

  // o'rgatuvchi vazifalar (haqiqiy o'yin holatidan aniqlanadi)
  bool tutorial = true;
  int tutStep = 0;
  bool _heatSeen = false;
  Offset _camStart = Offset.zero;
  double _zoomStart = 1;
  static const tutorialTexts = [
    "Kamerani suring, kattalashtiring yoki buring (2 barmoq)",
    "«To'g'ri» asbobi bilan birinchi yo'lni chizing",
    "Barcha binolarni yo'lga ulang",
    "Mashinalar yurishini kuzating (kamida 3 safar)",
    "«Tirbandlik» tugmasi bilan yo'l yuklanishini ko'ring",
    "«Svetofor» bilan chorrahaga svetofor qo'ying",
    "«Aylana» bilan aylana chorraha quring",
    "Mamnuniyatni oshirib 2-darajaga chiqing",
  ];
  double get _startBudgetFor => const [4500.0, 3000.0, 2000.0][difficulty];
  final List<Offset> roundabouts = [];
  static const double roundaboutRadius = 30;
  String? flash;
  double _flashT = 0;

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

  // ---------------------------------------------------------------- xarita

  /// Xarita yaratish. Xato bo'lsa ekranda ko'rsatiladi (qotib qolmaydi).
  Future<void> newMap(int s, {int? biome, int? difficulty, bool? sandbox}) async {
    if (biome != null) this.biome = biome;
    if (difficulty != null) this.difficulty = difficulty;
    if (sandbox != null) this.sandbox = sandbox;
    loadError = null;
    try {
      await _newMapImpl(s);
    } catch (e, st) {
      loadError = '$e\n${st.toString().split("\n").take(3).join("\n")}';
      loading = true;
      hud.value++;
    }
  }

  Future<void> _newMapImpl(int s) async {
    loading = true;
    loadStatus = "Relyef yaratilmoqda...";
    seed = s;
    stage = 0;
    currentPlan = null;
    hud.value++;
    terrain = Terrain(s, biome);
    terrainImage = await terrain.toImage();
    loadStatus = "Binolar joylashtirilmoqda...";
    hud.value++;
    net.clear();
    roundabouts.clear();
    graph = LaneGraph(net);
    sim = TrafficSim(graph, buildings, s);
    sim.demandScale = const [0.7, 1.0, 1.4][difficulty];
    budget = sandbox ? 1e9 : _startBudgetFor;
    demand = 1.0;
    selected = null;
    rot = 0;
    histVeh.clear();
    histSat.clear();
    histTrip.clear();
    histCong.clear();
    level = 1;
    satisfaction = 50;
    levelTimer = 0;
    _tripsAtLevel = 0;
    satNote = "";
    tutorial = !sandbox;
    tutStep = 0;
    _heatSeen = false;
    _placeBuildings();
    _camStart = cam;
    _zoomStart = zoom;
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

  static const _houseRoofs = [Color(0xFFC9694F), Color(0xFF7FA66B), Color(0xFFD9A441), Color(0xFF8C6E5D)];
  static const _shopRoofs = [Color(0xFF5B8DD6), Color(0xFF4F7FC4)];
  static const _factoryRoofs = [Color(0xFF9A9DA3), Color(0xFF8B8F96)];

  void _placeBuildings() {
    final rnd = Random(seed);
    buildings.clear();
    _nextBuildingId = 1;
    Offset? center;
    for (final rad in const [300.0, 220.0, 150.0, 100.0]) {
      for (var i = 0; i < 3000 && center == null; i++) {
        final p = Offset(800 + rnd.nextDouble() * 1600, 800 + rnd.nextDouble() * 1600);
        if (_landDisk(p, rad)) center = p;
      }
      if (center != null) break;
    }
    cityCenter = center ?? const Offset(1600, 1600);
    cam = cityCenter;
    zoom = 0.9;
    _placeBatch(rnd, 14, 4, 2, 420);
  }

  /// Yangi binolar to'plamini joylashtiradi (mavjud binolar va yo'llardan uzoqda).
  void _placeBatch(Random rnd, int houses, int shops, int factories, double reach) {
    void place(BuildingType type, int count, Size size, List<Color> roofs) {
      for (var k = 0; k < count; k++) {
        for (var t = 0; t < 400; t++) {
          final ang = rnd.nextDouble() * 2 * pi;
          final dist = sqrt(rnd.nextDouble()) * reach;
          final p = cityCenter + Offset(cos(ang), sin(ang)) * dist;
          final r = size.longestSide / 2 + 8;
          if (!terrain.isBuildableAt(p)) continue;
          if (!terrain.isBuildableAt(p + Offset(r, 0)) ||
              !terrain.isBuildableAt(p + Offset(-r, 0)) ||
              !terrain.isBuildableAt(p + Offset(0, r)) ||
              !terrain.isBuildableAt(p + Offset(0, -r))) {
            continue;
          }
          if (buildings.any((b) => (b.pos - p).distance < 90)) continue;
          if (net.nearestRoadPoint(p, r + 10) != null) continue;
          buildings.add(Building(
            id: _nextBuildingId++,
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

    place(BuildingType.house, houses, const Size(34, 26), _houseRoofs);
    place(BuildingType.shop, shops, const Size(52, 34), _shopRoofs);
    place(BuildingType.factory, factories, const Size(70, 46), _factoryRoofs);
  }

  // ------------------------------------------------------- mamnuniyat va darajalar

  /// Mamnuniyat (0-100) = 45% yo'lga ulanish + 25% safar vaqti + 20% oqim tezligi + 10% muvaffaqiyatli safarlar.
  void _push(List<double> l, double v) {
    l.add(v);
    if (l.length > 90) l.removeAt(0);
  }

  void _econTick() {
    _histT += 1;
    if (_histT >= 2) {
      _histT = 0;
      _push(histVeh, sim.vehicles.length.toDouble());
      _push(histSat, satisfaction);
      _push(histTrip, sim.avgTrip);
      var withV = 0, bad = 0;
      for (final l in graph.lanes.values) {
        if (l.vehicles.isNotEmpty) {
          withV++;
          if (l.ratio < 0.4) bad++;
        }
      }
      _push(histCong, withV == 0 ? 0.0 : 100.0 * bad / withV);
    }
    // mashinalar soni darajaga qarab o'sadi (tarmoq ortiqcha yuklanib qotib qolmasin)
    sim.maxVehicles = sandbox ? 250 : min(250, 100 + 25 * level);

    // ekologiya: ifloslanish (zavodgacha masofa) va shovqin (yaqin mashinalar, yuk mashinasi 2x)
    final factories = buildings.where((b) => b.type == BuildingType.factory).toList();
    final vpos = [for (final v in sim.vehicles) (v.track.pointAt(v.s), v.type == VType.truck ? 2.0 : 1.0)];
    var expoSum = 0.0;
    var houses = 0;
    envExpo.clear();
    for (final b in buildings) {
      if (b.type != BuildingType.house) continue;
      var pol = 0.0;
      for (final f in factories) {
        final d = (f.pos - b.pos).distance;
        if (d < 250) pol += 1 - d / 250;
      }
      var noise = 0.0;
      for (final p in vpos) {
        final d = (p.$1 - b.pos).distance;
        if (d < 110) noise += (1 - d / 110) * p.$2;
      }
      final e = min(1.0, 0.6 * min(1.0, pol) + 0.4 * min(1.0, noise / 3.0));
      envExpo[b.id] = e;
      expoSum += e;
      houses++;
    }
    env = houses == 0 ? 1.0 : 1 - expoSum / houses;

    final total = buildings.length;
    final access = total == 0 ? 0.0 : (total - noAccess) / total;
    final commute = sim.completed < 3
        ? 0.5
        : (1 - (sim.avgTrip - 20) / 80).clamp(0.0, 1.0).toDouble();
    var sum = 0.0;
    for (final l in graph.lanes.values) {
      sum += l.ratio;
    }
    final flow = graph.lanes.isEmpty ? 0.0 : sum / graph.lanes.length;
    final failFrac = sim.failed / (sim.failed + sim.completed + 1);
    final raw = 100 * (0.40 * access + 0.22 * commute + 0.18 * flow + 0.08 * (1 - failFrac) + 0.12 * env);
    satisfaction += (raw - satisfaction) * 0.15;

    if (noAccess > 0) {
      satNote = "Yo'lga ulanmagan binolar: $noAccess";
    } else if (commute < 0.5) {
      satNote = "Safarlar juda uzoq davom etyapti";
    } else if (flow < 0.6) {
      satNote = "Tirbandlik mamnuniyatni pasaytiryapti";
    } else if (env < 0.6) {
      satNote = "Zavod ifloslanishi va shovqin uylarni bezovta qilyapti";
    } else {
      satNote = "Tarmoq yaxshi ishlayapti";
    }

    final ok = satisfaction >= satTarget && noAccess == 0 && (sim.completed - _tripsAtLevel) >= 6;
    levelTimer = ok ? levelTimer + 1 : max(0.0, levelTimer - 1);
    if (levelTimer >= levelNeedSeconds && level < maxLevel && !sandbox) _levelUp();
  }

  void _levelUp() {
    level++;
    levelTimer = 0;
    final bonus = const [2000.0, 1500.0, 1000.0][difficulty];
    budget += bonus;
    _tripsAtLevel = sim.completed;
    final before = buildings.length;
    _placeBatch(Random(seed * 31 + level), 3 + level ~/ 2, level.isEven ? 1 : 0,
        level % 3 == 0 ? 1 : 0, 420 + 50.0 * level);
    _onNetworkChanged();
    flashMsg("Daraja $level! +${bonus.round()} mablag', yangi binolar: ${buildings.length - before}");
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
        'v': 2,
        'seed': seed,
        'budget': budget,
        'level': level,
        'biome': biome,
        'diff': difficulty,
        'sbx': sandbox ? 1 : 0,
        'buildings': [for (final b in buildings) b.toJson()],
        'cam': [cam.dx, cam.dy],
        'zoom': zoom,
        'roads': [
          for (final r in net.roads.values)
            {
              'p': [for (final p in r.pts) ...[p.dx, p.dy]],
              'o': r.oneWay ? 1 : 0,
              't': r.type,
            }
        ],
        'signals': [
          for (final s in sim.signals.values)
            [graph.net.nodes[s.nodeId]!.pos.dx, graph.net.nodes[s.nodeId]!.pos.dy, s.green]
        ],
        'rbs': [
          for (final c in roundabouts) [c.dx, c.dy]
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
        final ver = m['v'];
        if (ver != 1 && ver != 2) continue;
        final s = m['seed'] as int;
        final bud = (m['budget'] as num).toDouble();
        final lvl = (m['level'] as num?)?.toInt() ?? 1;
        final bio = (m['biome'] as num?)?.toInt() ?? 0;
        final dif = (m['diff'] as num?)?.toInt() ?? 1;
        final sbx = (m['sbx'] as num?)?.toInt() == 1;
        final savedB = <Building>[];
        var bid = 1;
        for (final e in (m['buildings'] as List? ?? const [])) {
          savedB.add(Building.fromJson(bid++, e as Map<String, dynamic>));
        }
        final c = (m['cam'] as List).map((e) => (e as num).toDouble()).toList();
        final z = (m['zoom'] as num).toDouble();
        final roads = <List<Offset>>[];
        final oneWays = <bool>[];
        final types = <int>[];
        for (final r in m['roads'] as List) {
          final raw = r is Map ? r['p'] : r;
          final f = (raw as List).map((e) => (e as num).toDouble()).toList();
          if (f.length < 4 || f.length.isOdd) throw const FormatException('road');
          roads.add([for (var i = 0; i < f.length; i += 2) Offset(f[i], f[i + 1])]);
          oneWays.add(r is Map && r['o'] == 1);
          types.add(r is Map ? ((r['t'] as num?)?.toInt() ?? 0) : 0);
        }
        final sigs = <List<double>>[
          for (final e in (m['signals'] as List? ?? const []))
            [for (final x in e as List) (x as num).toDouble()]
        ];
        final rbs = <List<double>>[
          for (final e in (m['rbs'] as List? ?? const []))
            [for (final x in e as List) (x as num).toDouble()]
        ];
        await newMap(s, biome: bio, difficulty: dif, sandbox: sbx);
        for (var i = 0; i < roads.length; i++) {
          net.addRoadPts(roads[i], oneWay: oneWays[i], type: types[i]);
        }
        for (final r in rbs) {
          roundabouts.add(Offset(r[0], r[1]));
        }
        _onNetworkChanged();
        for (final sg in sigs) {
          final nd = net.nodeNear(Offset(sg[0], sg[1]), 2.0);
          if (nd != null) sim.addSignal(nd.id, sg[2]);
        }
        if (savedB.isNotEmpty) {
          buildings
            ..clear()
            ..addAll(savedB);
          _nextBuildingId = savedB.length + 1;
        }
        level = lvl;
        tutorial = false;
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

  Offset _rot(Offset v, double a) {
    final c = cos(a), s = sin(a);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  Offset toWorld(Offset s) =>
      cam + _rot(Offset((s.dx - size.x / 2) / zoom, (s.dy - size.y / 2) / zoom), -rot);

  /// Dunyo nuqtasi w ekrandagi s joyda qolishi uchun kamerani moslaydi.
  void _anchor(Offset w, Offset s) {
    cam = w - _rot(Offset((s.dx - size.x / 2) / zoom, (s.dy - size.y / 2) / zoom), -rot);
  }

  /// Dunyo nuqtasi -> ekran (render bilan bir xil: translate, scale, rotate, translate).
  Offset worldToScreen(Offset w) =>
      Offset(size.x / 2, size.y / 2) + _rot(w - cam, rot) * zoom;

  String debugText() {
    final t = _lastTouch;
    if (t == null) return "DEBUG: ekranga tegib ko'ring";
    final w = toWorld(t);
    final back = worldToScreen(w);
    final g = lastGlobal;
    String f(double v, [int d = 1]) => v.toStringAsFixed(d);
    return "touch (${f(t.dx)}, ${f(t.dy)}) -> world (${f(w.dx)}, ${f(w.dy)}) -> back (${f(back.dx)}, ${f(back.dy)})  d=${f((back - t).distance, 3)}\n"
        "global-local d=${g == null ? '-' : f((g - t).distance)} | game ${f(size.x, 0)}x${f(size.y, 0)} widget ${f(widgetSize.width, 0)}x${f(widgetSize.height, 0)} | dpr ${f(dpr, 2)}\n"
        "cam (${cam.dx.round()}, ${cam.dy.round()}) zoom ${f(zoom, 2)} rot ${f(rot, 2)}";
  }

  void toggleEnv() {
    showEnv = !showEnv;
    hud.value++;
  }

  void toggleDebug() {
    debug = !debug;
    hud.value++;
  }

  void resetRotation() {
    rot = 0;
    hud.value++;
  }

  void _clampCam() {
    cam = Offset(
      cam.dx.clamp(0.0, Terrain.worldSize).toDouble(),
      cam.dy.clamp(0.0, Terrain.worldSize).toDouble(),
    );
  }

  void wheel(Offset pos, double dy) {
    final before = toWorld(pos);
    zoom = (zoom * exp(-dy * 0.0015)).clamp(minZoom, maxZoom).toDouble();
    _anchor(before, pos);
    _clampCam();
  }

  void _initPinch() {
    final p = _ptrs.values.take(2).toList();
    _lastMid = (p[0] + p[1]) / 2;
    _lastDist = (p[0] - p[1]).distance;
    _lastAng = atan2(p[1].dy - p[0].dy, p[1].dx - p[0].dx);
    _twist = 0;
    _rotating = false;
  }

  void _pinch() {
    final p = _ptrs.values.take(2).toList();
    final mid = (p[0] + p[1]) / 2;
    final dist = (p[0] - p[1]).distance;
    final ang = atan2(p[1].dy - p[0].dy, p[1].dx - p[0].dx);
    if (_lastDist > 0 && dist > 0) {
      final before = toWorld(_lastMid);
      zoom = (zoom * dist / _lastDist).clamp(minZoom, maxZoom).toDouble();
      var da = ang - _lastAng;
      while (da > pi) {
        da -= 2 * pi;
      }
      while (da < -pi) {
        da += 2 * pi;
      }
      _twist += da;
      if (!_rotating && _twist.abs() > 0.15) _rotating = true; // tasodifiy burilishdan himoya
      if (_rotating && dist > 60) rot += da;
      _anchor(before, mid);
    }
    _lastMid = mid;
    _lastDist = dist;
    _lastAng = ang;
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
    final n = net.nodeNear(w, 40 / zoom);
    if (n != null) return n.pos;
    // binoga yaqinlashsa, avtomatik uning old tomoniga tushadi
    Building? bb;
    var bdist = double.infinity;
    // radius ekran pikselida (34 px): dunyo birligida emas, shuning uchun zoom'da barmoqdan uzoqqa sakramaydi
    final pad = min(120.0, max(6.0, 34 / zoom));
    for (final b in buildings) {
      if (!b.containsPoint(w, pad)) continue;
      final d = (b.pos - w).distance;
      if (d < bdist) {
        bdist = d;
        bb = b;
      }
    }
    if (bb != null) return bb.frontPoint;
    final h = net.nearestRoadPoint(w, 28 / zoom);
    return h?.point ?? w;
  }

  void pointerDown(int id, Offset pos) {
    if (loading) return;
    _ptrs[id] = pos;
    if (_ptrs.length >= 2) {
      _multi = true;
      _dragScreen = null;
      if (stage == 1) stage = 0;
      if (stage == 3) stage = 2;
      _initPinch();
      _notify();
      return;
    }
    _multi = false;
    _downPos = pos;
    _dragScreen = pos;
    _lastTouch = pos;
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
    _dragScreen = pos;
    _lastTouch = pos;
    switch (tool) {
      case Tool.pan:
        cam -= _rot((pos - prev) / zoom, -rot);
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
      case Tool.signal:
      case Tool.roundabout:
      case Tool.erase:
      case Tool.building:
      case Tool.inspect:
        break;
    }
    _notify();
  }

  void pointerUp(int id) {
    final pos = _ptrs.remove(id);
    if (pos == null) return;
    _dragScreen = null;
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
      case Tool.signal:
        if (!_moved) _tapSignal(toWorld(pos));
        break;
      case Tool.roundabout:
        if (!_moved) _tapRoundabout(toWorld(pos));
        break;
      case Tool.building:
        if (!_moved) _tapBuilding(toWorld(pos));
        break;
      case Tool.inspect:
        if (!_moved) _tapInspect(toWorld(pos));
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
    var loose = false;
    for (final e in [p.a, p.b]) {
      final joined = net.nodeNear(e, 14) != null || net.nearestRoadPoint(e, 12) != null;
      final atBuilding = buildings.any((b) => (b.frontPoint - e).distance < 3);
      if (!joined && !atBuilding && net.nearestRoadPoint(e, 45) != null) loose = true;
    }
    net.connectRoad(p.pts, type: roadType);
    budget -= p.cost;
    _onNetworkChanged();
    if (loose) flashMsg("Diqqat: yo'l uchi yaqin yo'lga ulanmadi. Uchini yo'lga yaqinlashtiring");
  }

  // -------------------------------------------------------------- yo'l rejasi

  void cycleRoadType() {
    roadType = 1 - roadType;
    _notify();
  }

  void cycleBuildType() {
    buildType = (buildType + 1) % 3;
    hud.value++;
  }

  void cycleDemand() {
    const opts = [0.5, 1.0, 2.0, 4.0];
    final i = opts.indexOf(demand);
    demand = opts[(i + 1) % opts.length];
    sim.demandScale = const [0.7, 1.0, 1.4][difficulty] * demand;
    hud.value++;
  }

  void _tapBuilding(Offset w) {
    final size = const [Size(34, 26), Size(52, 34), Size(70, 46)][buildType];
    final r = size.longestSide / 2 + 8;
    if (!terrain.isBuildableAt(w) ||
        !terrain.isBuildableAt(w + Offset(r, 0)) ||
        !terrain.isBuildableAt(w + Offset(-r, 0)) ||
        !terrain.isBuildableAt(w + Offset(0, r)) ||
        !terrain.isBuildableAt(w + Offset(0, -r))) {
      flashMsg("Bu yerga bino qurib bo'lmaydi");
      return;
    }
    if (buildings.any((b) => (b.pos - w).distance < 90) || net.nearestRoadPoint(w, r + 10) != null) {
      flashMsg("Joy band yoki yo'l juda yaqin");
      return;
    }
    buildings.add(Building(
      id: _nextBuildingId++,
      type: BuildingType.values[buildType],
      pos: w,
      angle: 0,
      size: size,
      roof: [_houseRoofs[0], _shopRoofs[0], _factoryRoofs[0]][buildType],
    ));
    _onNetworkChanged();
  }

  /// Mashina, chorraha yoki yo'l haqida ma'lumot (haqiqiy simulyatsiya ma'lumotlari).
  void _tapInspect(Offset w) {
    selected = null;
    Vehicle? bv;
    var bd = 14 / zoom + 10;
    for (final v in sim.vehicles) {
      final d = (v.track.pointAt(v.s) - w).distance;
      if (d < bd) {
        bd = d;
        bv = v;
      }
    }
    if (bv != null) {
      selected = bv;
      flashMsg("Mashina #${bv.id}: ${(bv.v * 1.8).round()} km/s, safar ${(sim.time - bv.born).round()} s, manzil: bino #${bv.destB}");
      return;
    }
    for (final b in buildings) {
      if (!b.containsPoint(w, 4)) continue;
      final linked = graph.access.containsKey(b.id) ? 'bor' : "yo'q";
      switch (b.type) {
        case BuildingType.house:
          flashMsg("Uy: ekologik yuk ${((envExpo[b.id] ?? 0) * 100).round()}%, yo'lga ulangan: $linked");
          break;
        case BuildingType.shop:
          flashMsg("Do'kon: yo'lga ulangan: $linked");
          break;
        case BuildingType.factory:
          flashMsg("Zavod: ifloslanish manbai (250 birlik atrofida), yo'lga ulangan: $linked");
          break;
      }
      return;
    }
    final node = net.nodeNear(w, 26 / zoom + 10);
    if (node != null && node.roads.length >= 3) {
      final sg = sim.signals[node.id];
      flashMsg("Chorraha: ${node.roads.length} yo'l, svetofor: ${sg != null ? 'bor (yashil ${sg.green.round()} s)' : 'yo\'q'}, kutayotgan mashinalar: ${sim.waitingAt(node.id)}");
      return;
    }
    final hit = net.nearestRoadPoint(w, 14 / zoom + 8);
    if (hit != null) {
      final rd = hit.road;
      final ls = graph.lanesOf(rd.id);
      final cnt = ls.fold<int>(0, (s, l) => s + l.vehicles.length);
      final limit = (ls.isEmpty ? 22.0 : ls.first.speedLimit) * 1.8;
      flashMsg("${rd.type == 1 ? 'Katta yo\'l' : 'Oddiy yo\'l'}: limit ${limit.round()} km/s, oqim ${(_roadRatio(rd) * 100).round()}%, mashinalar: $cnt, uzunligi ${rd.length.round()} m");
      return;
    }
    flashMsg("Bu yerda ma'lumot yo'q");
  }

  bool _tutDone(int i) {
    switch (i) {
      case 0:
        return (cam - _camStart).distance > 80 || (zoom - _zoomStart).abs() > 0.15 || rot.abs() > 0.2;
      case 1:
        return net.roads.isNotEmpty;
      case 2:
        return net.roads.isNotEmpty && noAccess == 0;
      case 3:
        return sim.completed >= 3;
      case 4:
        return _heatSeen;
      case 5:
        return sim.signals.isNotEmpty;
      case 6:
        return roundabouts.isNotEmpty;
      default:
        return level >= 2;
    }
  }

  void _tutTick() {
    if (!tutorial || loading) return;
    while (tutStep < tutorialTexts.length && _tutDone(tutStep)) {
      tutStep++;
    }
    if (tutStep >= tutorialTexts.length) {
      tutorial = false;
      flashMsg("O'rgatish tugadi. Omad!");
    }
  }

  void skipTutorial() {
    tutorial = false;
    hud.value++;
  }

  void toggleCharts() {
    showCharts = !showCharts;
    hud.value++;
  }

  /// Eng og'ir tirbandlik joyi: ko'p mashina va past oqim tezligi.
  Road? worstRoad() {
    Road? best;
    var bestScore = 0.0;
    for (final r in net.roads.values) {
      final cnt = graph.lanesOf(r.id).fold<int>(0, (s, l) => s + l.vehicles.length);
      if (cnt < 4) continue;
      final score = cnt * (1 - _roadRatio(r));
      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return best;
  }

  void focusBottleneck() {
    final r = worstRoad();
    if (r == null) {
      flashMsg("Jiddiy tirbandlik topilmadi");
      return;
    }
    cam = r.pts[r.pts.length ~/ 2];
    zoom = 1.6;
    heat = true;
    _clampCam();
    final cnt = graph.lanesOf(r.id).fold<int>(0, (s, l) => s + l.vehicles.length);
    flashMsg("Eng og'ir joy: $cnt mashina, oqim ${(_roadRatio(r) * 100).round()}%");
  }

  void flashMsg(String m) {
    flash = m;
    _flashT = 2.5;
    hud.value++;
  }

  void toggleHeat() {
    heat = !heat;
    if (heat) _heatSeen = true;
    hud.value++;
  }

  void _tapSignal(Offset w) {
    final n = net.nodeNear(w, 26 / zoom + 10);
    if (n == null || n.roads.length < 3) {
      flashMsg("Chorraha ustiga bosing (kamida 3 yo'l)");
      return;
    }
    flashMsg(sim.cycleSignal(n.id));
  }

  void _tapRoundabout(Offset w) {
    final n = net.nodeNear(w, 26 / zoom + 10);
    if (n == null || n.roads.length < 3) {
      flashMsg("Chorraha ustiga bosing (kamida 3 yo'l)");
      return;
    }
    final center = n.pos;
    var spent = 0.0;
    final err = net.buildRoundabout(
      n.id,
      roundaboutRadius,
      (p) => terrain.isWaterAt(p) || buildings.any((b) => (b.pos - p).distance < b.radius),
      budget,
      (d) => spent += d,
    );
    if (err != null) {
      flashMsg(err);
      return;
    }
    budget -= spent;
    roundabouts.add(center);
    _onNetworkChanged();
    flashMsg("Aylana chorraha qurildi (${spent.round()})");
  }

  bool _tooSharp(Offset a, Offset b, Offset c) {
    final va = a - c, vb = b - c;
    final la = va.distance, lb = vb.distance;
    if (la < 1 || lb < 1) return true;
    final cosA = ((va.dx * vb.dx + va.dy * vb.dy) / (la * lb)).clamp(-1.0, 1.0).toDouble();
    return acos(cosA) < 0.9; // ~52 daraja
  }

  /// Yo'l markaz chizig'i (yarim kenglik bilan) bino maydoniga tegadimi: haqiqiy geometriya,
  /// har 4 birlikda tekshiriladi (oraliqdagi burchakni o'tkazib yubormaydi).
  bool _hitsBuilding(List<Offset> pts) {
    final pad = roadType == 1 ? 13.0 : 6.5;
    for (final bd in buildings) {
      for (var i = 0; i < pts.length; i++) {
        if (bd.containsPoint(pts[i], pad)) return true;
        if (i == 0) continue;
        final d = (pts[i] - pts[i - 1]).distance;
        final n = (d / 4).ceil();
        for (var k = 1; k < n; k++) {
          if (bd.containsPoint(Offset.lerp(pts[i - 1], pts[i], k / n)!, pad)) return true;
        }
      }
    }
    return false;
  }

  RoadPlan _buildPlan(Offset a, Offset b, Offset? c) {
    final pts = RoadNetwork.sample(a, b, c);
    final len = RoadNetwork.polyLength(pts);
    final cost = len * RoadNetwork.costPerUnit * RoadNetwork.costFactor(roadType);
    String? err;
    if (len < minRoadLength) {
      err = "Juda qisqa";
    } else if (c != null && _tooSharp(a, b, c)) {
      err = "Burchak juda keskin";
    } else if (pts.any(terrain.isWaterAt)) {
      err = "Suv ustiga yo'l qurib bo'lmaydi";
    } else if (_hitsBuilding(pts)) {
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
    final ds = _dragScreen;
    if (ds != null && (stage == 1 || stage == 3)) {
      // chizayotganda barmoq ekran chetiga yetsa, xarita o'zi suriladi
      const side = 60.0, top = 160.0, bottom = 240.0;
      var vx = 0.0, vy = 0.0;
      if (ds.dx < side) vx = -(side - ds.dx) / side;
      if (ds.dx > size.x - side) vx = (ds.dx - (size.x - side)) / side;
      if (ds.dy < top) vy = -(top - ds.dy) / top;
      if (ds.dy > size.y - bottom) vy = (ds.dy - (size.y - bottom)) / bottom;
      if (vx != 0 || vy != 0) {
        cam += _rot(Offset(vx, vy) * (450 / zoom * dt), -rot);
        _clampCam();
        if (stage == 1) {
          _b = _snap(toWorld(ds));
        } else {
          _c = toWorld(ds);
        }
        _notify();
      }
    }
    if (_flashT > 0) {
      _flashT -= dt;
      if (_flashT <= 0) {
        flash = null;
        hud.value++;
      }
    }
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
    if (speed > 0) {
      _econTimer += dt;
      if (_econTimer >= 1.0) {
        _econTimer -= 1.0;
        _econTick();
      }
    }
    _hudTimer += dt;
    if (_hudTimer > 0.3) {
      _hudTimer = 0;
      _tutTick();
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
    canvas.rotate(rot);
    canvas.translate(-cam.dx, -cam.dy);

    _drawTerrain(canvas);
    _drawRoads(canvas);
    for (final b in buildings) {
      b.draw(canvas);
    }
    _drawEnv(canvas);
    _drawVehicles(canvas);
    _drawSignals(canvas);
    _drawSelected(canvas);
    _drawPreview(canvas);

    canvas.restore();
    _drawDebug(canvas);
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

  static const _heatPos = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
  static const _heatCol = [
    Color(0xFF7A1F1F), // juda og'ir tirbandlik
    Color(0xFFD0392B),
    Color(0xFFE8873A),
    Color(0xFFE9C94A),
    Color(0xFF8CCB5E),
    Color(0xFF4CAF50), // erkin harakat
  ];

  Color _heatColor(double r) {
    final x = r.clamp(0.0, 1.0).toDouble();
    for (var i = 1; i < _heatPos.length; i++) {
      if (x <= _heatPos[i]) {
        final t = (x - _heatPos[i - 1]) / (_heatPos[i] - _heatPos[i - 1]);
        return Color.lerp(_heatCol[i - 1], _heatCol[i], t)!;
      }
    }
    return _heatCol.last;
  }

  double _roadRatio(Road r) {
    var m = 1.0;
    for (final l in graph.lanesOf(r.id)) {
      if (l.ratio < m) m = l.ratio;
    }
    return m;
  }

  bool _ringExists(Offset c) => net.roads.values.any((r) =>
      r.oneWay &&
      r.pts.length > 2 &&
      ((r.pts[r.pts.length ~/ 2] - c).distance - roundaboutRadius).abs() < 3);

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
      ..strokeJoin = StrokeJoin.round;
    final center = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xCCD9B85A);

    final roads = net.roads.values.toList();
    final paths = [for (final r in roads) _pathOf(r.pts)];
    for (var i = 0; i < roads.length; i++) {
      border.strokeWidth = roads[i].type == 1 ? w * 2 + 5 : w + 5;
      canvas.drawPath(paths[i], border);
    }
    for (var i = 0; i < roads.length; i++) {
      fill.strokeWidth = roads[i].type == 1 ? w * 2 : w;
      fill.color = heat ? _heatColor(_roadRatio(roads[i])) : const Color(0xFFDADCDF);
      canvas.drawPath(paths[i], fill);
    }
    if (!heat) {
      for (var i = 0; i < roads.length; i++) {
        if (!roads[i].oneWay) canvas.drawPath(paths[i], center);
      }
      // ko'p polosali yo'llarda polosa chiziqlari
      final laneLine = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xAAFFFFFF);
      for (final rd in roads) {
        if (rd.type != 1) continue;
        for (final off in const [-7.0, 7.0]) {
          canvas.drawPath(_pathOf(LaneGraph.offsetPath(rd.pts, off)), laneLine);
        }
      }
      final junction = Paint()..color = const Color(0xFFDADCDF);
      for (final n in net.nodes.values) {
        if (n.roads.length >= 3) canvas.drawCircle(n.pos, w * 0.7, junction);
      }
    }
    roundabouts.removeWhere((c) => !_ringExists(c));
    for (final c in roundabouts) {
      canvas.drawCircle(c, roundaboutRadius - 8, Paint()..color = const Color(0xFFB5CC7E));
      canvas.drawCircle(
        c,
        roundaboutRadius - 8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF4A4D52),
      );
    }
  }

  /// Ekologiya qatlami: zavod atrofida ifloslanish, uylarda ekologik yuk (yashil -> qizil).
  void _drawEnv(Canvas canvas) {
    if (!showEnv) return;
    for (final f in buildings) {
      if (f.type != BuildingType.factory) continue;
      canvas.drawCircle(
        f.pos,
        250,
        Paint()..shader = Gradient.radial(f.pos, 250, const [Color(0x66A05A2C), Color(0x00A05A2C)]),
      );
    }
    final p = Paint();
    for (final b in buildings) {
      if (b.type != BuildingType.house) continue;
      final e = envExpo[b.id] ?? 0.0;
      p.color = Color.lerp(const Color(0xFF3DBE5A), const Color(0xFFD64541), e)!;
      canvas.drawCircle(b.pos, 9, p);
      canvas.drawCircle(
        b.pos,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFFFFFFF),
      );
    }
  }

  /// Debug: qizil = barmoq (ekran), sariq = dunyo nuqtasidan ekranga qaytarilgan joy. Mos tushishi kerak.
  void _drawDebug(Canvas canvas) {
    final t = _lastTouch;
    if (!debug || t == null) return;
    final back = worldToScreen(toWorld(t));
    canvas.drawCircle(
      t,
      18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFE02020),
    );
    canvas.drawLine(t - const Offset(26, 0), t + const Offset(26, 0), Paint()..color = const Color(0xFFE02020));
    canvas.drawLine(t - const Offset(0, 26), t + const Offset(0, 26), Paint()..color = const Color(0xFFE02020));
    canvas.drawCircle(
      back,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFF2D020),
    );
  }

  void _drawSelected(Canvas canvas) {
    final v = selected;
    if (v == null) return;
    if (v.removed) {
      selected = null;
      return;
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xCC1B8FA0);
    for (var i = v.routeIdx; i < v.route.length; i++) {
      final l = v.route[i];
      if (graph.lanes.containsKey(l.id)) canvas.drawPath(_pathOf(l.pts), paint);
    }
    canvas.drawCircle(
      v.track.pointAt(v.s),
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF1B8FA0),
    );
  }

  void _drawSignals(Canvas canvas) {
    final p = Paint();
    for (final s in sim.signals.values) {
      for (final l in s.incoming) {
        final st = s.stateOfLane(l.id);
        p.color = st == 0
            ? const Color(0xFF3DBE5A)
            : (st == 1 ? const Color(0xFFF2B233) : const Color(0xFFD64541));
        canvas.drawCircle(l.pointAt(l.length - 3), 3.2, p);
      }
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
    // barmoqning haqiqiy joyi (to'q sariq halqa) va avtomatik ulangan nuqta orasidagi chiziq
    final ds = _dragScreen;
    if (ds != null && (stage == 1 || stage == 3)) {
      final raw = toWorld(ds);
      final target = stage == 1 ? _b : _c;
      canvas.drawCircle(
        raw,
        10 / zoom,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / zoom
          ..color = const Color(0xFFF2A33A),
      );
      if (target != null && (target - raw).distance > 4 / zoom) {
        canvas.drawLine(
          raw,
          target,
          Paint()
            ..strokeWidth = 1.5 / zoom
            ..color = const Color(0x99F2A33A),
        );
      }
    }
  }
}
