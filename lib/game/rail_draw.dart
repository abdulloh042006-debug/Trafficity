import 'dart:math';
import 'dart:ui';

import 'deck.dart';
import 'lane_graph.dart';
import 'rail.dart';
import 'road_network.dart';
import 'terrain.dart';

/// Temir yo'l uchastkasi turi: yer, suv ustidagi ko'prik, yer osti (tunnel), yo'l ustidan o'tish.
class RailCls {
  static const ground = 0, bridge = 1, tunnel = 2, overRoad = 3;
}

class RailRun {
  RailRun(this.cls, this.pts, this.s0, this.s1);
  final int cls;
  final List<Offset> pts;
  final double s0, s1; // yo'l bo'lagi bo'yicha boshlanish va tugash masofasi
}

class RailAnalysis {
  double cost = 0;
  double longestBridge = 0, longestTunnel = 0;
  bool hasBridge = false, hasTunnel = false;
}

class RailVis {
  final Map<int, List<RailRun>> runs = {};
  static const double step = 6;
  static const double maxBridge = 700, maxTunnel = 900;

  /// ~[step] oralig'ida nuqtalar va ularning yo'l bo'ylab masofasi.
  static List<(Offset, double)> sample(List<Offset> pts) {
    final out = <(Offset, double)>[(pts.first, 0)];
    var acc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final len = (b - a).distance;
      if (len < 1e-6) continue;
      final n = max(1, (len / step).ceil());
      for (var k = 1; k <= n; k++) {
        acc += len / n;
        out.add((Offset.lerp(a, b, k / n)!, acc));
      }
    }
    return out;
  }

  static int classOf(Offset p, int layer, Terrain terrain, RoadNetwork? roads) {
    if (layer == 1) return RailCls.tunnel; // yer osti rejimi
    if (terrain.isWaterAt(p)) return RailCls.bridge;
    if (terrain.isMountainAt(p)) return RailCls.tunnel;
    if (roads != null && roads.nearestRoadPoint(p, 9) != null) return RailCls.overRoad;
    return RailCls.ground;
  }

  /// Reja uchun: narx va ko'prik/tunnel uzunliklari.
  static RailAnalysis analyze(List<Offset> pts, int layer, Terrain terrain) {
    final a = RailAnalysis();
    final sm = sample(pts);
    var cls = -1;
    var run = 0.0;
    void close() {
      if (cls == RailCls.bridge) a.longestBridge = max(a.longestBridge, run);
      if (cls == RailCls.tunnel) a.longestTunnel = max(a.longestTunnel, run);
    }

    for (var i = 1; i < sm.length; i++) {
      final len = sm[i].$2 - sm[i - 1].$2;
      final c = classOf((sm[i].$1 + sm[i - 1].$1) / 2, layer, terrain, null);
      if (c != cls) {
        close();
        cls = c;
        run = 0;
      }
      run += len;
      a.cost += len *
          (c == RailCls.bridge
              ? RailConst.costBridge
              : (c == RailCls.tunnel ? RailConst.costTunnel : RailConst.costGround));
      if (c == RailCls.bridge) a.hasBridge = true;
      if (c == RailCls.tunnel) a.hasTunnel = true;
    }
    close();
    return a;
  }

  void rebuild(RoadNetwork rails, RoadNetwork roads, Terrain terrain) {
    runs.clear();
    for (final r in rails.roads.values) {
      final sm = sample(r.pts);
      final cls = [for (final e in sm) classOf(e.$1, r.layer, terrain, roads)];
      for (var i = 1; i < cls.length - 1; i++) {
        if (cls[i - 1] == cls[i + 1] && cls[i] != cls[i - 1]) cls[i] = cls[i - 1]; // yakka nuqta
      }
      // ko'prik qirg'oqdan ~18 birlik oldin boshlanadi (tayanch va ko'tarilish ko'rinsin)
      final wide = List<int>.of(cls);
      for (var i = 0; i < cls.length; i++) {
        if (cls[i] != RailCls.ground) continue;
        for (var k = max(0, i - 3); k <= min(cls.length - 1, i + 3); k++) {
          if (cls[k] == RailCls.bridge) {
            wide[i] = RailCls.bridge;
            break;
          }
        }
      }
      for (var i = 0; i < cls.length; i++) {
        cls[i] = wide[i];
      }
      final list = <RailRun>[];
      var start = 0;
      for (var i = 1; i <= cls.length; i++) {
        if (i == cls.length || cls[i] != cls[start]) {
          final end = min(i, cls.length - 1); // chegara nuqtasi ikkala uchastkaga kiradi
          if (end > start) {
            list.add(RailRun(cls[start], [for (var k = start; k <= end; k++) sm[k].$1], sm[start].$2, sm[end].$2));
          }
          start = i;
        }
      }
      runs[r.id] = list;
    }
  }

  int classAt(int roadId, double s) {
    final l = runs[roadId];
    if (l == null) return RailCls.ground;
    for (final r in l) {
      if (s >= r.s0 - 0.01 && s <= r.s1 + 0.01) return r.cls;
    }
    return RailCls.ground;
  }
}

