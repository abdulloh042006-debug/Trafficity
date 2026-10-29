# RoadFlow City (Trafficity-dan ilhomlangan, Flutter + Flame, Android)

Tepadan ko'rinadigan yo'l qurilishi va mikroskopik transport simulyatsiyasi.

## Ishga tushirish
```
git clone https://github.com/abdulloh042006-debug/Trafficity.git
cd Trafficity
flutter create --platforms=android --org uz.abdulloh .
flutter pub get
flutter run                  # telefon ulangan holda
flutter build apk --release  # build/app/outputs/flutter-apk/app-release.apk
```
(`flutter create .` mavjud `lib/` va `pubspec.yaml` ni o'zgartirmaydi, faqat `android/` papkasini qo'shadi.)

## 1-bosqich (tayyor)
- Seed asosida xarita (suv, qum, o'tloq, tog'), boshlang'ich binolar
- Kamera: 2 barmoq bilan zoom/surish, sichqoncha g'ildiragi
- To'g'ri va egri yo'l, snap, suv/bino/burchak/mablag' tekshiruvi
- O'chirishda narx to'liq qaytadi

## 2-bosqich (tayyor, sinovdan o'tmagan)
- Yo'llar kesishganda va uchi yo'lga tegganda avtomatik chorraha (bo'linish)
- Har yo'lda ikki yo'nalishli polosa (o'ng tomonlama harakat), burilish yo'laklari
- Binolardan talab: uy -> do'kon/zavod, qaytish safari, zavoddan yuk mashinalari
- A* marshrut (vaqt + burilish jarimasi + navbat taxmini)
- IDM mashina ketma-ketligi, burilishdan oldin sekinlash, navbatlar
- Chorraha: burilishlar to'qnashuvi bo'yicha ruxsat, kutganga adolatli navbat
- Tahrirdan keyin mashinalar qayta marshrutlanadi (o'chirilgan yo'ldagilar "yo'qotilgan" deb sanaladi)
- Tezlik: Pauza / 1x / 2x / 4x, Saqlash / Yuklash / avtosaqlash

## 3-bosqich (tayyor, sinovdan o'tmagan)
- Svetofor: "Svetofor" asbobi bilan 3+ yo'lli chorrahaga bosing. Qo'yiladi (yashil 12 s), keyingi bosishlarda 20 s, 30 s, so'ng olib tashlanadi. Qarama-qarshi yo'nalishlar bir fazada, boshqa o'qlar navbat bilan. Sariq 2 s, hammasi qizil 1 s
- Aylana chorraha: "Aylana" asbobi bilan 3+ yo'lli chorrahaga bosing. Yo'llar qisqartirilib, soat miliga teskari bir tomonlama halqaga ulanadi (stub narxi qaytariladi)
- Tirbandlik xaritasi: "Tirbandlik" tugmasi yo'llarni o'lchangan o'rtacha tezlik/limit nisbati bo'yicha bo'yaydi (yashil -> qizil -> to'q qizil)
- Bir tomonlama yo'l modeli, saqlash formati v2 (eski v1 ham o'qiladi)

## 4-bosqich (tayyor, sinovdan o'tmagan)
- Mamnuniyat (0-100): 45% yo'lga ulanish + 25% safar vaqti + 20% oqim tezligi + 10% muvaffaqiyatli safarlar; sabab matni ko'rsatiladi
- Shahar darajalari (1-12): mamnuniyat nishonidan yuqori bo'lsa va barcha binolar yo'lga ulangan bo'lsa 20 s ushlab turing, yangi daraja: +1500 mablag' va yangi binolar
- Saqlashda daraja va binolar ham saqlanadi
- Yuklash xatosi tuzatildi: relyef alohida isolate'da yaratiladi, xato ekranda ko'rinadi

