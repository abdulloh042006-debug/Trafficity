import 'package:flutter/material.dart';
import '../world/world_controller.dart';

class UzbekistanRegionSelectorOverlay extends StatelessWidget {
  final UzbekistanWorldController worldController;
  const UzbekistanRegionSelectorOverlay({super.key, required this.worldController});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: worldController.regions.length,
      itemBuilder: (context, index) {
        final r = worldController.regions[index];
        return ListTile(
          title: Text(r.names.uz),
          subtitle: Text('${r.isoCode} (${r.centroid.lat}, ${r.centroid.lon})'),
          onTap: () => worldController.selectRegion(r.regionId),
        );
      },
    );
  }
}
