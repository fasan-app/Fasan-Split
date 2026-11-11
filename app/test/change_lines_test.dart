// SPDX-License-Identifier: MPL-2.0
// Fasan Split – history lines (Nutzer 11.11.: „Summe 86,90 → 86,90“, „Datum geändert“ without a difference, the same line eight
// times). Pure unit test, invented data. MPL-2.0
import 'package:fasan_split/collab/bill_changes.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LwwDoc doc() {
    final d = LwwDoc('pia');
    d.set('p/lena', {'name': 'Lena', 'color': 1});
    d.set('i/pizza', {'name': 'Pizza', 'amount': 900, 'qty': 1});
    return d;
  }

  test('Gleicher Wert gibt keine Zeile: Summe, Name, Datum, Rückerstattung', () {
    final d = doc();
    final same = [
      (const Entry('meta/total', 8690, 1, 'pia'), const Entry('meta/total', 8690, 2, 'pia')),
      (const Entry('meta/purpose', 'Ferreiras LX Factory', 1, 'pia'), const Entry('meta/purpose', 'Ferreiras LX Factory', 2, 'pia')),
      (const Entry('meta/date', '2026-10-25', 1, 'pia'), const Entry('meta/date', '2026-10-25', 2, 'pia')),
      (const Entry('meta/refund', null, 1, 'pia'), const Entry('meta/refund', false, 2, 'pia')),
    ];
    expect(describeChanges(d, [for (final (o, n) in same) (o, n)]), isEmpty, reason: 'nichts hat sich geändert');
  }, tags: const []);

  test('Echte Änderung bleibt, und die Zeile über einen Posten merkt sich den Posten (Antippen öffnet ihn)', () {
    final d = doc();
    final lines = describeChanges(d, [
      (const Entry('meta/total', 8690, 1, 'pia'), const Entry('meta/total', 9000, 2, 'pia')),
      (const Entry('s/pizza/lena', null, 1, 'pia'), const Entry('s/pizza/lena', 1, 2, 'pia')),
    ]);
    expect(lines.map((l) => l.de), containsAll(['Summe 86,90 → 90,00', 'Lena bei „Pizza“ eingetragen']));
    expect(lines.firstWhere((l) => l.de.contains('Pizza')).item, 'pizza');
    final back = ChangeRecord.decode(ChangeRecord.encode([ChangeRecord(at: DateTime(2026, 11, 11), group: 'g', billId: 'b', title: 'Bar', who: 'Pia', whoKey: 'pia', lines: lines)]));
    expect(back.single.lines.firstWhere((l) => l.de.contains('Pizza')).item, 'pizza', reason: 'überlebt Speichern und Laden');
  });
}