## 5-bosqich (tayyor, sinovdan o'tmagan)
- Yangi o'yin oynasi: 4 biom (tekislik, daryo deltasi, tog' vodiysi, orollar), 3 qiyinlik (boshlang'ich mablag', talab, mamnuniyat nishoni), seed, sandbox
- Sandbox: cheksiz mablag', bino qo'yish asbobi (uy/do'kon/zavod), talab ko'paytmasi (x0.5 ... x4)
- "Ma'lumot" asbobi: mashina (tezlik, safar vaqti, marshrut yoritiladi), chorraha (svetofor, kutayotganlar), yo'l (limit, oqim, mashinalar)
- Yo'l turlari: oddiy (40 km/s) va katta yo'l (60 km/s, 1.6x narx); marshrut tezroq yo'lni tanlaydi
- Ikonka: `assets/icon/icon.png` va `flutter_launcher_icons` sozlamasi (workflow'ga 2 qadam qo'shilsa ulanadi)

## 6-bosqich qismi (tayyor, sinovdan o'tmagan)
- O'rgatuvchi vazifalar (8 ta): kamera, birinchi yo'l, hamma binoni ulash, mashinalar, tirbandlik xaritasi, svetofor, aylana, 2-daraja. Bajarilganligi haqiqiy o'yin holatidan aniqlanadi, "O'tkazish" tugmasi bor
- Xatolar ekranda qizil chiplarda ko'rinadi (bosib yopiladi)

## 7-bosqich: diagnostika (tayyor, sinovdan o'tmagan)
- "Grafik" paneli: mashinalar, mamnuniyat, o'rtacha safar vaqti, tirband yo'llar ulushi (oxirgi ~3 daqiqa)
- "Eng og'ir joyni ko'rsat": eng ko'p mashina va eng past oqimli yo'lga kamerani olib boradi
- Xarita aylantirish (2 barmoq), binoga yaqinlashganda yo'l old tomonga tushadi, yaqin tugunlar birlashadi, chizayotganda chetga yetsa xarita suriladi
- Yo'l bo'linganda mashinalar yo'qolmasdan yangi polosaga ko'chadi
- Yo'l uchi yaqin yo'lga ulanmasa ogohlantiradi

## 8-bosqich: tillar (tayyor, sinovdan o'tmagan)
- Til tugmasi (UZ / RU / EN): interfeys, xabarlar va o'rgatuvchi vazifalar tarjima qilinadi, tanlov saqlanadi
- Android ikonkasi `android/app/src/main/res/mipmap-*` ichida (workflow o'zgartirilmasa ham ishlaydi)

## 9-bosqich: ko'p polosali yo'llar (tayyor, sinovdan o'tmagan)
- "Katta yo'l" (60 km/s) har yo'nalishda 2 polosa, 2.2x narx; polosa chiziqlari chiziladi
- Mashinalar polosani chorrahada marshrut orqali tanlaydi (tirbandlikni hisobga olib); o'ngga ichki, chapga tashqi polosadan burilish jarimalanadi
- Polosalar soni bo'yicha chorraha to'qnashuvlari geometriyadan hisoblanadi (parallel polosalar to'qnashmaydi, kesishganlari navbat bilan o'tadi)
- Hali yo'q: yo'l o'rtasida polosa almashtirish (quvib o'tish)

## Koordinata tekshiruvi va yo'l tuzatishlari
- Ekran -> dunyo formulalari (pan, zoom, burish, pinch) raqamli tekshirildi: xatolik ~1e-12. Barcha asboblar bitta `toWorld` dan foydalanadi
- Binoga avtomatik tushish radiusi endi ekran pikselida (34 px); oldin dunyo birligida bo'lib, katta zoom'da barmoqdan ~160 px uzoqqa sakrardi
- Chizayotganda barmoqning haqiqiy joyi to'q sariq halqa, ulangan nuqta bilan chiziq bilan ko'rsatiladi
- "Debug" tugmasi: qizil = barmoq, sariq = dunyo nuqtasidan ekranga qaytarilgan joy (mos tushishi kerak), ustida raqamlar (touch/world/dpr/o'lchamlar)
- Yo'l-bino to'qnashuvi: har 4 birlikda, yo'l yarim kengligi bilan (oddiy 6.5, katta 13)
- Bino uchun ikkala yo'nalish va barcha polosalar nishon: mashina qulay tomondan keladi (keraksiz aylanmaydi)

## 10-bosqich: ekologiya (tayyor, sinovdan o'tmagan)
- Ifloslanish: zavodgacha masofa (250 birlik gacha), shovqin: uy yaqinidagi mashinalar (yuk mashinasi 2x, 110 birlik gacha)
- Har bir uyning ekologik yuki hisoblanadi; mamnuniyatning 12% i ekologiyadan (0.40 ulanish, 0.22 safar, 0.18 oqim, 0.08 muvaffaqiyat, 0.12 ekologiya)
- "Ekologiya" tugmasi: zavod atrofida ifloslanish doirasi, uylarda yashil -> qizil belgi; "Ma'lumot" bilan uyga bossangiz yuki ko'rinadi
- Yuqori chip: "Ekologiya: n%"

## 11-bosqich: estakada va ko'priklar (tayyor, sinovdan o'tmagan)
- Pastdagi "Yer usti / Estakada" tugmasi: estakada yo'li boshqa yo'llar bilan KESISHMAYDI (ustidan o'tadi), faqat uchlari bilan ulanadi (rampa)
- Estakada uchi yer usti yo'liga yoki chorrahaga tushsa, ulanadi; yer usti yo'li estakada o'rtasiga ulana olmaydi
- Estakada daryo/ko'l ustidan o'ta oladi (uchlari quruqlikda bo'lishi kerak), 1.5x narx; soyasi bilan yuqorida chiziladi
- Binolar estakadaga to'g'ridan-to'g'ri chiqmaydi; saqlashda qatlam saqlanadi
- Shu bilan ko'p qavatli chorrahalar (rampali) qurish mumkin

## 12-bosqich: qulaylik (tayyor, sinovdan o'tmagan)
- Ortga / Oldinga (30 qadamgacha): yo'l qurish, o'chirish, aylana, svetofor, to'r; byudjet ham qaytariladi
- 3 ta saqlash uyasi + avtosaqlash ("Slotlar" oynasi, sana va daraja ko'rinadi)
- "To'r" asbobi: burchakdan burchakka sudrang, ko'rinish yo'nalishiga mos ko'cha to'ri; oraliq 80/110/150/200
- Ovoz/tebranish (tizim ovozi va haptik), debug'da fps va simulyatsiya vaqti
- `test/network_test.dart`: tarmoq/marshrut testlari (ishga tushirish: `flutter test`)

## 13-bosqich: ta'minot va moslashuvchanlik (tayyor, sinovdan o'tmagan)
- Do'konlarda tovar zaxirasi: yuk mashinasi yetib kelsa +12, mijoz kelsa -1; zaxira tugasa mijoz xizmatsiz qoladi
- Mamnuniyatning 8% i ta'minotdan (0.37 ulanish, 0.20 safar, 0.17 oqim, 0.07 muvaffaqiyat, 0.11 ekologiya, 0.08 ta'minot); yuk mashinalari tirbandlikda qolsa ta'minot pasayadi
- "Ranglar": ko'r odamlar uchun tirbandlik palitrasi; "Hajm": interfeys matn va tugma hajmi (saqlanadi)

## Tayyor shahar (boshlang'ich holat)
- O'yin ochilganda tayyor shahar turadi: 2 ta katta yo'l (2 polosali) kesishmasida aylana chorraha, parallel yo'l va svetoforli chorraha, hamma binoga mahalliy yo'l. Faqat mavjud asboblar ishlatilgan, yangi imkoniyat yo'q
- Reja bino joylashuviga qarab ishga tushganda hisoblanadi (har seedda mos tushadi), xato bo'lsa bo'sh xarita bilan davom etadi
- Yakunda o'chirish: `lib/game/road_game.dart` ichida `static const bool idealCityOnStart = true;` ni `false` qiling (o'yin bo'sh boshlanadi)
- Tayyor shahar byudjetga bog'lanmay quriladi, so'ng qolgan mablag' qiyinlikka qarab 1500 / 1000 / 700 qilib qo'yiladi (sandbox'da cheksiz)
- Rejalashtirish mantig'i 300 ta tasodifiy bino joylashuvida Python'da sinab ko'rilgan: asosiy yo'llar har doim topildi; mahalliy yo'l variantlari bilan 10 ta shaharda 200 binoning 100% i ulandi
- "Yangi" tugmasi bilan boshlangan o'yinlar oldingidek bo'sh boshlanadi

## 14-bosqich: ustuvor yo'llar va adaptiv svetofor (tayyor, sinovdan o'tmagan)
- Svetoforsiz chorrahada kiruvchi yo'llar turli sinfda (oddiy / katta yo'l) bo'lsa, past sinfdagi mashina stopline'da TO'LIQ to'xtaydi va yaqinlashayotgan (45 birlik) to'qnashuvchi mashinaga yo'l beradi; ustun yo'ldagilar to'xtamaydi
- Svetofor tugmasi: yashil 12 -> 20 -> 30 s -> adaptiv -> olib tashlash. Adaptiv: faol faza bo'sh, boshqasida kutayotgan bo'lsa, yashilni (6 s dan keyin) erta tugatadi
- Adaptiv holat saqlanadi va bekor qilish/qaytarishda tiklanadi

## 15-bosqich: magistral va polosa almashtirish (tayyor, sinovdan o'tmagan)
- Yo'l turi tugmasi: Oddiy (40 km/s, 1 polosa) -> Katta yo'l (60 km/s, 2 polosa) -> Magistral (100 km/s, har yo'nalishda 3 polosa, 3.6x narx)
- Magistral hech qaysi yo'l bilan kesishmaydi (qavatlararo); ulanish faqat uchlari yoki unga ulangan yo'l (rampa) orqali. Binolar magistralga chiqmaydi. "Estakada" bilan birga daryo ustidan o'tadi
- Polosa almashtirish: sekin mashina ortida qolgan mashina qo'shni polosaga o'tadi (old/orqa masofa va foyda tekshiriladi, 5 s kutish, silliq ko'ndalang siljish)
- Chorrahada burilish polosasi tanlovi to'g'rilandi: o'ngga tashqi, chapga ichki polosa afzal
- Polosa id'lari 8 ga kengaytirildi (3 polosagacha)

## 16-bosqich: bosh menyu va sozlamalar (tayyor, sinovdan o'tmagan)
- Bosh menyu: Davom etish, Yangi o'yin, O'rgatish, Sandbox, Saqlangan o'yinlar, Sozlamalar, Chiqish. Menyu ochiq bo'lganda simulyatsiya to'xtaydi; pastki panelda "Menyu" tugmasi bor
- Sozlamalar oynasi: til (UZ/RU/EN), ovoz, ko'r odamlar uchun ranglar, matn hajmi
- "Yangi o'yin" oynasida tanlangan seed va biom bo'yicha xarita ko'rinishi (relyef rasmi) chiqadi

## 17-bosqich: fon musiqasi (tayyor, sinovdan o'tmagan)
- `assets/audio/ambient.wav`: 24 soniyalik, uzluksiz takrorlanadigan sokin pad (Am-F-C-G akkordlari). Loyiha ichida kod bilan yaratilgan, tashqi manba yo'q, mualliflik huquqi masalasi yo'q
- "Ovoz" tugmasi / sozlamalardagi "Ovoz" musiqani ham yoqadi/o'chiradi; ilova fonga o'tganda to'xtaydi
- Paket: `audioplayers` (xato bo'lsa o'yin davom etadi, faqat musiqasiz)

## 18-bosqich: tashqi ko'rinishni soddalashtirish va estakada rampasi (tayyor, sinovdan o'tmagan)
- Estakada uchi yer usti yo'liga endi rampa bo'lib tushadi: oxirgi ~70 birlikda yo'l yerdan silliq ko'tariladi, soya va chekka balandlik bilan o'sadi (oldin qora halqa va soya yer yo'li ustiga "yopishib" turardi). Hech narsaga ulanmagan estakada uchi ham yerga tushadi (ko'prik tayanchi)
- Chizish tartibi: yer usti yo'li -> bino -> yer usti mashinalari -> estakada -> estakadadagi mashinalar. Estakada ostidan o'tgan mashinalar ko'prik ostida yashirinadi
- Yo'l belgilari: ikki tomonlama oddiy yo'lda sariq punktir, katta yo'l/magistralda sariq ajratgich, polosalar orasida oq punktir; uzoqdan (zoom < 0.3) chizilmaydi
- Yuqori panel: bitta ixcham panel (asosiy: mablag', daraja, mamnuniyat; ikkinchi qator: mashina, yetib bordi, o'rtacha, ekologiya, ta'minot); "Yo'llar" soni olib tashlandi
- Pastki panel: Ovoz, Ranglar, Hajm, Til, Debug, Slotlar, Yangi tugmalari olib tashlandi (menyu va sozlamalarda bor; Debug sozlamalarga ko'chdi). Tugmalar guruhlarga ajratildi
- Ortiqcha animatsiyalar olib tashlandi: bosilganda to'lqin (splash) va yuklanishdagi aylanuvchi indikator

## 19-bosqich: chorrahada silliq burilish (tayyor, headless sinovdan o'tgan, telefonda emas)
- Sabab: polosalar tugun markazida tugardi, burilish yo'li esa 3.5 birlikli kichik egri bo'lib, boshlang'ich/oxirgi yo'nalishi mashina yo'nalishiga mos kelmasdi (o'ng burilishda mashina halqa bo'lib aylanardi). Ideal shaharda 248 burilishdan 236 tasining boshlang'ich yo'nalishi 20° dan ko'p og'gan edi
- Polosalar chorraha oldida to'xtash chizig'igacha qisqartiriladi (chorraha o'lchamiga qarab: yo'l yarim eni + 3; tupikda kesilmaydi; qisqa yo'lda uzunlikning 25% igacha). Svetoforlar ham shu chiziqda turadi
- Burilish: urinma chiziqlar kesishgan nuqtada kvadratik Bezye (o'ng/chap), aks holda kubik (to'g'ri, U-burilish)
- Yo'l uchi boshqa yo'lga ulanganda qolgan keskin burchaklar va siniq mahalliy yo'llar polosa chizig'ida yumaloqlanadi; keskin egri yo'llar zichroq tanlanadi
- Binoga kirish nuqtasi qisqa polosada xavfsiz (clamp xatosi yo'q); chorrahada yo'l o'zgarsa mashinalar kengroq radiusda ko'chiriladi
- O'lchov (3 ta shahar, 125 mashina, 8 daqiqa): burilishda 28° dan katta sakrashlar ~400-670 -> 4-7; yetib borgan safarlar 326 -> 416. Tirbandlik (mashinalarning ~85% i to'xtab qolishi) ikkala variantda ham bor: u alohida muammo (chiqish polosasida joy yo'qligi)

## Hali yo'q
Aylanada kiruvchiga "yo'l bering" qoidasi (hozir kim birinchi so'rasa), ko'p polosali yo'llar, magistral va ramplar, iqtisodiyot va darajalar, qo'lda svetofor fazalarini tahrirlash.

## Eslatma
Kod Flutter bo'lmagan muhitda yozilgan va kompilyatsiya qilib sinalmagan.
