import 'dart:math';
import 'dart:ui';

Offset closestOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return a;
  final ap = p - a;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / l2).clamp(0.0, 1.0).toDouble();
  return a + ab * t;
}

Offset? _segInter(Offset p, Offset p2, Offset q, Offset q2) {
  final r = p2 - p, s = q2 - q;
  final den = r.dx * s.dy - r.dy * s.dx;
  if (den.abs() < 1e-9) return null;
  final qp = q - p;
  final t = (qp.dx * s.dy - qp.dy * s.dx) / den;
  final u = (qp.dx * r.dy - qp.dy * r.dx) / den;
  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return p + r * t;
}

class RoadNode {
  RoadNode(this.id, this.pos);
  final int id;
  final Offset pos;
  final Set<int> roads = {};
}

/// Ikki chorraha (yoki uchi) orasidagi yo'l bo'lagi.
class Road {
  Road({
    required this.id,
    required this.a,
    required this.b,
    required this.pts,
    required this.length,
    required this.cost,
    this.oneWay = false,
  });

  final bool oneWay;
  final int id;
  final int a; // boshlang'ich tugun
  final int b; // oxirgi tugun
  final List<Offset> pts; // markaz chizig'i
  final double length;
  final double cost;
}

class RoadHit {
  RoadHit(this.road, this.seg, this.point, this.dist);
  final Road road;
  final int seg;
  final Offset point;
  final double dist;
}

class _Arm {
  _Arm(this.roadId, this.cp, this.ang);
  final int roadId;
  final Offset cp;
  final double ang;
}

class _Cut {
  _Cut(this.d, this.p, {this.node});
  final double d;
  final Offset p;
  RoadNode? node;
}

/// Chizishdan mustaqil yo'l topologiyasi.
class RoadNetwork {
  static const double costPerUnit = 0.5;
  static const double roadWidth = 14;

  final Map<int, RoadNode> nodes = {};
  final Map<int, Road> roads = {};
  int _nextNode = 1;
  int _nextRoad = 1;

  void clear() {
    nodes.clear();
    roads.clear();
    _nextNode = 1;
    _nextRoad = 1;
  }

  // ------------------------------------------------------------- geometriya

  static Offset _bez(Offset a, Offset b, Offset c, double t) {
    final u = 1 - t;
    return Offset(
      u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx,
      u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy,
    );
  }

  static List<Offset> sample(Offset a, Offset b, Offset? c) {
    if (c == null) {
      final n = max(1, ((b - a).distance / 12).ceil());
      return [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];
    }
    final approx = (c - a).distance + (b - c).distance;
    final n = max(2, (approx / 10).ceil());
    return [for (var i = 0; i <= n; i++) _bez(a, b, c, i / n)];
  }

  static double polyLength(List<Offset> pts) {
    var len = 0.0;
    for (var i = 1; i < pts.length; i++) {
      len += (pts[i] - pts[i - 1]).distance;
    }
    return len;
  }

  static List<Offset> _dedupe(List<Offset> pts) {
    final out = <Offset>[];
    for (final p in pts) {
      if (out.isEmpty || (p - out.last).distance > 0.01) out.add(p);
    }
    return out;
  }

  // ------------------------------------------------------------------ qidiruv

  RoadNode? nodeNear(Offset p, double radius) {
    RoadNode? best;
    var bestD = radius;
    for (final n in nodes.values) {
      final d = (n.pos - p).distance;
      if (d <= bestD) {
        bestD = d;
        best = n;
      }
    }
    return best;
  }

  RoadHit? nearestRoadPoint(Offset p, double radius) {
    RoadHit? best;
    var bestD = radius;
    for (final r in roads.values) {
      for (var i = 1; i < r.pts.length; i++) {
        final q = closestOnSegment(p, r.pts[i - 1], r.pts[i]);
        final d = (q - p).distance;
        if (d <= bestD) {
          bestD = d;
          best = RoadHit(r, i, q, d);
        }
      }
    }
    return best;
  }

  Road? roadNear(Offset p, double radius) => nearestRoadPoint(p, radius)?.road;

  // ------------------------------------------------------------- tuzilish

  RoadNode _newNode(Offset p) {
    final n = RoadNode(_nextNode++, p);
    nodes[n.id] = n;
    return n;
  }

  RoadNode _nodeAt(Offset p) => nodeNear(p, 1.0) ?? _newNode(p);

