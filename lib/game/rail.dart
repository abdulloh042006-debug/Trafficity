import 'dart:math';
import 'dart:ui';

import 'lane_graph.dart';
import 'road_network.dart';
import 'traffic_model.dart';

/// Temir yo'l doimiylari (1 birlik ~ 1 m).
class RailConst {
  static const double vMax = 48; // birlik/s
  static const double accel = 10, decel = 12;
  static const double trackOffset = 2.8; // har yo'nalish uchun alohida izi (o'ng tomonlama harakat)
  static const double locoLen = 24, carLen = 21, gap = 2;
  static const int cars = 3;
  static const double stationRadius = 280; // xizmat zonasi
  static const double stationCost = 350;
  static const double costGround = 1.5; // birlik uzunligi uchun
  static const double costBridge = 4.5;
  static const double costTunnel = 6.0;
  static const double maxTurn = 1.22; // tugunda eng katta burilish (~70 daraja)
  static const double dwell = 5; // stansiyada to'xtash vaqti, s
  static double get trainLength => locoLen + cars * (carLen + gap) + gap;
}

class Station {
  Station(this.id, this.pos);
  final int id;
  final Offset pos;
  int nodeId = 0; // bog'langan tugun (0 = yo'q)
  bool active = false; // shu stansiyaga poyezd qatnaydi
  int served = 0; // xizmat zonasidagi uylar
  int visits = 0;
}

/// Yo'nalishli temir yo'l bo'lagi (har yo'l bo'lagi ikki yo'nalishli).
class RailEdge {
  RailEdge(this.road, this.fwd, this.track);
  final Road road;
  final bool fwd;
  final Lane track;
  int get key => road.id * 2 + (fwd ? 0 : 1);
  int get from => fwd ? road.a : road.b;
  int get to => fwd ? road.b : road.a;
  double get length => track.length;
}

class Train {
  Train(this.id, this.color);
  final int id;
  final Color color;
  List<RailEdge> hist = []; // bosib o'tilgan bo'laklar (oxirgisi - lokomotiv turgan)
  List<RailEdge> plan = []; // oldinda kutayotgan bo'laklar
  double s = 0; // lokomotiv old nuqtasining hozirgi bo'lakdagi joyi
  double v = 0;
  double dwell = 0;
  Station? station; // maqsad stansiya
  bool cont = false; // rejaning oxirgi bo'lagi stansiyadan keyingi davomiy bo'lak (o'rtasi tugunda to'xtash uchun)
  double contLen = 0;
  int lastId = 0; // oxirgi to'xtagan stansiya
  bool atStation = false;
  double get length => RailConst.trainLength;
}

typedef RailPose = ({Offset p, double a});

class RailSim {
  RailSim(this.net);

  final RoadNetwork net;
  final List<Station> stations = [];
  final List<Train> trains = [];
  final Map<int, RailEdge> edges = {};
  final Map<int, List<RailEdge>> outAt = {};
  final Random _rnd = Random(11);
  int _stationSeq = 1, _trainSeq = 1;
  int trips = 0;
  double earned = 0;

  /// Poyezd stansiyaga yetganda chaqiriladi (yo'lovchi tushirib/olinadi, daromad).
  void Function(Station st, double fare)? onFare;

  static const _colors = [Color(0xFFC0392B), Color(0xFF2E7DB5), Color(0xFF2F8F5B), Color(0xFFD08A1E)];

  Station addStation(Offset p) {
    final st = Station(_stationSeq++, p);
    stations.add(st);
    return st;
  }

  Station? stationAtNode(int node) {
    for (final st in stations) {
      if (st.nodeId == node) return st;
    }
    return null;
  }

