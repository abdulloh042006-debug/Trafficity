import 'dart:math';
import 'dart:ui';

import 'building.dart';
import 'lane_graph.dart';
import 'road_network.dart' show closestOnSegment;
import 'signal.dart';
import 'traffic_model.dart';

class Trip {
  Trip(this.originB, this.destB, this.isReturn, this.truck);
  final int originB, destB;
  final bool isReturn, truck;
}

class _Nx {
  _Nx(this.track, this.ri);
  final Track track;
  final int ri;
}

/// Mikroskopik harakat: har bir mashina mustaqil agent.
/// Bo'ylama harakat: Intelligent Driver Model (IDM).
/// Chorrahalar: burilishlar o'rtasidagi geometrik to'qnashuv asosida ruxsat berish.
class TrafficSim {
  TrafficSim(this.graph, this.buildings, int seed) : rnd = Random(seed);

  final LaneGraph graph;
  final List<Building> buildings;
  final Random rnd;
  final List<Vehicle> vehicles = [];

  double time = 0;
  int _nextId = 1;
  int completed = 0;
  int failed = 0; // marshrut topilmadi
  int lost = 0; // tahrir tufayli yo'qolgan
  int served = 0; // xizmat ko'rsatilgan mijozlar
  int unserved = 0; // tovar yo'qligi sababli xizmatsiz qolganlar
  int delivered = 0; // yetkazilgan yuklar
  double avgTrip = 0;
  int maxVehicles = 250;
  double demandScale = 1.0;

  /// Avariyalar: keskin tormoz kerak bo'lgan xavfli holatda [accidentChance] ehtimol bilan yuz beradi; avariyadagi
  /// mashinalar [accidentClearTime] soniya yo'lni to'sadi, keyin olib ketiladi ([towed]).
  bool accidentsEnabled = true;
  double accidentChance = 0.06;
  static const double accidentClearTime = 30;
  int accidents = 0;
  int towed = 0;
  final List<Accident> accidentLog = []; // faol (hali tozalanmagan) avariyalar

  /// Boshqa polosa/yo'ldagi mashinaga qarab tormozlash (ustma-ust tushmaslik uchun).
  bool crossAvoidance = true;

  final Map<int, List<Vehicle>> _grid = {};
  static const double _cell = 24;

  final Map<int, Signal> signals = {};
  double _sanT = 0;
  double _statAcc = 0;
  final Map<int, double> _accum = {};
  final Map<int, List<Trip>> _pending = {};
  final Map<int, List<Vehicle>> _holders = {};
  final Map<int, Set<Vehicle>> _waiters = {};

  static const double _s0 = 4.0; // minimal masofa
  static const double _headway = 1.2; // soniya
  static const double _bMax = 20.0;
  static const List<Color> _carColors = [
    Color(0xFF5B8DD6),
    Color(0xFFC9694F),
    Color(0xFF7FA66B),
    Color(0xFFD9A441),
    Color(0xFF8E6BBF),
    Color(0xFF3FA7A0),
    Color(0xFFE07BA0),
    Color(0xFF55585E),
  ];

  // ------------------------------------------------------------- tarmoq o'zgarishi

  void onGraphChanged() {
    for (final v in List<Vehicle>.of(vehicles)) {
      final t = v.track;
      var dead = false;
      if (t is Lane) {
        dead = !graph.lanes.containsKey(t.id);
      } else if (t is Connector) {
        dead = !graph.lanes.containsKey(t.from.id) || !graph.lanes.containsKey(t.to.id);
      }
      final hc = v.holdConn;
      if (hc != null && (!graph.lanes.containsKey(hc.from.id) || !graph.lanes.containsKey(hc.to.id))) {
        dead = true;
      }
      if (dead) {
        if (!_relocate(v)) {
          _remove(v);
          lost++;
        }
      } else {
        v.needsReroute = true;
      }
    }
    vehicles.removeWhere((v) => v.removed);
    _refreshSignals();
  }

