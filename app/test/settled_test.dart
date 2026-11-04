// Fasan Split – bill status (Nutzer 04.11.): „eingetragen“ (done) stays under Offen and counts in the balances; only
// „ausgeglichen“ (settled, paid back) goes to the archive and no longer counts. MPL-2.0
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/model/settle.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

Bill pizza(String id, {bool done = true}) => Bill(id: id, created: DateTime(2026, 11, 4), purpose: 'Pizza', total: 1000, done: done, people: [Person('Chris', 0), Person('Angi', 1)], items: [
      BillItem(name: 'Pizza', amount: 1000, shares: {0: 1, 1: 1}),
    ])
      ..payer = 0
      ..group = 'Lissabon';

void main() {
  test('Eingetragen bleibt offen und zählt; ausgeglichen geht ins Archiv und zählt nicht mehr', () {
    final store = BillStore.memory();
    final a = pizza('a'), b = pizza('b'), draft = pizza('c', done: false);
    store
      ..upsert(a)
      ..upsert(b)
      ..upsert(draft);
    expect(store.drafts.map((x) => x.id), containsAll(['a', 'b', 'c']));
    expect(store.finished, isEmpty);
    expect(store.groupBalance('Lissabon')['Angi'], -1000);

    final changed = store.setSettled([a, draft], true);
    expect(changed.map((x) => x.id), ['a'], reason: 'nicht eingetragene Bons können nicht ausgeglichen werden');
    expect(store.finished.map((x) => x.id), ['a']);
    expect(store.inGroup('Lissabon', archived: false).map((x) => x.id), containsAll(['b', 'c']));
    expect(store.groupBalance('Lissabon')['Angi'], -500);
    expect(myDebts([a], (n) => n == 'Angi'), isEmpty);

    store.setSettled(changed, false); // Rückgängig
    expect(store.finished, isEmpty);
    store.setDone([b], false);
    expect(b.settled, isFalse);
  });

  test('Ausgeglichen wird geteilt und kommt zurück', () {
    final b = pizza('x')..settled = true;
    final doc = LwwDoc('me');
    BillSync.write(doc, b);
    final back = BillSync.read(doc, id: 'x');
    expect(back.settled, isTrue);
    expect(Bill.fromJson(b.toJson()).settled, isTrue);
    expect(Bill.fromJson(pizza('y').toJson()).settled, isFalse);
  });
}
