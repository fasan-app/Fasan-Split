// SPDX-License-Identifier: MPL-2.0
// Standardlook ohne teure Effekte (Nutzer 08.11.): nichts, was Rechenlast erzeugt, ist standardmäßig an. MPL-2.0
import 'package:fasan_split/ui/look_defaults.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ohne teure Effekte: Film, Hintergrundbewegung, Lichtband, Neigung, Schatten und Glas-Unschärfe aus', () {
    for (final start in [const FasanSettings(), const FasanSettings().copyWith(style: FasanStyle.fullGlass)]) {
      final s = withoutCostlyEffects(start);
      expect(s.effects.enabled, isFalse);
      expect(s.effects.any, isFalse, reason: 'kein Effekt läuft');
      expect(s.effects.shadows, isFalse);
      expect(s.effects.grain, 0);
      expect(s.reduceTransparency, isTrue, reason: 'undurchsichtige Flächen statt Unschärfe');
      expect(s.style, start.style, reason: 'Stil bleibt');
    }
    // Gegenprobe: die Standardeinstellung der Bibliothek hat Effekte an (der Test ist nicht blind)
    expect(const FasanSettings().effects.any, isTrue);
  });
}
