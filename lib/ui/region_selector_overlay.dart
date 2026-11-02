import 'package:flutter/material.dart';
import '../world/admin_hierarchy.dart';
import '../world/geo_coordinate_system.dart';
import '../world/world_controller.dart';

class UzbekistanRegionSelectorOverlay extends StatefulWidget {
  final UzbekistanWorldController worldController;
  final String languageCode;
  final ValueChanged<RegionCatalogEntry> onRegionConfirmed;
  final VoidCallback onClose;

  const UzbekistanRegionSelectorOverlay({
    super.key,
    required this.worldController,
    required this.languageCode,
    required this.onRegionConfirmed,
    required this.onClose,
  });

  @override
  State<UzbekistanRegionSelectorOverlay> createState() =>
      _UzbekistanRegionSelectorOverlayState();
}

class _UzbekistanRegionSelectorOverlayState
    extends State<UzbekistanRegionSelectorOverlay> {
  late RegionCatalogEntry? _selectedRegion;
  CityIndexEntry? _selectedCity;
  String _searchQuery = '';
  final TransformationController _mapTransform = TransformationController();

  @override
  void initState() {
    super.initState();
    _selectedRegion = widget.worldController.activeRegion;
    _selectedCity = widget.worldController.activeCity;
  }

  @override
  void dispose() {
    _mapTransform.dispose();
    super.dispose();
  }

  String _tr(String uz, String ru, String en) {
    switch (widget.languageCode.toLowerCase()) {
      case 'uz':
        return uz;
      case 'ru':
        return ru;
      default:
        return en;
    }
  }

  void _onRegionTapped(RegionCatalogEntry region) {
    setState(() {
      _selectedRegion = region;
      final citiesInRegion = widget.worldController.cities
          .where((c) => c.regionId == region.regionId)
          .toList();
      _selectedCity = citiesInRegion.isNotEmpty ? citiesInRegion.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final regions = widget.worldController.regions.where((r) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return r.names.uz.toLowerCase().contains(q) ||
          r.names.ru.toLowerCase().contains(q) ||
          r.names.en.toLowerCase().contains(q) ||
          r.isoCode.toLowerCase().contains(q);
    }).toList();

    final selected = _selectedRegion;
    final readiness = selected != null
        ? widget.worldController.packageManager.resolveReadiness(selected)
        : RegionReadinessStatus.overviewOnly;

    return Material(
      color: const Color(0xE60B131E),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool isWide = constraints.maxWidth > 760;
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildInteractiveMap(constraints),
                        ),
                        SizedBox(
                          width: 360,
                          child: _buildSidebar(regions, selected, readiness),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildInteractiveMap(constraints),
                      ),
                      Expanded(
                        flex: 6,
                        child: _buildSidebar(regions, selected, readiness),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF122033),
        border: Border(bottom: BorderSide(color: Color(0xFF263B59))),
      ),
      child: Row(
        children: [
          const Icon(Icons.public, color: Color(0xFF38BDF8), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _tr(
                'OʻZBEKISTON RESPUBLIKASI — HUDUD TANLASH (14 HUDUD)',
                'РЕСПУБЛИКА УЗБЕКИСТАН — ВЫБОР РЕГИОНА (14 РЕГИОНОВ)',
                'REPUBLIC OF UZBEKISTAN — REGION SELECTOR (14 DIVISIONS)',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.6,
              ),
            ),
          ),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: _tr('Yopish', 'Закрыть', 'Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveMap(BoxConstraints constraints) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1B2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF243B55)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            InteractiveViewer(
              transformationController: _mapTransform,
              minScale: 1.0,
              maxScale: 6.0,
              child: GestureDetector(
                onTapUp: (details) => _handleMapTap(details.localPosition),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _UzbekistanMapPainter(
                    boundaries: widget.worldController.boundaries,
                    regions: widget.worldController.regions,
                    cities: widget.worldController.cities,
                    selectedRegionId: _selectedRegion?.regionId,
                    selectedCityId: _selectedCity?.cityId,
                    languageCode: widget.languageCode,
                    packageManager: widget.worldController.packageManager,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xCC0B131E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2B4666)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _legendDot(const Color(0xFF10B981)),
                    const SizedBox(width: 6),
                    Text(
                      _tr(
                        'Batafsil 2D/3D paket',
                        'Детальный 2D/3D пакет',
                        'Detailed 2D/3D Pack',
                      ),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(width: 14),
                    _legendDot(const Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Text(
                      _tr(
                        'Umumiy xarita (Overview)',
                        'Обзорная карта',
                        'Overview Only (L1-L2)',
                      ),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  void _handleMapTap(Offset localPos) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    const bbox = NationalCoordinateSystem.uzbekistanNationalBbox;
    final size = box.size;
    final double mapWidth =
        size.width > 760 ? size.width - 384 : size.width - 24;
    final double mapHeight =
        size.width > 760 ? size.height - 70 : (size.height - 70) * 0.45;
    if (mapWidth <= 0 || mapHeight <= 0) return;

    final double lon =
        bbox.minLon + (localPos.dx / mapWidth) * (bbox.maxLon - bbox.minLon);
    final double lat =
        bbox.maxLat - (localPos.dy / mapHeight) * (bbox.maxLat - bbox.minLat);

    final hit = widget.worldController.findRegionAtCoordinate(lon, lat);
    if (hit != null) {
      _onRegionTapped(hit);
    } else {
      RegionCatalogEntry? nearest;
      double bestDist = double.infinity;
      for (final r in widget.worldController.regions) {
        final d = NationalCoordinateSystem.geodesicDistanceMeters(
          Wgs84Coord(lon: lon, lat: lat),
          r.centroid,
        );
        if (d < bestDist) {
          bestDist = d;
          nearest = r;
        }
      }
      if (nearest != null && bestDist < 220000) {
        _onRegionTapped(nearest);
      }
    }
  }

  Widget _buildSidebar(
    List<RegionCatalogEntry> regions,
    RegionCatalogEntry? selected,
    RegionReadinessStatus readiness,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF122033),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF263B59)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: _tr(
                'Viloyat yoki shaharni qidiring...',
                'Поиск региона или города...',
                'Search region or city...',
              ),
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon:
                  const Icon(Icons.search, color: Colors.white54, size: 18),
              filled: true,
              fillColor: const Color(0xFF0B131E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: regions.length,
              itemBuilder: (context, idx) {
                final r = regions[idx];
                final isSel = r.regionId == selected?.regionId;
                final st =
                    widget.worldController.packageManager.resolveReadiness(r);
                final bool isDetailed =
                    st == RegionReadinessStatus.installedDetailed;
                return Card(
                  color:
                      isSel ? const Color(0xFF1E3A5F) : const Color(0xFF0E1826),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    dense: true,
                    onTap: () => _onRegionTapped(r),
                    title: Text(
                      r.names.forLang(widget.languageCode),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      '${r.isoCode} • SOATO ${r.soatoCode}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDetailed
                            ? const Color(0x3310B981)
                            : const Color(0x33F59E0B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDetailed
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                      child: Text(
                        isDetailed
                            ? _tr(
                                'TAYYOR (L1-L4)',
                                'ГОТОВО (L1-L4)',
                                'DETAILED (L1-L4)',
                              )
                            : _tr(
                                'UMUMIY (L1-L2)',
                                'ОБЗОР (L1-L2)',
                                'OVERVIEW ONLY',
                              ),
                        style: TextStyle(
                          color: isDetailed
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFBBF24),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (selected != null) ...[
            const Divider(color: Color(0xFF263B59)),
            _buildSelectedRegionDetails(selected, readiness),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedRegionDetails(
    RegionCatalogEntry selected,
    RegionReadinessStatus readiness,
  ) {
    final bool isDetailed =
        readiness == RegionReadinessStatus.installedDetailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selected.names.forLang(widget.languageCode),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isDetailed
              ? _tr(
                  'Toʻliq koʻcha tarmogʻi, svetoforlar, metro va 3D binolar oʻrnatilgan.',
                  'Полная дорожная сеть, светофоры, метро и 3D-здания установлены.',
                  'Full street network, traffic signals, metro, and 3D buildings installed.',
                )
              : _tr(
                  'Faqat viloyat chegaralari va magistral yoʻllar mavjud (OVERVIEW_ONLY). Batafsil shahar paketi hali oʻrnatilmagan.',
                  'Доступны только границы и магистрали (OVERVIEW_ONLY). Детальный пакет города ещё не установлен.',
                  'Regional boundaries and national highways available (OVERVIEW_ONLY). Detailed city street package not yet installed.',
                ),
          style: TextStyle(
            color: isDetailed
                ? const Color(0xFF6EE7B7)
                : const Color(0xFFFCD34D),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isDetailed ? const Color(0xFF0284C7) : const Color(0xFF475569),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: () {
            widget.worldController.selectRegion(
              selected.regionId,
              cityId: _selectedCity?.cityId,
            );
            widget.onRegionConfirmed(selected);
          },
          icon: Icon(
            isDetailed ? Icons.play_arrow : Icons.map_outlined,
            size: 18,
          ),
          label: Text(
            isDetailed
                ? _tr(
                    'SHAHAR SIMULYATSIYASINI OCHISH',
                    'ОТКРЫТЬ СИМУЛЯЦИЮ ГОРОДА',
                    'LAUNCH DETAILED SIMULATION',
                  )
                : _tr(
                    'UMUMIY XARITADA KOʻRISH (L1-L2)',
                    'ОТКРЫТЬ ОБЗОРНУЮ КАРТУ (L1-L2)',
                    'VIEW REGIONAL OVERVIEW (L1-L2)',
                  ),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _UzbekistanMapPainter extends CustomPainter {
  final List<RegionBoundaryPolygon> boundaries;
  final List<RegionCatalogEntry> regions;
  final List<CityIndexEntry> cities;
  final String? selectedRegionId;
  final String? selectedCityId;
  final String languageCode;
  final dynamic packageManager;

  _UzbekistanMapPainter({
    required this.boundaries,
    required this.regions,
    required this.cities,
    required this.selectedRegionId,
    required this.selectedCityId,
    required this.languageCode,
    required this.packageManager,
  });

  Offset _project(double lon, double lat, Size size) {
    const bbox = NationalCoordinateSystem.uzbekistanNationalBbox;
    final double padX = size.width * 0.06;
    final double padY = size.height * 0.08;
    final double usableW = size.width - padX * 2;
    final double usableH = size.height - padY * 2;

    final double nx = (lon - bbox.minLon) / (bbox.maxLon - bbox.minLon);
    final double ny = (bbox.maxLat - lat) / (bbox.maxLat - bbox.minLat);
    return Offset(padX + nx * usableW, padY + ny * usableH);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (final poly in boundaries) {
      final bool isSelected = poly.regionId == selectedRegionId;
      final bool isDetailed = poly.regionId == 'uz_tashkent_city';

      final fillPaint = Paint()
        ..color = isSelected
            ? (isDetailed
                ? const Color(0x8810B981)
                : const Color(0x880284C7))
            : (isDetailed
                ? const Color(0x4410B981)
                : const Color(0xFF162840))
        ..style = PaintingStyle.fill;

      for (final ring in poly.rings) {
        if (ring.isEmpty) continue;
        final path = Path();
        for (int i = 0; i < ring.length; i++) {
          final pt = _project(ring[i].lon, ring[i].lat, size);
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(
          path,
          isSelected
              ? (Paint()
                ..color = const Color(0xFF7DD3FC)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.4)
              : borderPaint,
        );
      }
    }

    final highwayPaint = Paint()
      ..color = const Color(0x99F59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    const List<List<List<double>>> nationalCorridors = [
      [
        [67.278, 37.224],
        [65.789, 38.860],
        [66.975, 39.655],
        [67.842, 40.115],
        [68.784, 40.489],
        [69.280, 41.311],
      ],
      [
        [66.975, 39.655],
        [65.379, 40.084],
        [64.421, 39.774],
        [60.631, 41.550],
        [59.610, 42.460],
      ],
      [
        [69.280, 41.311],
        [70.942, 40.528],
        [71.786, 40.384],
        [72.344, 40.782],
        [71.672, 40.998],
      ],
    ];

    for (final corridor in nationalCorridors) {
      final path = Path();
      for (int i = 0; i < corridor.length; i++) {
        final pt = _project(corridor[i][0], corridor[i][1], size);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, highwayPaint);
    }

    for (final city in cities) {
      final Offset pos = _project(city.location.lon, city.location.lat, size);
      final Color dotColor = city.hasDetailedPack
          ? const Color(0xFF10B981)
          : const Color(0xFFF59E0B);

      canvas.drawCircle(
        pos,
        city.hasDetailedPack ? 6.0 : 4.2,
        Paint()..color = dotColor,
      );
      canvas.drawCircle(
        pos,
        city.hasDetailedPack ? 8.5 : 6.0,
        Paint()
          ..color = dotColor.withAlpha(90)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: city.names.forLang(languageCode),
          style: TextStyle(
            color: Colors.white,
            fontSize: city.hasDetailedPack ? 11.5 : 10.0,
            fontWeight:
                city.hasDetailedPack ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos + const Offset(7, -6));
    }
  }

  @override
  bool shouldRepaint(covariant _UzbekistanMapPainter oldDelegate) {
    return oldDelegate.selectedRegionId != selectedRegionId ||
        oldDelegate.languageCode != languageCode;
  }
}

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
