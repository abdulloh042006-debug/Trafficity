import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/road_game.dart';
import 'game/terrain.dart';
import 'l10n.dart';

/// Oxirgi xatoni ekranda ko'rsatish uchun (release rejimida xatolar sezilmay qolmasligi uchun).
class AppErr {
  static String? last;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (d) {
    AppErr.last = d.exceptionAsString();
    FlutterError.presentError(d); // standart hisobot ham saqlanadi
  };
  ui.PlatformDispatcher.instance.onError = (e, s) {
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
  double _uiScale = 1.0;
  bool _menu = true;

  // fon musiqasi (24 soniyalik uzluksiz sokin pad, loyiha ichida yaratilgan)
  final AudioPlayer _music = AudioPlayer();
  bool _musicOn = false;
  bool _musicBusy = false;
  bool _musicFailed = false; // audio ishlamasa qayta urinmaymiz

  Future<void> _syncMusic() async {
    if (_musicBusy || _musicFailed) return;
    final want = game.soundOn;
    if (want == _musicOn) return;
    _musicBusy = true;
    try {
      if (want) {
        await _music.setReleaseMode(ReleaseMode.loop);
        await _music.setVolume(0.3);
        await _music.play(AssetSource('audio/ambient.wav'));
      } else {
        await _music.pause();
      }
      _musicOn = want; // faqat muvaffaqiyatdan keyin
    } catch (_) {
      _musicFailed = true; // audio ishlamasa o'yin davom etadi
    } finally {
      _musicBusy = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    game.menuOpen = true;
    // yuklashni birinchi kadrdan keyin boshlaymiz: ekran darhol chiqadi, xatolar ko'rinadi
    WidgetsBinding.instance
        .addPostFrameCallback((_) => game.newMap(game.seed, ideal: RoadGame.idealCityOnStart));
    SharedPreferences.getInstance().then((p) {
      final sc = p.getDouble('uiScale');
      if (sc != null && sc >= 0.8 && sc <= 1.5 && mounted) setState(() => _uiScale = sc);
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
    _music.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // faqat yo'l qurilgan bo'lsa avtosaqlaymiz (bo'sh xarita saqlangan o'yinni bosib ketmasin)
    if (state == AppLifecycleState.paused) {
      _music.pause();
      _musicOn = false; // qaytganda qayta ishga tushadi
      if (game.net.roads.isNotEmpty) game.save(auto: true);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(L.t(text)), duration: const Duration(seconds: 2)));
  }

  Future<void> _slotsDialog() async {
    final infos = [for (var i = 0; i <= 3; i++) await game.slotInfo(i)];
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t("Slotlar")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i <= 3; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(i == 0 ? L.t("Avtosaqlash") : "Slot $i"),
                subtitle: Text(L.t(infos[i] ?? "Bo'sh"), style: const TextStyle(fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i > 0)
                      IconButton(
                        icon: const Icon(Icons.save),
                        tooltip: L.t("Saqlash"),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final ok = await game.save(slot: i);
                          _toast(ok ? "Saqlandi" : "Saqlab bo'lmadi");
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      tooltip: L.t("Yuklash"),
                      onPressed: infos[i] == null
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              final ok = await game.load(slot: i);
                              _toast(ok ? "Yuklandi" : "Saqlangan o'yin topilmadi");
                              if (ok) _closeMenu();
                            },
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.t("Bekor")))],
      ),
    );
  }

  void _closeMenu() {
    if (!mounted) return;
    setState(() => _menu = false);
    game.menuOpen = false;
    game.hud.value++;
  }

  Future<void> _setLang(int i) async {
    setState(() => L.lang = i);
    game.hud.value++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('lang', i);
    } catch (_) {}
  }

  Future<void> _setScale(double sc) async {
    setState(() => _uiScale = sc);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('uiScale', sc);
    } catch (_) {}
  }

  Future<void> _settingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(L.t("Sozlamalar")),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t("Til")),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 0; i < 3; i++)
                      ChoiceChip(
                        label: Text(["O'zbekcha", "Русский", "English"][i]),
                        selected: L.lang == i,
                        onSelected: (_) async {
                          await _setLang(i);
                          setS(() {});
                        },
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L.t("Ovoz")),
                  value: game.soundOn,
                  onChanged: (_) {
                    game.toggleSound();
                    setS(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L.t("Ranglar")),
                  value: game.colorBlind,
                  onChanged: (_) {
                    game.toggleColorBlind();
                    setS(() {});
                  },
                ),
                Text(L.t("Hajm")),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final sc in const [0.9, 1.0, 1.15, 1.3])
                      ChoiceChip(
                        label: Text("${(sc * 100).round()}%"),
                        selected: _uiScale == sc,
                        onSelected: (_) async {
                          await _setScale(sc);
                          setS(() {});
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.t("Yopish")))],
        ),
      ),
    );
  }

  Widget _menuOverlay() {
    Widget item(IconData icon, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: SizedBox(
            width: 270,
            child: FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon), label: Text(L.t(label))),
          ),
        );
    return Container(
      color: const Color(0xD91F2A22),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "RoadFlow City",
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  L.t("Yo'l qurilishi va transport simulyatsiyasi"),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 22),
                item(Icons.play_arrow, "Davom etish", _closeMenu),
                item(Icons.add_circle_outline, "Yangi o'yin", _newGameDialog),
                item(Icons.school, "O'rgatish", () {
                  game.newMap(7, biome: 0, difficulty: 1, sandbox: false);
                  _closeMenu();
                }),
                item(Icons.construction, "Sandbox", () {
                  game.newMap(Random().nextInt(100000), sandbox: true);
                  _closeMenu();
                }),
                item(Icons.folder_open, "Saqlangan o'yinlar", _slotsDialog),
                item(Icons.settings, "Sozlamalar", _settingsDialog),
                item(Icons.exit_to_app, "Chiqish", () => SystemNavigator.pop()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _newGameDialog() async {
    var biome = game.biome, diff = game.difficulty, sbx = game.sandbox;
    final seedCtl = TextEditingController(text: Random().nextInt(100000).toString());
    ui.Image? preview;
    var req = 0;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        // xarita ko'rinishi: tanlangan seed va biom bo'yicha kichik relyef rasmi
        Future<void> regen() async {
          final my = ++req;
          final sd = int.tryParse(seedCtl.text) ?? 0;
          try {
            final im = await Terrain(sd, biome).toImage(res: 96);
            if (my == req) setS(() => preview = im);
          } catch (_) {}
        }

        if (req == 0) regen();
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
                if (preview != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 120,
                      width: double.infinity,
                      child: RawImage(image: preview, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(L.t("Biom")),
                chips(const ["Tekislik", "Daryo deltasi", "Tog' vodiysi", "Orollar"], biome, (i) {
                  biome = i;
                  regen();
                }),
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
                  onChanged: (_) => regen(),
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
      _closeMenu();
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
      case Tool.grid:
        return "Burchakdan burchakka sudrang: ko'cha to'ri quriladi";
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
                  _syncMusic();
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
          if (_menu) Positioned.fill(child: _menuOverlay()),
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
        style: TextStyle(fontSize: 12 * _uiScale, fontWeight: FontWeight.w600, color: color ?? const Color(0xFF2B2E33)),
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
              _chip("Ta'minot: ${(game.supply * 100).round()}%"),
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
            _chip(game.flash ?? (game.tool == Tool.grid && game.gridInfo.isNotEmpty ? game.gridInfo : _hint())),
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
                Icon(icon, size: 21 * _uiScale, color: fg),
                Text(L.t(label), style: TextStyle(fontSize: 10.5 * _uiScale, color: fg)),
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
            _btn(Icons.menu, "Menyu", () {
              setState(() => _menu = true);
              game.menuOpen = true;
            }),
            _btn(Icons.open_with, "Kamera", () => game.setTool(Tool.pan), selected: game.tool == Tool.pan),
            if (game.rot.abs() > 0.01) _btn(Icons.explore, "Shimol", game.resetRotation),
            if (game.canUndo) _btn(Icons.undo, "Ortga", game.undo),
            if (game.canRedo) _btn(Icons.redo, "Oldinga", game.redo),
            _btn(Icons.horizontal_rule, "To'g'ri", () => game.setTool(Tool.straight),
                selected: game.tool == Tool.straight),
            _btn(Icons.gesture, "Egri", () => game.setTool(Tool.curve), selected: game.tool == Tool.curve),
            _btn(Icons.grid_on, "To'r", () => game.setTool(Tool.grid), selected: game.tool == Tool.grid),
            if (game.tool == Tool.grid) _btn(Icons.space_bar, "Oraliq ${game.gridSpacing}", game.cycleGridSpacing),
            _btn(Icons.traffic, "Svetofor", () => game.setTool(Tool.signal),
                selected: game.tool == Tool.signal),
            _btn(Icons.trip_origin, "Aylana", () => game.setTool(Tool.roundabout),
                selected: game.tool == Tool.roundabout),
            _btn(Icons.delete_outline, "O'chirish", () => game.setTool(Tool.erase),
                selected: game.tool == Tool.erase),
            _btn(Icons.info_outline, "Ma'lumot", () => game.setTool(Tool.inspect),
                selected: game.tool == Tool.inspect),
            _btn(Icons.alt_route, ["Oddiy yo'l", "Katta yo'l", "Magistral"][game.roadType], game.cycleRoadType),
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
            _btn(game.soundOn ? Icons.volume_up : Icons.volume_off, "Ovoz", game.toggleSound),
            _btn(Icons.palette, "Ranglar", game.toggleColorBlind, selected: game.colorBlind),
            _btn(Icons.format_size, "Hajm", () async {
              const opts = [0.9, 1.0, 1.15, 1.3];
              final i = opts.indexOf(_uiScale);
              setState(() => _uiScale = opts[(i + 1) % opts.length]);
              try {
                final p = await SharedPreferences.getInstance();
                await p.setDouble('uiScale', _uiScale);
              } catch (_) {}
            }),
            _btn(Icons.bug_report, "Debug", game.toggleDebug, selected: game.debug),
            _btn(Icons.save_outlined, "Slotlar", _slotsDialog),
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
