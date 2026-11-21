# Manbalar katalogi

Tekshiruv sanasi: 2026-11-22. Litsenziya va endpointlar o'zgarishi mumkin.

## Ochiq vektor ma'lumotlari

### 1. Geofabrik / OpenStreetMap Uzbekistan
https://download.geofabrik.de/asia/uzbekistan/

- PBF, SHP ZIP va GeoPackage ZIP formatlari.
- Tekshiruv vaqtida PBF ~120 MB, GPKG ZIP ~263 MB.
- Binolar, yo'llar, parklar, daraxtlar, suv yo'llari, POI, manzillar va boshqa OSM obyektlari.
- ODbL 1.0. Attribution: © OpenStreetMap contributors.
- Bu butun O'zbekiston extracti; shahar chegarasi bilan clip qilish kerak.
- Litsenziya: https://www.openstreetmap.org/copyright

### 2. Overture Maps
https://docs.overturemaps.org/  
Python CLI: https://docs.overturemaps.org/getting-data/overturemaps-py/  
Data repository: https://github.com/OvertureMaps/data

- Themes: addresses, base, buildings, divisions, places, transportation.
- Feature types orasida building/building_part, place, segment/connector, address, water, land, land_use, land_cover, infrastructure va division qatlamlari bor.
- GeoParquet; bbox bo'yicha GeoJSON yoki GeoParquet eksport qilish mumkin.
- Hujjatda ko'ringan release: 2026-11-18.0; CLI STAC katalogidan eng so'nggi release'ni tanlaydi.
- Litsenziya theme bo'yicha farq qiladi. OSM asosidagi theme'larda ODbL talablari bo'lishi mumkin. Har theme attribution: https://docs.overturemaps.org/attribution/

### 3. Microsoft Global ML Building Footprints
https://github.com/microsoft/GlobalMLBuildingFootprints/

- Sun'iy yo'ldosh tasvirlaridan olingan global bino konturlari; ayrim hududlarda height estimate.
- Repo 2026-08-13 yangilanishida 225 region va 30,340 tile ko'rsatgan.
- CDLA Permissive 2.0, repository shartlariga muvofiq.
- Toshkent tile qamrovi index'da tekshirilmaguncha bor deb hisoblamang.
- Turli yillardagi tasvirlardan tuzilgan; hozirgi bino holati bilan farq qilishi mumkin.

## Toshkentga xos ma'lumotlar

### 4. Green Tashkent
https://green.tashkent.uz/en

- Daraxtlarning koordinatalari va reyestr kartalari; loyiha tavsifida daraxt turi, yoshi, balandligi, tana qalinligi, toj diametri va foto kabi atributlar tasvirlangan.
- Hokimlik loyiha sahifasi: https://uchtepa.tashkent.uz/en/projects/digital/7
- O'zA xabari: https://uza.uz/oz/posts/toshkentdagi-daraxtlar-onlayn-platformaga-kiritilmoqda_765367
- Green Tashkent ishlab chiquvchisi daraxt, mahalla va park qatlamlari shahar GeoServer'idan kelishini bildirgan: https://enzora.uz/en/keysy/green-tashkent/
- GeoServer: https://geoserver.mahalla.tashkent.uz/geoserver
- WMS capabilities: https://geoserver.mahalla.tashkent.uz/geoserver/ows?service=WMS&request=GetCapabilities
- WFS capabilities: https://geoserver.mahalla.tashkent.uz/geoserver/ows?service=WFS&request=GetCapabilities
- Ko'rish mumkinligi bulk eksport/qayta tarqatish ruxsati degani emas. Terms va ruxsatni tekshiring.

### 5. Tashkent Open Data
https://opendata.tashkent.uz/  
Hokimlik tavsifi: https://tashkent.uz/en/projects/digital/8

Hokimlik sahifasida 2025-yil sentabr holatiga 16 yo'nalishda 229 dataset borligi aytilgan. Har datasetning format, update date, koordinata va license shartini alohida tekshiring.

### 6. Milliy geoaxborot portali / Kadastr
https://open.ngis.uz/  
Digital Government tavsifi: https://dgov.uz/uz/solution/detail/52/

Yer uchastkasi poligoni, kadastr raqami, yer toifasi, manzil va foydalanish maqsadi kabi ma'lumotlar uchun muhim. Ayrim ma'lumotlar rasmiy murojaat/autentifikatsiya talab qilishi mumkin. Shaxsiy mulk egasi ma'lumotlarini yig'mang.

### 7. Toshkent bino yoshi xaritasi
https://tashkent.uz/en/projects/digital/1

Binolarni qurilish davri bo'yicha va madaniy meros obyektlarini ko'rish uchun. Hozircha vizual tekshiruv manbasi; eksport/API huquqini alohida aniqlang.

### 8. Toshkent bosh rejasi ArcGIS FeatureServer
https://services-ap1.arcgis.com/jqzZqLEr1TZGsLRh/arcgis/rest/services/Генплан_Ташкента/FeatureServer