  /// Yo'l bo'linganda mashinani xuddi shu joydagi yangi polosaga ko'chiradi (yo'qolib ketmasin).
  bool _relocate(Vehicle v) {
    final pos = v.track.pointAt(v.s);
    final dir = v.track.dirAt(v.s);
    Lane? best;
    var bestD = 9.0;
    var bestS = 0.0;
    // avval yaqin polosa; topilmasa chorraha ichida (kesilgan polosalar oralig'ida) kengroq qidiradi
    for (final radius in const [9.0, 26.0]) {
      bestD = radius;
      for (final l in graph.lanes.values) {
        for (var i = 1; i < l.pts.length; i++) {
          final a = l.pts[i - 1], b = l.pts[i];
          final q = closestOnSegment(pos, a, b);
          final d = (q - pos).distance;
          if (d >= bestD) continue;
          final sd = b - a;
          final len = sd.distance;
          if (len < 1e-6) continue;
          if ((sd.dx * dir.dx + sd.dy * dir.dy) / len < 0.7) continue;
          bestD = d;
          best = l;
          bestS = l.cum[i - 1] + (q - a).distance;
        }
      }
      if (best != null) break;
    }
    if (best == null) return false;
    _release(v);
    final pc = v.pendingConn;
    if (pc != null) _waiters[pc.nodeId]?.remove(v);
    v.pendingConn = null;
    v.track = best;
    v.lat = 0;
    v.s = bestS;
    v.route = [best];
    v.routeIdx = 0;
    v.needsReroute = true;
    best.vehicles.add(v);
    return true;
  }

  // ------------------------------------------------------------------ svetoforlar

  void _refreshSignals() {
    signals.removeWhere((id, _) => (graph.net.nodes[id]?.roads.length ?? 0) < 3);
    for (final s in signals.values) {
      s.rebuild([
        for (final l in graph.lanes.values)
          if (l.toNode == s.nodeId) l,
      ]);
    }
  }

  /// Svetofor qo'yadi, yashil vaqtini 12 -> 20 -> 30 s aylantiradi, so'ng olib tashlaydi.
  /// Adaptiv svetofor: faol faza bo'sh, boshqa fazada kutayotgan bo'lsa, yashilni (6 s dan keyin) erta tugatadi.
  void _adapt(Signal s) {
    if (s.phases.length < 2) return;
    final ap = s.activePhase;
    final local = s.t - ap * s.phaseLen;
    if (local < 6 || local >= s.green) return;
    bool busy(int phase) {
      for (final id in s.phases[phase]) {
        final l = graph.lanes[id];
        if (l == null) continue;
        for (final u in l.vehicles) {
          if (l.length - u.s < 45) return true;
        }
      }
      return false;
    }

    var others = false;
    for (var p = 0; p < s.phases.length; p++) {
      if (p != ap && busy(p)) others = true;
    }
    if (!busy(ap) && others) s.t = ap * s.phaseLen + s.green;
  }

  /// Svetofor: yashil 12 -> 20 -> 30 s -> adaptiv -> olib tashlash.
  String cycleSignal(int nodeId) {
    final s = signals[nodeId];
    if (s == null) {
      signals[nodeId] = Signal(nodeId);
      _refreshSignals();
      return "Svetofor qo'yildi: yashil 12 s";
    }
    if (s.adaptive) {
      signals.remove(nodeId);
      return "Svetofor olib tashlandi";
    }
    if (s.green < 15) {
      s.green = 20;
    } else if (s.green < 25) {
      s.green = 30;
    } else {
      s.adaptive = true;
      s.green = 25;
      s.t = 0;
      return "Adaptiv svetofor: navbatga qarab";
    }
    s.t = 0;
    return "Yashil vaqt: ${s.green.round()} s";
  }

  int waitingAt(int nodeId) => _waiters[nodeId]?.length ?? 0;

  void addSignal(int nodeId, double green, {bool adaptive = false}) {
    final s = Signal(nodeId)
      ..green = green
      ..adaptive = adaptive;
    signals[nodeId] = s;
    _refreshSignals();
  }

  void _updateRatios() {
    for (final l in graph.lanes.values) {
      var target = 1.0;
      if (l.vehicles.isNotEmpty) {
        var sum = 0.0;
        for (final v in l.vehicles) {
          sum += v.v;
        }
        target = min(1.0, sum / l.vehicles.length / l.speedLimit);
      }
      l.ratio += (target - l.ratio) * 0.15;
    }
  }

  // ------------------------------------------------------------------ qadam

  void step(double dt) {
    time += dt;
    _sanT += dt;
    if (_sanT >= 2) {
      _sanT = 0;
      _sanitize();
    }
    for (final s in signals.values) {
      if (s.adaptive) _adapt(s);
      s.tick(dt);
    }
    _statAcc += dt;
    if (_statAcc >= 0.5) {
      _statAcc = 0;
      _updateRatios();
    }
    _spawn(dt);
    for (final v in vehicles) {
      if (v.needsReroute && !v.crashed && v.track is Lane && v.holdConn == null) _reroute(v);
    }
    vehicles.removeWhere((v) => v.removed);
    _clearCrashes(dt);
    vehicles.removeWhere((v) => v.removed);
    _laneChanges(dt);
    _indexPoses();
    for (final v in vehicles) {
      _computeAccel(v, dt);
    }
    for (final v in List<Vehicle>.of(vehicles)) {
      _advance(v, dt);
    }
    vehicles.removeWhere((v) => v.removed);
    for (final l in graph.lanes.values) {
      _sort(l);
    }
    for (final c in graph.connectors.values) {
      _sort(c);
    }
  }

