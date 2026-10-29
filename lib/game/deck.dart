import 'dart:math';
import 'dart:ui';

/// Estakada bo'lagi: markaz chizig'i nuqtalari va har nuqtadagi balandlik (0 = yer, 1 = to'liq).
class Deck {
  Deck(this.pts, this.h, this.half, this.capA, this.capB, this.baseA, this.baseB);

  final List<Offset> pts;
  final List<double> h;
  final double half; // yo'lning yarim eni
  final bool capA, capB; // boshqa estakadaga ulangan uchlar (yumaloq birikma kerak)
  final bool baseA, baseB; // yer usti yo'liga tushadigan uchlar

  /// Markaz chizig'i bo'ylab lenta: eni base + grow*h, siljishi lift*h.
  Path ribbon(double base, double grow, Offset lift) {
    final n = pts.length;
    final left = <Offset>[], right = <Offset>[];
    for (var i = 0; i < n; i++) {
      var t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)];
      final l = t.distance;
      t = l < 1e-9 ? const Offset(1, 0) : t / l;
      final nrm = Offset(-t.dy, t.dx);
      final hw = base + grow * h[i];
      final c = pts[i] + lift * h[i];
      left.add(c + nrm * hw);
      right.add(c - nrm * hw);
    }
    final path = Path()..moveTo(left[0].dx, left[0].dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(left[i].dx, left[i].dy);
    }
    for (var i = n - 1; i >= 0; i--) {
      path.lineTo(right[i].dx, right[i].dy);
    }
    path.close();
    return path;
  }
}