  Road? _addNodes(List<Offset> pts, RoadNode na, RoadNode nb, {bool oneWay = false}) {
    final p = List<Offset>.of(_dedupe(pts));
    if (p.length < 2) return null;
    p[0] = na.pos;
    p[p.length - 1] = nb.pos;
    final len = polyLength(p);
    if (len < 3) return null;
    final road = Road(
      id: _nextRoad++,
      a: na.id,
      b: nb.id,
      pts: p,
      length: len,
      cost: len * costPerUnit,
      oneWay: oneWay,
    );
    roads[road.id] = road;
    na.roads.add(road.id);
    nb.roads.add(road.id);
    return road;
  }

  /// Saqlangan yo'l bo'lagini to'g'ridan-to'g'ri qo'shadi (yuklash uchun).
  Road? addRoadPts(List<Offset> pts, {bool oneWay = false}) {
    if (pts.length < 2) return null;
    return _addNodes(pts, _nodeAt(pts.first), _nodeAt(pts.last), oneWay: oneWay);
  }

  void _detach(Road r) {
    roads.remove(r.id);
    nodes[r.a]?.roads.remove(r.id);
    nodes[r.b]?.roads.remove(r.id);
  }

  void removeRoad(int id) {
    final r = roads[id];
    if (r == null) return;
    _detach(r);
    for (final nid in [r.a, r.b]) {
      final n = nodes[nid];
      if (n != null && n.roads.isEmpty) nodes.remove(nid);
    }
  }

  /// Yo'lni p nuqtada ikkiga bo'ladi va chorraha tugunini qaytaradi.
  RoadNode splitRoadAt(int roadId, Offset p) {
    final r = roads[roadId]!;
    for (final nid in [r.a, r.b]) {
      final n = nodes[nid]!;
      if ((n.pos - p).distance < 2.0) return n;
    }
    var bi = 1;
    var bd = double.infinity;
    var bp = p;
    for (var i = 1; i < r.pts.length; i++) {
      final q = closestOnSegment(p, r.pts[i - 1], r.pts[i]);
      final d = (q - p).distance;
      if (d < bd) {
        bd = d;
        bi = i;
        bp = q;
      }
    }
    final left = [...r.pts.sublist(0, bi), bp];
    final right = [bp, ...r.pts.sublist(bi)];
    final na = nodes[r.a]!;
    final nb = nodes[r.b]!;
    _detach(r);
    final mid = _newNode(bp);
    _addNodes(left, na, mid, oneWay: r.oneWay);
    _addNodes(right, mid, nb, oneWay: r.oneWay);
    return mid;
  }

  RoadNode _attachEnd(Offset p) {
    final n = nodeNear(p, 1.5);
    if (n != null) return n;
    final hit = nearestRoadPoint(p, 1.5);
    if (hit != null) return splitRoadAt(hit.road.id, hit.point);
    return _newNode(p);
  }

