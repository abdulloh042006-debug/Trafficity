# CLAUDE.md — RoadFlow City (Trafficity klon) — YAGONA MANBA, AVVAL SHUNI O'QING

## Loyiha kimligi (boshqa loyihalar bilan adashtirmang)
Bu **RoadFlow City**: Flutter + Flame'da Android o'yini, tepadan ko'rinadigan yo'l qurilishi va transport simulyatsiyasi
(Steam'dagi Trafficity'dan ilhomlangan, original). Egasi: Abdulloh. Bu MUU LMS, K-Quest, Phone Mouse, Acoustic3D,
KoreyaViza EMAS. Repo: https://github.com/abdulloh042006-debug/Trafficity (public, branch `main`). Til: foydalanuvchi bilan o'zbekcha.

## Tejamkorlik qoidalari (kredit tugamasligi uchun, majburiy)
- Fayllarni to'liq chiqarib o'qima: `grep -n`, `sed -n 'a,bp'`. O'zgarmagan faylni qayta o'qima. Avval shu fayl, keyin kerakli joy.
- O'zgartirish: Python skriptda `rep(s, eski, yangi)` + `count==1` tekshiruvi (anchor topilmasa to'xtaydi), keyin qavs-balans tekshiruvi.
- Bir bosqich = bitta push. Hujjat o'zgarishi uchun commit xabarida `[skip ci]`. CI natijasini ko'pi bilan 2 marta (har biri <=60 s) tekshir, bo'lmasa foydalanuvchidan so'ra.
- Python sinovlari <=60 s (timeout 100). Uzoq simulyatsiyani kichraytir (N=10). 300 s dan oshgan buyruq ish bermaydi.
- present_files faqat yakuniy yuklab olinadigan fayl uchun (APK/arxiv); har fayl uchun emas.
- Javob qisqa: nima qilindi, nima tekshirilmagan, keyingi qadam. Ortiqcha reja/hisobot yozma.
- Yangi funksiya qo'shishdan oldin foydalanuvchi so'ragan narsa ekanini tekshir ("ortiqcha yangilik qo'shma" degan edi).

## Muhit va ishlash tartibi
- Flutter bu muhitda oldindan YO'Q, lekin o'rnatsa bo'ladi (proxy orqali ishladi): scratchpad'da `git clone --depth 1 -b stable https://github.com/flutter/flutter.git`, so'ng `flutter pub get` (~3 daqiqa; PATH ga `flutter/bin`, `CI=true`). Shunda `flutter analyze` va `flutter test` (10 ta test PASS) ishlaydi. Renderni tekshirish: vaqtinchalik `test/zz_*_test.dart` da `testWidgets` + `tester.runAsync`, `RoadGame().render(canvas)` yoki `RepaintBoundary.toImage` -> PNG (shrift: `bin/cache/artifacts/material_fonts` dan `FontLoader`); keyin faylni o'chiring. Telefon sinovi o'rnini baribir bosmaydi.
- Mantiqni Python'da modellashtirish mumkin (foydalanuvchi ruxsat bergan): geometriya/marshrut/rejalashtirish.
- Loyiha nusxasi: `/mnt/user-data/outputs/roadflow_city/` (repo bilan bir xil). Push: vaqtinchalik klon, `cp -r`, `git checkout HEAD -- .github`
  (token `workflow` ruxsatisiz: workflow faylini o'zgartirib push qilib bo'lmaydi), commit, push, token URL'dan olib tashlanadi.
- Token KODGA/HUJJATGA/XOTIRAGA YOZILMAYDI. Foydalanuvchi uni chatda oshkor qilgan; o'chirib yangisini yaratishi tavsiya etilgan.
- APK: Actions -> oxirgi "Build APK" -> Artifacts `roadflow-apk`. Imzo har build'da o'zgaradi: eski ilovani o'chirib o'rnatish kerak
  (doimiy imzo `ci/debug.keystore` tayyor, lekin workflow'ni foydalanuvchi qo'lda yangilashi kerak, hali yangilamagan).

