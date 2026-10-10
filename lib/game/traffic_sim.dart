import 'dart:math';
import 'dart:ui';

import 'building.dart';
import 'lane_graph.dart';
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
  double avgTrip = 0;
  int maxVehicles = 250;
  double demandScale = 1.0;

  final Map<int, Signal> signals = {};
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
      if (hc != null &&
          (!graph.lanes.containsKey(hc.from.id) || !graph.lanes.containsKey(hc.to.id))) {
        dead = true;
      }
      if (dead) {
        _remove(v);
        lost++;
      } else {
        v.needsReroute = true;
      }
    }
    vehicles.removeWhere((v) => v.removed);
    _refreshSignals();
  }

  // ------------------------------------------------------------------ svetoforlar

  void _refreshSignals() {
    signals.removeWhere((id, _) => (graph.net.nodes[id]?.roads.length ?? 0) < 3);
    for (final s in signals.values) {
      s.rebuild([for (final l in graph.lanes.values) if (l.toNode == s.nodeId) l]);
    }
  }

  /// Svetofor qo'yadi, yashil vaqtini 12 -> 20 -> 30 s aylantiradi, so'ng olib tashlaydi.
  String cycleSignal(int nodeId) {
    final s = signals[nodeId];
    if (s == null) {
      signals[nodeId] = Signal(nodeId);
      _refreshSignals();
      return "Svetofor qo'yildi: yashil 12 s";
    }
    if (s.green < 15) {
      s.green = 20;
    } else if (s.green < 25) {
      s.green = 30;
    } else {
      signals.remove(nodeId);
      return "Svetofor olib tashlandi";
    }
    s.t = 0;
    return "Yashil vaqt: ${s.green.round()} s";
  }

  int waitingAt(int nodeId) => _waiters[nodeId]?.length ?? 0;

  void addSignal(int nodeId, double green) {
    final s = Signal(nodeId)..green = green;
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
    for (final s in signals.values) {
      s.tick(dt);
    }
    _statAcc += dt;
    if (_statAcc >= 0.5) {
      _statAcc = 0;
      _updateRatios();
    }
    _spawn(dt);
    for (final v in vehicles) {
      if (v.needsReroute && v.track is Lane && v.holdConn == null) _reroute(v);
    }
    vehicles.removeWhere((v) => v.removed);
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
    final route = graph.findRoute(lane, s0, da.lane, da.s);
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
      destS: da.s,
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
    final lane = v.track as Lane;
    final ad = graph.access[v.destB];
    final route = ad == null ? null : graph.findRoute(lane, v.s, ad.lane, ad.s);
    if (ad == null || route == null) {
      _remove(v);
      lost++;
      return;
    }
    v.route = route;
    v.routeIdx = 0;
    v.destS = ad.s;
    v.needsReroute = false;
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
    final Iterable<Track> cands =
        nt is Connector ? (graph.connectorsFrom[nt.from.id] ?? [nt]) : [nt];
    for (final c in cands) {
      if (c.vehicles.isEmpty) continue;
      final f = c.vehicles.first;
      if (best == null || f.s - f.length < best.s - best.length) best = f;
    }
    return best;
  }

  bool _tryGrant(Vehicle v, Connector c) {
    final node = c.nodeId;
    final sg = signals[node];
    if (sg != null && sg.stateOfLane(c.from.id) != 0) return false; // qizil/sariq
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
      if (identical(w, v) || w.pendingConn == null) continue;
      if (w.wait > 3 && w.wait > v.wait && c.conflicts(w.pendingConn!)) return false;
    }
    v.holdConn = c;
    _holders.putIfAbsent(node, () => []).add(v);
    _waiters[node]?.remove(v);
    v.pendingConn = null;
    v.wait = 0;
    return true;
  }

  void _computeAccel(Vehicle v, double dt) {
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
        if (v.holdConn == null) {
          final dreq = v.v * v.v / (2 * v.bComf) + 20;
          if (endDist <= dreq && !_tryGrant(v, conn)) {
            if (v.v < 1.0 && endDist < 15) v.wait += dt;
            v.pendingConn = conn;
            _waiters.putIfAbsent(conn.nodeId, () => {}).add(v);
            final sg = endDist - 1.0;
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
    if (v.removed) return;
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

  void _release(Vehicle v) {
    final hc = v.holdConn;
    if (hc == null) return;
    _holders[hc.nodeId]?.remove(v);
    v.holdConn = null;
  }

  void _remove(Vehicle v) {
    v.removed = true;
    v.track.vehicles.remove(v);
    _release(v);
    final pc = v.pendingConn;
    if (pc != null) _waiters[pc.nodeId]?.remove(v);
  }

  void _arrive(Vehicle v) {
    completed++;
    final tt = time - v.born;
    avgTrip = avgTrip == 0 ? tt : avgTrip * 0.9 + tt * 0.1;
    if (!v.isReturn) {
      final q = _pending.putIfAbsent(v.destB, () => []);
      if (q.length < 6) q.add(Trip(v.destB, v.originB, true, v.type == VType.truck));
    }
    _remove(v);
  }
}