  static Offset _pointAlong(List<Offset> pts, double d) {
    var acc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final seg = (pts[i] - pts[i - 1]).distance;
      if (seg > 0 && acc + seg >= d) return Offset.lerp(pts[i - 1], pts[i], (d - acc) / seg)!;
      acc += seg;
    }
    return pts.last;
  }

  /// Chorraha tuguni o'rniga aylana chorraha quradi (soat miliga teskari harakat).
  /// Xatolik matnini qaytaradi, muvaffaqiyatda null. [charge] sarflangan mablag'ni (+) yoki
  /// qaytarilgan stub narxini (-) xabar qiladi.
  String? buildRoundabout(
    int nodeId,
    double radius,
    bool Function(Offset) blocked,
    double budget,
    void Function(double) charge,
  ) {
    final n = nodes[nodeId];
    if (n == null || n.roads.length < 3) return "Kamida 3 ta yo'l kerak";
    final c = n.pos;
    final cutDist = radius + 16;
    final arms = <_Arm>[];
    for (final rid in n.roads) {
      final r = roads[rid]!;
      if (r.oneWay) return "Bir tomonlama yo'l bilan bo'lmaydi";
      if (r.a == r.b) return "Yopiq halqa yo'l bilan bo'lmaydi";
      final pts = r.a == nodeId ? r.pts : r.pts.reversed.toList();
      if (polyLength(pts) < cutDist + 25) return "Yo'llar juda qisqa";
      final cp = _pointAlong(pts, cutDist);
      final dir = _pointAlong(pts, radius + 8) - c;
      arms.add(_Arm(rid, cp, atan2(dir.dy, dir.dx)));
    }
    arms.sort((x, y) => y.ang.compareTo(x.ang)); // kamayish = soat miliga teskari
    for (var i = 0; i < arms.length; i++) {
      var d = arms[i].ang - arms[(i + 1) % arms.length].ang;
      if (d <= 0) d += 2 * pi;
      if (d < 0.6) return "Yo'llar orasidagi burchak juda kichik";
    }
    for (var k = 0; k < 24; k++) {
      final a = k / 24 * 2 * pi;
      if (blocked(c + Offset(cos(a), sin(a)) * (radius + 4))) return "Aylana uchun joy band";
    }
    final need = 150 +
        2 * pi * radius * costPerUnit +
        arms.length * 16 * costPerUnit -
        arms.length * cutDist * costPerUnit;
    if (need > budget) return "Mablag' yetarli emas";

    var spent = 150.0;
    final cutNodes = <RoadNode>[];
    for (final a in arms) {
      cutNodes.add(splitRoadAt(a.roadId, a.cp));
    }
    for (final cn in cutNodes) {
      int? stubId;
      for (final rid in n.roads) {
        final r = roads[rid];
        if (r != null && (r.a == cn.id || r.b == cn.id)) stubId = rid;
      }
      if (stubId != null) {
        spent -= roads[stubId]!.cost; // stub narxi qaytariladi
        removeRoad(stubId);
      }
    }
    final ringNodes = <RoadNode>[
      for (final a in arms) _newNode(c + Offset(cos(a.ang), sin(a.ang)) * radius)
    ];
    for (var i = 0; i < arms.length; i++) {
      final conn = _addNodes([cutNodes[i].pos, ringNodes[i].pos], cutNodes[i], ringNodes[i]);
      if (conn != null) spent += conn.cost;
    }
    for (var i = 0; i < arms.length; i++) {
      final j = (i + 1) % arms.length;
      var d = arms[i].ang - arms[j].ang;
      if (d <= 0) d += 2 * pi;
      final steps = max(3, (radius * d / 10).ceil());
      final pts = <Offset>[];
      for (var k = 0; k <= steps; k++) {
        final ph = arms[i].ang - d * k / steps;
        pts.add(c + Offset(cos(ph), sin(ph)) * radius);
      }
      final ring = _addNodes(pts, ringNodes[i], ringNodes[j], oneWay: true);
      if (ring != null) spent += ring.cost;
    }
    charge(spent);
    return null;
  }

  /// Yangi yo'lni quradi: uchlari yo'lga tegsa, ikkala yo'l ham bo'linadi;
  /// boshqa yo'llarni kesib o'tsa, har bir kesishuvda chorraha hosil bo'ladi.
  void connectRoad(List<Offset> raw) {
    final path = List<Offset>.of(_dedupe(raw));
    if (path.length < 2) return;

    final startNode = _attachEnd(path.first);
    final endNode = _attachEnd(path.last);
    path[0] = startNode.pos;
    path[path.length - 1] = endNode.pos;

    final cum = <double>[0];
    for (var i = 1; i < path.length; i++) {
      cum.add(cum[i - 1] + (path[i] - path[i - 1]).distance);
    }
    final total = cum.last;

    final cuts = <_Cut>[];
    for (var i = 1; i < path.length; i++) {
      for (final r in roads.values) {
        for (var j = 1; j < r.pts.length; j++) {
          final x = _segInter(path[i - 1], path[i], r.pts[j - 1], r.pts[j]);
          if (x == null) continue;
          final d = cum[i - 1] + (x - path[i - 1]).distance;
          if (d < 4 || d > total - 4) continue;
          cuts.add(_Cut(d, x));
        }
      }
    }
    cuts.sort((a, b) => a.d.compareTo(b.d));

    final stops = <_Cut>[_Cut(0, startNode.pos, node: startNode)];
    for (final c in cuts) {
      if (c.d - stops.last.d < 4) continue;
      final hit = nearestRoadPoint(c.p, 2.0);
      if (hit == null) continue;
      c.node = splitRoadAt(hit.road.id, c.p);
      stops.add(c);
    }
    stops.add(_Cut(total, endNode.pos, node: endNode));

    for (var k = 1; k < stops.length; k++) {
      final d0 = stops[k - 1].d, d1 = stops[k].d;
      final piece = <Offset>[stops[k - 1].node!.pos];
      for (var i = 1; i < path.length - 1; i++) {
        if (cum[i] > d0 + 0.5 && cum[i] < d1 - 0.5) piece.add(path[i]);
      }
      piece.add(stops[k].node!.pos);
      _addNodes(piece, stops[k - 1].node!, stops[k].node!);
    }
  }
}
