import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trafficity/game/lane_graph.dart';
import 'package:trafficity/game/road_network.dart';
import 'package:trafficity/game/traffic_model.dart';
import 'package:trafficity/game/traffic_sim.dart';

List<Offset> line(double x0, double y0, double x1, double y1) =>
    RoadNetwork.sample(Offset(x0, y0), Offset(x1, y1), null);

/// Footprint of a vehicle along its real path (front, rear found by [TrafficSim.rearOf]).
List<Offset> box(TrafficSim sim, Vehicle v) {
  final f = v.track.pointAt(v.s), r = sim.rearOf(v);
  final d = f - r;
  final u = d / max(d.distance, 1e-6), n = Offset(-u.dy, u.dx);
  final c = (f + r) / 2, hl = v.length / 2 - 0.3, hw = v.width / 2 - 0.2;
  return [c + u * hl + n * hw, c - u * hl + n * hw, c - u * hl - n * hw, c + u * hl - n * hw];
}

bool overlap(List<Offset> a, List<Offset> b) {
  for (final poly in [a, b]) {
    for (var i = 0; i < 4; i++) {
      final e = poly[(i + 1) % 4] - poly[i];
      final ax = Offset(-e.dy, e.dx);
      double lo(List<Offset> p) => p.map((q) => q.dx * ax.dx + q.dy * ax.dy).reduce(min);
      double hi(List<Offset> p) => p.map((q) => q.dx * ax.dx + q.dy * ax.dy).reduce(max);
      if (hi(a) < lo(b) || hi(b) < lo(a)) return false;
    }
  }
  return true;
}

Lane laneOf(LaneGraph g, Road r) => g.lanes[Lane.idFor(r.id, true, 0)]!;

Vehicle put(
  TrafficSim sim,
  LaneGraph g,
  int id,
  VType type,
  Lane from,
  double s,
  Lane to,
  double destS, {
  double v0 = 0,
}) {
  final route = g.findRoute(from, s, to, destS)!;
  final v = Vehicle(
    id: id,
    type: type,
    track: from,
    s: s,
    route: route,
    originB: -1,
    destB: -2,
    destS: destS,
    isReturn: true,
    born: 0,
    color: const Color(0xFF888888),
  )..v = v0;
  from.vehicles.add(v);
  from.vehicles.sort((a, b) => a.s.compareTo(b.s));
  sim.vehicles.add(v);
  return v;
}

