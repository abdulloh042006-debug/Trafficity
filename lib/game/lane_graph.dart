import 'dart:math';
import 'dart:ui';

import 'building.dart';
import 'road_network.dart';
import 'traffic_model.dart';

class Access {
  Access(this.lane, this.s, [Map<int, double>? goals]) : goals = goals ?? {lane.id: s};

  final Lane lane; // eng yaqin polosa (mashina shu yerdan chiqadi)
  final double s;

  /// Binoga yetib borish mumkin bo'lgan polosalar: laneId -> s.
  /// Ikkala yo'nalish va barcha polosalar, shuning uchun mashina uchun qulay tomondan keladi.
  final Map<int, double> goals;
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
  final Map<int, List<Lane>> incoming = {}; // tugun -> shu tugunga kiruvchi polosalar
  final Map<String, Connector> connectors = {};
  final Map<int, List<Connector>> connectorsFrom = {};
  final Map<int, Access> access = {}; // bino -> eng yaqin polosa nuqtasi
  int routeCalls = 0; // marshrut hisoblari soni (ishlash diagnostikasi)

  static const double laneOffset = 3.5;

  /// Chorraha oldidagi to'xtash chizig'i tugun markazidan qancha orqada (chorraha o'lchamiga qarab).
  /// Tupikda (bitta yo'l) kesilmaydi.
  double _setback(int nodeId) {
    final n = net.nodes[nodeId];
    if (n == null || n.roads.length < 2) return 0;
    var half = 7.0;
    for (final rid in n.roads) {
      final r = net.roads[rid];
      if (r != null) half = max(half, 7.0 * (r.type + 1));
    }
    return half + 3;
  }

  /// Polosa chizig'idagi keskin burchaklarni (yo'l uchi boshqa yo'lga ulanganda qolgan qiyshiqlik, siniq
  /// yo'llar) kvadratik egri bilan yumaloqlaydi, shunda mashina nuqtada keskin burilmaydi.
  static List<Offset> smoothCorners(List<Offset> p, {double maxCut = 9.0, double minAngle = 0.25}) {
    if (p.length < 3) return p;
    final out = <Offset>[p.first];
    for (var i = 1; i < p.length - 1; i++) {
      final v = p[i];
      final d1 = (v - p[i - 1]).distance, d2 = (p[i + 1] - v).distance;
      if (d1 < 1e-6 || d2 < 1e-6) continue;
      final u1 = (v - p[i - 1]) / d1, u2 = (p[i + 1] - v) / d2;
      final cr = u1.dx * u2.dy - u1.dy * u2.dx;
      final dt = u1.dx * u2.dx + u1.dy * u2.dy;
      final th = atan2(cr.abs(), dt);
      final d = min(maxCut, 0.45 * min(d1, d2));
      if (th < minAngle || d < 1.0) {
        out.add(v);
        continue;
      }
      final a = v - u1 * d, b = v + u2 * d;
      final n = max(3, (th / 0.25).ceil());
      for (var k = 0; k <= n; k++) {
        final t = k / n, q = 1 - t;
        out.add(Offset(
          q * q * a.dx + 2 * q * t * v.dx + t * t * b.dx,
          q * q * a.dy + 2 * q * t * v.dy + t * t * b.dy,
        ));
      }
    }
    out.add(p.last);
    return out;
  }

  static double _pathLen(List<Offset> p) {
    var s = 0.0;
    for (var i = 1; i < p.length; i++) {
      s += (p[i] - p[i - 1]).distance;
    }
    return s;
  }

  /// Chiziqning boshidan [a] va oxiridan [b] uzunlikdagi qismini kesadi (juda qisqa bo'lsa kesmaydi).
  static List<Offset> trimPath(List<Offset> p, double a, double b) {
    if (a <= 1e-6 && b <= 1e-6) return p;
    final cum = <double>[0];
    for (var i = 1; i < p.length; i++) {
      cum.add(cum[i - 1] + (p[i] - p[i - 1]).distance);
    }
    final end = cum.last - b;
    if (end - a < 1.0) return p;
    Offset at(double d) {
      for (var i = 1; i < p.length; i++) {
        final seg = cum[i] - cum[i - 1];
        if (seg > 1e-9 && d <= cum[i]) return Offset.lerp(p[i - 1], p[i], (d - cum[i - 1]) / seg)!;
      }
      return p.last;
    }

    final out = <Offset>[at(a)];
    for (var i = 1; i < p.length - 1; i++) {
      if (cum[i] > a + 1e-6 && cum[i] < end - 1e-6) out.add(p[i]);
    }
    out.add(at(end));
    return out;
  }

  /// Polosa uchlarini chorraha oldida kesadi (qisqa yo'lda uzunlikning 25% idan oshmaydi).
  /// Geometriya o'zgargan bo'lsa true; polosadagi mashinalar o'z joyida qoladi.
  bool _applyTrim(Lane l) {
    final cap = 0.25 * l.fullLen;
    final sa = min(_setback(l.fromNode), cap), sb = min(_setback(l.toNode), cap);
    if ((l.trimA - sa).abs() < 0.01 && (l.trimB - sb).abs() < 0.01 && l.pts.isNotEmpty) return false;
    final shift = sa - l.trimA;
    l.setPts(trimPath(l.full, sa, sb));
    l.trimA = sa;
    l.trimB = sb;
    for (final v in l.vehicles) {
      v.s = (v.s - shift).clamp(0.0, l.length).toDouble();
    }
    return true;
  }

