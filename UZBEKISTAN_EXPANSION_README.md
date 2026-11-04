# Trafficity — O'zbekiston 14 hududli kengaytma (haqiqiy holat)

Bu hujjat kod bilan tasdiqlanadigan narsalarnigina yozadi. Inglizcha to'liq versiya: `README.md`.

## 1. Hozir nima ishlaydi va nima ishlamaydi

| Narsa | Holat |
|---|---|
| Batafsil (o'ynaladigan) xarita | **Faqat Toshkent shahri**: 2495 ta haqiqiy OSM yo'li, 16 ta WGS84 chunk. |
| 3D ko'rinish (Toshkent) | **Yangi.** Asboblar panelidagi "3D" tugmasi: ishlayotgan o'yinning dasturiy perspektiv 3D ko'rinishi (`lib/game3d/`) — xarita teksturali yer, yo'llar, temir yo'l, 31 908 ta haqiqiy bino konturi (Microsoft ML Building Footprints, ODbL; xarita bilan bir xil proyeksiya, 79 OSM nuqtaga nisbatan 0,004 m), o'yin binolari, mashina/yuk mashinalari, estakadalar, quyosh soyalari, tuman. 1 barmoq aylantirish/qiyalik, 2 barmoq yaqinlashtirish/surish/burish; simulyatsiya to'xtamaydi. **Balandliklar taxminiy** (manbada yo'q). Faqat ko'rish (qurish 2D da); svetoforlar (har kirishda joriy rangli ustun), yo'l belgilari (sariq o'rta chiziq, oq polosa ajratgich — 2D dagidek) va avariya belgisi chiziladi; daraxt va poyezd 3D da hali yo'q. `tools/map/export_tashkent_obj.py` — Blender uchun OBJ. Headless chizilgan va testlangan; **telefonda hali sinalmagan**. |
| 2D xarita | **Yangi.** Tanlagich va «faqat umumiy ko'rinish» kartasi O'zbekistonning haqiqiy 2D xaritasini chizadi: 14 hudud konturi Natural Earth admin-1 dan (ochiq ma'lumot, `assets/world/uzbekistan/region_borders.json`, `tools/map/build_uzbekistan_borders.py`, ~440 m umumlashtirilgan). Surish/zoom, hududni bosib tanlash, yashil nuqta = batafsil xarita bor, yorliqlar sig'gan joyda ko'rinadi. Tekshiruvlar: 14 ISO kodi katalogga mos, har bir vakil nuqta o'z konturi ichida, umumiy maydon 449 023 km² (rasmiy 448 978 km²). Bu **kartografik kontur, huquqiy chegara EMAS**; Toshkent shahridan tashqarida yo'l/bino yo'q, 3D renderer yo'q. |
| Qolgan 13 hudud | `OVERVIEW_ONLY`. Tanlansa o'yin to'xtaydi va «faqat umumiy ko'rinish» kartasi chiqadi. Toshkent xaritasi hech qachon boshqa hudud nomi ostida ko'rsatilmaydi. |
| Hudud chegaralari | GeoJSON'dagi to'rtburchaklar — **taxminiy bounding-box konvertlar**, ma'muriy chegara EMAS. |
| ISO 3166-2:UZ kodlari | Ikkilamchi manba (statoids.com) bilan 2026-11-03 da tekshirilgan. **SOATO kodlari tasdiqlanmagan.** |
| Toshkent koordinata o'tkazmasi | `verified_approximate`: boshlang'ich nuqta, o'qlar va 1 birlik = 1 m masshtabi 79 ta mustaqil OpenStreetMap tugun koordinatasi bilan solishtirilgan (`tools/map/tashkent_osm_anchors.json`, OSM API, 2026-11-04). 10 km ichidagi 21 nuqta: o'rtacha 17,7 m, eng katta 23,1 m (chegara 30 m); masofa bilan ~0,2% o'sadi (~22 km da 70 m). Yo'llar hududida faqat 2 nuqta bor (3,3 m va 10,4 m). **Geodezik aniqlikda EMAS**: tayanch nuqtalar OSM joy nomlari, nazorat punktlari emas. |
| Paket menejeri | O'rnatish/yangilash/o'chirish/tiklash va SHA-256, Zip-Slip himoyasi, atomik almashtirish tayyor va testlangan. **Ilova ichida yuklab olish yoki server yo'q**, shuning uchun UI orqali Toshkentdan boshqa hududni o'rnatib bo'lmaydi. |

## 2. Modullar (nima qiladi, nima qilmaydi)

- `lib/world/geo_coordinate_system.dart`: WGS84 ↔ Local ENU (ellipsoid formulalari), eski Toshkent birliklari ↔ WGS84, 2000 m floating-origin rebasing, geodezik masofa. Eski birliklar uchun `wgs84ToLegacyUnitsExact` (double); Flame `Vector2` float32 bo'lgani uchun u ~5e-4 birlik aniqlikka ega.
- `lib/world/admin_hierarchy.dart`: 14 hudud katalogi (uz/ru/en nomlari, ISO/SOATO, bbox, tayyorlik holati).
- `lib/world/region_package_manager.dart`: SHA-256 (`crypto`), manifest tekshiruvi, tranzaksion o'rnatish/yangilash/o'chirish, holat saqlash, tayyorlikni aniqlash.
- `lib/world/multi_scale_lod_controller.dart`: kamera zoom, 3D bayrog'i va paket borligiga qarab 4 darajadan birini tanlaydi. **Chunk streaming va 3D renderer yo'q.**
- `lib/world/world_controller.dart`: katalogni bir marta yuklaydi (holat/xato/qayta urinish), faol hudud, floating origin, LOD.
- `lib/ui/region_selector_overlay.dart`, `lib/ui/uzbekistan_hud_button.dart`: o'yin HUD'idagi tugma, 14 hududli ro'yxat va «faqat umumiy ko'rinish» kartasi. (Xarita chizmasi emas, ro'yxat.)
- `lib/world/national_save_manager.dart` (saqlash v3 + v1/v2 migratsiyasi): **ulangan (additiv)** — `RoadGame.save()` o'yin saqlashining (v2, o'zgarmagan) yoniga `nat` konvertini yozadi (davlat, hudud, WGS84 kamera faqat haqiqiy Toshkent xaritasida, zoom); `load()` uni o'qiydi, yo'q yoki yaroqsiz bo'lsa e'tibor bermaydi; yuklashdan so'ng hudud faqat batafsil paketi bor bo'lsa tiklanadi. Saqlanadigan hudud — o'yin holati tegishli hudud, «faqat umumiy ko'rinish» tanlovi emas.
- `lib/world/architecture_profile_engine.dart`: **faqat metadata sifatida ulangan** — umumiy ko'rinish kartasida profil va «vizuallar hali yo'q» (`visualsImplemented: false`) ko'rsatiladi; profilga xos bino vizuallari yo'q.
- `lib/world/road_graph_linker.dart` (portallar): **ataylab ulanmagan** — u ikki *batafsil* hudud o'rtasidagi yo'l portallarini bog'laydi, hozir faqat Toshkent batafsil, shuning uchun iste'molchi yo'q (faqat unit-test).
- `tools/map/migrate_tashkent_legacy.py`: `assets/map/tashkent_roads.json` → WGS84 chunklar + manifest (deterministik, 2495/2495).
- `tools/uzbekistan_pack_cli.mjs`, `tools/packager_core.mjs`, `Trafficity-Uzbekistan-Complete-Packager.html`: tekshirish, deterministik ZIP, GitHub'ga majburlamasdan push.
- `tools/package_release.py`: qat'iy chiqarish quvuri (tekshiruvlar → ZIP → Android scaffold → debug APK).

## 3. Buyruqlar

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
npm test
python3 -m unittest discover -s tools/tests -v
python3 tools/map/migrate_tashkent_legacy.py
python3 tools/package_release.py            # Android SDK kerak; SDK'siz: --allow-blocked (hech qachon "release ready" bo'lmaydi)
```

Android loyiha fayllari repoda yo'q (faqat ikonkalar): `flutter create --platforms=android --org uz.abdulloh .`, so'ng yaratilgan `test/widget_test.dart` ni o'chiring. `package_release.py` buni ZIP yaratilgandan keyin o'zi bajaradi.

## 4. Ma'lumot manbasi va litsenziya
- Yo'llar va xarita: `© OpenStreetMap contributors (ODbL-1.0)`.
- Kod: MIT (`LICENSE`).
- To'qib chiqarilgan yo'l tarmog'i yo'q: batafsil paket o'rnatilmagan hududlar `OVERVIEW_ONLY` bo'lib qoladi.
