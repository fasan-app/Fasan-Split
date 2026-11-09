// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the Fasan symbol (pheasant) top left on every main page (Nutzer 09.11.: the tabs below already say where you are,
// like Instagram; the top left never changes, so nothing jumps). Uses the launcher icon, 96 px source for a 32 dp mark. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

class FasanMark extends StatelessWidget {
  const FasanMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    return Semantics(
      image: true,
      label: 'Fasan',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24 * (l.radius > 0 ? 1 : 0.5)),
        child: Image.asset('assets/icon/ic_launcher-xhdpi.png', width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.medium, errorBuilder: (_, _, _) => SizedBox(width: size, height: size)),
      ),
    );
  }
}