  /// O'zgarmagan yo'llarning polosalari saqlanadi (ustidagi mashinalar buzilmaydi).
  void rebuild() {
    final want = <int>{};
    final changed = <int>{};
    for (final r in net.roads.values) {
      for (final fwd in [true, false]) {
        if (!fwd && r.oneWay) continue;
        final count = r.type == 2 ? 3 : (r.type == 1 ? 2 : 1); // magistral 3, katta yo'l 2 polosa
        for (var k = 0; k < count; k++) {
          final id = Lane.idFor(r.id, fwd, k);
          want.add(id);
          final old = lanes[id];
          if (old == null) {
            final base = fwd ? r.pts : r.pts.reversed.toList();
            final full = smoothCorners(offsetPath(base, laneOffset + k * 7.0));
            final lane = Lane(
              full,
              id: id,
              roadId: r.id,
              fwd: fwd,
              fromNode: fwd ? r.a : r.b,
              toNode: fwd ? r.b : r.a,
              speedLimit: r.type == 2 ? 55.0 : (r.type == 1 ? 33.0 : 22.0),
              laneIdx: k,
              laneCount: count,
            )
              ..full = full
              ..fullLen = _pathLen(full);
            _applyTrim(lane);
            lanes[id] = lane;
          } else if (_applyTrim(old)) {
            changed.add(id); // tugun o'zgargan (masalan, tupikka yo'l ulandi): burilishlar qayta quriladi
          }
        }
      }
    }
    lanes.removeWhere((id, _) => !want.contains(id));
    if (changed.isNotEmpty) {
      for (final c in connectors.values) {
        if (changed.contains(c.from.id) || changed.contains(c.to.id)) {
          c.setPts(_turnPts(c.from, c.to));
          for (final v in c.vehicles) {
            v.s = min(v.s, c.length);
          }
        }
      }
    }
    connectors.removeWhere(
        (_, c) => !lanes.containsKey(c.from.id) || !lanes.containsKey(c.to.id));
    connectorsFrom.clear();
    for (final c in connectors.values) {
      connectorsFrom.putIfAbsent(c.from.id, () => []).add(c);
    }
    outgoing.clear();
    incoming.clear();
    for (final l in lanes.values) {
      outgoing.putIfAbsent(l.fromNode, () => []).add(l);
      incoming.putIfAbsent(l.toNode, () => []).add(l);
    }
  }

