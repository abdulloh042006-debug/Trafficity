import 'package:flutter/material.dart';
import '../world/admin_hierarchy.dart';
import '../world/world_controller.dart';
import 'region_selector_overlay.dart';

/// Drop-in HUD button that opens the interactive 14-region Uzbekistan map selector.
class UzbekistanHudButton extends StatefulWidget {
  final UzbekistanWorldController worldController;
  final String languageCode;
  final ValueChanged<RegionCatalogEntry>? onRegionSelected;

  const UzbekistanHudButton({
    super.key,
    required this.worldController,
    this.languageCode = 'uz',
    this.onRegionSelected,
  });

  @override
  State<UzbekistanHudButton> createState() => _UzbekistanHudButtonState();
}

class _UzbekistanHudButtonState extends State<UzbekistanHudButton> {
  @override
  void initState() {
    super.initState();
    widget.worldController.initializeFromAssets();
  }

  void _openSelector() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => UzbekistanRegionSelectorOverlay(
        worldController: widget.worldController,
        languageCode: widget.languageCode,
        onRegionConfirmed: (region) {
          Navigator.of(ctx).pop();
          widget.onRegionSelected?.call(region);
        },
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.worldController,
      builder: (context, _) {
        final active = widget.worldController.activeRegion;
        final title = active?.names.forLang(widget.languageCode) ?? 'Toshkent';
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openSelector,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xD9122033),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF38BDF8)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.public, color: Color(0xFF38BDF8), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'UZ: $title',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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
