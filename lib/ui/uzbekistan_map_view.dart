import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../world/region_borders.dart';

/// One region as the map needs it: id, display name, label/marker anchor (`Offset(lon, lat)`) and whether it
/// has a detailed (playable) package.
class MapRegionInfo {
  final String id;
  final String name;
  final Offset anchor;
  final bool detailed;
  const MapRegionInfo({required this.id, required this.name, required this.anchor, required this.detailed});
}

/// Maps drawing-plane coordinates of [RegionBorders.project] into widget pixels (uniform scale, centred).
class MapFit {
  final double scale;
  final Offset offset; // widget px of plane point (0, 0)

  const MapFit(this.scale, this.offset);

  static const double padding = 10;

  factory MapFit.of(Rect lonLatBounds, Size size) {
    // lon/lat bounds store the minimum latitude in `top`, so (left, bottom) is the north-west corner
    final a = RegionBorders.project(lonLatBounds.left, lonLatBounds.bottom);
    final b = RegionBorders.project(lonLatBounds.right, lonLatBounds.top);
    final plane = Rect.fromPoints(a, b);
    final sx = (size.width - 2 * padding) / plane.width;
    final sy = (size.height - 2 * padding) / plane.height;
    final s = math.max(0.0001, math.min(sx, sy));
    final ox = (size.width - plane.width * s) / 2 - plane.left * s;
    final oy = (size.height - plane.height * s) / 2 - plane.top * s;
    return MapFit(s, Offset(ox, oy));
  }

  Offset toPx(double lon, double lat) {
    final p = RegionBorders.project(lon, lat);
    return Offset(p.dx * scale + offset.dx, p.dy * scale + offset.dy);
  }

  /// Widget px -> (lon, lat) as `Offset(lon, lat)`.
  Offset toLonLat(Offset px) =>
      RegionBorders.unproject(Offset((px.dx - offset.dx) / scale, (px.dy - offset.dy) / scale));
}

/// Pannable, zoomable 2D map of the 14 divisions. Tapping a region (or the green marker of a region that has a
/// detailed map) reports its id through [onRegionTap]; with `onRegionTap == null` the map is a static picture.
/// Labels appear only where they fit, so zooming in reveals more names.
class UzbekistanMapView extends StatefulWidget {
  static const Key mapKey = Key('uzbekistan-map');

  final RegionBorders borders;
  final List<MapRegionInfo> regions;
  final String? activeRegionId;
  final ValueChanged<String>? onRegionTap;
  final double maxScale;

  const UzbekistanMapView({
    super.key,
    required this.borders,
    required this.regions,
    this.activeRegionId,
    this.onRegionTap,
    this.maxScale = 14,
  });

  @override
  State<UzbekistanMapView> createState() => _UzbekistanMapViewState();
}

class _UzbekistanMapViewState extends State<UzbekistanMapView> {
  final TransformationController _controller = TransformationController();
  late final List<RegionBorderShape> _drawOrder = [...widget.borders.shapes]
    ..sort((a, b) => b.areaDeg2.compareTo(a.areaDeg2)); // big first, so a city is drawn over its province

  Size _size = Size.zero;
  MapFit? _fit;
  Map<String, Path> _paths = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ensureLayout(Size size) {
    if (size == _size && _fit != null) return;
    _size = size;
    final fit = MapFit.of(widget.borders.bounds, size);
    _fit = fit;
    _paths = {
      for (final s in widget.borders.shapes)
        s.regionId: () {
          final path = Path()..fillType = PathFillType.evenOdd; // holes stay empty
          for (final poly in s.polygons) {
            for (final ring in poly) {
              _addRing(path, ring, fit);
            }
          }
          return path;
        }(),
    };
  }

  static void _addRing(Path path, List<Offset> ring, MapFit fit) {
    for (var i = 0; i < ring.length; i++) {
      final p = fit.toPx(ring[i].dx, ring[i].dy);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
  }

  void _onTap(Offset p) {
    final cb = widget.onRegionTap;
    final fit = _fit;
    if (cb == null || fit == null) return;
    final k = _controller.value.getMaxScaleOnAxis();
    // the marker of a playable region is a finger-sized target that does not shrink when zooming out
    for (final r in widget.regions) {
      if (r.detailed && (fit.toPx(r.anchor.dx, r.anchor.dy) - p).distance <= 16 / k) {
        cb(r.id);
        return;
      }
    }
    final ll = fit.toLonLat(p);
    final id = widget.borders.hitTest(ll.dx, ll.dy);
    if (id != null) cb(id);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth.isFinite ? c.maxWidth : 320, c.maxHeight.isFinite ? c.maxHeight : 200);
        _ensureLayout(size);
        final painter = CustomPaint(
          key: UzbekistanMapView.mapKey,
          size: size,
          painter: _MapPainter(
            controller: _controller,
            fit: _fit!,
            paths: _paths,
            order: _drawOrder,
            borders: widget.borders,
            regions: widget.regions,
            activeId: widget.activeRegionId,
            textStyle: DefaultTextStyle.of(context).style, // theme font, so labels match the rest of the app
          ),
        );
        if (widget.onRegionTap == null)
          return ClipRect(
            child: SizedBox.fromSize(size: size, child: painter),
          );
        return ClipRect(
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 1,
            maxScale: widget.maxScale,
            boundaryMargin: const EdgeInsets.all(60),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _onTap(d.localPosition),
              child: SizedBox.fromSize(size: size, child: painter),
            ),
          ),
        );
      },
    );
  }
}