  /// Yo'l tarmog'i yoki stansiyalar o'zgarganda: yo'nalishli bo'laklar qayta quriladi, poyezdlar qayta paydo bo'ladi.
  void rebuild() {
    edges.clear();
    outAt.clear();
    trains.clear();
    for (final r in net.roads.values) {
      for (final fwd in const [true, false]) {
        final base = fwd ? r.pts : r.pts.reversed.toList();
        final pts = LaneGraph.smoothCorners(LaneGraph.offsetPath(base, RailConst.trackOffset));
        final lane = Lane(
          pts,
          id: r.id * 2 + (fwd ? 0 : 1),
          roadId: r.id,
          fwd: fwd,
          fromNode: fwd ? r.a : r.b,
          toNode: fwd ? r.b : r.a,
        );
        final e = RailEdge(r, fwd, lane);
        edges[e.key] = e;
        outAt.putIfAbsent(e.from, () => []).add(e);
      }
    }
    // stansiyalar tugunlarga bog'lanadi; bir komponentda 2+ stansiya bo'lsa, xizmat ko'rsatiladi
    final parent = <int, int>{};
    int find(int x) {
      var r = x;
      while ((parent[r] ?? r) != r) {
        r = parent[r]!;
      }
      return r;
    }

    for (final r in net.roads.values) {
      parent[find(r.a)] = find(r.b);
    }
    final comp = <int, List<Station>>{};
    for (final st in stations) {
      st.active = false;
      st.nodeId = net.nodeNear(st.pos, 4)?.id ?? 0;
      if (st.nodeId != 0) comp.putIfAbsent(find(st.nodeId), () => []).add(st);
    }
    for (final list in comp.values) {
      if (list.length < 2) continue;
      for (final st in list) {
        st.active = true;
      }
      final n = min(3, (list.length + 1) ~/ 2);
      for (var i = 0; i < n; i++) {
        _spawn(list[(i * list.length ~/ n) % list.length]);
      }
    }
  }

  void _spawn(Station st) {
    final outs = outAt[st.nodeId];
    if (outs == null || outs.isEmpty) return;
    var e = outs.first;
    for (final o in outs) {
      if (o.length > e.length) e = o;
    }
    final t = Train(_trainSeq++, _colors[(_trainSeq) % _colors.length]);
    t.hist = [e];
    t.s = min(e.length * 0.5, t.length + 2);
    t.lastId = st.id;
    if (!_assign(t)) t.dwell = RailConst.dwell;
    trains.add(t);
  }

  // --------------------------------------------------------------- marshrut

  bool _allowed(RailEdge a, RailEdge o) {
    if (o.road.id == a.road.id) return false; // teskari burilish faqat stansiyada
    final d1 = a.track.dirAt(a.length), d2 = o.track.dirAt(0);
    final dot = (d1.dx * d2.dx + d1.dy * d2.dy).clamp(-1.0, 1.0).toDouble();
    return acos(dot) <= RailConst.maxTurn;
  }

  /// Dijkstra: [start] bo'lakning qolgan [rem] uzunligidan, [target] tugunga yetguncha bo'laklar ro'yxati.
  List<RailEdge>? _route(RailEdge start, double rem, int target) {
    if (start.to == target) return <RailEdge>[];
    final dist = <int, double>{start.key: rem};
    final prev = <int, RailEdge?>{start.key: null};
    final done = <int>{};
    while (true) {
      RailEdge? cur;
      var best = double.infinity;
      for (final en in dist.entries) {
        if (!done.contains(en.key) && en.value < best) {
          best = en.value;
          cur = edges[en.key];
        }
      }
      if (cur == null) return null;
      if (cur.to == target) {
        final out = <RailEdge>[];
        RailEdge? x = cur;
        while (x != null && x.key != start.key) {
          out.add(x);
          x = prev[x.key];
        }
        return out.reversed.toList();
      }
      done.add(cur.key);
      for (final o in outAt[cur.to] ?? const <RailEdge>[]) {
        if (!_allowed(cur, o)) continue;
        final nd = best + o.length;
        if (nd < (dist[o.key] ?? double.infinity)) {
          dist[o.key] = nd;
          prev[o.key] = cur;
        }
      }
    }
  }

  double _cost(double rem, List<RailEdge> plan) => rem + plan.fold<double>(0, (s, e) => s + e.length);

  /// Poyezdni teskari yo'naltirilgan holati (dum lokomotivga aylanadi): (yangi hist, yangi s).
  ({List<RailEdge> hist, double s})? _reversed(Train t) {
    var idx = t.hist.length - 1;
    var pos = t.s - t.length;
    while (pos < 0 && idx > 0) {
      idx--;
      pos += t.hist[idx].length;
    }
    final orig = t.hist[idx];
    pos = pos.clamp(0.0, orig.length).toDouble();
    final nh = <RailEdge>[];
    for (var i = t.hist.length - 1; i >= idx; i--) {
      final e = t.hist[i];
      final r = edges[e.road.id * 2 + (e.fwd ? 1 : 0)];
      if (r == null) return null;
      nh.add(r);
    }
    return (hist: nh, s: nh.last.length * (1 - pos / max(orig.length, 1e-6)));
  }

