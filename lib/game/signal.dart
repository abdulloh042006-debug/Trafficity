import 'dart:math';

import 'traffic_model.dart';

/// Qat'iy vaqtli svetofor. Fazalar: bir o'qdagi (qarama-qarshi) yo'nalishlar
/// birgalikda yashil yonadi, boshqa o'qlar kutadi.
class Signal {
  Signal(this.nodeId);

  final int nodeId;
  double green = 12;
  double amber = 2;
  double allRed = 1; // tozalash oralig'i
  double t = 0;

  List<Lane> incoming = [];
  List<List<int>> phases = [];
  final Map<int, int> laneToPhase = {};

  double get phaseLen => green + amber + allRed;
  double get cycle => phases.length * phaseLen;
  int get activePhase => phases.isEmpty ? 0 : min(phases.length - 1, t ~/ phaseLen);

  /// 0 yashil, 1 sariq, 2 qizil
  int stateOf(int phase) {
    if (phases.length < 2) return 0;
    final ap = activePhase;
    if (phase != ap) return 2;
    final local = t - ap * phaseLen;
    if (local < green) return 0;
    if (local < green + amber) return 1;
    return 2;
  }

  int stateOfLane(int laneId) {
    final p = laneToPhase[laneId];
    return p == null ? 0 : stateOf(p);
  }

  void tick(double dt) {
    if (phases.length < 2) return;
    t += dt;
    final c = cycle;
    if (t >= c) t -= c;
  }

  double _axis(Lane l) {
    final d = l.dirAt(l.length);
    var a = atan2(d.dy, d.dx);
    if (a < 0) a += pi;
    if (a >= pi) a -= pi;
    return a;
  }

  void rebuild(List<Lane> lanes) {
    incoming = lanes;
    final items = [for (final l in lanes) MapEntry(l, _axis(l))];
    items.sort((a, b) => a.value.compareTo(b.value));
    final clusters = <List<MapEntry<Lane, double>>>[];
    for (final e in items) {
      if (clusters.isEmpty || e.value - clusters.last.first.value > 0.5) {
        clusters.add([e]);
      } else {
        clusters.last.add(e);
      }
    }
    if (clusters.length > 1 &&
        (clusters.first.first.value + pi - clusters.last.last.value) < 0.5) {
      clusters.first.addAll(clusters.removeLast());
    }
    phases = [
      for (final c in clusters) [for (final e in c) e.key.id]
    ];
    laneToPhase.clear();
    for (var i = 0; i < phases.length; i++) {
      for (final id in phases[i]) {
        laneToPhase[id] = i;
      }
    }
    if (t >= cycle) t = 0;
  }
}