Ko'rinayotgan qatlam: Tasdiqlangan_final_02112024. Rejalashtirish/zoning kontekstini tekshirish uchun. Xizmat metadata'sida copyright text bo'sh; ruxsat aniqlanmaguncha bulk eksport va qayta tarqatmang.

## Yer qoplami, suv va relyef

### 9. ESA WorldCover 10 m
https://esa-worldcover.org/en/data-access

- 2020 v100 va 2021 v200 mahsulotlari.
- 10 m Cloud Optimized GeoTIFF, 11 land-cover klass.
- Qurilgan hudud, daraxt qoplami, grassland, suv va boshqa sinflarni tekshirish.
- CC BY 4.0. Attribution: © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium.
- 10 m piksel mayda ariqlar, kichik favvoralar yoki alohida daraxt inventarini almashtirmaydi.

### 10. JRC Global Surface Water
https://global-surface-water.appspot.com/download

- Yangilangan portal 1984-2024 vaqt oralig'ini ko'rsatadi.
- Tarixiy suv occurrence, seasonality va suv chegaralarining o'zgarishini tekshirish.
- Copernicus Programme ma'lumoti; attribution: Source: EC JRC/Google va tegishli ilmiy citation.
- Suv chuqurligi yoki kanal kesimini bermaydi.
- Eski Earth Engine v1.4 katalogi (1984-2021): https://developers.google.com/earth-engine/datasets/catalog/JRC_GSW1_4_GlobalSurfaceWater

### 11. Copernicus DEM
https://doi.org/10.5270/esa-c5d3d65

- GLO-30 va GLO-90 global DSM.
- DSM bino va o'simlik yuzasini ham o'z ichiga oladi; yalang'och yer DEM'i emas.
- 2026-08-25 xabariga ko'ra GLO-30 View Service uchun Contributing Missions user category ruxsati talab qilinadi; GLO-90 fallback bo'lishi mumkin: https://dataspace.copernicus.eu/news/2026-8-25-copernicus-dem-30m-view-service-update
- 30/90 m shahar mayda relyefi, bordyur yoki kanal qirg'og'i uchun survey-grade emas.

### 12. Copernicus Sentinel-2
https://dataspace.copernicus.eu/browser/  
https://dataspace.copernicus.eu/explore-data

Optik sun'iy yo'ldosh tasvirlari, 10 m klassdagi bandlar, NDVI/vegetatsiya va o'zgarishlarni tekshirish uchun. Bepul hisob kerak. Fasad teksturasi emas. Attribution: Contains modified Copernicus Sentinel data [year].

### 13. HydroSHEDS HydroRIVERS
https://www.hydrosheds.org/products/hydrorivers

Katta daryo tarmoqlari va gidrologik kontekst uchun. Toshkentning mayda shahar kanallari, ariqlari va zovurlarini alohida OSM/mahalliy qatlamlardan olish kerak.

## Ko'cha suratlari va panoramalar

### 14. Yandex Maps
https://yandex.com/maps/10335/tashkent/

Spot xabariga ko'ra 2026-yil iyulida Toshkentda 3,400 km yo'l bo'ylab qariyb 130,000 panorama yangilangan: https://www.spot.uz/oz/2026/07/23/yandex-maps/
Fasad, eshik, peshlavha va ko'cha muhitini vizual tekshirish uchun. Provider shartlarisiz tasvirlarni bulk yuklab olmang, saqlamang yoki texture sifatida qayta tarqatmang.

### 15. Google Maps / Street View
https://www.google.com/maps/@41.2995,69.2401,14z

Ko'rib tekshirish va joyga navigatsiya uchun. Google Maps kontentini ruxsatsiz scrape yoki offline texture kutubxonasiga aylantirmang.

### 16. Mapillary
https://www.mapillary.com/app/

Ko'ngillilar yuklagan ko'cha tasvirlari. Mapillary Help Center tasvirlar CC BY-SA ekanini bildiradi: https://help.mapillary.com/hc/en-us/articles/115001770409-CC-BY-SA-license-for-open-data
Har rasmda muallif, rasm URL'i va CC BY-SA attributionini yozib boring.

### 17. 2GIS
https://2gis.uz/tashkent

POI, kompaniya, kirish joylari va suratlarni solishtirish uchun. 2GIS shartlarisiz scrape yoki bulk export qilmang.

## Texnik vositalar

- QGIS: https://qgis.org/
- GDAL: https://gdal.org/
- Osmium Tool: https://osmcode.org/osmium-tool/
- Overpass API: https://overpass-api.de/
- Blender: https://www.blender.org/
- Unity: https://unity.com/
- Cesium OSM Buildings: https://cesium.com/platform/cesium-ion/content/cesium-osm-buildings/ — global OSM-derived 3D Tiles preview; o'z data licensing va ion foydalanish shartlari bor.