  /// [e] oxiridan eng to'g'ri davom etadigan bo'lak (bo'lmasa null: tugun boshi berk).
  RailEdge? _continuation(RailEdge e) {
    RailEdge? best;
    var bestAng = double.infinity;
    for (final o in outAt[e.to] ?? const <RailEdge>[]) {
      if (!_allowed(e, o)) continue;
      final d1 = e.track.dirAt(e.length), d2 = o.track.dirAt(0);
      final ang = acos((d1.dx * d2.dx + d1.dy * d2.dy).clamp(-1.0, 1.0).toDouble());
      if (ang < bestAng) {
        bestAng = ang;
        best = o;
      }
    }
    return best;
  }

  /// Teskari yo'naltirilgan poyezd tanasi boshqa poyezd bilan to'qnashmasligini tekshiradi (nuqtalar bo'yicha).
  bool _free(Train self, List<RailEdge> hist, double s) {
    Offset at(List<RailEdge> h, double head, double behind) {
      var idx = h.length - 1;
      var pos = head - behind;
      while (pos < 0 && idx > 0) {
        idx--;
        pos += h[idx].length;
      }
      return h[idx].track.pointAt(pos.clamp(0.0, h[idx].length).toDouble());
    }

    final len = self.length;
    for (final u in trains) {
      if (identical(u, self)) continue;
      for (var i = 0; i <= 6; i++) {
        final a = at(hist, s, len * i / 6);
        for (var j = 0; j <= 6; j++) {
          if ((a - at(u.hist, u.s, u.length * j / 6)).distance < 14) return false;
        }
      }
    }
    return true;
  }

  /// Keyingi stansiyani tanlaydi (to'xtab turgan bo'lsa, teskari yo'nalish ham sinab ko'riladi).
  bool _assign(Train t) {
    final cands = [
      for (final st in stations)
        if (st.active && st.id != t.lastId && st.nodeId != 0) st
    ]..shuffle(_rnd);
    for (final st in cands) {
      final cur = t.hist.last;
      var plan = _route(cur, cur.length - t.s, st.nodeId);
      var bestCost = plan == null ? double.infinity : _cost(cur.length - t.s, plan);
      ({List<RailEdge> hist, double s})? rv;
      if (t.atStation) {
        final r = _reversed(t);
        if (r != null && _free(t, r.hist, r.s)) {
          final rc = r.hist.last;
          final p = _route(rc, rc.length - r.s, st.nodeId);
          if (p != null) {
            final c = _cost(rc.length - r.s, p);
            if (c < bestCost) {
              bestCost = c;
              plan = p;
              rv = r;
            }
          }
        }
      }
      if (plan == null) continue;
      if (rv != null) {
        t.hist = rv.hist;
        t.s = rv.s;
      }
      t.plan = plan;
      t.station = st;
      t.atStation = false;
      // o'tuvchi stansiya: poyezd o'rtasi stansiya tugunida to'xtashi uchun davomiy bo'lak qo'shiladi (boshi berkda yo'q)
      t.cont = false;
      final cont = _continuation(plan.isEmpty ? t.hist.last : plan.last);
      if (cont != null && cont.length > t.length / 2 + 6) {
        t.plan.add(cont);
        t.cont = true;
        t.contLen = cont.length;
      }
      return true;
    }
    return false;
  }

  // ----------------------------------------------------------- harakat

  void step(double dt) {
    for (final t in trains) {
      _stepTrain(t, dt);
    }
  }

  double? _stopDist(Train t) {
    if (t.station == null) return null;
    final cur = t.hist.last;
    var d = cur.length - t.s;
    for (final e in t.plan) {
      d += e.length;
    }
    // o'tuvchi stansiyada old nuqta tugundan L/2 narida to'xtaydi (poyezd o'rtasi tugunda), boshi berkda tugunda
    return t.cont ? d - (t.contLen - t.length / 2) : d;
  }

