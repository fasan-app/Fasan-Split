// SPDX-License-Identifier: MPL-2.0
// Quantity column read into a grouped amount: „RED BULL 2 140.00 280.00“ (Weltkorpus b2-001, 07.11.). MPL-2.0
// Einheitstests des Lesers: dieselben 30 Fälle wie fasan-diagnose/tests/einheit.mjs (Web 3.19: 30/30).
// Zeilen als Text (ohne Bild); unsicher: {Stelle: (p, alt, p2)}; Ausgabe im selben Format wie das JS-Testskript.
import 'package:fasan_reader/model.dart';
import 'package:fasan_reader/reader.dart';
import 'package:flutter_test/flutter_test.dart';

Line _z(String t, int y, [Map<int, (double, String, double)> unsure = const {}, double x = 0]) {
  final runes = t.runes.toList();
  return Line(const [])
    ..text = t
    ..box = Box(x, y * 20.0, 500, y * 20.0 + 20)
    ..conf = 95
    ..glyphs = [
      for (var i = 0; i < runes.length; i++)
        unsure[i] != null
            ? Glyph(String.fromCharCode(runes[i]), unsure[i]!.$1, alt: unsure[i]!.$2, p2: unsure[i]!.$3)
            : Glyph(String.fromCharCode(runes[i]), 0.999)
    ];
}

List<Line> L(List<Object> rows) => [
      for (var i = 0; i < rows.length; i++)
        rows[i] is String
            ? _z(rows[i] as String, i)
            : _z((rows[i] as List)[0] as String, i, ((rows[i] as List).length > 1 ? (rows[i] as List)[1] as Map<int, (double, String, double)> : const {}),
                ((rows[i] as List).length > 2 ? ((rows[i] as List)[2] as num).toDouble() : 0))
    ];


void main() {
  test('Menge vor Einzelpreis wird nicht als Tausender gelesen („2 140.00 280.00“)', () {
    final r = readGeneral(L(['FISH PLATTER 1 980.00 980.00', 'RED BULL 2 140.00 280.00', 'SODA 3 20.00 60.00', 'Total 1320.00']), null, null);
    final bull = r.items.firstWhere((p) => p.name.startsWith('RED BULL'));
    expect((bull.qty, bull.unit, bull.amount), (2, 14000, 28000));
    expect(r.check.ok, isTrue);
  });

  test('Echter Tausender bleibt einer („1 140.00 1140.00“, „2 140.00 2 140.00“)', () {
    final r = readGeneral(L(['TV 1 140.00 1140.00', 'SOFA 2 140.00 2 140.00', 'Total 3280.00']), null, null);
    expect([for (final p in r.items) p.amount], [114000, 214000]);
    expect(r.items.every((p) => p.qty == 1), isTrue);
  });

  test('„50% Off Today -2.50“ ist Rabatt am Artikel darüber, nicht Steuer (Weltkorpus b1-087)', () {
    final r = readGeneral(L(['000001803 SPOCKLEY 5.00', '50% Off Today -2.50', '000021013 MR BUMP PRESENTS: 12.75', '50% Off Today -6.38', 'Subtotal 8.87', 'Total 8.87']), null, null);
    expect([for (final p in r.items) (p.name, p.amount - p.extras.fold<int>(0, (a, z) => a + z.amount))], [('SPOCKLEY', 500), ('MR BUMP PRESENTS', 1275)]);
    expect([for (final p in r.items) p.extras.map((z) => z.amount).toList()], [[-250], [-638]]);
    expect(r.check.ok, isTrue);
  });

  test('Artikelnummer vorn: 5–14 Ziffern, in langen Nummern ein Verleser; Wörter bleiben', () {
    expect(nameFrom('000001803 SPOCKLEY'), 'SPOCKLEY');
    expect(nameFrom('0520B0250 CGIRL LIPSTK'), 'CGIRL LIPSTK');
    expect(nameFrom('4006381333931 Edding 3000'), 'Edding 3000');
    expect(nameFrom('814998 Bio Spaghetti'), 'Bio Spaghetti');
    expect(nameFrom('12B45 Bio'), '12B45 Bio', reason: 'kurze Nummer mit Buchstabe ist keine Artikelnummer');
  });
}
