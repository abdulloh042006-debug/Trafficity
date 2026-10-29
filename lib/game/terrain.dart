import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

/// Haqiqiy Toshkent xaritasi (OpenStreetMap, markazi: Amir Temur xiyoboni). 1 birlik ~ 1 metr.
/// Asosiy rasm 3200x3200 piksel (2 m/piksel), suv niqobi 1600x1600 (4 m/piksel); dunyo 6400x6400 birlik.
class TashkentMap {
  static const int maskRes = 1600;
  static Uint8List? _mask;

  static Future<void> loadMask() async {
    if (_mask != null) return;
    final data = await rootBundle.load('assets/map/tashkent_water.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final img = (await codec.getNextFrame()).image;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final px = bd!.buffer.asUint8List();
    final m = Uint8List(maskRes * maskRes);
    for (var i = 0; i < m.length; i++) {
      m[i] = px[i * 4] > 127 ? 1 : 0;
    }
    _mask = m;
  }

  static bool isWater(double wx, double wy) {
    final m = _mask;
    if (m == null) return false;
    final x = (wx / Terrain.bigSize * maskRes).floor();
    final y = (wy / Terrain.bigSize * maskRes).floor();
    if (x < 0 || y < 0 || x >= maskRes || y >= maskRes) return false;
    return m[y * maskRes + x] != 0;
  }

  static Future<ui.Image> loadBase(int width) async {
    final data = await rootBundle.load('assets/map/tashkent.webp');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    return (await codec.getNextFrame()).image;
  }
}

/// Seed asosida deterministik relyef. Balandlik funksiyasi uzluksiz,
/// shuning uchun suv tekshiruvi va rasm bir xil formuladan foydalanadi.
class Terrain {
  Terrain(this.seed, [this.biome = 0, this.size = 3200]);

  final int seed;
  final int biome; // 0 tekislik, 1 daryo deltasi, 2 tog' vodiysi, 3 orollar, 4 Toshkent (haqiqiy xarita)
  final double size; // dunyo o'lchami (birlik); eski saqlashlar 3200, yangi o'yinlar 6400
  static const int tashkent = 4;
  static const double legacySize = 3200;
  static const double bigSize = 6400;
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
    final nx = wx / size, ny = wy / size;
    if (nx < 0 || ny < 0 || nx > 1 || ny > 1) return -1;
    if (biome == tashkent) return TashkentMap.isWater(wx, wy) ? 0.2 : 0.5;
    final k = size / legacySize; // yirik dunyoda ham relyef xususiyatlari bir xil o'lchamda
    final dx = nx - 0.5, dy = ny - 0.5;
    final d = sqrt(dx * dx + dy * dy) * 2;
    switch (biome) {
      case 1: // daryo deltasi: egri-bugri daryolar
        var n = (_fbm(nx * 5 * k, ny * 5 * k) - 0.5) * 1.6 + 0.5;
        final r = (_fbm(nx * 3 * k + 9.1, ny * 3 * k + 4.7) - 0.5).abs();
        if (r < 0.04) n -= 0.4 * (1 - r / 0.04);
        return n - 0.40 * d * d * d;
      case 2: // tog' vodiysi: ko'p qiyalik, tor tekis joylar
        final n = (_fbm(nx * 5 * k, ny * 5 * k) - 0.5) * 2.3 + 0.58;
        return n - 0.30 * d * d * d;
      case 3: // orollar
        final n = (_fbm(nx * 6.5 * k, ny * 6.5 * k) - 0.5) * 1.8 + 0.42;
        return n - 0.55 * d * d;
      default:
        final n = (_fbm(nx * 5 * k, ny * 5 * k) - 0.5) * 1.6 + 0.5;
        return n - 0.45 * d * d * d;
    }
  }

  bool isWaterAt(ui.Offset p) => heightAt(p.dx, p.dy) < waterLevel;

  /// Tog' (poyezd tunnel qazishi kerak bo'ladigan joy). Toshkent tekis, u yerda tog' yo'q.
  static const double mountainLevel = 0.64;
  bool isMountainAt(ui.Offset p) => biome != tashkent && heightAt(p.dx, p.dy) >= mountainLevel;

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
        final h = heightAt((x + 0.5) / res * size, (y + 0.5) / res * size);
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
    if (biome == tashkent) {
      await TashkentMap.loadMask();
      return TashkentMap.loadBase(res >= 256 ? 3200 : res);
    }
    if (res == 256 && size > legacySize) res = 512; // yirik dunyo: shu zichlikda (12.5 birlik/piksel)
    Uint8List bytes;
    try {
      bytes = await compute(terrainBytes, [seed, res, biome, size.round()]);
    } catch (_) {
      bytes = _pixels(res);
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, res, res, ui.PixelFormat.rgba8888, done.complete);
    return done.future.timeout(const Duration(seconds: 20));
  }
}

Uint8List terrainBytes(List<int> args) => Terrain(args[0], args[2], args[3].toDouble())._pixels(args[1]);
