import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadflow_city/game/lane_graph.dart';
import 'package:roadflow_city/game/road_network.dart';
import 'package:roadflow_city/game/traffic_model.dart';

List<Offset> line(double x0, double y0, double x1, double y1) =>
    RoadNetwork.sample(Offset(x0, y0), Offset(x1, y1), null);

void main() {
  test('kesishgan yo\'llar chorrahaga bo\'linadi', () {
    final n = RoadNetwork();
    n.connectRoad(line(0, 100, 400, 100));
    n.connectRoad(line(200, 0, 200, 200));
    expect(n.roads.length, 4);
    expect(n.nodes.values.where((x) => x.roads.length == 4).length, 1);
  });

  test('estakada pastdagi yo\'l bilan kesishmaydi', () {
    final n = RoadNetwork();
    n.connectRoad(line(0, 100, 400, 100));
    n.connectRoad(line(200, 0, 200, 200), layer: 1);
    expect(n.roads.length, 2);
    expect(n.nodes.values.where((x) => x.roads.length > 1).length, 0);
  });

  test('juda yaqin tugunlar birlashadi', () {
    final n = RoadNetwork();
    n.connectRoad(line(0, 0, 200, 0));
    n.connectRoad(line(215, 10, 215, 200));
    expect(n.nodes.length, 3);
    expect(n.roads.length, 2);
  });

  test('yo\'l o\'chirilganda yetim tugunlar ham o\'chadi', () {
    final n = RoadNetwork();
    n.connectRoad(line(0, 0, 200, 0));
    n.removeRoad(n.roads.keys.first);
    expect(n.roads, isEmpty);
    expect(n.nodes, isEmpty);
  });

  test('ulangan yo\'llarda marshrut topiladi, uzilganida topilmaydi', () {
    final n = RoadNetwork();
    final a = n.addRoadPts(line(0, 0, 300, 0))!;
    final b = n.addRoadPts(line(300, 0, 300, 300))!;
    final far = n.addRoadPts(line(1000, 1000, 1300, 1000))!;
    final g = LaneGraph(n)..rebuild();
    final start = g.lanes[Lane.idFor(a.id, true, 0)]!;
    final goal = g.lanes[Lane.idFor(b.id, true, 0)]!;
    final route = g.findRoute(start, 10, goal, 100);
    expect(route, isNotNull);
    expect(route!.length, 2);
    final lost = g.lanes[Lane.idFor(far.id, true, 0)]!;
    expect(g.findRoute(start, 10, lost, 100), isNull);
  });

  test('katta yo\'lda har yo\'nalishda 2 polosa bor', () {
    final n = RoadNetwork();
    final r = n.addRoadPts(line(0, 0, 300, 0), type: 1)!;
    final g = LaneGraph(n)..rebuild();
    expect(g.lanesOf(r.id).length, 4);
  });

  test('uchga juda yaqin bo\'linishda yo\'l yo\'qolmaydi', () {
    final n = RoadNetwork();
    n.connectRoad(line(0, 0, 300, 0));
    final id = n.roads.keys.first;
    final before = n.roads.length;
    n.splitRoadAt(id, const Offset(2.5, 0)); // uchdan 2.5 birlik: bo'linmasligi kerak
    expect(n.roads.length, before);
  });

  test('juda qisqa yo\'l tarmoqni o\'zgartirmaydi', () {
    final n = RoadNetwork();
    n.connectRoad(line(0, 0, 300, 0));
    final roads = n.roads.length;
    final nodes = n.nodes.length;
    n.connectRoad([const Offset(150, 0), const Offset(153, 0)]);
    expect(n.roads.length, roads);
    expect(n.nodes.length, nodes);
  });

  double angDiff(Offset p, Offset q) {
    final d = (atan2(p.dy, p.dx) - atan2(q.dy, q.dx)).abs();
    return d > pi ? 2 * pi - d : d;
  }

  test('chorrahadagi burilishlar silliq: boshi/oxiri polosa yo\'nalishiga mos, halqa yo\'q', () {
    final n = RoadNetwork();
    n.connectRoad(line(0, 200, 400, 200));
    n.connectRoad(line(200, 0, 200, 400));
    final g = LaneGraph(n)..rebuild();
    final node = n.nodes.values.firstWhere((x) => x.roads.length == 4);
    var count = 0;
    for (final a in g.incoming[node.id]!) {
      for (final b in g.outgoing[node.id]!) {
        if (a.roadId == b.roadId) continue; // U-burilish
        final c = g.connector(a, b);
        count++;
        final dA = a.dirAt(a.length), dB = b.dirAt(0);
        expect(angDiff(c.dirAt(0), dA), lessThan(0.35), reason: 'boshi ${a.id}->${b.id}');
        expect(angDiff(c.dirAt(c.length), dB), lessThan(0.35), reason: 'oxiri ${a.id}->${b.id}');
        var rot = 0.0;
        for (var i = 2; i < c.pts.length; i++) {
          rot += angDiff(c.pts[i] - c.pts[i - 1], c.pts[i - 1] - c.pts[i - 2]);
        }
        expect(rot, lessThan(angDiff(dA, dB) + 0.3), reason: 'halqa ${a.id}->${b.id}');
      }
    }
    expect(count, 12);
  });

  test('polosa chorraha oldida to\'xtash chizig\'igacha qisqaradi, tupikda esa kesilmaydi', () {
    final n = RoadNetwork();
    n.connectRoad(line(0, 200, 400, 200));
    n.connectRoad(line(200, 0, 200, 400));
    final g = LaneGraph(n)..rebuild();
    final node = n.nodes.values.firstWhere((x) => x.roads.length == 4);
    final dead = n.nodes.values.firstWhere((x) => x.roads.length == 1);
    for (final l in g.lanes.values) {
      if (l.toNode == node.id) expect(l.trimB, greaterThan(5));
      if (l.toNode == dead.id) expect(l.trimB, 0);
      expect((l.pts.last - n.nodes[l.toNode]!.pos).distance, l.toNode == node.id ? greaterThan(8) : lessThan(8));
    }
  });
}