  void _sort(Track t) {
    final l = t.vehicles;
    for (var i = 1; i < l.length; i++) {
      final x = l[i];
      var j = i - 1;
      while (j >= 0 && l[j].s > x.s) {
        l[j + 1] = l[j];
        j--;
      }
      l[j + 1] = x;
    }
  }

  // ------------------------------------------------------------------ talab

  double _rate(BuildingType t) {
    switch (t) {
      case BuildingType.house:
        return 0.05;
      case BuildingType.shop:
        return 0.03;
      case BuildingType.factory:
        return 0.04;
    }
  }

  Trip? _newTrip(Building b) {
    final List<BuildingType> want;
    switch (b.type) {
      case BuildingType.house:
        want = [BuildingType.shop, BuildingType.factory]; // do'kon, ish
        break;
      case BuildingType.shop:
        want = [BuildingType.house];
        break;
      case BuildingType.factory:
        want = [BuildingType.shop, BuildingType.house];
        break;
    }
    final cands = buildings
        .where((o) => o.id != b.id && want.contains(o.type) && graph.access.containsKey(o.id))
        .toList();
    if (cands.isEmpty) return null;
    final truck = b.type == BuildingType.factory && rnd.nextDouble() < 0.7;
    return Trip(b.id, cands[rnd.nextInt(cands.length)].id, false, truck);
  }

  void _spawn(double dt) {
    for (final b in buildings) {
      if (!graph.access.containsKey(b.id)) continue;
      final queue = _pending.putIfAbsent(b.id, () => []);
      final acc = (_accum[b.id] ?? rnd.nextDouble()) + dt * _rate(b.type) * demandScale;
      if (acc >= 1 && queue.length < 3) {
        _accum[b.id] = acc - 1;
        final t = _newTrip(b);
        if (t != null) queue.add(t);
      } else {
        _accum[b.id] = min(acc, 1.0);
      }
      if (queue.isNotEmpty && vehicles.length < maxVehicles) {
        if (_trySpawn(b, queue.first)) queue.removeAt(0);
      }
    }
  }

  /// true: reja ko'rib chiqildi (mashina chiqdi yoki bekor qilindi), false: joy band, keyinroq.
  bool _trySpawn(Building b, Trip trip) {
    final oa = graph.access[b.id];
    final da = graph.access[trip.destB];
    if (oa == null || da == null) return true;
    final len = trip.truck ? 22.0 : 9.0;
    final lane = oa.lane;
    final s0 = max(oa.s, len + 2);
    for (final u in lane.vehicles) {
      if (u.s >= s0 - len - 8 && u.s - u.length <= s0 + 8) return false;
    }
    final route = graph.findRoute(lane, s0, da.lane, da.s, goals: da.goals);
    if (route == null) {
      failed++;
      return true;
    }
    final color = trip.truck
        ? (rnd.nextBool() ? const Color(0xFFEDEDED) : const Color(0xFFB0B4BA))
        : _carColors[rnd.nextInt(_carColors.length)];
    final v = Vehicle(
      id: _nextId++,
      type: trip.truck ? VType.truck : VType.car,
      track: lane,
      s: s0,
      route: route,
      originB: trip.originB,
      destB: trip.destB,
      destS: da.goals[route.last.id] ?? da.s,
      isReturn: trip.isReturn,
      born: time,
      color: color,
    )..v = 4.0;
    lane.vehicles.add(v);
    _sort(lane);
    vehicles.add(v);
    return true;
  }

  void _reroute(Vehicle v) {
    _clearWait(v); // eski kutish yozuvi yangi marshrutga xalaqit bermasin
    final lane = v.track as Lane;
    final ad = graph.access[v.destB];
    final route = ad == null ? null : graph.findRoute(lane, v.s, ad.lane, ad.s, goals: ad.goals);
    if (ad == null || route == null) {
      _remove(v);
      lost++;
      return;
    }
    v.route = route;
    v.routeIdx = 0;
    v.destS = ad.goals[route.last.id] ?? ad.s;
    v.needsReroute = false;
  }

  // ------------------------------------------------------- polosa almashtirish

