import 'package:flutter/material.dart';
import '../world/admin_hierarchy.dart';
import '../world/world_controller.dart';

class UzbekistanRegionSelectorOverlay extends StatelessWidget {
  final UzbekistanWorldController worldController;
  final String languageCode;
  final ValueChanged<RegionCatalogEntry> onRegionConfirmed;
  final VoidCallback onClose;

  const UzbekistanRegionSelectorOverlay({
    super.key,
    required this.worldController,
    this.languageCode = 'uz',
    required this.onRegionConfirmed,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: worldController.regions.length,
      itemBuilder: (context, index) {
        final r = worldController.regions[index];
        return ListTile(
          title: Text(r.names.forLang(languageCode)),
          subtitle: Text('${r.isoCode} (${r.centroid.lat}, ${r.centroid.lon})'),
          onTap: () {
            worldController.selectRegion(r.regionId);
            onRegionConfirmed(r);
          },
        );
      },
    );
  }
}
