import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/road_game.dart';
import '../l10n.dart';
import 'city3d_renderer.dart';
import 'city_buildings.dart';

/// Full-screen 3D view of the running game (Tashkent). It only looks: building and editing stay in the 2D view.
/// The simulation keeps running underneath, so vehicles move.
///
/// One finger: orbit (left/right) and tilt (up/down). Two fingers: zoom, pan and turn.
class City3DView extends StatefulWidget {
  static const Key viewKey = Key('city3d-view');
  static const Key closeKey = Key('city3d-close');

  final RoadGame game;
  final VoidCallback onClose;

  const City3DView({super.key, required this.game, required this.onClose});

  @override
  State<City3DView> createState() => City3DViewState();
}

class City3DViewState extends State<City3DView> with SingleTickerProviderStateMixin {
  late final City3DRenderer renderer = City3DRenderer(widget.game)..syncFrom2D();
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  Duration _last = Duration.zero;
  String? loadError;

  double _startDistance = 0, _startYaw = 0;
  Offset? _lastFocal;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    CityBuildings.load()
        .then((c) {
          if (mounted) setState(() => renderer.city = c);
        })
        .catchError((Object e) {
          if (mounted) setState(() => loadError = '$e');
        });
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _last < const Duration(milliseconds: 33)) return; // ~30 fps is enough for the view
    _last = elapsed;
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _clampTarget() {
    final w = widget.game.worldSize;
    final cam = renderer.cam;
    cam.targetX = cam.targetX.clamp(0.0, w).toDouble();
    cam.targetY = cam.targetY.clamp(0.0, w).toDouble();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startDistance = renderer.cam.distance;
    _startYaw = renderer.cam.yaw;
    _lastFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final cam = renderer.cam;
    if (d.pointerCount >= 2) {
      cam.distance = (_startDistance / math.max(d.scale, 0.05)).toDouble();
      cam.yaw = _startYaw - d.rotation;
      final last = _lastFocal;
      if (last != null) {
        final before = cam.groundAt(last), after = cam.groundAt(d.localFocalPoint);
        if (before != null && after != null) {
          cam.targetX += before.dx - after.dx;
          cam.targetY += before.dy - after.dy;
        }
      }
    } else {
      cam.yaw -= d.focalPointDelta.dx * 0.006;
      cam.pitch += d.focalPointDelta.dy * 0.004;
    }
    _lastFocal = d.localFocalPoint;
    _clampTarget();
    _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    final city = renderer.city;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: CustomPaint(key: City3DView.viewKey, painter: _City3DPainter(renderer, _frame)),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          right: 12,
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  key: City3DView.closeKey,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.map),
                  label: Text(L.t('2D xarita')),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xE6FFFFFF), borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      L.t("1 barmoq: aylantirish va qiyalik · 2 barmoq: yaqinlashtirish, surish, burish"),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF2B2E33)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 8,
          child: SafeArea(
            child: Text(
              '${loadError != null ? '${L.t("Binolar yuklanmadi")} · ' : ''}'
              '${city == null && loadError == null ? '${L.t("Yuklanmoqda...")} · ' : ''}'
              '${L.t("Balandliklar taxminiy")} · ${CityBuildings.attribution}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10, color: Color(0xCC2B2E33)),
            ),
          ),
        ),
      ],
    );
  }
}

class _City3DPainter extends CustomPainter {
  _City3DPainter(this.renderer, Listenable repaint) : super(repaint: repaint);

  final City3DRenderer renderer;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    renderer.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _City3DPainter oldDelegate) => !identical(oldDelegate.renderer, renderer);
}
