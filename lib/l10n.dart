/// Til tanlash: 0 o'zbekcha (asl matnlar), 1 ruscha, 2 inglizcha.
/// Matnlar o'zbekcha yoziladi, ko'rsatishda jadval bo'yicha tarjima qilinadi.
/// Jadvalda yo'q iboralar o'zbekcha qoladi (xato bermaydi).
class L {
  static int lang = 0;

  // [uz, ru, en]
  static const List<List<String>> _t = [
    // --- jumlalar va yo'riqnomalar
    ["Xaritani suring; 2 barmoq bilan kattalashtiring va buring", "Двигайте карту; двумя пальцами масштабируйте и вращайте", "Drag to pan; use two fingers to zoom and rotate"],
    ["Barmoqni bosib sudrang: to'g'ri yo'l shu yerda quriladi", "Проведите пальцем: здесь будет прямая дорога", "Drag your finger: a straight road will be built here"],
    ["Yo'lni egish uchun kerakli joyga barmoqni bosing", "Нажмите, чтобы изогнуть дорогу", "Tap to bend the road"],
    ["Boshidan oxirigacha sudrang, keyin eging", "Проведите от начала до конца, затем изогните", "Drag from start to end, then bend"],
    ["Chorrahaga bosing: svetofor qo'yish, vaqtini o'zgartirish yoki olib tashlash", "Нажмите на перекрёсток: поставить светофор, изменить время или убрать", "Tap a junction: add a signal, change timing or remove"],
    ["Chorrahaga bosing: shu joyda aylana chorraha quriladi", "Нажмите на перекрёсток: здесь построится кольцо", "Tap a junction: a roundabout will be built here"],
    ["Bo'sh joyga bosing: bino qo'yiladi", "Нажмите на свободное место: появится здание", "Tap an empty spot to place a building"],
    ["Mashina, yo'l yoki chorrahaga bosing: ma'lumot chiqadi", "Нажмите на машину, дорогу или перекрёсток: покажется информация", "Tap a vehicle, road or junction for info"],
    ["Yo'lga tegib o'chiring (pul to'liq qaytadi)", "Коснитесь дороги, чтобы убрать (деньги вернутся полностью)", "Tap a road to erase (full refund)"],
    // --- xatolar va xabarlar
    ["Mablag' yetarli emas", "Недостаточно средств", "Not enough budget"],
    ["Juda qisqa", "Слишком короткая", "Too short"],
    ["Burchak juda keskin", "Слишком острый угол", "Angle too sharp"],
    ["Suv ustiga yo'l qurib bo'lmaydi", "На воде строить нельзя", "Can't build on water"],
    ["Yo'l binoga tegmoqda", "Дорога задевает здание", "Road touches a building"],
    ["Chorraha ustiga bosing (kamida 3 yo'l)", "Нажмите на перекрёсток (минимум 3 дороги)", "Tap a junction (at least 3 roads)"],
    ["Aylana chorraha qurildi", "Кольцо построено", "Roundabout built"],
    ["Svetofor qo'yildi: yashil", "Светофор поставлен: зелёный", "Signal placed: green"],
    ["Svetofor olib tashlandi", "Светофор убран", "Signal removed"],
    ["Yashil vaqt", "Зелёный свет", "Green time"],
    ["Bu yerga bino qurib bo'lmaydi", "Здесь строить нельзя", "Can't build here"],
    ["Joy band yoki yo'l juda yaqin", "Место занято или дорога слишком близко", "Spot taken or road too close"],
    ["Bu yerda ma'lumot yo'q", "Здесь нет информации", "No info here"],
    ["Diqqat: yo'l uchi yaqin yo'lga ulanmadi. Uchini yo'lga yaqinlashtiring", "Внимание: конец дороги не соединён с соседней. Приблизьте его к дороге", "Warning: the road end is not joined to a nearby road. Move it closer"],
    ["Kamida 3 ta yo'l kerak", "Нужно минимум 3 дороги", "At least 3 roads needed"],
    ["Bir tomonlama yo'l bilan bo'lmaydi", "Нельзя с односторонней дорогой", "Not possible with a one-way road"],
    ["Yopiq halqa yo'l bilan bo'lmaydi", "Нельзя с замкнутой петлёй", "Not possible with a closed loop"],
    ["Yo'llar juda qisqa", "Дороги слишком короткие", "Roads too short"],
    ["Yo'llar orasidagi burchak juda kichik", "Слишком малый угол между дорогами", "Angle between roads too small"],
    ["Aylana uchun joy band", "Место под кольцо занято", "No room for a roundabout"],
    ["Jiddiy tirbandlik topilmadi", "Серьёзных пробок нет", "No serious congestion"],
    ["Eng og'ir joyni ko'rsat", "Показать худшее место", "Show the worst spot"],
    ["Eng og'ir joy", "Самое тяжёлое место", "Worst spot"],
    ["O'rgatish tugadi. Omad!", "Обучение завершено. Удачи!", "Tutorial finished. Good luck!"],
    ["Yo'lga ulanmagan binolar", "Здания без дороги", "Buildings without road"],
    ["Safarlar juda uzoq davom etyapti", "Поездки слишком долгие", "Trips take too long"],
    ["Tirbandlik mamnuniyatni pasaytiryapti", "Пробки снижают довольство", "Congestion lowers satisfaction"],
    ["Tarmoq yaxshi ishlayapti", "Сеть работает хорошо", "The network works well"],
    ["yangi binolar", "новые здания", "new buildings"],
    ["Yuklanmoqda...", "Загрузка...", "Loading..."],
    ["Relyef yaratilmoqda...", "Создаётся рельеф...", "Generating terrain..."],
    ["Binolar joylashtirilmoqda...", "Размещаются здания...", "Placing buildings..."],
    ["Saqlab bo'lmadi", "Не удалось сохранить", "Could not save"],
    ["Saqlangan o'yin topilmadi", "Сохранение не найдено", "No saved game found"],
    ["Saqlandi", "Сохранено", "Saved"],
    ["Yuklandi", "Загружено", "Loaded"],
    // --- o'rgatuvchi vazifalar
    ["Kamerani suring, kattalashtiring yoki buring (2 barmoq)", "Двигайте, масштабируйте или вращайте карту (2 пальца)", "Pan, zoom or rotate the map (2 fingers)"],
    ["«To'g'ri» asbobi bilan birinchi yo'lni chizing", "Проведите первую дорогу инструментом «Прямая»", "Draw your first road with the «Straight» tool"],
    ["Barcha binolarni yo'lga ulang", "Соедините все здания дорогами", "Connect all buildings with roads"],
    ["Mashinalar yurishini kuzating (kamida 3 safar)", "Понаблюдайте за движением (минимум 3 поездки)", "Watch the traffic flow (at least 3 trips)"],
    ["«Tirbandlik» tugmasi bilan yo'l yuklanishini ko'ring", "Нажмите «Пробки», чтобы увидеть загрузку дорог", "Press «Traffic» to see road load"],
    ["«Svetofor» bilan chorrahaga svetofor qo'ying", "Поставьте светофор на перекрёстке («Светофор»)", "Place a signal at a junction with «Signal»"],
    ["«Aylana» bilan aylana chorraha quring", "Постройте кольцо инструментом «Кольцо»", "Build a roundabout with «Roundabout»"],
    ["Mamnuniyatni oshirib 2-darajaga chiqing", "Повысьте довольство и достигните 2-го уровня", "Raise satisfaction and reach level 2"],
    // --- sarlavhalar, tugmalar, chiplar
    ["Sandbox: cheksiz mablag'", "Песочница: безлимитный бюджет", "Sandbox: unlimited budget"],
    ["Sandbox (cheksiz mablag')", "Песочница (безлимитный бюджет)", "Sandbox (unlimited budget)"],
    ["Yangi o'yin", "Новая игра", "New game"],
    ["Tirband yo'llar", "Пробки на дорогах", "Congested roads"],
    ["Safar vaqti", "Время поездки", "Trip time"],
    ["Yo'l topilmadi", "Маршрут не найден", "No route"],
    ["Qayta urinish", "Повторить", "Retry"],
    ["Daryo deltasi", "Дельта реки", "River delta"],
    ["Tog' vodiysi", "Горная долина", "Highland valley"],
    ["Katta yo'l", "Магистраль", "Arterial"],
    ["Oddiy yo'l", "Обычная дорога", "Local road"],
    ["Mablag'", "Бюджет", "Budget"],
    ["mablag'", "бюджет", "budget"],
    ["Yo'llar", "Дороги", "Roads"],
    ["Daraja", "Уровень", "Level"],
    ["Mamnuniyat", "Довольство", "Satisfaction"],
    ["Mashina:", "Машин:", "Vehicles:"],
    ["Mashinalar", "Машины", "Vehicles"],
    ["Mashina", "Машина", "Vehicle"],
    ["Yetib bordi", "Доехали", "Arrived"],
    ["O'rtacha", "Среднее", "Average"],
    ["Yo'qotilgan", "Потеряно", "Lost"],
    ["Vazifa", "Задача", "Task"],
    ["Xato", "Ошибка", "Error"],
    ["Kamera", "Камера", "Camera"],
    ["Shimol", "Север", "North"],
    ["To'g'ri", "Прямая", "Straight"],
    ["Egri", "Кривая", "Curve"],
    ["Svetofor", "Светофор", "Signal"],
    ["Aylana", "Кольцо", "Roundabout"],
    ["O'chirish", "Снос", "Erase"],
    ["Ma'lumot", "Инфо", "Info"],
    ["Do'kon", "Магазин", "Shop"],
    ["Zavod", "Завод", "Factory"],
    ["Uy", "Дом", "House"],
    ["Talab", "Спрос", "Demand"],
    ["Bekor", "Отмена", "Cancel"],
    ["O'tkazish", "Пропуск", "Skip"],
    ["Pauza", "Пауза", "Pause"],
    ["Tirbandlik", "Пробки", "Traffic"],
    ["Grafik", "Графики", "Charts"],
    ["Saqlash", "Сохранить", "Save"],
    ["Yuklash", "Загрузить", "Load"],
    ["Yangi", "Новая", "New"],
    ["Boshlash", "Начать", "Start"],
    ["Biom", "Биом", "Biome"],
    ["Qiyinlik", "Сложность", "Difficulty"],
    ["Tekislik", "Равнина", "Plains"],
    ["Orollar", "Острова", "Islands"],
    ["Oson", "Лёгкая", "Easy"],
    ["Oddiy", "Обычная", "Normal"],
    ["Qiyin", "Трудная", "Hard"],
    // --- ma'lumot asbobi
    ["Chorraha", "Перекрёсток", "Junction"],
    ["kutayotgan mashinalar", "ожидающих машин", "waiting vehicles"],
    ["mashinalar", "машин", "vehicles"],
    ["uzunligi", "длина", "length"],
    ["limit", "лимит", "limit"],
    ["oqim", "поток", "flow"],
    ["safar", "поездка", "trip"],
    ["manzil", "цель", "dest."],
    ["bino", "здание", "bldg"],
    ["yashil", "зелёный", "green"],
    ["svetofor", "светофор", "signal"],
    ["narx", "цена", "cost"],
    ["yo'l", "дор.", "roads"],
    ["bor", "есть", "yes"],
    ["yo'q", "нет", "no"],
    ["km/s", "км/ч", "km/h"],
  ];

  static List<(RegExp, String, String)>? _cache;

  static List<(RegExp, String, String)> get _rules => _cache ??= () {
        final l = List<List<String>>.of(_t)..sort((a, b) => b[0].length.compareTo(a[0].length));
        return [
          for (final e in l)
            (
              RegExp("(?<![\\p{L}'’])${RegExp.escape(e[0])}(?![\\p{L}'’])", unicode: true),
              e[1],
              e[2],
            )
        ];
      }();

  /// O'zbekcha matnni tanlangan tilga o'giradi.
  static String t(String s) {
    if (lang == 0) return s;
    var out = s;
    for (final r in _rules) {
      out = out.replaceAll(r.$1, lang == 1 ? r.$2 : r.$3);
    }
    if (lang == 1) {
      out = out.replaceAllMapped(RegExp(r'(\d) s\b'), (m) => '${m[1]} с');
    }
    return out;
  }
}
