# Toshkent 3D ishlab chiqarish rejasi

## 1. Asosiy geometriya
- Shahar chegarasi, 12 tuman va mahalla poligonlarini rasmiy manbadan olish.
- Buildings: footprint, building parts, entrance, roof outline, address.
- Green: park, garden, lawn, wood, tree/tree row, shrub, path, playground.
- Blue: water polygon, river/canal/ditch/drain centerline, pond, reservoir, fountain, dam/weir, bridge, embankment.
- Transport: roads, sidewalks, railway, stop/platform, parking, crossing, bridge/tunnel.
- POI: shop, market, office, school, hospital, mosque, museum, sport and public service.
- Terrain/imagery: elevation, land cover, NDVI and satellite image.

## 2. Atributlarni to'ldirish
Har feature uchun source, source_id, source_date, license, confidence saqlansin. Kerakli atributlar: name, address, category, operator, height_m, levels, roof_shape, roof_material, facade_material, surface, species, tree_height, crown_diameter, water_type.

Balandlik mavjud bo'lmasa estimated_height maydonida alohida belgilang. Unknown qiymatni 0 qilib yozmang.

## 3. 3D geometriya
- Buildings: footprint extrude + height/levels. Tom va fasadni tasdiqlangan rasmlardan tiklash.
- Trees: daraxt nuqtasi + species/height/crown. Bir xil turlarni GPU instancing bilan joylashtirish.
- Parks: terrain-conforming park surface, yo'lak, maysazor, gulzor, playground, sport.
- Water: kanal/ariq spline, suv polygon, qirg'oq va kesim profili, ko'prik va suv inshooti.
- Roads: road mesh, sidewalk, curb, marking, crossing, traffic equipment.
- Furniture: lamp, bench, sign, bin va barrier uchun instanced model library.

## 4. Vizual tekshiruv
1. Xarita koordinatasidan street panorama yoki litsenziyali Mapillary suratini oching.
2. Fasad/kirishni imkon qadar ikki yo'nalishdan tekshiring.
3. Surat sanasi va qurilish o'zgarishini qayd qiling.
4. Ruxsat bo'lmagan panora tasvirini texture sifatida nusxalamang. Geometriyani mustaqil modellashtiring yoki ruxsatli foto ishlating.

## 5. QA
- Geometry: duplicate, self-intersection, gap, overlap va CRS alignment.
- Attribute: height/levels manbasi aniq bo'lsin.
- Water: tarixiy suv occurrence'ni hozirgi shoreline bilan aralashtirmang.
- Coverage: 12 tuman bo'yicha bino, park, tree, water va POI count; unknown-height va no-photo statistika.
- Unity: joylashuv, scale, rotation, LOD va chunk seams.

## 6. Unity optimizatsiyasi
- 500 m–1 km grid yoki Trafficity mavjud chunk sxemasidan foydalanish.
- LOD0: yaqin fasad; LOD1: soddalashtirilgan bino; LOD2: blok massing; LOD3: uzoqdagi instanced/2D.
- Park daraxtlari va ko'cha jihozlari GPU instancing.
- Suv va yo'l meshlarini chunk bo'yicha ajratish.
- Collider faqat gameplay/navigatsiya uchun kerak bo'lgan joyda.

## 7. Tavsiya etilgan bajarish tartibi
1. Rasmiy Toshkent chegarasi va 12 tuman poligonlarini olish.
2. OSM + Overture'ni kesish, dublikatlarni aniqlash.
3. Green Tashkent va shahar GeoServer'idan foydalanish ruxsatini aniqlash.
4. Bitta tumanda pilot: buildings + roads + parks + trees + waterways + POI.
5. 20-50 muhim bino va 2-3 parkni yuqori detalda modellashtirish.
6. Qolgan binolarni massing qilib, quality auditdan keyin 12 tumanga yoyish.
