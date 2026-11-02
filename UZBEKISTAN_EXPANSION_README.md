# Trafficity — O'zbekiston 14 Hududli Geografik va Transport Kengaytmasi

Ushbu kengaytma **Trafficity** (`abdulloh042006-debug/Trafficity`) loyihasini faqat Toshkent shahri bilan cheklangan simulyatordan O'zbekiston Respublikasining barcha **14 ta birinchi darajali ma'muriy hududini** qamrab oluvchi ko'p masshtabli (L1–L4 LOD) platformaga aylantiradi.

## 1. Qamrab Olingan 14 ta Ma'muriy Hudud (ISO 3166-2:UZ va SOATO)

1. `uz_tashkent_city` (`UZ-TK`, SOATO `1726`) — Toshkent shahri (`INSTALLED_DETAILED`, L1–L4)
2. `uz_karakalpakstan` (`UZ-QR`, SOATO `1735`) — Qoraqalpog'iston Respublikasi (Markaz: Nukus)
3. `uz_andijan` (`UZ-AN`, SOATO `1703`) — Andijon viloyati (Markaz: Andijon)
4. `uz_bukhara` (`UZ-BU`, SOATO `1706`) — Buxoro viloyati (Markaz: Buxoro)
5. `uz_fergana` (`UZ-FA`, SOATO `1730`) — Farg'ona viloyati (Markaz: Farg'ona)
6. `uz_jizzakh` (`UZ-JI`, SOATO `1708`) — Jizzax viloyati (Markaz: Jizzax)
7. `uz_kashkadarya` (`UZ-QA`, SOATO `1710`) — Qashqadaryo viloyati (Markaz: Qarshi)
8. `uz_khorezm` (`UZ-XO`, SOATO `1733`) — Xorazm viloyati (Markaz: Urganch)
9. `uz_namangan` (`UZ-NG`, SOATO `1714`) — Namangan viloyati (Markaz: Namangan)
10. `uz_navoi` (`UZ-NW`, SOATO `1712`) — Navoiy viloyati (Markaz: Navoiy)
11. `uz_samarkand` (`UZ-SA`, SOATO `1718`) — Samarqand viloyati (Markaz: Samarqand)
12. `uz_surkhandarya` (`UZ-SU`, SOATO `1722`) — Surxondaryo viloyati (Markaz: Termiz)
13. `uz_syrdarya` (`UZ-SI`, SOATO `1724`) — Sirdaryo viloyati (Markaz: Guliston)
14. `uz_tashkent_region` (`UZ-TO`, SOATO `1727`) — Toshkent viloyati (Markaz: Nurafshon)

## 2. Arxitektura Modullari (23 ta Fayl)

- `lib/world/geo_coordinate_system.dart`: WGS84 (`EPSG:4326`) va Local ENU metrik koordinatalar tizimi (2000m floating-origin rebasing bilan).
- `lib/world/admin_hierarchy.dart`: 14 viloyat katalogi, shaharlar indeksi va GeoJSON chegaralari.
- `lib/world/region_package_manager.dart`: SHA-256 xesh tekshiruviga ega hudud paketlari menejeri.
- `lib/world/multi_scale_lod_controller.dart`: 4 bosqichli LOD va spatial chunk streaming nazoratchisi.
- `lib/world/road_graph_linker.dart`: Hududlararo magistral yo'llarni (M39 va b.) bog'lovchi portal tizimi.
- `lib/world/architecture_profile_engine.dart`: Toshkent, Samarqand, Buxoro, Xiva, Farg'ona va Qoraqalpog'iston me'moriy profillari.
- `lib/world/national_save_manager.dart`: Eski Toshkent saqlash fayllarini (v1/v2) milliy WGS84 v3 formatiga o'tkazish.
- `lib/world/world_controller.dart`: Asosiy `UzbekistanWorldController`.
- `lib/ui/region_selector_overlay.dart` va `lib/ui/uzbekistan_hud_button.dart`: Interaktiv O'zbekiston xaritasi va HUD tugmasi.
- `tools/map/trafficity_ingest.py` va `tools/map/migrate_tashkent_legacy.py`: GIS va OSM GeoJSON ma'lumotlarini paketlash CLI vositalari.

## 3. Ishga Tushirish va Tekshirish Buyruqlari

```bash
python3 tools/map/migrate_tashkent_legacy.py
flutter pub get
flutter analyze
flutter test test/uzbekistan_world_test.dart
python3 tools/package_release.py
```

## 4. Ma'lumotlar Manbasi va Litsenziya
- Geografik ma'lumotlar: `© OpenStreetMap contributors (ODbL-1.0)`.
- Soxta yo'l tarmoqlari to'qib chiqarilmagan: to'liq yo'l paketi o'rnatilmagan hududlar `OVERVIEW_ONLY` maqomida ishlaydi.
