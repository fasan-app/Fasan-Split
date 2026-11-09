// SPDX-License-Identifier: MPL-2.0
// Protocol must show what the user corrected (Nutzer 07.11.: Wasser 2 → 3 war im Protokoll nicht zu sehen).
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('erkannte Werte bleiben beim Speichern und Laden erhalten', () {
    final it = BillItem(name: 'Sprudel', amount: 1050, qty: 2, rec: {'t': 'Sprudel', 'menge': 2.0, 'b': 1050});
    final back = BillItem.fromJson(it.toJson());
    expect(back.rec, {'t': 'Sprudel', 'menge': 2.0, 'b': 1050});
    it.qty = 3;
    expect(it.rec!['menge'], 2.0, reason: 'recognized value must not follow edits');
  });

  test('Verlauf nennt Posten, Feld, vorher und nachher', () {
    final it = BillItem(name: 'Sprudel', amount: 1050, qty: 2);
    final b = Bill(id: 'x', created: DateTime(2026), total: 1050, items: [it], people: []);
    final store = BillStore.memory([b]);
    store.watchHistory(b);
    it.qty = 3;
    store.upsert(b);
    final ch = store.historyChanges(b);
    expect(ch, [
      {'schritt': 1, 'posten': 'Sprudel', 'feld': 'qty', 'von': 2, 'nach': 3}
    ]);
  });
}