  /// Ko'p polosali yo'lda sekin mashina ortida qolgan mashina qo'shni polosaga o'tadi (quvib o'tish):
  /// maqsad polosada old va orqa masofa xavfsiz va foyda bor bo'lsa. Ko'ndalang siljish silliq (lat).
  void _laneChanges(double dt) {
    final decay = exp(-3.0 * dt);
    for (final v in vehicles) {
      v.lat *= decay;
      v.lcCool -= dt;
      final tr = v.track;
      if (tr is! Lane || tr.laneCount < 2 || v.lcCool > 0 || v.removed || v.crashed) continue;
      if (v.holdConn != null || v.needsReroute) continue;
      if (v.s < 25 || tr.length - v.s < 70) continue;
      if (v.routeIdx >= v.route.length - 1 && v.destS - v.s < 80) continue;
      final idx = tr.vehicles.indexOf(v);
      final lead = (idx >= 0 && idx + 1 < tr.vehicles.length) ? tr.vehicles[idx + 1] : null;
      final gapNow = lead == null ? 999.0 : lead.s - lead.length - v.s;
      final v0 = min(tr.speedLimit, v.vMaxSelf);
      final blocked = lead != null && gapNow < 40 && lead.v < min(v0 * 0.75, v.v - 1.5);
      v.lcCool = 1.0;
      if (!blocked) continue;
      for (final k in [tr.laneIdx - 1, tr.laneIdx + 1]) {
        if (k < 0 || k >= tr.laneCount) continue;
        final target = graph.lanes[Lane.idFor(tr.roadId, tr.fwd, k)];
        if (target == null || !_laneChangeOk(v, target, gapNow, lead)) continue;
        _clearWait(v);
        tr.vehicles.remove(v);
        target.vehicles.add(v);
        v.lat += (k - tr.laneIdx) * -7.0; // eski polosa markazidan yangisiga qarab silliq o'tadi
        v.track = target;
        v.route[v.routeIdx] = target;
        v.lcCool = 5.0;
        break;
      }
    }
  }

  bool _laneChangeOk(Vehicle v, Lane target, double gapNow, Vehicle? lead) {
    Vehicle? ahead;
    Vehicle? behind;
    for (final u in target.vehicles) {
      final overlap = u.s > v.s - v.length - 4 && u.s - u.length < v.s + 4;
      if (overlap) return false;
      if (u.s - u.length >= v.s + 4) {
        if (ahead == null || u.s < ahead.s) ahead = u;
      } else if (behind == null || u.s > behind.s) {
        behind = u;
      }
    }
    if (ahead != null) {
      final gap = ahead.s - ahead.length - v.s;
      if (gap < 14 + max(0.0, v.v - ahead.v)) return false;
    }
    if (behind != null) {
      final gap = v.s - v.length - behind.s;
      if (gap < 10 + max(0.0, behind.v - v.v) * 1.4) return false;
    }
    // foyda: maqsad polosada ancha ko'p joy yoki tezroq lider
    final gapT = ahead == null ? 999.0 : ahead.s - ahead.length - v.s;
    final fasterAhead = ahead == null || (lead != null && ahead.v > lead.v + 2);
    return gapT > gapNow + 12 || fasterAhead;
  }

  // -------------------------------------------------------------- tezlanish

  _Nx? _next(Track t, int ri, List<Lane> route) {
    if (ri + 1 >= route.length) return null;
    final nl = route[ri + 1];
    if (!graph.lanes.containsKey(nl.id)) return null;
    if (t is Lane) return _Nx(graph.connector(t, nl), ri);
    if (t is Connector) return _Nx(graph.lanes[nl.id]!, ri + 1);
    return null;
  }

  Vehicle? _rearmost(Track nt) {
    Vehicle? best;
    final Iterable<Track> cands = nt is Connector ? (graph.connectorsFrom[nt.from.id] ?? [nt]) : [nt];
    for (final c in cands) {
      if (c.vehicles.isEmpty) continue;
      final f = c.vehicles.first;
      if (best == null || f.s - f.length < best.s - best.length) best = f;
    }
    return best;
  }

  int _rank(Lane l) => graph.net.roads[l.roadId]?.type ?? 0;

  /// Svetofor yo'q chorrahada, kiruvchi yo'llar turli sinfda bo'lsa, past sinfdagisi "kichik yo'l":
  /// u to'liq to'xtab, ustun yo'lga yo'l beradi.
  bool _minorAt(Lane l, int node) {
    if (signals.containsKey(node)) return false;
    final inc = graph.incoming[node];
    if (inc == null) return false;
    var maxR = 0;
    for (final x in inc) {
      final rk = _rank(x);
      if (rk > maxR) maxR = rk;
    }
    return _rank(l) < maxR;
  }