void main() {
  group('earlier stop line at acute junctions', () {
    test('an acute approach stops earlier; a right-angle approach does not', () {
      final net = RoadNetwork();
      final a = net.addRoadPts(line(0, 0, 300, 0), oneWay: true)!;
      final b = net.addRoadPts(line(0, 70, 300, 0), oneWay: true)!; // ~13° to a
      net.addRoadPts(line(300, 0, 600, 0), oneWay: true);
      final c = net.addRoadPts(line(300, -300, 300, 0), oneWay: true)!; // 90°
      final g = LaneGraph(net)..rebuild();
      expect(laneOf(g, a).stopBack, greaterThan(15));
      expect(laneOf(g, b).stopBack, greaterThan(15));
      // c meets a, b and the exit at about 90°, but the acute pair a/b makes the node itself acute only for them
      expect(laneOf(g, c).stopBack, lessThan(laneOf(g, a).stopBack));
    });

    test('vehicles waiting on two acute approaches do not overlap', () {
      final net = RoadNetwork();
      final a = net.addRoadPts(line(0, 0, 300, 0), oneWay: true)!;
      final b = net.addRoadPts(line(0, 70, 300, 0), oneWay: true)!;
      final out = net.addRoadPts(line(300, 0, 600, 0), oneWay: true)!;
      final g = LaneGraph(net)..rebuild();
      final sim = TrafficSim(g, [], 1)..accidentsEnabled = false;
      final la = laneOf(g, a), lb = laneOf(g, b), lo = laneOf(g, out);
      // the exit is blocked right at its start, so both approaches have to wait at their stop lines
      final blocker = put(sim, g, 1, VType.truck, lo, 23, lo, 200)..crashed = true;
      blocker.crashT = 1e9;
      final va = put(sim, g, 2, VType.car, la, la.length - 60, lo, 200, v0: 10);
      final vb = put(sim, g, 3, VType.truck, lb, lb.length - 60, lo, 200, v0: 10);
      for (var i = 0; i < 400; i++) {
        sim.step(0.05);
        expect(overlap(box(sim, va), box(sim, vb)), isFalse, reason: 'step $i');
      }
      expect(va.v, lessThan(0.5));
      expect(vb.v, lessThan(0.5));
    });
  });

  group('vehicles on other roads ahead', () {
    // two roads that share a corridor (lanes 2 m apart), joined only at their end: the real-map artefact
    ({RoadNetwork net, LaneGraph g, Lane a, Lane b}) corridor() {
      final net = RoadNetwork();
      final ra = net.addRoadPts(line(0, 0, 400, 0), oneWay: true)!;
      final rb = net.addRoadPts(line(50, 2, 400, 2), oneWay: true)!;
      final g = LaneGraph(net)..rebuild();
      return (net: net, g: g, a: laneOf(g, ra), b: laneOf(g, rb));
    }

    test('a vehicle brakes for a crashed vehicle on the other road and never drives into it', () {
      final c = corridor();
      final sim = TrafficSim(c.g, [], 1)..accidentsEnabled = false;
      final obstacle = put(sim, c.g, 1, VType.car, c.b, 120, c.b, 300)..crashed = true;
      obstacle.crashT = 1e9;
      final follower = put(sim, c.g, 2, VType.car, c.a, 40, c.a, 380, v0: 12);
      for (var i = 0; i < 600; i++) {
        sim.step(0.05);
        expect(overlap(box(sim, follower), box(sim, obstacle)), isFalse, reason: 'step $i');
      }
      expect(follower.v, lessThan(0.5));
    });

    test('a late emergency stop can cause an accident; the wreck is towed after the clear time', () {
      final c = corridor();
      final sim = TrafficSim(c.g, [], 1)..accidentChance = 1.0;
      final slow = put(sim, c.g, 1, VType.car, c.b, 150, c.b, 330);
      // fast car 14 m behind the stopped one: needs far more than a comfortable stop
      final fast = put(sim, c.g, 2, VType.car, c.a, 177, c.a, 390, v0: 20);
      sim.step(0.05);
      expect(sim.accidents, 1);
      expect(fast.crashed && slow.crashed, isTrue);
      expect(sim.accidentLog, hasLength(1));
      for (var i = 0; i < (TrafficSim.accidentClearTime / 0.05).ceil() + 5; i++) {
        sim.step(0.05);
        if (!fast.removed) expect(fast.v, 0);
      }
      expect(fast.removed && slow.removed, isTrue);
      expect(sim.towed, 2);
      expect(sim.accidentLog, isEmpty);
    });

    test('accidents can be switched off', () {
      final c = corridor();
      final sim = TrafficSim(c.g, [], 1)
        ..accidentChance = 1.0
        ..accidentsEnabled = false;
      put(sim, c.g, 1, VType.car, c.b, 150, c.b, 330);
      put(sim, c.g, 2, VType.car, c.a, 177, c.a, 390, v0: 20);
      for (var i = 0; i < 100; i++) {
        sim.step(0.05);
      }
      expect(sim.accidents, 0);
    });
  });

  test('the rear of a vehicle that just entered a lane lies on the junction behind it', () {
    final net = RoadNetwork();
    net.connectRoad(line(0, 0, 300, 0));
    net.connectRoad(line(300, 0, 300, 300));
    final g = LaneGraph(net)..rebuild();
    final sim = TrafficSim(g, [], 1);
    final first = g.lanes.values.firstWhere((l) => l.pointAt(0).dx < 50 && l.pointAt(l.length).dx > 250);
    final second = g.lanes.values.firstWhere((l) => l.pointAt(0).dy < 50 && l.pointAt(l.length).dy > 250);
    final v = put(sim, g, 1, VType.truck, first, 30, second, 250);
    // move it onto the second lane, 5 m in
    first.vehicles.remove(v);
    v
      ..routeIdx = 1
      ..track = second
      ..s = 5;
    second.vehicles.add(v);
    final conn = g.connector(first, second); // created on demand while driving
    final rear = sim.rearOf(v);
    // the rear is 22 m back along the path: 5 m on this lane, the rest on the connector (or the lane before it)
    expect((rear - second.pointAt(0)).distance, greaterThan(3));
    final onConn = [for (var s = 0.0; s <= conn.length; s += 0.5) (conn.pointAt(s) - rear).distance].reduce(min);
    final onFirst = [for (var s = 0.0; s <= first.length; s += 0.5) (first.pointAt(s) - rear).distance].reduce(min);
    expect(min(onConn, onFirst), lessThan(0.6));
  });
}
