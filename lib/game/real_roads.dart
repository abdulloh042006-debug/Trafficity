import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

/// Toshkentning haqiqiy yo'li (OpenStreetMap): `tools/map/build_tashkent_roads.py` yaratgan tugunlar orasidagi bo'lak.
class RealRoad {
  RealRoad(this.cls, this.layer, this.oneWay, this.pts, this.cheb);

  final int cls; // 0 trunk, 1 primary, 2 secondary, 3 tertiary, 4 residential
  final int layer; // 0 yer usti, 1 estakada/ko'prik
  final bool oneWay;
  final List<Offset> pts;
  final double cheb; // markazdan Chebyshev masofa (hudud chegarasi bilan solishtirish uchun)

  /// O'yindagi yo'l turi: katta yo'l (2 polosa/yo'nalish) faqat ikki tomonlama trunk/primary uchun;
  /// juft bir tomonlama prospekt yo'llari tor (bir polosa), shunda ikki tomoni bir-birining ustiga tushmaydi.
  int get type => (cls <= 1 && !oneWay) ? 1 : 0;
}

class RealRoads {
  static List<RealRoad>? _cache;

  static Future<List<RealRoad>> load() async {
    final c = _cache;
    if (c != null) return c;
    final raw = jsonDecode(await rootBundle.loadString('assets/map/tashkent_roads.json')) as Map<String, dynamic>;
    final out = <RealRoad>[];
    for (final r in raw['roads'] as List) {
      final f = (r[3] as List).map((e) => (e as num).toDouble()).toList();
      final pts = [for (var i = 0; i + 1 < f.length; i += 2) Offset(f[i], f[i + 1])];
      if (pts.length < 2) continue;
      final mid = pts[pts.length ~/ 2];
      out.add(RealRoad(r[0] as int, r[1] as int, (r[2] as int) == 1, pts, max((mid.dx - 3200).abs(), (mid.dy - 3200).abs())));
    }
    return _cache = out;
  }
}