  /// Old nuqtadan oldindagi poyezd dumigacha masofa (shu poyezd yo'li bo'ylab); yo'q bo'lsa cheksiz.
  double _gapAhead(Train t) {
    var gap = double.infinity;
    var base = -t.s;
    final startOf = <int, double>{};
    for (final e in [t.hist.last, ...t.plan].take(6)) {
      startOf[e.key] = base;
      base += e.length;
    }
    for (final u in trains) {
      if (identical(u, t)) continue;
      final tail = locate(u, u.length);
      final b = startOf[tail.e.key];
      if (b == null) continue;
      final d = b + tail.pos;
      if (d >= 0) gap = min(gap, d);
    }
    return gap;
  }

  void _stepTrain(Train t, double dt) {
    if (t.dwell > 0) {
      t.dwell -= dt;
      if (t.dwell <= 0) {
        t.dwell = 0;
        if (!_assign(t)) t.dwell = RailConst.dwell;
      }
      return;
    }
    final stop = _stopDist(t);
    var vt = RailConst.vMax;
    if (stop != null) vt = min(vt, sqrt(max(0.0, 2 * RailConst.decel * max(0.0, stop - 0.3))));
    final gap = _gapAhead(t);
    if (gap < 140) vt = min(vt, max(0.0, (gap - 30) * 0.5));
    if (t.v < vt) {
      t.v = min(vt, t.v + RailConst.accel * dt);
    } else {
      t.v = max(vt, t.v - RailConst.decel * dt);
    }
    t.s += t.v * dt;
    while (t.plan.isNotEmpty && t.s >= t.hist.last.length) {
      t.s -= t.hist.last.length;
      t.hist.add(t.plan.removeAt(0));
      _trimHist(t);
    }
    final cur = t.hist.last;
    if (t.plan.isEmpty && t.s > cur.length) t.s = cur.length;
    final stop2 = _stopDist(t);
    if (stop2 != null && stop2 < 0.8 && t.v < 1.5) {
      t.v = 0;
      t.dwell = RailConst.dwell;
      t.atStation = true;
      final st = t.station;
      if (st != null) {
        t.lastId = st.id;
        st.visits++;
        trips++;
        final fare = min(90.0, 1.2 * st.served);
        earned += fare;
        onFare?.call(st, fare);
      }
      t.station = null;
      t.cont = false;
    }
  }

  /// Tarix: poyezd dumi hozirgi bo'lak boshidan orqada turgan joyni qoplaydigan bo'laklar saqlanadi.
  void _trimHist(Train t) {
    final need = t.length + 12 - t.s;
    var keep = 1;
    var acc = 0.0;
    for (var i = t.hist.length - 2; i >= 0 && acc < need; i--) {
      acc += t.hist[i].length;
      keep++;
    }
    while (t.hist.length > keep) {
      t.hist.removeAt(0);
    }
  }

  // ----------------------------------------------------------- chizish uchun

  /// Poyezd old nuqtasidan [behind] orqadagi bo'lak va undagi joy.
  ({RailEdge e, double pos}) locate(Train t, double behind) {
    var idx = t.hist.length - 1;
    var pos = t.s - behind;
    while (pos < 0 && idx > 0) {
      idx--;
      pos += t.hist[idx].length;
    }
    final e = t.hist[idx];
    return (e: e, pos: pos.clamp(0.0, e.length).toDouble());
  }

  /// Poyezd old nuqtasidan [behind] orqadagi nuqta va yo'nalish.
  RailPose poseAt(Train t, double behind) {
    final l = locate(t, behind);
    final d = l.e.track.dirAt(l.pos);
    return (p: l.e.track.pointAt(l.pos), a: atan2(d.dy, d.dx));
  }

  /// Xizmat zonasidagi uylar ulushi (0..1); har stansiyaning `served` qiymati ham yangilanadi.
  double coverage(Iterable<Offset> houses) {
    for (final st in stations) {
      st.served = 0;
    }
    var n = 0, c = 0;
    for (final h in houses) {
      n++;
      Station? best;
      var bd = RailConst.stationRadius;
      for (final st in stations) {
        if (!st.active) continue;
        final d = (st.pos - h).distance;
        if (d < bd) {
          bd = d;
          best = st;
        }
      }
      if (best != null) {
        best.served++;
        c++;
      }
    }
    return n == 0 ? 0.0 : c / n;
  }
}
