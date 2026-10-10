import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/road_game.dart';
import 'l10n.dart';

/// Oxirgi xatoni ekranda ko'rsatish uchun (release rejimida xatolar sezilmay qolmasligi uchun).
class AppErr {
  static String? last;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (d) => AppErr.last = d.exceptionAsString();
  PlatformDispatcher.instance.onError = (e, s) {
    AppErr.last = '$e';
    return true;
  };
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
    // yuklashni birinchi kadrdan keyin boshlaymiz: ekran darhol chiqadi, xatolar ko'rinadi
    WidgetsBinding.instance.addPostFrameCallback((_) => game.newMap(game.seed));
    SharedPreferences.getInstance().then((p) {
      final v = p.getInt('lang');
      if (v != null && v >= 0 && v < 3 && mounted) {
        setState(() => L.lang = v);
        game.hud.value++;
      }
    }).catchError((_) {});
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
      ..showSnackBar(SnackBar(content: Text(L.t(text)), duration: const Duration(seconds: 2)));
  }

  Future<void> _newGameDialog() async {
    var biome = game.biome, diff = game.difficulty, sbx = game.sandbox;
    final seedCtl = TextEditingController(text: Random().nextInt(100000).toString());
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Widget chips(List<String> names, int sel, void Function(int) on) => Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < names.length; i++)
                  ChoiceChip(
                    label: Text(L.t(names[i])),
                    selected: sel == i,
                    onSelected: (_) => setS(() => on(i)),
                  ),
              ],
            );
        return AlertDialog(
          title: Text(L.t("Yangi o'yin")),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t("Biom")),
                chips(const ["Tekislik", "Daryo deltasi", "Tog' vodiysi", "Orollar"], biome, (i) => biome = i),
                const SizedBox(height: 12),
                Text(L.t("Qiyinlik")),
                chips(const ["Oson", "Oddiy", "Qiyin"], diff, (i) => diff = i),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L.t("Sandbox (cheksiz mablag')")),
                  value: sbx,
                  onChanged: (v) => setS(() => sbx = v),
                ),
                TextField(
                  controller: seedCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Seed"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t("Bekor"))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(L.t("Boshlash"))),
          ],
        );
      }),
    );
    if (go == true) {
      game.newMap(int.tryParse(seedCtl.text) ?? Random().nextInt(100000),
          biome: biome, difficulty: diff, sandbox: sbx);
    }
  }

  String _hint() {
    switch (game.tool) {
      case Tool.pan:
        return "Xaritani suring; 2 barmoq bilan kattalashtiring va buring";
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
      case Tool.building:
        return "Bo'sh joyga bosing: bino qo'yiladi";
      case Tool.inspect:
        return "Mashina, yo'l yoki chorrahaga bosing: ma'lumot chiqadi";
      case Tool.erase:
        return "Yo'lga tegib o'chiring (pul to'liq qaytadi)";
    }
  }

  @override
  Widget build(BuildContext context) {
    game.dpr = MediaQuery.of(context).devicePixelRatio;
    return Scaffold(
      body: Stack(
        children: [
          LayoutBuilder(builder: (context, c) {
            game.widgetSize = Size(c.maxWidth, c.maxHeight);
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                game.lastGlobal = e.position;
                game.pointerDown(e.pointer, e.localPosition);
              },
              onPointerMove: (e) {
                game.lastGlobal = e.position;
                game.pointerMove(e.pointer, e.localPosition);
              },
              onPointerUp: (e) => game.pointerUp(e.pointer),
              onPointerCancel: (e) => game.pointerUp(e.pointer),
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) game.wheel(e.localPosition, e.scrollDelta.dy);
              },
              child: GameWidget(game: game),
            );
          }),
          Positioned.fill(
            child: SafeArea(
              child: ValueListenableBuilder<int>(
                valueListenable: game.hud,
                builder: (context, _, __) {
                  final plan = game.currentPlan;
                  return Stack(
                    children: [
                      Align(alignment: Alignment.topCenter, child: _topBar(plan)),
                      if (game.showCharts && !game.loading)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(padding: const EdgeInsets.only(bottom: 100), child: _chartPanel()),
                        ),
                      Align(alignment: Alignment.bottomCenter, child: _bottomBar()),
                      if (game.loading)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (game.loadError == null) const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              _chip(
                                game.loadError == null ? game.loadStatus : "Xato: ${game.loadError}",
                                color: game.loadError == null ? null : const Color(0xFFC0392B),
                              ),
                              if (game.loadError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: _btn(Icons.refresh, "Qayta urinish", () => game.newMap(game.seed)),
                                ),
                            ],
                          ),
                        ),
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

  Widget _chartPanel() {
    Widget row(String label, List<double> data, Color color, String Function(double) fmt) {
      final cur = data.isEmpty ? 0.0 : data.last;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 128,
              child: Text(L.t("$label: ${fmt(cur)}"),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: SizedBox(height: 30, child: CustomPaint(painter: _SparkPainter(data, color))),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row("Mashinalar", game.histVeh, const Color(0xFF5B8DD6), (v) => v.round().toString()),
          row("Mamnuniyat", game.histSat, const Color(0xFF3DBE5A), (v) => "${v.round()}%"),
          row("Safar vaqti", game.histTrip, const Color(0xFFE8873A), (v) => "${v.round()} s"),
          row("Tirband yo'llar", game.histCong, const Color(0xFFD64541), (v) => "${v.round()}%"),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: game.focusBottleneck,
              icon: const Icon(Icons.my_location, size: 18),
              label: Text(L.t("Eng og'ir joyni ko'rsat")),
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
        L.t(text),
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
              _chip(game.sandbox ? "Sandbox: cheksiz mablag'" : "Mablag': ${game.budget.round()}"),
              _chip("Yo'llar: ${game.net.roads.length}"),
              _chip("Daraja: ${game.level}"),
              _chip("Ekologiya: ${(game.env * 100).round()}%"),
              _chip(
                "Mamnuniyat: ${game.satisfaction.round()}/${game.satTarget.round()}"
                "${game.levelTimer > 0 ? '  (${game.levelTimer.round()}/${RoadGame.levelNeedSeconds.round()} s)' : ''}",
                color: game.satisfaction >= game.satTarget ? const Color(0xFF2E8B3E) : null,
              ),
              if (sim != null) ...[
                _chip("Mashina: ${sim.vehicles.length}"),
                _chip("Yetib bordi: ${sim.completed}"),
                _chip("O'rtacha: ${sim.avgTrip.round()} s"),
                if (sim.failed > 0)
                  _chip("Yo'l topilmadi: ${sim.failed}", color: const Color(0xFFC0392B)),
                if (sim.lost > 0) _chip("Yo'qotilgan: ${sim.lost}"),
              ],
            ],
          ),
          if (game.debug) ...[
            _chip(game.debugText()),
            const SizedBox(height: 6),
          ],
          if (AppErr.last != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => AppErr.last = null,
              child: _chip(
                "Xato: ${AppErr.last!.length > 160 ? AppErr.last!.substring(0, 160) : AppErr.last}",
                color: const Color(0xFFC0392B),
              ),
            ),
          ],
          if (game.tutorial && !game.loading && game.tutStep < RoadGame.tutorialTexts.length) ...[
            const SizedBox(height: 6),
            _chip(
              "Vazifa ${game.tutStep + 1}/${RoadGame.tutorialTexts.length}: ${RoadGame.tutorialTexts[game.tutStep]}",
              color: const Color(0xFF1B6EA0),
            ),
          ],
          if (!game.loading && game.satNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            _chip(game.satNote),
          ],
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
                Text(L.t(label), style: TextStyle(fontSize: 10.5, color: fg)),
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
            if (game.rot.abs() > 0.01) _btn(Icons.explore, "Shimol", game.resetRotation),
            _btn(Icons.horizontal_rule, "To'g'ri", () => game.setTool(Tool.straight),
                selected: game.tool == Tool.straight),
            _btn(Icons.gesture, "Egri", () => game.setTool(Tool.curve), selected: game.tool == Tool.curve),
            _btn(Icons.traffic, "Svetofor", () => game.setTool(Tool.signal),
                selected: game.tool == Tool.signal),
            _btn(Icons.trip_origin, "Aylana", () => game.setTool(Tool.roundabout),
                selected: game.tool == Tool.roundabout),
            _btn(Icons.delete_outline, "O'chirish", () => game.setTool(Tool.erase),
                selected: game.tool == Tool.erase),
            _btn(Icons.info_outline, "Ma'lumot", () => game.setTool(Tool.inspect),
                selected: game.tool == Tool.inspect),
            _btn(Icons.alt_route, game.roadType == 1 ? "Katta yo'l" : "Oddiy yo'l", game.cycleRoadType),
            _btn(Icons.layers, game.roadLayer == 1 ? "Estakada" : "Yer usti", game.cycleRoadLayer, selected: game.roadLayer == 1),
            if (game.sandbox) ...[
              _btn(Icons.home_work, ["Uy", "Do'kon", "Zavod"][game.buildType], () {
                if (game.tool == Tool.building) {
                  game.cycleBuildType();
                } else {
                  game.setTool(Tool.building);
                }
              }, selected: game.tool == Tool.building),
              _btn(Icons.groups, "Talab x${game.demand}", game.cycleDemand),
            ],
            if (game.stage != 0) _btn(Icons.close, "Bekor", game.cancel),
            if (game.tutorial) _btn(Icons.school, "O'tkazish", game.skipTutorial),
            _btn(game.speed == 0 ? Icons.pause : Icons.speed, speedLabel, game.cycleSpeed),
            _btn(Icons.local_fire_department, "Tirbandlik", game.toggleHeat, selected: game.heat),
            _btn(Icons.show_chart, "Grafik", game.toggleCharts, selected: game.showCharts),
            _btn(Icons.eco, "Ekologiya", game.toggleEnv, selected: game.showEnv),
            _btn(Icons.bug_report, "Debug", game.toggleDebug, selected: game.debug),
            _btn(Icons.save_outlined, "Saqlash", () async {
              final ok = await game.save();
              _toast(ok ? "Saqlandi" : "Saqlab bo'lmadi");
            }),
            _btn(Icons.folder_open, "Yuklash", () async {
              final ok = await game.load();
              _toast(ok ? "Yuklandi" : "Saqlangan o'yin topilmadi");
            }),
            _btn(Icons.language, ["UZ", "RU", "EN"][L.lang], () async {
              L.lang = (L.lang + 1) % 3;
              setState(() {});
              game.hud.value++;
              try {
                final p = await SharedPreferences.getInstance();
                await p.setInt('lang', L.lang);
              } catch (_) {}
            }),
            _btn(Icons.refresh, "Yangi", _newGameDialog),
          ],
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.data, this.color);

  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    var hi = 1.0;
    for (final v in data) {
      if (v > hi) hi = v;
    }
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = size.height - size.height * (data[i] / hi).clamp(0.0, 1.0).toDouble();
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}
