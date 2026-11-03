import 'package:flutter/material.dart';

import '../l10n.dart';
import '../world/admin_hierarchy.dart';
import '../world/multi_scale_lod_controller.dart';
import '../world/world_controller.dart';

String _levelText(GeographicalDetailLevel level) {
  switch (level) {
    case GeographicalDetailLevel.level1CountryOverview:
      return "1/4 · Butun mamlakat";
    case GeographicalDetailLevel.level2RegionalView:
      return "2/4 · Viloyat ko'rinishi";
    case GeographicalDetailLevel.level3CityView2D:
      return "3/4 · Shahar (2D)";
    case GeographicalDetailLevel.level4DetailedUrban3D:
      return "4/4 · Shahar (3D)";
  }
}

/// List of the 14 first-level divisions with their real readiness. Selecting a region reports it through
/// [onRegionConfirmed]; the caller decides what the game shows (a region without a detailed package is
/// overview-only and must never be drawn with the Tashkent road map).
class UzbekistanRegionSelectorOverlay extends StatelessWidget {
  static const Key listKey = Key('region-list');
  static const Key closeKey = Key('region-selector-close');
  static Key tileKey(String regionId) => Key('region-tile-$regionId');

  final UzbekistanWorldController worldController;
  final String languageCode;
  final double scale;
  final ValueChanged<RegionCatalogEntry> onRegionConfirmed;
  final VoidCallback onClose;

  const UzbekistanRegionSelectorOverlay({
    super.key,
    required this.worldController,
    required this.onRegionConfirmed,
    required this.onClose,
    this.languageCode = 'uz',
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
      child: ListenableBuilder(
        listenable: worldController,
        builder: (context, _) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        L.t("O'zbekiston viloyatlari"),
                        style: TextStyle(fontSize: 17 * scale, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      key: closeKey,
                      tooltip: L.t('Yopish'),
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Text(
                  '${L.t("Ko'rinish darajasi")}: ${L.t(_levelText(worldController.lodLevel))}\n'
                  '${L.t("Batafsil xarita hozircha faqat Toshkent shahri uchun mavjud.")}',
                  style: TextStyle(fontSize: 11.5 * scale, color: const Color(0xFF55585E)),
                ),
              ),
              const Divider(height: 1),
              Flexible(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (worldController.loadState) {
      case WorldLoadState.error:
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(L.t('Katalog yuklanmadi'), style: const TextStyle(color: Color(0xFFC0392B))),
              const SizedBox(height: 10),
              FilledButton(onPressed: worldController.retry, child: Text(L.t('Qayta urinish'))),
            ],
          ),
        );
      case WorldLoadState.idle:
      case WorldLoadState.loading:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(L.t('Yuklanmoqda...'))),
        );
      case WorldLoadState.ready:
        final regions = worldController.regions;
        return ListView.separated(
          key: listKey,
          shrinkWrap: true,
          itemCount: regions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _tile(regions[i]),
        );
    }
  }

  Widget _tile(RegionCatalogEntry r) {
    final detailed = worldController.readinessOf(r) == RegionReadinessStatus.installedDetailed;
    final active = worldController.activeRegion?.regionId == r.regionId;
    return ListTile(
      key: tileKey(r.regionId),
      dense: true,
      selected: active,
      leading: Icon(
        detailed ? Icons.location_city : Icons.map_outlined,
        color: detailed ? const Color(0xFF2E8B3E) : const Color(0xFF8A8D93),
      ),
      title: Text(
        r.names.forLang(languageCode),
        style: TextStyle(fontWeight: active ? FontWeight.w800 : FontWeight.w600),
      ),
      subtitle: Text(
        '${r.isoCode} · ${detailed ? L.t("Batafsil xarita") : L.t("Faqat umumiy ko'rinish")}',
        style: TextStyle(fontSize: 11 * scale),
      ),
      trailing: active ? const Icon(Icons.check_circle, color: Color(0xFF2E7DB5)) : null,
      onTap: () => onRegionConfirmed(r),
    );
  }
}

/// Opaque full-screen card shown while the active region has no detailed package. It replaces the game view,
/// so the Tashkent road map is never visible under another region's name.
class RegionOverviewCard extends StatelessWidget {
  static const Key cardKey = Key('region-overview-card');
  static const Key backKey = Key('region-overview-back');
  static const Key regionsKey = Key('region-overview-regions');

  final UzbekistanWorldController worldController;
  final String languageCode;
  final double scale;
  final VoidCallback onBackToDetailed;
  final VoidCallback onOpenSelector;

  const RegionOverviewCard({
    super.key,
    required this.worldController,
    required this.onBackToDetailed,
    required this.onOpenSelector,
    this.languageCode = 'uz',
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: worldController,
      builder: (context, _) {
        final r = worldController.activeRegion;
        if (r == null) return const SizedBox.shrink();
        final p = r.representativePoint;
        return Container(
          key: cardKey,
          color: const Color(0xFFE9EEF3),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.map_outlined, size: 54 * scale, color: const Color(0xFF6A7480)),
                  const SizedBox(height: 10),
                  Text(
                    r.names.forLang(languageCode),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24 * scale, fontWeight: FontWeight.w800, color: const Color(0xFF2B2E33)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${r.isoCode} · ${L.t("Faqat umumiy ko'rinish")}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: const Color(0xFF6A7480)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${p.lat.toStringAsFixed(3)}°N, ${p.lon.toStringAsFixed(3)}°E · ${L.t("Ko'rinish darajasi")}: ${L.t(_levelText(worldController.lodLevel))}\n'
                    '${L.t("SOATO kodi tasdiqlanmagan")}: ${r.soatoCode}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12 * scale, color: const Color(0xFF55585E)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    L.t(
                      "Batafsil xarita (yo'llar, binolar) bu viloyat uchun hali o'rnatilmagan. O'yin faqat Toshkent shahri xaritasida o'ynaladi.",
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13 * scale, color: const Color(0xFF2B2E33)),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: backKey,
                    onPressed: onBackToDetailed,
                    icon: const Icon(Icons.location_city),
                    label: Text(L.t('Toshkent shahriga qaytish')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: regionsKey,
                    onPressed: onOpenSelector,
                    icon: const Icon(Icons.public),
                    label: Text(L.t('Viloyatlar')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
