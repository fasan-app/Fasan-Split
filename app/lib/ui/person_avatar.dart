// SPDX-License-Identifier: MPL-2.0
// Fasan Split – a person's avatar with a hatching of their own next to colour and initials (Beschluss Bon 3.9, Karte 29.10.: Schraffur je
// Person zusätzlich zu Farbe und Kürzel), so that people are told apart without colour vision. The pattern follows the colour index, eight
// patterns for the eight colours; drawn once, never repainted. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

/// Number of distinct hatchings (the person colours of fasan_ui repeat after that many).
const kHatchCount = 8;

/// [FasanAvatar] with the hatching of [index] drawn over the colour (below the initials' readable weight: thin, translucent lines).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, required this.index, this.size = 32, this.ring = false});

  final String name;
  final int index;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final avatar = FasanAvatar(name: name, index: index, size: size, ring: ring);
    final kind = index.abs() % kHatchCount;
    if (kind == 0) return avatar; // the first person stays plain: a plain disc is a pattern too
    return Stack(alignment: Alignment.center, children: [
      avatar,
      ExcludeSemantics(
        child: SizedBox(
          width: size - 3,
          height: size - 3,
          child: ClipOval(child: CustomPaint(painter: HatchPainter(kind, FasanLook.of(context).brightness == Brightness.dark ? Colors.black : Colors.white))),
        ),
      ),
    ]);
  }
}

/// Lines for pattern [kind] (1 diagonal /, 2 diagonal \, 3 horizontal, 4 vertical, 5 dots, 6 crossed diagonals, 7 grid); [kind] 0 draws nothing.
class HatchPainter extends CustomPainter {
  const HatchPainter(this.kind, this.color);

  final int kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.38)
      ..strokeWidth = (s.width / 14).clamp(1.0, 2.2)
      ..style = PaintingStyle.stroke;
    final gap = (s.width / 5).clamp(4.0, 9.0);
    switch (kind) {
      case 1:
        for (var d = -s.height; d < s.width; d += gap) {
          canvas.drawLine(Offset(d, s.height), Offset(d + s.height, 0), p);
        }
      case 2:
        for (var d = -s.height; d < s.width; d += gap) {
          canvas.drawLine(Offset(d, 0), Offset(d + s.height, s.height), p);
        }
      case 3:
        for (var y = gap / 2; y < s.height; y += gap) {
          canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
        }
      case 4:
        for (var x = gap / 2; x < s.width; x += gap) {
          canvas.drawLine(Offset(x, 0), Offset(x, s.height), p);
        }
      case 6:
        for (var d = -s.height; d < s.width; d += gap) {
          canvas.drawLine(Offset(d, s.height), Offset(d + s.height, 0), p);
          canvas.drawLine(Offset(d, 0), Offset(d + s.height, s.height), p);
        }
      case 7:
        for (var y = gap / 2; y < s.height; y += gap) {
          canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
        }
        for (var x = gap / 2; x < s.width; x += gap) {
          canvas.drawLine(Offset(x, 0), Offset(x, s.height), p);
        }
      case 5:
        final f = Paint()..color = p.color;
        for (var y = gap / 2; y < s.height; y += gap) {
          for (var x = gap / 2 + ((y / gap).floor().isOdd ? gap / 2 : 0); x < s.width; x += gap) {
            canvas.drawCircle(Offset(x, y), p.strokeWidth * 0.8, f);
          }
        }
    }
  }

  @override
  bool shouldRepaint(HatchPainter old) => old.kind != kind || old.color != color;
}
