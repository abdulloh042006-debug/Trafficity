import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/road_game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);
  runApp(const RoadFlowApp());
}

class RoadFlowApp extends StatelessWidget {
  const RoadFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoadFlow City',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF6E8F5A)),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final RoadGame game = RoadGame();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // faqat yo'l qurilgan bo'lsa avtosaqlaymiz (bo'sh xarita saqlangan o'yinni bosib ketmasin)
    if (state == AppLifecycleState.paused && game.net.roads.isNotEmpty) {
      game.save(auto: true);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  String _hint() {
    switch (game.tool) {
      case Tool.pan:
        return "Xaritani suring, 2 barmoq bilan kattalashtiring";
      case Tool.straight:
        return "Barmoqni bosib sudrang: to'g'ri yo'l shu yerda quriladi";
      case Tool.curve:
        return game.stage >= 2
            ? "Yo'lni egish uchun kerakli joyga barmoqni bosing"
            : "Boshidan oxirigacha sudrang, keyin eging";
      case Tool.signal:
        return "Chorrahaga bosing: svetofor qo'yish, vaqtini o'zgartirish yoki olib tashlash";
      case Tool.roundabout:
        return "Chorrahaga bosing: shu joyda aylana chorraha quriladi";
      case Tool.erase:
        return "Yo'lga tegib o'chiring (pul to'liq qaytadi)";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => game.pointerDown(e.pointer, e.localPosition),
            onPointerMove: (e) => game.pointerMove(e.pointer, e.localPosition),
            onPointerUp: (e) => game.pointerUp(e.pointer),
            onPointerCancel: (e) => game.pointerUp(e.pointer),
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) game.wheel(e.localPosition, e.scrollDelta.dy);
            },
            child: GameWidget(game: game),
          ),
          Positioned.fill(
            child: SafeArea(
              child: ValueListenableBuilder<int>(
                valueListenable: game.hud,
                builder: (context, _, __) {
                  final plan = game.currentPlan;
                  return Stack(
                    children: [
                      Align(alignment: Alignment.topCenter, child: _topBar(plan)),
                      Align(alignment: Alignment.bottomCenter, child: _bottomBar()),
                      if (game.loading) const Center(child: CircularProgressIndicator()),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color ?? const Color(0xFF2B2E33)),
      ),
    );
  }

  Widget _topBar(RoadPlan? plan) {
    final loaded = !game.loading;
    final sim = loaded ? game.sim : null;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _chip("Mablag': ${game.budget.round()}"),
              _chip("Yo'llar: ${game.net.roads.length}"),
              if (sim != null) ...[
                _chip("Mashina: ${sim.vehicles.length}"),
                _chip("Yetib bordi: ${sim.completed}"),
                _chip("O'rtacha: ${sim.avgTrip.round()} s"),
                if (game.noAccess > 0)
                  _chip("Yo'lsiz bino: ${game.noAccess}", color: const Color(0xFFC0392B)),
                if (sim.failed > 0)
                  _chip("Yo'l topilmadi: ${sim.failed}", color: const Color(0xFFC0392B)),
                if (sim.lost > 0) _chip("Yo'qotilgan: ${sim.lost}"),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (plan != null)
            _chip(
              plan.valid ? "${plan.length.round()} m  ·  narx ${plan.cost.round()}" : plan.error!,
              color: plan.valid ? const Color(0xFF1B8FA0) : const Color(0xFFC0392B),
            )
          else
            _chip(game.flash ?? _hint()),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap, {bool selected = false}) {
    final fg = selected ? Colors.white : const Color(0xFF2B2E33);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? const Color(0xFF6E8F5A) : const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: fg),
                Text(label, style: TextStyle(fontSize: 10.5, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final speedLabel = game.speed == 0 ? "Pauza" : "${game.speed}x";
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _btn(Icons.open_with, "Kamera", () => game.setTool(Tool.pan), selected: game.tool == Tool.pan),
            _btn(Icons.horizontal_rule, "To'g'ri", () => game.setTool(Tool.straight),
                selected: game.tool == Tool.straight),
            _btn(Icons.gesture, "Egri", () => game.setTool(Tool.curve), selected: game.tool == Tool.curve),
            _btn(Icons.traffic, "Svetofor", () => game.setTool(Tool.signal),
                selected: game.tool == Tool.signal),
            _btn(Icons.trip_origin, "Aylana", () => game.setTool(Tool.roundabout),
                selected: game.tool == Tool.roundabout),
            _btn(Icons.delete_outline, "O'chirish", () => game.setTool(Tool.erase),
                selected: game.tool == Tool.erase),
            if (game.stage != 0) _btn(Icons.close, "Bekor", game.cancel),
            _btn(game.speed == 0 ? Icons.pause : Icons.speed, speedLabel, game.cycleSpeed),
            _btn(Icons.local_fire_department, "Tirbandlik", game.toggleHeat, selected: game.heat),
            _btn(Icons.save_outlined, "Saqlash", () async {
              final ok = await game.save();
              _toast(ok ? "Saqlandi" : "Saqlab bo'lmadi");
            }),
            _btn(Icons.folder_open, "Yuklash", () async {
              final ok = await game.load();
              _toast(ok ? "Yuklandi" : "Saqlangan o'yin topilmadi");
            }),
            _btn(Icons.refresh, "Yangi", () => game.newMap(Random().nextInt(100000))),
          ],
        ),
      ),
    );
  }
}
