# Tashkent 3D City Research

Toshkentning real geografiyasiga mos 3D raqamli nusxasini yaratish uchun geoma'lumotlar manbalari, litsenziya qaydlari, yuklab olish skriptlari va Overpass so'rovlari.

**Tekshiruv sanasi:** 2026-11-22  
**Hudud:** Toshkent shahri, O'zbekiston  
**Holat:** research pack; hali tayyor 3D model yoki barcha xom geoma'lumotlar emas.

## Qamrov

- Binolar va bino qismlari: footprint, balandlik, qavat, tom, fasad.
- Do'konlar, restoranlar, bozorlar, ofislar, xizmatlar va boshqa POI.
- Parklar, xiyobonlar, bog'lar, maysazorlar, sport/playground hududlari.
- Daraxtlar, daraxt qatorlari, o'rmonzorlar, butalar va ko'chatlar.
- Daryo, kanal, ariq, zovur, kollektor, ko'l, hovuz, suv ombori, favvora, dambalar va ko'priklar.
- Yo'llar, piyoda yo'laklari, temir yo'l, bekatlar, parking, svetofor va ko'cha jihozlari.
- Relyef, yer qoplami, NDVI, tarixiy suv qoplamasi.
- Ko'cha panoramalari, mahalliy daraxt reyestri va bino yoshi xaritasi.

## Tez boshlash

Python 3.10+, Bash, internet kerak.

```bash
python -m pip install --upgrade overturemaps
bash research/tashkent-3d/scripts/download_overture.sh
bash research/tashkent-3d/scripts/download_osm_uzbekistan.sh
```

OSM skripti Geofabrikdan butun O'zbekiston PBF faylini oladi (tekshiruv vaqtida taxminan 120 MB). Toshkentni kesish uchun rasmiy/tekshirilgan shahar chegarasi Osmium .poly fayli talab qilinadi.

Overture skripti bbox bo'yicha alohida GeoParquet qatlamlarini yuklaydi. Default bbox: west 69.10, south 41.18, east 69.45, north 41.46. **Bu rasmiy Toshkent chegarasi emas**, faqat keng qidiruv oynasi. Yakuniy ma'lumotlarni rasmiy shahar poligoni bilan clip qiling.

## Muhim manbalar

- [Geofabrik Uzbekistan OSM](https://download.geofabrik.de/asia/uzbekistan/)
- [Overture Maps docs](https://docs.overturemaps.org/)
- [Green Tashkent tree inventory](https://green.tashkent.uz/en)
- [National Geoinformation Portal](https://open.ngis.uz/)
- [Tashkent Open Data](https://opendata.tashkent.uz/)
- [ESA WorldCover 10 m](https://esa-worldcover.org/en/data-access)
- [JRC Global Surface Water 1984-2024](https://global-surface-water.appspot.com/download)
- [Copernicus Browser / Sentinel](https://dataspace.copernicus.eu/browser/)
- [Yandex Maps Tashkent](https://yandex.com/maps/10335/tashkent/)
- [Mapillary](https://www.mapillary.com/app/)

Batafsil manbalar va foydalanish cheklovlari: [SOURCES.md](SOURCES.md). 3D ishlab chiqarish rejasi: [BUILD_PLAN.md](BUILD_PLAN.md). Qatlamlar inventari: [LAYER_MATRIX.csv](LAYER_MATRIX.csv).

## Mavjud Trafficity materiallari

Repo ichida avvaldan Toshkent OSM yo'llari va suv maskasi mavjud: `assets/map/`, shuningdek `assets/world/uzbekistan/regions/tashkent_city/`. Ularni qayta ishlatishdan avval har bir faylning manba, koordinata tizimi va qamrovini tekshiring. Ushbu research folder mavjud o'yin fayllarini o'zgartirmaydi.

## Aniqlik belgisi

- verified: mustaqil tekshirilgan.
- mapped: manbada belgilangan, ammo joyida/rasmda tasdiqlanmagan.
- estimated: qiymat taxmin qilingan.
- unknown: ma'lumot yo'q.

Bino balandligi, daraxt turi yoki suv chuqurligi noma'lum bo'lsa, fakt sifatida uydirmang; unknown/estimated deb saqlang.

## Litsenziya

OSM ODbL; Overture litsenziyasi theme bo'yicha; ESA WorldCover CC BY 4.0; Mapillary CC BY-SA. Yandex, Google, 2GIS va mahalliy portal xaritasini ko'rish imkoniyati ularning tasvirlarini bulk ko'chirish, texture sifatida saqlash yoki qayta tarqatish ruxsati degani emas. Har bir eksportda source, source_date va license maydonlarini saqlang.
