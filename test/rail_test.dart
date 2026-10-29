import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadflow_city/game/rail.dart';
import 'package:roadflow_city/game/road_network.dart';

List<Offset> line(double x0, double y0, double x1, double y1) =>
    RoadNetwork.sample(Offset(x0, y0), Offset(x1, y1), null);

void main() {
  test('ikki stansiya orasida poyezd qatnaydi, uchida teskari yo\'naladi', () {
    final net = RoadNetwork();
    net.connectRoad(line(100, 100, 900, 100));
    final sim = RailSim(net);
    sim.addStation(const Offset(100, 100));
    sim.addStation(const Offset(900, 100));
    var fares = 0.0;
    sim.onFare = (st, f) => fares += f;
    sim.rebuild();
    expect(sim.stations.every((s) => s.active), isTrue);
    expect(sim.trains.length, 1);
    final visited = <int>{};
    var maxX = 0.0, minX = 1e9;
    for (var t = 0.0; t < 240; t += 0.05) {
      sim.step(0.05);
      final p = sim.poseAt(sim.trains.first, 0).p;
      maxX = max(maxX, p.dx);
      minX = min(minX, p.dx);
      for (final s in sim.stations) {
        if (s.visits > 0) visited.add(s.id);
      }
    }
    expect(visited.length, 2);
    expect(sim.trips, greaterThanOrEqualTo(3)); // A -> B -> A -> B
    expect(maxX, greaterThan(895)); // oxirgi stansiyada poyezd old nuqtasi tugunga yetadi
    expect(minX, lessThan(105));
  });

  test('bitta stansiyada poyezd yo\'q; ikkinchisi qo\'shilsa paydo bo\'ladi', () {
    final net = RoadNetwork();
    net.connectRoad(line(100, 100, 700, 100));
    final sim = RailSim(net);
    sim.addStation(const Offset(100, 100));
    sim.rebuild();
    expect(sim.trains, isEmpty);
    expect(sim.stations.first.active, isFalse);
    sim.addStation(const Offset(700, 100));
    sim.rebuild();
    expect(sim.trains, isNotEmpty);
  });

  test('keskin burchakli tarmoqda poyezd yetib bora olmaydi (marshrut yo\'q), qotib qolmaydi', () {
    final net = RoadNetwork();
    net.connectRoad(line(100, 100, 500, 100));
    net.connectRoad(line(500, 100, 500, 500)); // 90 daraja: poyezd o'ta olmaydi
    final sim = RailSim(net);
    sim.addStation(const Offset(100, 100));
    sim.addStation(const Offset(500, 500));
    sim.rebuild();
    for (var t = 0.0; t < 60; t += 0.05) {
      sim.step(0.05);
    }
    expect(sim.trips, 0);
  });

  test('ikki poyezd bir yo\'lda to\'qnashmaydi (masofa saqlanadi)', () {
    final net = RoadNetwork();
    net.connectRoad(line(100, 100, 1500, 100));
    final sim = RailSim(net);
    for (final x in [100.0, 500.0, 900.0, 1500.0]) {
      final p = Offset(x, 100);
      final hit = net.nearestRoadPoint(p, 5);
      if (hit != null) net.splitRoadAt(hit.road.id, p);
      sim.addStation(p);
    }
    sim.rebuild();
    expect(sim.trains.length, 2);
    var minGap = 1e9, minDist = 1e9;
    for (var t = 0.0; t < 600; t += 0.05) {
      sim.step(0.05);
      final a = sim.trains[0], b = sim.trains[1];
      for (var i = 0; i <= 8; i++) {
        for (var j = 0; j <= 8; j++) {
          final d = (sim.poseAt(a, a.length * i / 8).p - sim.poseAt(b, b.length * j / 8).p).distance;
          if (d < minDist) minDist = d;
        }
      }
      if (a.hist.last.key == b.hist.last.key) {
        final front = a.s > b.s ? a : b, rear = a.s > b.s ? b : a;
        minGap = min(minGap, front.s - front.length - rear.s);
      }
    }
    expect(minGap, greaterThan(-1));
    expect(minDist, greaterThan(3.5)); // qarama-qarshi izlar 5.6 oralig'ida: o'tib ketadi, ustma-ust tushmaydi
    expect(sim.trips, greaterThan(4)); // ikkalasi ham qotib qolmadi
  });
}