  bool _tryGrant(Vehicle v, Connector c) {
    final node = c.nodeId;
    final sg = signals[node];
    if (sg != null && sg.stateOfLane(c.from.id) != 0) return false; // qizil/sariq
    if (_minorAt(c.from, node)) {
      // ustun yo'lda yaqinlashayotgan (45 birlik ichida) va bu burilish bilan to'qnashadigan mashina bo'lsa, kutadi
      for (final l in graph.incoming[node] ?? const <Lane>[]) {
        if (_rank(l) <= _rank(c.from)) continue;
        for (final u in l.vehicles) {
          if (l.length - u.s > max(45.0, u.v * 2.5)) continue; // yuqori tezlikda masofa ortadi
          final nx = _next(l, u.routeIdx, u.route);
          final nc = nx?.track;
          if (nc is Connector && c.conflicts(nc)) return false;
        }
      }
    }
    final to = c.to;
    if (to.vehicles.isNotEmpty) {
      final f = to.vehicles.first;
      if (f.s - f.length < v.length + 6) return false; // chiqish joyi yo'q
    }
    for (final h in _holders[node] ?? const <Vehicle>[]) {
      final hc = h.holdConn!;
      if (hc.from.id == c.from.id) continue; // bir polosadagi ketma-ket mashinalar
      if (c.conflicts(hc)) return false;
    }
    // adolat: uzoq kutgan mashinaga yo'l beriladi
    for (final w in sg != null ? const <Vehicle>{} : (_waiters[node] ?? const <Vehicle>{})) {
      // eskirgan kutuvchilar (o'chirilgan, boshqa polosaga o'tgan) adolat tekshiruvida qatnashmaydi
      if (identical(w, v) || w.removed || w.pendingConn == null || !identical(w.track, w.pendingConn!.from)) continue;
      if (w.wait > 3 && w.wait > v.wait && c.conflicts(w.pendingConn!)) return false;
    }
    _release(v); // qisqa polosadagi uzun mashina orqadagi chorrahani endi bo'shatadi
    v.holdConn = c;
    _holders.putIfAbsent(node, () => []).add(v);
    _waiters[node]?.remove(v);
    v.pendingConn = null;
    v.wait = 0;
    return true;
  }

  void _computeAccel(Vehicle v, double dt) {
    if (v.crashed) {
      v.a = 0;
      v.v = 0;
      return;
    }
    final tr = v.track;
    final route = v.route;
    var v0 = tr is Lane ? tr.speedLimit : (tr as Connector).vmax;
    v0 = min(v0, v.vMaxSelf);
    var gap = double.infinity;
    var vl = 0.0;

    final idx = tr.vehicles.indexOf(v);
    if (idx >= 0 && idx + 1 < tr.vehicles.length) {
      final l = tr.vehicles[idx + 1];
      gap = l.s - l.length - v.s;
      vl = l.v;
    } else {
      var dist = tr.length - v.s;
      Track cur = tr;
      var ri = v.routeIdx;
      for (var k = 0; k < 4 && dist < 160; k++) {
        final nx = _next(cur, ri, route);
        if (nx == null) break;
        final f = _rearmost(nx.track);
        if (f != null && !identical(f, v)) {
          gap = dist + f.s - f.length;
          vl = f.v;
          break;
        }
        dist += nx.track.length;
        cur = nx.track;
        ri = nx.ri;
      }
    }

    if (tr is Lane && v.routeIdx < route.length - 1) {
      final endDist = tr.length - v.s;
      final nextLane = route[v.routeIdx + 1];
      if (graph.lanes.containsKey(nextLane.id)) {
        final conn = graph.connector(tr, nextLane);
        // burilishdan oldin sekinlash
        v0 = min(v0, sqrt(conn.vmax * conn.vmax + 2 * v.bComf * max(0.0, endDist)));
        // Uzun mashina (yuk) o'zidan qisqa polosada orqa chorraha ruxsatini bo'shata olmaydi (orqasi polosaga 1 m kira
        // olmaydi); shunda ham keyingi chorrahaga ruxsat so'rashi kerak, aks holda abadiy qotadi (Amir Temur yonidagi yuk).
        if (_mayAsk(v, tr)) {
          final dreq = v.v * v.v / (2 * v.bComf) + 20;
          final stopDist = endDist - tr.stopBack; // o'tkir chorrahada to'xtash chizig'i oldinroq
          // kichik yo'l: stopline'da to'liq to'xtamaguncha ruxsat so'ralmaydi
          final ready = !_minorAt(tr, conn.nodeId) || (v.v < 0.6 && stopDist < 8);
          if (stopDist <= dreq && !(ready && _tryGrant(v, conn))) {
            if (v.v < 1.0 && stopDist < 15) v.wait += dt;
            if (v.wait > 25) {
              v.wait = 8; // uzoq qotib qolsa, tirbandlikni hisobga olib yangi marshrut qidiradi
              v.needsReroute = true;
            }
            v.pendingConn = conn;
            _waiters.putIfAbsent(conn.nodeId, () => {}).add(v);
            final sg = stopDist - 1.0;
            if (sg < gap) {
              gap = sg;
              vl = 0;
            }
          }
        }
      } else {
        final sg = endDist - 1.0;
        if (sg < gap) {
          gap = sg;
          vl = 0;
        }
      }
    }

    // boshqa polosa/yo'ldagi mashina old yo'lakda bo'lsa (o'tkir chorraha, ustma-ust yo'llar, avariya) - unga qarab tormoz
    final cross = crossAvoidance ? _crossLeader(v, dt) : null;
    if (cross != null && cross.$1 < gap) {
      gap = cross.$1;
      vl = cross.$2;
    }

    v0 = max(v0, 4.0);
    final free = 1 - pow(v.v / v0, 4);
    var inter = 0.0;
    if (gap.isFinite) {
      final dv = v.v - vl;
      final sStar = _s0 + max(0.0, v.v * _headway + v.v * dv / (2 * sqrt(v.aMax * v.bComf)));
      inter = pow(sStar / max(gap, 0.1), 2).toDouble();
    }
    v.a = (v.aMax * (free - inter)).clamp(-_bMax, v.aMax).toDouble();
  }