// -------------------------------------------------------------------- chizish

const _ballast = Color(0xFFB9B09D), _ballastEdge = Color(0xFF857C69);

Path _path(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    p.lineTo(pts[i].dx, pts[i].dy);
  }
  return p;
}

void _dash(List<Offset> pts, double on, double off, List<Offset> out) {
  var drawing = true;
  var left = on;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final len = (b - a).distance;
    if (len < 1e-9) continue;
    var pos = 0.0;
    while (pos < len - 1e-9) {
      final step = min(len - pos, left);
      if (drawing) {
        out.add(Offset.lerp(a, b, pos / len)!);
        out.add(Offset.lerp(a, b, (pos + step) / len)!);
      }
      pos += step;
      left -= step;
      if (left <= 1e-9) {
        drawing = !drawing;
        left = drawing ? on : off;
      }
    }
  }
}

Deck _bridgeDeck(RailRun r) {
  final cum = <double>[0];
  for (var i = 1; i < r.pts.length; i++) {
    cum.add(cum[i - 1] + (r.pts[i] - r.pts[i - 1]).distance);
  }
  final total = cum.last;
  final ramp = r.cls == RailCls.bridge ? 14.0 : 10.0;
  final h = [
    for (final c in cum)
      () {
        final v = min(1.0, min(c / ramp, (total - c) / ramp)).clamp(0.0, 1.0).toDouble();
        return v * v * (3 - 2 * v);
      }()
  ];
  return Deck(r.pts, h, 7.5, false, false, false, false);
}

void drawRails(Canvas canvas, RailVis vis, double zoom) {
  if (vis.runs.isEmpty) return;
  final all = [for (final l in vis.runs.values) ...l];
  final surface = [for (final r in all) if (r.cls != RailCls.tunnel && r.pts.length >= 2) r];
  final bridges = [for (final r in surface) if (r.cls == RailCls.bridge || r.cls == RailCls.overRoad) r];
  final detail = zoom >= 0.3;

  // 1) ko'priklar: soya, chekka, yuza
  if (bridges.isNotEmpty) {
    final decks = [for (final r in bridges) _bridgeDeck(r)];
    final shadow = Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final d in decks) {
      canvas.drawPath(d.ribbon(d.half + 1, 0, const Offset(4, 6)), shadow);
    }
    final edge = Paint()..color = const Color(0xFF4A4D52);
    final fill = Paint()..color = const Color(0xFFD4D0C6);
    for (final d in decks) {
      canvas.drawPath(d.ribbon(d.half, 3.0, Offset.zero), edge);
    }
    for (final d in decks) {
      canvas.drawPath(d.ribbon(d.half, 0, Offset.zero), fill);
    }
  }

  // 2) yer ustidagi shag'al to'shama
  final bed = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final ground = [for (final r in surface) if (r.cls == RailCls.ground) r];
  bed
    ..strokeWidth = 12
    ..color = _ballastEdge;
  for (final r in ground) {
    canvas.drawPath(_path(r.pts), bed);
  }
  bed
    ..strokeWidth = 9.5
    ..color = _ballast;
  for (final r in ground) {
    canvas.drawPath(_path(r.pts), bed);
  }
  bed
    ..strokeWidth = 8
    ..strokeCap = StrokeCap.butt;
  for (final r in bridges) {
    canvas.drawPath(_path(r.pts), bed);
  }

  // 3) shpal va relslar
  final rail = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = detail ? 1.0 : 2.0
    ..color = const Color(0xFF55585E);
  final ties = <Offset>[];
  for (final r in surface) {
    if (detail) {
      final o = LaneGraph.offsetPath(r.pts, 0);
      for (var i = 1; i < o.length; i++) {
        final seg = o[i] - o[i - 1];
        final l = seg.distance;
        if (l < 1e-6) continue;
        final n = Offset(-seg.dy, seg.dx) / l;
        final k = max(1, (l / 4.5).round());
        for (var j = 0; j < k; j++) {
          final c = o[i - 1] + seg * ((j + 0.5) / k);
          ties
            ..add(c - n * 4.2)
            ..add(c + n * 4.2);
        }
      }
      for (final off in const [-2.6, 2.6]) {
        canvas.drawPath(_path(LaneGraph.offsetPath(r.pts, off)), rail);
      }
    } else {
      canvas.drawPath(_path(r.pts), rail);
    }
  }
  if (ties.isNotEmpty) {
    canvas.drawPoints(
      PointMode.lines,
      ties,
      Paint()
        ..strokeWidth = 1.6
        ..color = const Color(0xFF6B5E4B),
    );
  }

  // 4) tunnellar: xira punktir va og'izlari
  final tunnels = [for (final r in all) if (r.cls == RailCls.tunnel && r.pts.length >= 2) r];
  if (tunnels.isNotEmpty) {
    final dashes = <Offset>[];
    for (final r in tunnels) {
      _dash(r.pts, 7, 6, dashes);
    }
    canvas.drawPoints(
      PointMode.lines,
      dashes,
      Paint()
        ..strokeWidth = 2.6
        ..color = const Color(0x77303844),
    );
    final outer = Paint()..color = const Color(0xFF4A4D52);
    final inner = Paint()..color = const Color(0xFF1E2227);
    for (final r in tunnels) {
      for (final end in [true, false]) {
        final p = end ? r.pts.first : r.pts.last;
        final q = end ? r.pts[1] : r.pts[r.pts.length - 2];
        final d = p - q; // tunnel ichidan tashqariga
        final l = d.distance;
        if (l < 1e-6) continue;
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(atan2(d.dy, d.dx));
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-3, -8, 7, 16), const Radius.circular(2)), outer);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-1, -5, 4, 10), const Radius.circular(1.5)), inner);
        canvas.restore();
      }
    }
  }
}

