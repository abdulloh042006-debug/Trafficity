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
}
