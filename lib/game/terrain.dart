import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;

/// Seed asosida deterministik relyef. Balandlik funksiyasi uzluksiz,
/// shuning uchun suv tekshiruvi va rasm bir xil formuladan foydalanadi.
class Terrain {
  Terrain(this.seed, [this.biome = 0]);

  final int seed;
  final int biome; // 0 tekislik, 1 daryo deltasi, 2 tog' vodiysi, 3 orollar
  static const double worldSize = 3200;
  static const double waterLevel = 0.30;

  double _hash(int x, int y) {
    var n = x * 374761393 + y * 668265263 + seed * 1442695041;
    n = (n ^ (n >> 13)) * 1274126177;
    n = n ^ (n >> 16);
    return (n & 0xffff) / 65535.0;
  }

  double _noise(double x, double y) {
    final xi = x.floor(), yi = y.floor();
    final xf = x - xi, yf = y - yi;
    final u = xf * xf * (3 - 2 * xf);
    final v = yf * yf * (3 - 2 * yf);
    final a = _hash(xi, yi);
    final b = _hash(xi + 1, yi);
    final c = _hash(xi, yi + 1);
    final d = _hash(xi + 1, yi + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }

  double _fbm(double x, double y) {
    var sum = 0.0, amp = 0.5, f = 1.0, norm = 0.0;
    for (var i = 0; i < 4; i++) {
      sum += _noise(x * f, y * f) * amp;
      norm += amp;
      amp *= 0.5;
      f *= 2;
    }
    return sum / norm;
  }

  double heightAt(double wx, double wy) {
    final nx = wx / worldSize, ny = wy / worldSize;
    if (nx < 0 || ny < 0 || nx > 1 || ny > 1) return -1;
    final dx = nx - 0.5, dy = ny - 0.5;
    final d = sqrt(dx * dx + dy * dy) * 2;
    switch (biome) {
      case 1: // daryo deltasi: egri-bugri daryolar
        var n = (_fbm(nx * 5, ny * 5) - 0.5) * 1.6 + 0.5;
        final r = (_fbm(nx * 3 + 9.1, ny * 3 + 4.7) - 0.5).abs();
        if (r < 0.04) n -= 0.4 * (1 - r / 0.04);
        return n - 0.40 * d * d * d;
      case 2: // tog' vodiysi: ko'p qiyalik, tor tekis joylar
        final n = (_fbm(nx * 5, ny * 5) - 0.5) * 2.3 + 0.58;
        return n - 0.30 * d * d * d;
      case 3: // orollar
        final n = (_fbm(nx * 6.5, ny * 6.5) - 0.5) * 1.8 + 0.42;
        return n - 0.55 * d * d;
      default:
        final n = (_fbm(nx * 5, ny * 5) - 0.5) * 1.6 + 0.5;
        return n - 0.45 * d * d * d;
    }
  }

  bool isWaterAt(ui.Offset p) => heightAt(p.dx, p.dy) < waterLevel;

  /// Bino qurish uchun yaroqli joy (suv ham, tog' ham emas).
  bool isBuildableAt(ui.Offset p) {
    final h = heightAt(p.dx, p.dy);
    return h > 0.34 && h < 0.68;
  }

  static const _deep = [157, 191, 227];
  static const _shallow = [183, 211, 238];
  static const _sand = [237, 226, 176];
  static const _grassA = [201, 217, 143];
  static const _grassB = [181, 204, 126];
  static const _hill = [150, 176, 120];
  static const _rock = [154, 159, 138];

  List<int> _mix(List<int> a, List<int> b, double t) {
    t = t.clamp(0.0, 1.0);
    return [
      (a[0] + (b[0] - a[0]) * t).round(),
      (a[1] + (b[1] - a[1]) * t).round(),
      (a[2] + (b[2] - a[2]) * t).round(),
    ];
  }

  List<int> _colorAt(double h) {
    if (h < 0.22) return _deep;
    if (h < waterLevel) return _mix(_deep, _shallow, (h - 0.22) / 0.08);
    if (h < 0.33) return _mix(_sand, _grassA, (h - waterLevel) / 0.03);
    if (h < 0.55) return _mix(_grassA, _grassB, (h - 0.33) / 0.22);
    if (h < 0.70) return _mix(_grassB, _hill, (h - 0.55) / 0.15);
    return _mix(_hill, _rock, (h - 0.70) / 0.1);
  }

  Uint8List _pixels(int res) {
    final bytes = Uint8List(res * res * 4);
    var i = 0;
    for (var y = 0; y < res; y++) {
      for (var x = 0; x < res; x++) {
        final h = heightAt((x + 0.5) / res * worldSize, (y + 0.5) / res * worldSize);
        final c = _colorAt(h);
        bytes[i++] = c[0];
        bytes[i++] = c[1];
        bytes[i++] = c[2];
        bytes[i++] = 255;
      }
    }
    return bytes;
  }

  /// Hisob alohida isolate'da bajariladi (ekran qotib qolmasligi uchun).
  Future<ui.Image> toImage({int res = 256}) async {
    Uint8List bytes;
    try {
      bytes = await compute(terrainBytes, [seed, res, biome]);
    } catch (_) {
      bytes = _pixels(res);
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, res, res, ui.PixelFormat.rgba8888, done.complete);
    return done.future.timeout(const Duration(seconds: 20));
  }
}

Uint8List terrainBytes(List<int> args) => Terrain(args[0], args[2])._pixels(args[1]);