void drawStations(Canvas canvas, RailSim sim) {
  for (final st in sim.stations) {
    var d = const Offset(1, 0);
    final outs = sim.outAt[st.nodeId];
    if (outs != null && outs.isNotEmpty) d = outs.first.track.dirAt(0);
    final n = Offset(-d.dy, d.dx);
    final ang = atan2(d.dy, d.dx);
    final c = st.nodeId == 0 ? st.pos : (sim.net.nodes[st.nodeId]?.pos ?? st.pos);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(ang);
    final plat = Paint()..color = const Color(0xFFD9D5CB);
    final platEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = const Color(0xFF857C69);
    for (final side in const [-1.0, 1.0]) {
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, side * 8.5), width: 84, height: 6), const Radius.circular(1.5));
      canvas.drawRRect(r, plat);
      canvas.drawRRect(r, platEdge);
    }
    final bld = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 21), width: 34, height: 14), const Radius.circular(2.5));
    canvas.drawRRect(bld.shift(const Offset(1.5, 2)), Paint()..color = const Color(0x33000000));
    canvas.drawRRect(bld, Paint()..color = st.active ? const Color(0xFFB5563F) : const Color(0xFF8E8F94));
    canvas.drawRRect(bld.deflate(2.5), Paint()..color = st.active ? const Color(0xFFD9775C) : const Color(0xFFAAABB0));
    canvas.drawRRect(
      bld,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF4A4D52),
    );
    canvas.restore();
    // belgi
    final sign = c - n * 16;
    canvas.drawCircle(sign, 5.2, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(sign, 3.8, Paint()..color = st.active ? const Color(0xFF2E7DB5) : const Color(0xFF9AA0A6));
  }
}

void drawTrains(Canvas canvas, RailSim sim, RailVis vis, double zoom) {
  final k = max(1.0, 2.6 / (RailConst.carLen * zoom * 0.3 + 1e-9)).clamp(1.0, 2.2).toDouble();
  final shadow = Paint()..color = const Color(0x33000000);
  for (final t in sim.trains) {
    var back = 0.0;
    for (var u = 0; u <= RailConst.cars; u++) {
      final len = u == 0 ? RailConst.locoLen : RailConst.carLen;
      final front = sim.poseAt(t, back);
      final rear = sim.poseAt(t, back + len);
      final loc = sim.locate(t, back + len / 2);
      back += len + RailConst.gap;
      final roadLen = max(loc.e.road.length, 1e-6);
      final sRoad = (loc.e.fwd ? loc.pos : loc.e.length - loc.pos) * roadLen / max(loc.e.length, 1e-6);
      if (vis.classAt(loc.e.road.id, sRoad) == RailCls.tunnel) continue; // tunnel ichida ko'rinmaydi
      final c = (front.p + rear.p) / 2;
      final d = front.p - rear.p;
      final ang = d.distance < 1e-6 ? front.a : atan2(d.dy, d.dx);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(ang);
      final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: len, height: 8.2 * k),
        const Radius.circular(2.4),
      );
      canvas.drawRRect(body.shift(const Offset(1.5, 2.2)), shadow);
      canvas.drawRRect(body, Paint()..color = u == 0 ? t.color : const Color(0xFFEDEBE5));
      if (u == 0) {
        canvas.drawRect(Rect.fromLTWH(len / 2 - 8, -3.2 * k, 5, 6.4 * k), Paint()..color = const Color(0x99101820));
      } else {
        final win = Paint()..color = const Color(0xFF55585E);
        for (var i = -2; i <= 2; i++) {
          canvas.drawRect(Rect.fromCenter(center: Offset(i * 3.8, 0), width: 2.3, height: 5.4 * k), win);
        }
        canvas.drawRect(Rect.fromLTWH(-len / 2 + 1, -0.9, len - 2, 1.8), Paint()..color = t.color);
      }
      canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = const Color(0xFF3A3D42),
      );
      canvas.restore();
    }
  }
}
