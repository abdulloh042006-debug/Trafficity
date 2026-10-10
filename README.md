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

## Hali yo'q
Aylanada kiruvchiga "yo'l bering" qoidasi (hozir kim birinchi so'rasa), ko'p polosali yo'llar, magistral va ramplar, iqtisodiyot va darajalar, qo'lda svetofor fazalarini tahrirlash.

## Eslatma
Kod Flutter bo'lmagan muhitda yozilgan va kompilyatsiya qilib sinalmagan.
