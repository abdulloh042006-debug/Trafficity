/// Static metadata about an architecture profile referenced by the region catalog.
///
/// [visualsImplemented] is false for every profile today: the game has no profile-specific building
/// visuals yet, only the profile identifiers. This flag exists so UI/docs never overstate support.
class ArchitectureProfile {
  final String id;
  final String label;
  final bool visualsImplemented;
  const ArchitectureProfile({required this.id, required this.label, this.visualsImplemented = false});
}

class ArchitectureProfileEngine {
  /// Profile identifiers used by `region_catalog.json` (`architectureProfileId`).
  static const Map<String, ArchitectureProfile> supportedProfiles = {
    'tashkent_modern_soviet': ArchitectureProfile(id: 'tashkent_modern_soviet', label: 'Tashkent modern / Soviet'),
    'samarkand_timurid_heritage': ArchitectureProfile(id: 'samarkand_timurid_heritage', label: 'Samarkand Timurid heritage'),
    'bukhara_historic_oasis': ArchitectureProfile(id: 'bukhara_historic_oasis', label: 'Bukhara historic oasis'),
    'khiva_ichan_kala': ArchitectureProfile(id: 'khiva_ichan_kala', label: 'Khiva Ichan-Kala'),
    'fergana_valley_urban': ArchitectureProfile(id: 'fergana_valley_urban', label: 'Fergana Valley urban'),
    'karakalpak_steppe_modern': ArchitectureProfile(id: 'karakalpak_steppe_modern', label: 'Karakalpak steppe modern'),
  };

  final Set<String> _excludedFootprintIds = {};

  void registerLandmarkExclusions(Iterable<String> ids) => _excludedFootprintIds.addAll(ids);
  bool isFootprintExcluded(String id) => _excludedFootprintIds.contains(id);

  /// Profile metadata for [profileId], or null when the identifier is unknown.
  ArchitectureProfile? profileFor(String profileId) => supportedProfiles[profileId];

  /// True only when profile-specific visuals really exist for [profileId] (currently never).
  bool hasProfileVisuals(String profileId) => supportedProfiles[profileId]?.visualsImplemented ?? false;
}