class _MapPainter extends CustomPainter {
  static const _tints = [Color(0xFFDCE8D2), Color(0xFFE8E2CC), Color(0xFFD5E3EA), Color(0xFFEBD9D2), Color(0xFFE0D8E8)];

  final TransformationController controller;
  final MapFit fit;
  final Map<String, Path> paths;
  final List<RegionBorderShape> order;
  final RegionBorders borders;
  final List<MapRegionInfo> regions;
  final String? activeId;
  final TextStyle textStyle;

  _MapPainter({
    required this.controller,
    required this.fit,
    required this.paths,
    required this.order,
    required this.borders,
    required this.regions,
    required this.activeId,
    required this.textStyle,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final k = controller.value.getMaxScaleOnAxis();
    final byId = {for (final r in regions) r.id: r};
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF2F4F6));

    final index = {for (var i = 0; i < borders.shapes.length; i++) borders.shapes[i].regionId: i};
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF7C8794)
      ..strokeWidth = 0.9 / k;
    for (final s in order) {
      final info = byId[s.regionId];
      final path = paths[s.regionId]!;
      var fill = _tints[(index[s.regionId] ?? 0) % _tints.length];
      if (info?.detailed ?? false) fill = const Color(0xFFBFE0C2);
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(path, line);
    }
    final active = activeId == null ? null : paths[activeId];
    if (active != null) {
      canvas.drawPath(active, Paint()..color = const Color(0xFF2E7DB5).withValues(alpha: 0.28));
      canvas.drawPath(
        active,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF1F5F8F)
          ..strokeWidth = 2.4 / k,
      );
    }

    // markers for regions that have a detailed map (constant on-screen size)
    for (final r in regions) {
      if (!r.detailed) continue;
      final c = fit.toPx(r.anchor.dx, r.anchor.dy);
      canvas.drawCircle(c, 6.5 / k, Paint()..color = Colors.white);
      canvas.drawCircle(c, 4.8 / k, Paint()..color = const Color(0xFF2E8B3E));
    }

    // Labels are laid out at their real size and drawn through the inverse zoom, so the font stays crisp and keeps a
    // constant on-screen size. A label is shown only if it fits inside its region and does not touch a label that is
    // already placed (large regions first), so zooming in reveals more names.
    final placed = <Rect>[];
    for (final s in order) {
      final info = byId[s.regionId];
      if (info == null) continue;
      final isActive = s.regionId == activeId;
      final tp = TextPainter(
        text: TextSpan(
          text: info.name,
          style: textStyle.copyWith(
            fontSize: isActive ? 11 : 9.5,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: const Color(0xFF2B2E33),
            decoration: TextDecoration.none,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final tl = fit.toPx(s.bounds.left, s.bounds.bottom);
      final br = fit.toPx(s.bounds.right, s.bounds.top);
      // a region with a detailed map keeps its label whenever there is room (its marker is always visible)
      if (!info.detailed && tp.width * 1.1 > (br.dx - tl.dx).abs() * k) continue;
      final a = fit.toPx(info.anchor.dx, info.anchor.dy);
      final dy = info.detailed ? 9.0 : 0.0; // keep the label clear of the marker (screen px)
      final box = Rect.fromCenter(
        center: a + Offset(0, dy / k),
        width: tp.width / k,
        height: tp.height / k,
      ).inflate(1 / k);
      if (placed.any(box.overlaps)) continue;
      placed.add(box);
      canvas.save();
      canvas.translate(box.center.dx, box.center.dy);
      canvas.scale(1 / k);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.activeId != activeId ||
      old.textStyle != textStyle ||
      old.fit.scale != fit.scale ||
      old.fit.offset != fit.offset ||
      !identical(old.paths, paths) ||
      !identical(old.regions, regions);
}
