import 'dart:ui';

enum BuildingType { house, shop, factory }

class Building {
  Building({
    required this.id,
    required this.type,
    required this.pos,
    required this.angle,
    required this.size,
    required this.roof,
  });

  final int id;
  final BuildingType type;
  final Offset pos;
  final double angle;
  final Size size;
  final Color roof;

  double get radius => size.longestSide / 2 + 8;

  void draw(Canvas c) {
    c.save();
    c.translate(pos.dx, pos.dy);
    c.rotate(angle);

    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height),
      const Radius.circular(3),
    );

    // soya
    c.drawRRect(body.shift(const Offset(4, 5)), Paint()..color = const Color(0x2E000000));
    // devor
    c.drawRRect(body, Paint()..color = const Color(0xFFF3EAD3));

    final roofRect = body.deflate(3);
    c.drawRRect(roofRect, Paint()..color = roof);

    final line = Paint()
      ..color = const Color(0x33000000)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    switch (type) {
      case BuildingType.house:
        c.drawLine(Offset(-size.width / 2 + 3, 0), Offset(size.width / 2 - 3, 0), line);
        break;
      case BuildingType.shop:
        for (var i = -2; i <= 2; i++) {
          final x = i * size.width / 6;
          c.drawLine(Offset(x, -size.height / 2 + 3), Offset(x, size.height / 2 - 3), line);
        }
        break;
      case BuildingType.factory:
        for (var i = -1; i <= 1; i++) {
          final x = i * size.width / 4;
          c.drawLine(Offset(x, -size.height / 2 + 3), Offset(x, size.height / 2 - 3), line);
        }
        final chimney = Offset(size.width / 2 - 12, -size.height / 2 + 12);
        c.drawCircle(chimney + const Offset(2, 2), 6, Paint()..color = const Color(0x33000000));
        c.drawCircle(chimney, 6, Paint()..color = const Color(0xFF8A8D93));
        c.drawCircle(chimney, 3.5, Paint()..color = const Color(0xFF55585E));
        break;
    }

    c.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF4A4D52),
    );
    c.restore();
  }
}
