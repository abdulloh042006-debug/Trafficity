import 'dart:ui';

/// Mashina harakatlanadigan chiziq: polosa yoki chorraha ichidagi burilish.
abstract class Track {
  Track(this.pts) : cum = _cumulative(pts);

  final List<Offset> pts;
  final List<double> cum;
  final List<Vehicle> vehicles = []; // s bo'yicha o'sish tartibida

  double get length => cum.last;

  static List<double> _cumulative(List<Offset> p) {
    final c = <double>[0];
    for (var i = 1; i < p.length; i++) {
      c.add(c[i - 1] + (p[i] - p[i - 1]).distance);
    }
    return c;
  }

  int _segAt(double s) {
    var lo = 1, hi = pts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] < s) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  Offset pointAt(double s) {
    s = s.clamp(0.0, length).toDouble();
    final i = _segAt(s);
    final seg = cum[i] - cum[i - 1];
    final t = seg < 1e-9 ? 0.0 : (s - cum[i - 1]) / seg;
    return Offset.lerp(pts[i - 1], pts[i], t)!;
  }

  Offset dirAt(double s) {
    final i = _segAt(s.clamp(0.0, length).toDouble());
    final d = pts[i] - pts[i - 1];
    final l = d.distance;
    return l < 1e-9 ? const Offset(1, 0) : d / l;
  }
}

class Lane extends Track {
  Lane(
    super.pts, {
    required this.id,
    required this.roadId,
    required this.fwd,
    required this.fromNode,
    required this.toNode,
  });

  static const double speed = 22; // birlik/s (~40 km/soat)

  /// O'rtacha tezlik / limit (tirbandlik o'lchovi, 1 = erkin harakat).
  double ratio = 1.0;

  final int id; // roadId*2 + (fwd ? 0 : 1)
  final int roadId;
  final bool fwd;
  final int fromNode;
  final int toNode;

  int get oppositeId => id ^ 1;
}

class Connector extends Track {
  Connector(
    super.pts, {
    required this.from,
    required this.to,
    required this.nodeId,
    required this.vmax,
  });

  final Lane from;
  final Lane to;
  final int nodeId;
  final double vmax;
  final Map<String, bool> _conf = {};

  String get key => '${from.id}_${to.id}';

  /// Ikki burilish bir vaqtda bo'la olmaydimi (kesishadi yoki bir polosaga qo'shiladi).
  bool conflicts(Connector o) {
    if (identical(o, this)) return false;
    if (o.to.id == to.id) return true;
    return _conf.putIfAbsent(o.key, () => _near(o));
  }

  bool _near(Connector o) {
    for (final p in pts) {
      for (final q in o.pts) {
        if ((p - q).distance < 6) return true;
      }
    }
    return false;
  }
}

enum VType { car, truck }

class Vehicle {
  Vehicle({
    required this.id,
    required this.type,
    required this.track,
    required this.s,
    required this.route,
    required this.originB,
    required this.destB,
    required this.destS,
    required this.isReturn,
    required this.born,
    required this.color,
  })  : length = type == VType.truck ? 22.0 : 9.0,
        width = type == VType.truck ? 6.0 : 4.4,
        aMax = type == VType.truck ? 3.0 : 6.0,
        bComf = type == VType.truck ? 6.0 : 8.0,
        vMaxSelf = type == VType.truck ? 18.0 : 26.0;

  final int id;
  final VType type;
  final double length, width, aMax, bComf, vMaxSelf;
  final int originB, destB;
  final bool isReturn;
  final double born;
  final Color color;

  Track track;
  double s; // old bamper holati
  double v = 0;
  double a = 0;
  List<Lane> route;
  int routeIdx = 0;
  double destS;

  Connector? holdConn; // chorrahadan o'tish ruxsati
  Connector? pendingConn; // ruxsat kutilayotgan burilish
  double wait = 0;
  bool needsReroute = false;
  bool removed = false;
}