  // ---------------------------------------------------------------- harakat

  void _advance(Vehicle v, double dt) {
    if (v.removed || v.crashed) return;
    v.v = max(0.0, v.v + v.a * dt);
    v.s += v.v * dt;

    final tr = v.track;
    final idx = tr.vehicles.indexOf(v);
    if (idx >= 0 && idx + 1 < tr.vehicles.length) {
      final l = tr.vehicles[idx + 1];
      final maxS = l.s - l.length - 0.5;
      if (v.s > maxS) {
        v.s = max(maxS, v.s - v.v * dt);
        v.v = min(v.v, l.v);
      }
    }

    final t = v.track;
    if (t is Lane) {
      if (v.routeIdx == v.route.length - 1) {
        if (v.s >= v.destS) {
          _arrive(v);
          return;
        }
      } else if (v.s >= t.length) {
        final hc = v.holdConn;
        if (hc == null || hc.from.id != t.id) {
          v.s = t.length - 0.5;
          v.v = 0;
          return;
        }
        t.vehicles.remove(v);
        v.s -= t.length;
        v.track = hc;
        hc.vehicles.add(v);
      }
    }
    final c = v.track;
    if (c is Connector && v.s >= c.length) {
      final nl = graph.lanes[v.route[v.routeIdx + 1].id];
      if (nl == null) {
        _remove(v);
        lost++;
        return;
      }
      c.vehicles.remove(v);
      v.routeIdx++;
      v.s -= c.length;
      v.track = nl;
      nl.vehicles.add(v);
    }
    final hc = v.holdConn;
    final cur = v.track;
    if (hc != null && cur is Lane && cur.id == hc.to.id && v.s - v.length >= 1.0) {
      _release(v);
    }
  }

  /// Ruxsat so'rash mumkinmi: ruxsat yo'q, yoki faqat shu polosaga kirgan chorrahaning ruxsati bor va polosa
  /// mashinadan qisqa (orqa bamper uni hech qachon 1 m ga tark eta olmaydi).
  bool _mayAsk(Vehicle v, Lane lane) {
    final h = v.holdConn;
    return h == null || (h.to.id == lane.id && lane.length < v.length + 1.0);
  }

  // ------------------------------------------------------------- holat, to'qnashuvdan saqlanish, avariya

  /// Orqa bamper: haqiqiy yo'l bo'ylab orqaga (oldingi chorraha yoki polosaga o'tishi mumkin).
  Offset rearOf(Vehicle v) {
    var back = v.length;
    Track t = v.track;
    var s = v.s;
    var ri = v.routeIdx;
    for (var k = 0; k < 4; k++) {
      if (s >= back) return t.pointAt(s - back);
      back -= s;
      Track? prev;
      if (t is Connector) {
        prev = t.from;
      } else if (ri > 0 && ri < v.route.length) {
        prev = graph.connectors['${v.route[ri - 1].id}_${(t as Lane).id}'];
        ri -= 1;
      }
      if (prev == null) return t.pointAt(0) - t.dirAt(0) * back; // marshrut boshi: to'g'ri chiziq bo'ylab
      t = prev;
      s = prev.length;
    }
    return t.pointAt(max(0.0, s - back));
  }

  int _layerOf(Track t) => graph.net.roads[t is Lane ? t.roadId : (t as Connector).from.roadId]?.layer ?? 0;

