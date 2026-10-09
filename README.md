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

## Hali yo'q
Svetoforlar, aylanma chorraha, ko'p polosali yo'llar, magistral, iqtisodiyot va darajalar, tirbandlik xaritasi.

## Eslatma
Kod Flutter bo'lmagan muhitda yozilgan va kompilyatsiya qilib sinalmagan.
