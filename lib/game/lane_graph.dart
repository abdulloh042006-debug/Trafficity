import 'dart:math';
import 'dart:ui';

import 'building.dart';
import 'road_network.dart';
import 'traffic_model.dart';

class Access {
  Access(this.lane, this.s);
  final Lane lane;
  final double s;
}

class _Heap {
  final List<double> _f = [];
  final List<int> _id = [];

  bool get isEmpty => _f.isEmpty;

  void push(double f, int id) {
    _f.add(f);
    _id.add(id);
    var i = _f.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_f[p] <= _f[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  int pop() {
    final top = _id[0];
    final lastF = _f.removeLast();
    final lastId = _id.removeLast();
    if (_f.isNotEmpty) {
      _f[0] = lastF;
      _id[0] = lastId;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _f.length && _f[l] < _f[m]) m = l;
        if (r < _f.length && _f[r] < _f[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final tf = _f[a];
    _f[a] = _f[b];
    _f[b] = tf;
    final ti = _id[a];
    _id[a] = _id[b];
    _id[b] = ti;
  }
}

/// Yo'l tarmog'idan yo'nalishli polosalar grafini quradi.
/// O'ng tomonlama harakat: har bir yo'l bo'lagida ikkita polosa.
class LaneGraph {
  LaneGraph(this.net);

  final RoadNetwork net;
  final Map<int, Lane> lanes = {};
  final Map<int, List<Lane>> outgoing = {}; // tugun -> shu tugundan chiquvchi polosalar
  final Map<String, Connector> connectors = {};
  final Map<int, List<Connector>> connectorsFrom = {};
  final Map<int, Access> access = {}; // bino -> eng yaqin polosa nuqtasi

  static const double laneOffset = 3.5;

  /// O'zgarmagan yo'llarning polosalari saqlanadi (ustidagi mashinalar buzilmaydi).
  void rebuild() {
    final want = <int>{};
    for (final r in net.roads.values) {
      for (final fwd in [true, false]) {
        if (!fwd && r.oneWay) continue;
        final id = r.id * 2 + (fwd ? 0 : 1);
        want.add(id);
        if (!lanes.containsKey(id)) {
          final base = fwd ? r.pts : r.pts.reversed.toList();
          lanes[id] = Lane(
            _offset(base),
            id: id,
            roadId: r.id,
            fwd: fwd,
            fromNode: fwd ? r.a : r.b,
            toNode: fwd ? r.b : r.a,
            speedLimit: r.type == 1 ? 33.0 : 22.0,
          );
        }
      }
    }
    lanes.removeWhere((id, _) => !want.contains(id));
    connectors.removeWhere(
        (_, c) => !lanes.containsKey(c.from.id) || !lanes.containsKey(c.to.id));
    connectorsFrom.clear();
    for (final c in connectors.values) {
      connectorsFrom.putIfAbsent(c.from.id, () => []).add(c);
    }
    outgoing.clear();
    for (final l in lanes.values) {
      outgoing.putIfAbsent(l.fromNode, () => []).add(l);
    }
  }

  List<Offset> _offset(List<Offset> p) {
    final n = p.length;
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      Offset t;
      if (i == 0) {
        t = p[1] - p[0];
      } else if (i == n - 1) {
        t = p[n - 1] - p[n - 2];
      } else {
        t = p[i + 1] - p[i - 1];
      }
      final l = t.distance;
      t = l < 1e-9 ? const Offset(1, 0) : t / l;
      out.add(p[i] + Offset(-t.dy, t.dx) * laneOffset);
    }
    return out;
  }

  Connector connector(Lane a, Lane b) {
    final key = '${a.id}_${b.id}';
    return connectors.putIfAbsent(key, () {
      final pA = a.pts.last, pB = b.pts.first;
      final dA = a.dirAt(a.length), dB = b.dirAt(0);
      final node = net.nodes[a.toNode]!.pos;
      final dot = (dA.dx * dB.dx + dA.dy * dB.dy).clamp(-1.0, 1.0).toDouble();
      final ang = acos(dot);
      var ctrl = node;
      if (dot < -0.7) ctrl = node + dA * 10; // U-burilish
      final n = (pA - pB).distance < 0.5 ? 1 : 8;
      final pts = <Offset>[];
      if (n == 1) {
        pts..add(pA)..add(pB);
      } else {
        for (var i = 0; i <= n; i++) {
          final t = i / n, u = 1 - t;
          pts.add(Offset(
            u * u * pA.dx + 2 * u * t * ctrl.dx + t * t * pB.dx,
            u * u * pA.dy + 2 * u * t * ctrl.dy + t * t * pB.dy,
          ));
        }
      }
      final c = Connector(
        pts,
        from: a,
        to: b,
        nodeId: a.toNode,
        vmax: a.speedLimit * (1 - 0.75 * ang / pi),
      );
      connectorsFrom.putIfAbsent(a.id, () => []).add(c);
      return c;
    });
  }

  /// Har bir bino uchun eng yaqin polosa nuqtasini topadi (yo'l kirish joyi).
  void computeAccess(List<Building> buildings) {
    access.clear();
    for (final b in buildings) {
      Lane? best;
      var bestD = 100.0;
      var bestS = 0.0;
      for (final l in lanes.values) {
        if (l.length < 50) continue;
        for (var i = 1; i < l.pts.length; i++) {
          final q = closestOnSegment(b.pos, l.pts[i - 1], l.pts[i]);
          final d = (q - b.pos).distance;
          if (d < bestD) {
            bestD = d;
            best = l;
            bestS = l.cum[i - 1] + (q - l.pts[i - 1]).distance;
          }
        }
      }
      if (best != null) {
        access[b.id] = Access(best, bestS.clamp(30.0, best.length - 14).toDouble());
      }
    }
  }

  // ------------------------------------------------------------ marshrut

  Iterable<Lane> _successors(Lane from) sync* {
    final out = outgoing[from.toNode];
    if (out == null) return;
    final deg = net.nodes[from.toNode]?.roads.length ?? 0;
    for (final s in out) {
      if (s.id == from.oppositeId && deg > 1) continue; // U-burilish faqat boshi berk yo'lda
      yield s;
    }
  }

  double _turn(Lane from, Lane to) {
    final a = from.dirAt(from.length), b = to.dirAt(0);
    final dot = (a.dx * b.dx + a.dy * b.dy).clamp(-1.0, 1.0).toDouble();
    return 0.5 + acos(dot) * 1.2;
  }

  /// A*: generalized cost = yurish vaqti + burilish jarimasi + navbat (tirbandlik) taxmini.
  List<Lane>? findRoute(Lane start, double startS, Lane goal, double goalS) {
    if (!lanes.containsKey(start.id) || !lanes.containsKey(goal.id)) return null;
    if (start.id == goal.id && goalS > startS + 8) return [start];

    final g = <int, double>{};
    final prev = <int, int>{};
    final closed = <int>{};
    final heap = _Heap();
    final goalPt = goal.pointAt(goalS);
    double h(Lane l) => (l.pts.last - goalPt).distance / 33.0;

    void expand(Lane from, double baseG, int fromKey) {
      for (final s in _successors(from)) {
        final cost = baseG + s.length / s.speedLimit + _turn(from, s) + s.vehicles.length * 0.3;
        if (cost < (g[s.id] ?? double.infinity)) {
          g[s.id] = cost;
          prev[s.id] = fromKey;
          heap.push(cost + h(s), s.id);
        }
      }
    }

    expand(start, (start.length - startS) / start.speedLimit, -1);
    var iter = 0;
    while (!heap.isEmpty && iter++ < 20000) {
      final id = heap.pop();
      if (!closed.add(id)) continue;
      if (id == goal.id) {
        final path = <Lane>[];
        var cur = id;
        while (cur != -1) {
          path.add(lanes[cur]!);
          cur = prev[cur]!;
        }
        path.add(start);
        return path.reversed.toList();
      }
      expand(lanes[id]!, g[id]!, id);
    }
    return null;
  }
}