  /// Har qadam boshida: mashinalarning holati va fazoviy indeks (boshqa polosalardagilarni tez topish uchun).
  void _indexPoses() {
    _grid.clear();
    for (final v in vehicles) {
      if (v.removed) continue;
      final f = v.track.pointAt(v.s), r = rearOf(v);
      var dx = f.dx - r.dx, dy = f.dy - r.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1e-6) {
        final d = v.track.dirAt(v.s);
        dx = d.dx;
        dy = d.dy;
      } else {
        dx /= len;
        dy /= len;
      }
      v
        ..fx = f.dx
        ..fy = f.dy
        ..ux = dx
        ..uy = dy
        ..cx = (f.dx + r.dx) / 2 - dy * v.lat
        ..cy = (f.dy + r.dy) / 2 + dx * v.lat
        ..layer = _layerOf(v.track);
      final ext = v.length / 2 + 1;
      final x0 = ((v.cx - ext) / _cell).floor(), x1 = ((v.cx + ext) / _cell).floor();
      final y0 = ((v.cy - ext) / _cell).floor(), y1 = ((v.cy + ext) / _cell).floor();
      for (var gy = y0; gy <= y1; gy++) {
        for (var gx = x0; gx <= x1; gx++) {
          _grid.putIfAbsent(gy * 100000 + gx, () => []).add(v);
        }
      }
    }
  }

  /// Old yo'lakda (o'z marshrutidan boshqa yo'lda) turgan mashina: (bamperdan masofa, uning yo'nalish bo'yicha tezligi).
  /// O'zaro ko'rishsa kichik id li o'tadi; 8 s kutgan mashina halqa bo'lmasligi uchun 3 s e'tiborsiz o'tadi.
  (double, double)? _crossLeader(Vehicle v, double dt) {
    final passing = v.crossPass > 0;
    if (passing) v.crossPass -= dt;
    if (v.riskCool > 0) v.riskCool -= dt;
    // halqani buzish paytida ham avariyadagi mashina e'tiborsiz qolmaydi
    final hit = _probe(v, wrecksOnly: passing);
    if (hit == null) {
      v.crossWait = 0;
      return null;
    }
    final o = hit.$3;
    if (!o.crashed && _probe(o, only: v) != null && o.id > v.id) {
      v.crossWait = 0;
      return null; // ikkalasi ham bir-birini ko'radi: kichik id li ustun
    }
    if (v.v < 0.5 && !o.crashed) {
      v.crossWait += dt;
      if (v.crossWait > 8) {
        v.crossWait = 0;
        v.crossPass = 3;
      }
    }
    final gap = hit.$1, vl = hit.$2;
    if (accidentsEnabled && v.riskCool <= 0 && !o.crashed) {
      final closing = v.v - vl;
      final need = closing <= 0 ? 0.0 : closing * closing / (2 * max(gap - 0.5, 0.3));
      if (need > 1.6 * v.bComf) {
        v.riskCool = 8;
        if (rnd.nextDouble() < accidentChance) _crash(v, o);
      }
    }
    return (gap, vl);
  }

  /// [v] ning old yo'lagidagi eng yaqin begona mashina: (masofa, tezlik proyeksiyasi, mashina). [only] berilsa faqat u.
  (double, double, Vehicle)? _probe(Vehicle v, {Vehicle? only, bool wrecksOnly = false}) {
    final reach = min(42.0, 5 + v.v * 1.3), half = v.width * 0.45;
    final ax = v.fx, ay = v.fy, ux = v.ux, uy = v.uy, nx = -uy, ny = ux;
    final bx = ax + ux * reach, by = ay + uy * reach;
    final x0 = ((min(ax, bx) - half) / _cell).floor(), x1 = ((max(ax, bx) + half) / _cell).floor();
    final y0 = ((min(ay, by) - half) / _cell).floor(), y1 = ((max(ay, by) + half) / _cell).floor();
    final tr = v.track;
    Track? next1, next2;
    if (tr is Lane && v.routeIdx + 1 < v.route.length) {
      next1 = graph.connectors['${tr.id}_${v.route[v.routeIdx + 1].id}'];
      next2 = v.route[v.routeIdx + 1];
    } else if (tr is Connector) {
      next1 = tr.to;
    }
    (double, double, Vehicle)? best;
    final seen = <Vehicle>{};
    for (var gy = y0; gy <= y1; gy++) {
      for (var gx = x0; gx <= x1; gx++) {
        for (final o in _grid[gy * 100000 + gx] ?? const <Vehicle>[]) {
          if (identical(o, v) || o.removed || !seen.add(o)) continue;
          if (only != null && !identical(o, only)) continue;
          if (wrecksOnly && !o.crashed) continue;
          if (o.layer != v.layer) continue;
          final ot = o.track;
          if (identical(ot, tr) || identical(ot, next1) || identical(ot, next2)) continue; // IDM o'zi ko'radi
          if (tr is Lane && ot is Lane && ot.roadId == tr.roadId) continue; // qo'shni polosa: polosa almashtirish
          // faqat bir yo'nalishdagi (qo'shilish, ustma-ust koridor) yoki avariyadagi mashina; kesishuvlarni chorraha
          // ruxsati boshqaradi (A/B: kesishuvlarni ham kutish o'tkazuvchanlikni 2 barobar kamaytirdi)
          if (!o.crashed && o.ux * ux + o.uy * uy < 0.6) continue;
          var tmin = double.infinity, tmax = -double.infinity, wmin = double.infinity, wmax = -double.infinity;
          final hl = o.length / 2, hw = o.width / 2;
          for (final sl in const [-1.0, 1.0]) {
            for (final sw in const [-1.0, 1.0]) {
              final px = o.cx + o.ux * hl * sl - o.uy * hw * sw - ax;
              final py = o.cy + o.uy * hl * sl + o.ux * hw * sw - ay;
              final t = px * ux + py * uy, w = px * nx + py * ny;
              tmin = min(tmin, t);
              tmax = max(tmax, t);
              wmin = min(wmin, w);
              wmax = max(wmax, w);
            }
          }
          if (tmax <= 0.2 || tmin >= reach || wmax < -half || wmin > half) continue;
          final gap = max(0.0, tmin);
          if (best == null || gap < best.$1) best = (gap, max(0.0, o.v * (o.ux * ux + o.uy * uy)), o);
        }
      }
    }
    return best;
  }

  void _crash(Vehicle a, Vehicle b) {
    for (final v in [a, b]) {
      v
        ..crashed = true
        ..crashT = accidentClearTime
        ..v = 0
        ..a = 0;
      _clearWait(v);
    }
    accidents++;
    accidentLog.add(Accident(Offset((a.fx + b.cx) / 2, (a.fy + b.cy) / 2), time, time + accidentClearTime, a.id, b.id));
  }

  /// Avariyadagi mashinalar vaqti tugagach olib ketiladi.
  void _clearCrashes(double dt) {
    for (final v in vehicles) {
      if (!v.crashed || v.removed) continue;
      v.crashT -= dt;
      if (v.crashT <= 0) {
        _remove(v);
        towed++;
      }
    }
    accidentLog.removeWhere((a) => a.until <= time);
  }

  void _release(Vehicle v) {
    final hc = v.holdConn;
    if (hc == null) return;
    _holders[hc.nodeId]?.remove(v);
    v.holdConn = null;
  }

  void _clearWait(Vehicle v) {
    final pc = v.pendingConn;
    if (pc != null) _waiters[pc.nodeId]?.remove(v);
    v.pendingConn = null;
  }

  /// Invariantlar: _holders faqat haqiqatan ruxsat ushlab turganlarni, _waiters faqat haqiqiy kutayotganlarni saqlaydi.
  void _sanitize() {
    for (final e in _holders.entries) {
      e.value.removeWhere((v) => v.removed || v.holdConn == null || v.holdConn!.nodeId != e.key);
    }
    for (final e in _waiters.entries) {
      e.value.removeWhere(
        (v) =>
            v.removed ||
            v.pendingConn == null ||
            (v.holdConn != null && !(v.track is Lane && _mayAsk(v, v.track as Lane))) ||
            v.pendingConn!.nodeId != e.key,
      );
    }
  }

  void _remove(Vehicle v) {
    v.removed = true;
    v.track.vehicles.remove(v);
    _release(v);
    final pc = v.pendingConn;
    if (pc != null) _waiters[pc.nodeId]?.remove(v);
  }

  Building? _bld(int id) {
    for (final b in buildings) {
      if (b.id == id) return b;
    }
    return null;
  }

  void _arrive(Vehicle v) {
    completed++;
    final dest = _bld(v.destB);
    if (dest != null && dest.type == BuildingType.shop && !v.isReturn) {
      if (v.type == VType.truck) {
        dest.stock = min(100.0, dest.stock + 12); // yuk yetib keldi
        delivered++;
      } else if (dest.stock >= 1) {
        dest.stock -= 1; // mijoz xizmat oldi
        served++;
      } else {
        unserved++; // tovar yo'q
      }
    }
    final tt = time - v.born;
    avgTrip = avgTrip == 0 ? tt : avgTrip * 0.9 + tt * 0.1;
    if (!v.isReturn) {
      final q = _pending.putIfAbsent(v.destB, () => []);
      if (q.length < 6) q.add(Trip(v.destB, v.originB, true, v.type == VType.truck));
    }
    _remove(v);
  }
}
