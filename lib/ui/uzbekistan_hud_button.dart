import 'package:flutter/material.dart';

import '../l10n.dart';
import '../world/world_controller.dart';

/// Compact HUD button showing the active Uzbekistan region; tapping it opens the region selector.
///
/// The controller is owned by the parent screen (one instance for the whole app run); this widget only
/// reads it and never creates, loads or disposes it.
class UzbekistanHudButton extends StatelessWidget {
  static const Key buttonKey = Key('uzbekistan-region-button');

  final UzbekistanWorldController worldController;
  final String languageCode;
  final double scale;
  final VoidCallback onPressed;

  const UzbekistanHudButton({
    super.key,
    required this.worldController,
    required this.onPressed,
    this.languageCode = 'uz',
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: worldController,
      builder: (context, _) {
        final active = worldController.activeRegion;
        final String label;
        switch (worldController.loadState) {
          case WorldLoadState.ready:
            label = active?.names.forLang(languageCode) ?? '-';
            break;
          case WorldLoadState.error:
            label = L.t('Katalog yuklanmadi');
            break;
          case WorldLoadState.idle:
          case WorldLoadState.loading:
            label = L.t('Yuklanmoqda...');
            break;
        }
        final overview = worldController.isReady && !worldController.isActiveDetailed;
        return Semantics(
          button: true,
          label: label,
          child: InkWell(
            key: buttonKey,
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.public, size: 15 * scale, color: const Color(0xFF2E7DB5)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      overview ? '$label · ${L.t("Faqat umumiy ko'rinish")}' : label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2B2E33),
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, size: 18 * scale, color: const Color(0xFF55585E)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