## Arxitektura (lib/)
- `main.dart`: ixcham HUD paneli (`_panel`/`_stat`), pastki asboblar paneli (faqat asboblar va qatlamlar; til/ovoz/ranglar/hajm/debug sozlamalarda, slotlar/yangi o'yin menyuda), bosh menyu, sozlamalar, slotlar, yangi o'yin oynasi (xarita ko'rinishi), musiqa (audioplayers), xato chipi. Animatsiyalar ataylab yo'q (splash o'chirilgan, yuklashda spinner yo'q).
- `l10n.dart`: UZ/RU/EN, o'zbekcha matnlar jadval bo'yicha tarjima qilinadi (`L.t`). Yangi matn qo'shsang jadvalga ham qo'sh.
- `game/road_game.dart` (eng katta): kamera (zoom/pan/burish), pointer boshqaruvi, asboblar (to'g'ri, egri, to'r, svetofor, aylana, o'chirish,
  bino, ma'lumot), chizish, saqlash/yuklash (3 slot + avto), undo/redo, iqtisod/mamnuniyat/daraja, ekologiya, tayyor shahar, debug.
- `game/road_network.dart`: yo'l topologiyasi (tugun/yo'l bo'lagi), connectRoad (kesishuvda bo'lish), splitRoadAt, mergeCloseNodes,
  buildRoundabout, qatlamlar (layer 1 = estakada), tur (0 oddiy, 1 katta=2 polosa, 2 magistral=3 polosa).
- `game/lane_graph.dart`: polosalar (id = roadId*8 + (fwd?0:4) + lane), connectors, A* marshrut, bino kirishi (Access.goals).
- `game/traffic_sim.dart`: IDM, chorraha ruxsati (_tryGrant, geometrik to'qnashuv, adolat), ustuvor yo'llar (_minorAt), svetofor (fixed + adaptiv),
  polosa almashtirish, talab (uy->do'kon/zavod, yuk mashinasi), do'kon zaxirasi, mashinalarni yo'l o'zgarganda ko'chirish (_relocate).
- `game/terrain.dart`: protsedura biomlar (0-3) va biom 4 = haqiqiy Toshkent (`TashkentMap`: `assets/map/tashkent.webp` + suv niqobi; markaz Amir Temur xiyoboni = (3200,3200)); `RoadGame.terrHalf` hudud yarim kengligi (1200 + 300/daraja), tashqarisi tuman; `tools/map/build_tashkent.py` aktivlarni OSM SVG'dan yaratadi (SVG repoda yo'q).
- `game/{traffic_model,signal,terrain,building}.dart`; `test/network_test.dart` (10 test, PASS); `ci/debug.keystore`; `assets/{audio,icon}`.
- Konstantalar: dunyo 6400x6400 birlik (eski saqlashlar 3200), Toshkent biomida 1 birlik ~ 1 m (tezlik km/s hisobi 0.5 m/birlik deb qoldi); polosa 7; yo'l eni 14; mashina 9 (yuk 22); maxVehicles 100+25*daraja (<=250).

## Holat (dalil bilan)
**IMPLEMENTED AND VERIFIED** (foydalanuvchi skrinshotlari / telefon): xarita va relyef yuklanadi; kamera surish/zoom; to'g'ri va egri yo'l;
kesishuvda chorraha bo'linishi; mashinalar yuradi va navbat hosil qiladi; mamnuniyat va daraja oshishi; tirbandlik xaritasi; aylana chorraha;
APK o'rnatiladi.
**VERIFIED HEADLESS** (flutter analyze + render PNG, telefonda emas): Toshkent xaritasi (haqiqiy OSM, Amir Temur markazi, suv niqobi, hudud kengayishi `_growTerritory`, tuman, 12 unit test), chorrahada silliq burilish (polosa to'xtash chizig'igacha qisqaradi, urinmali Bezye burilish, `LaneGraph._turnPts`/`_setback`/`smoothCorners`; 10 unit test), estakada rampasi (uchi yerga silliq tushadi, soya/chekka balandlik bilan o'sadi, `_drawElevated`), yer usti mashinalari estakada ostida, punktir yo'l belgilari, ixcham yuqori panel, 8 unit test.
**IMPLEMENTED BUT NOT VERIFIED** (faqat CI kompilyatsiyasi o'tgan): xarita burish; binoga avtomatik tushish (ekran pikselidagi radius); tugunlarni
birlashtirish; undo/redo; 3 saqlash uyasi; to'r asbobi; grafiklar + "eng og'ir joy"; ekologiya; do'kon zaxirasi/ta'minot; estakada/ko'prik;
katta yo'l va magistral; polosa almashtirish; ustuvor yo'llar; adaptiv svetofor; TAYYOR SHAHAR (default); bosh menyu; musiqa; UZ/RU/EN;
ko'r odamlar palitrasi; matn hajmi; debug overlay (barmoq<->dunyo); audit tuzatishlari (eskirgan kutuvchilar, xavfsiz bo'lish).
**INCOMPLETE**: o'rgatish (8 vazifa); iqtisod zanjiri (ishchilar/ishlab chiqarish yo'q); ishlash o'lchovi (faqat debug fps/sim ms/marshrut soni).
**NOT IMPLEMENTED**: polosa qo'shish/yo'l yangilash asbobi; stop/yield belgisi asbobi (ustuvorlik avtomatik); svetofor fazalarini qo'lda tahrirlash;
5000+ agent; piyoda/avtobus; replay; haqiqiy audio effektlar (faqat tizim tovushi).
**BLOCKED** (foydalanuvchi kerak): workflow YAML yangilash (nom "RoadFlow City", doimiy imzo, `flutter test`); telefonda sinash.

## Tayyor shahar
`idealCityOnStart = true` (`road_game.dart`): ochilganda 2 katta yo'l + aylana + parallel yo'l + svetoforli chorraha + hamma binoga mahalliy yo'l,
byudjet 1500/1000/700 (qiyinlikka qarab). Reja Python'da 300 tasodifiy joylashuvda sinalgan (asosiy yo'llar doim topildi; yo'l izlash
kuchaytirilgach 10 shaharda 100% bino ulandi). Dart kodining o'zi telefonda sinalmagan; xatoda bo'sh xaritada ochiladi + "Tayyor shahar qurilmadi" xabari.
**O'yin 100% tugaganda "0 qilish": shu konstantani `false` qiling.**

## Ma'lum xavflar
Chorrahada qotib qolish (gridlock) headless o'lchandi: ideal shaharda 125 mashina bilan ~8 daqiqada mashinalarning ~85% i to'xtab qoladi (asosiy sabab: chiqish polosasida joy yo'q, `_tryGrant` 'exit'; qisqa polosalar ko'p) — hal qilinmagan; polosa almashtirish va ustuvorlik mantiqi sinalmagan; tahrirda mashinalar yo'qolishi
("Yo'qotilgan" chipi); 250+ mashinada ishlash o'lchanmagan; `connectRoad` kesishuvlari juda yaqin nuqtalarda.

## Keyingi qadamlar (ustuvorlik tartibida)
1. Foydalanuvchi oxirgi APK'ni o'rnatadi va xatolarni (skrinshot, "Debug" raqamlari, qizil "Xato:" chip) yuboradi -> ildiz sababni topib tuzat.
2. Foydalanuvchi workflow YAML'ni qo'yadi (README oxiridagi/yaqinda yuborilgan blok: keystore + icon/name + `flutter test`).
3. Telefon natijalariga ko'ra: qotib qolish, tayyor shahar, polosa almashtirish tuzatishlari.
4. Ishlash: 250 mashinada fps/sim ms (Debug) o'lcha; faqat o'lchovga qarab optimallashtir.
5. Faqat so'ralsa: polosa qo'shish/yangilash asbobi, stop/yield, svetofor fazalari.

## Sinov (foydalanuvchi/AI agent bajaradi, Flutter bor muhitda)
`flutter pub get && flutter analyze && flutter test && flutter build apk --release`. Kutiladi: analyze xatosiz, `test/network_test.dart` 10 ta test PASS,
APK yig'iladi. Xato bo'lsa: to'liq chiqishni yuboring (PASS/FAIL/BLOCKED/NOT TESTED). Telefonda: ochilganda tayyor shahar, mashinalar yuradi,
"Debug" yoqilganda qizil va sariq halqa ustma-ust, Ortga/Oldinga, To'r, Estakada, Magistral, til tugmasi, musiqa.

## Yangi sessiya uchun qisqa prompt (nusxa oling)
"Sen RoadFlow City (Flutter+Flame, Android traffic o'yini) dasturchisisan. Avval repo ildizidagi CLAUDE.md ni o'qi (yagona manba), keyin faqat
kerakli fayl joylarini grep/sed bilan ko'r. Tejamkor bo'l: uzun chiqish, ortiqcha push/CI kutish, uzoq sinov yo'q. Dart ishga tushmaydi: mantiqni
Python'da <=60 s sinab ko'r, kompilyatsiyani CI tekshiradi. Faqat foydalanuvchi so'ragan ishni qil, yangi funksiya qo'shma. 'Keyingi qadamlar'
dagi eng yuqori tugallanmagan vazifadan davom et, o'zbekcha qisqa yoz va nima tekshirilmaganini ochiq ayt."
