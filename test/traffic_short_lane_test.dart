import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/game/lane_graph.dart';
import 'package:trafficity/game/road_network.dart';
import 'package:trafficity/game/traffic_model.dart';
import 'package:trafficity/game/traffic_sim.dart';

List<Offset> line(double x0, double y0, double x1, double y1) =>
    RoadNetwork.sample(Offset(x0, y0), Offset(x1, y1), null);

/// Regression for the truck that froze next to Amir Temur xiyoboni (owner's phone screenshot): a vehicle longer than
/// the lane it is on could never release the junction it came through, so it never asked for the next one.
void main() {
  ({TrafficSim sim, LaneGraph graph, Lane first, Lane short, Lane last}) corridor(double shortLen) {
    final net = RoadNetwork();
    // a side road at each end of the short piece makes both ends real junctions (as in the city centre)
    net.connectRoad(line(0, 0, 300, 0));
    net.connectRoad(line(300, 0, 300 + shortLen, 0));
    net.connectRoad(line(300 + shortLen, 0, 700 + shortLen, 0));
    net.connectRoad(line(300, 0, 300, 200));
    net.connectRoad(line(300 + shortLen, 0, 300 + shortLen, -200));
    final graph = LaneGraph(net)..rebuild();
    Lane? first, short, last;
    for (final l in graph.lanes.values) {
      final a = l.pointAt(0), b = l.pointAt(l.length);
      if (b.dx <= a.dx || (a.dy - b.dy).abs() > 1) continue; // eastbound, horizontal lanes only
      if (a.dx < 100) first = l;
      if (a.dx > 290 && b.dx < 300 + shortLen + 10) short = l;
      if (b.dx > 600) last = l;
    }
    return (sim: TrafficSim(graph, [], 1), graph: graph, first: first!, short: short!, last: last!);
  }

  Vehicle put(TrafficSim sim, LaneGraph graph, VType type, Lane from, Lane to) {
    final route = graph.findRoute(from, 30, to, to.length - 20)!;
    final v = Vehicle(
      id: 1,
      type: type,
      track: from,
      s: 30,
      route: route,
      originB: -1,
      destB: -2,
      destS: to.length - 20,
      isReturn: true,
      born: 0,
      color: const Color(0xFF888888),
    )..v = 4;
    from.vehicles.add(v);
    sim.vehicles.add(v);
    return v;
  }

  for (final type in VType.values) {
    test('a ${type.name} crosses a lane that is shorter than itself and arrives', () {
      final c = corridor(40);
      expect(c.short.length, lessThan(22 + 1), reason: 'the middle lane must be shorter than a truck + 1 m');
      final v = put(c.sim, c.graph, type, c.first, c.last);
      var t = 0.0;
      while (!v.removed && t < 120) {
        c.sim.step(0.05);
        t += 0.05;
      }
      expect(v.removed, isTrue, reason: '${type.name} still on ${v.track.runtimeType} s=${v.s} after ${t.round()} s');
      expect(c.sim.completed, 1);
      expect(c.sim.lost, 0);
    });
  }

  test('the junction hold is released, so a crossing vehicle is not blocked forever', () {
    final c = corridor(40);
    final v = put(c.sim, c.graph, VType.truck, c.first, c.last);
    var t = 0.0;
    while (!v.removed && t < 120) {
      c.sim.step(0.05);
      t += 0.05;
      if (v.track == c.last) expect(v.holdConn == null || v.holdConn!.to.id == c.last.id, isTrue);
    }
    expect(v.holdConn, isNull);
  });
}