  static List<Offset> offsetPath(List<Offset> p, double off) {
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
      out.add(p[i] + Offset(-t.dy, t.dx) * off);
    }
    return out;
  }

  /// Burilish chizig'i: polosa uchidagi yo'nalishdan keyingi polosa boshidagi yo'nalishga silliq o'tadi
  /// (urinma chiziqlar kesishgan joyda kvadratik Bezye, aks holda kubik).
  List<Offset> _turnPts(Lane a, Lane b) {
    final pA = a.pts.last, pB = b.pts.first;
    final dA = a.dirAt(a.length), dB = b.dirAt(0);
    final w = pB - pA;
    final chord = w.distance;
    if (chord < 0.5) return [pA, pB];
    final cr = dA.dx * dB.dy - dA.dy * dB.dx;
    if (cr.abs() > 0.12) {
      final t = (w.dx * dB.dy - w.dy * dB.dx) / cr;
      final u = (dA.dx * w.dy - dA.dy * w.dx) / cr;
      if (t > 0.3 && u > 0.3 && t < chord * 3 && u < chord * 3) {
        final c = pA + dA * t;
        final n = max(6, min(16, ((t + u) / 3).ceil()));
        return [
          for (var i = 0; i <= n; i++)
            () {
              final s = i / n, q = 1 - s;
              return Offset(
                q * q * pA.dx + 2 * q * s * c.dx + s * s * pB.dx,
                q * q * pA.dy + 2 * q * s * c.dy + s * s * pB.dy,
              );
            }()
        ];
      }
    }
    final dot = (dA.dx * dB.dx + dA.dy * dB.dy).clamp(-1.0, 1.0).toDouble();
    final th = acos(dot);
    final k = th < 0.02 ? chord / 3 : (4 / 3) * tan(th / 4) * chord / (2 * sin(th / 2));
    final c1 = pA + dA * k, c2 = pB - dB * k;
    final n = max(6, min(16, max((chord * 1.3 / 3).ceil(), (th / 0.2).ceil())));
    return [
      for (var i = 0; i <= n; i++)
        () {
          final s = i / n, q = 1 - s;
          return Offset(
            q * q * q * pA.dx + 3 * q * q * s * c1.dx + 3 * q * s * s * c2.dx + s * s * s * pB.dx,
            q * q * q * pA.dy + 3 * q * q * s * c1.dy + 3 * q * s * s * c2.dy + s * s * s * pB.dy,
          );
        }()
    ];
  }

  Connector connector(Lane a, Lane b) {
    final key = '${a.id}_${b.id}';
    return connectors.putIfAbsent(key, () {
      final dA = a.dirAt(a.length), dB = b.dirAt(0);
      final dot = (dA.dx * dB.dx + dA.dy * dB.dy).clamp(-1.0, 1.0).toDouble();
      final ang = acos(dot);
      final c = Connector(
        _turnPts(a, b),
        from: a,
        to: b,
        nodeId: a.toNode,
        vmax: a.speedLimit * (1 - 0.75 * ang / pi),
      );
      connectorsFrom.putIfAbsent(a.id, () => []).add(c);
      return c;
    });
  }

  List<Lane> lanesOf(int roadId) => [
        for (var i = 0; i < 8; i++)
          if (lanes.containsKey(roadId * 8 + i)) lanes[roadId * 8 + i]!
      ];

  /// Kirish nuqtasi polosa boshidan kamida ~30, oxiridan ~14 birlik (qisqa polosada nisbatan).
  static double _clampS(double s, double len) {
    final lo = min(30.0, len * 0.4);
    final hi = max(lo, len - min(14.0, len * 0.25));
    return s.clamp(lo, hi).toDouble();
  }

  /// Har bir bino uchun eng yaqin polosa nuqtasini topadi (yo'l kirish joyi).
  void computeAccess(List<Building> buildings) {
    access.clear();
    for (final b in buildings) {
      Lane? best;
      var bestD = 100.0;
      var bestS = 0.0;
      for (final l in lanes.values) {
        final rdd = net.roads[l.roadId];
        if (rdd == null || rdd.length < 50) continue; // qisqa yo'lga bino chiqmaydi (kesilgan polosa emas, yo'l uzunligi)
        if (rdd.layer == 1 || rdd.type == 2) continue; // estakada va magistralga bino to'g'ridan-to'g'ri chiqmaydi
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
        final goals = <int, double>{};
        for (final l in lanesOf(best.roadId)) {
          var ls = 0.0;
          var ld = double.infinity;
          for (var i = 1; i < l.pts.length; i++) {
            final q = closestOnSegment(b.pos, l.pts[i - 1], l.pts[i]);
            final d = (q - b.pos).distance;
            if (d < ld) {
              ld = d;
              ls = l.cum[i - 1] + (q - l.pts[i - 1]).distance;
            }
          }
          goals[l.id] = _clampS(ls, l.length);
        }
        final s0 = _clampS(bestS, best.length);
        access[b.id] = Access(best, s0, goals.isEmpty ? null : goals);
      }
    }
  }

  // ------------------------------------------------------------ marshrut

  Iterable<Lane> _successors(Lane from) sync* {
    final out = outgoing[from.toNode];
    if (out == null) return;
    final deg = net.nodes[from.toNode]?.roads.length ?? 0;
    for (final s in out) {
      if (s.roadId == from.roadId && s.fwd != from.fwd && deg > 1) continue; // U-burilish faqat boshi berk yo'lda
      yield s;
    }
  }

  double _turn(Lane from, Lane to) {
    final a = from.dirAt(from.length), b = to.dirAt(0);
    final dot = (a.dx * b.dx + a.dy * b.dy).clamp(-1.0, 1.0).toDouble();
    final cross = a.dx * b.dy - a.dy * b.dx; // > 0: o'ngga burilish
    var pen = 0.5 + acos(dot) * 1.2;
    if (from.laneCount > 1) {
      if (cross > 0.5 && from.laneIdx < from.laneCount - 1) pen += 2.0; // o'ngga ichki polosadan
      if (cross < -0.5 && from.laneIdx > 0) pen += 2.0; // chapga tashqi polosadan
    }
    return pen;
  }

  /// A*: generalized cost = yurish vaqti + burilish jarimasi + navbat (tirbandlik) taxmini.
  List<Lane>? findRoute(Lane start, double startS, Lane goal, double goalS, {Map<int, double>? goals}) {
    routeCalls++;
    final gm = <int, double>{
      for (final e in (goals ?? {goal.id: goalS}).entries)
        if (lanes.containsKey(e.key)) e.key: e.value
    };
    if (gm.isEmpty || !lanes.containsKey(start.id)) return null;
    final direct = gm[start.id];
    if (direct != null && direct > startS + 8) return [start];

    final g = <int, double>{};
    final prev = <int, int>{};
    final closed = <int>{};
    final heap = _Heap();
    final goalPts = [for (final e in gm.entries) lanes[e.key]!.pointAt(e.value)];
    double h(Lane l) {
      var m = double.infinity;
      for (final p in goalPts) {
        final d = (l.pts.last - p).distance;
        if (d < m) m = d;
      }
      return m / 55.0;
    }

    void expand(Lane from, double baseG, int fromKey) {
      for (final s in _successors(from)) {
        final cost = baseG + s.length / s.speedLimit + _turn(from, s) + min(s.vehicles.length * 0.3, s.length / s.speedLimit * 0.8);
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
      if (gm.containsKey(id)) {
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
