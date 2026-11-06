// A storno line torn in two by the OCR (de-discount 06.11.): the keyword line without amount and the amount line with a misread
// name must still cancel the item above. MPL-2.0
import 'package:fasan_reader/model.dart';
import 'package:fasan_reader/reader.dart';
import 'package:flutter_test/flutter_test.dart';

Line _z(String t, int y) => Line(const [])
  ..text = t
  ..box = Box(0, y * 20.0, 500, y * 20.0 + 20)
  ..conf = 95
  ..glyphs = [for (final r in t.runes) Glyph(String.fromCharCode(r), 0.999)];

void main() {
  test('Zerrissene Storno-Zeile hebt den Posten darüber auf', () {
    final rows = ['EUR', 'Vollkornbrot 1,49 B', 'Chips Paprika 1,79 A', 'cYanmaGtaYelow -1,79 A', 'Storno os Paprika', 'Bananen 0,90 B', 'Summe 2,39'];
    final r = readLines([for (var i = 0; i < rows.length; i++) _z(rows[i], i)], null);
    expect(r.items.map((i) => i.amount).toList(), [149, 90]);
    expect(r.total, 239);
  });

  test('Ein negativer Posten ohne Storno-Zeile daneben bleibt (z. B. Pfandrückgabe)', () {
    final rows = ['EUR', 'Vollkornbrot 1,49 B', 'Chips Paprika 1,79 A', 'Gutschrift -1,79 A', 'Bananen 0,90 B', 'Summe 2,39'];
    final r = readLines([for (var i = 0; i < rows.length; i++) _z(rows[i], i)], null);
    expect(r.items.map((i) => i.amount).toList(), containsAll([149, 179, -179, 90]));
  });
}
