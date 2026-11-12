// SPDX-License-Identifier: MPL-2.0
// Two devices on one shared bill must come to rest: after the edits stop, no further writes (11.11.: the history showed the same
// share „ausgetragen/eingetragen“ eight times without anybody editing). MPL-2.0
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_core/bill.dart';
import 'package:flutter_test/flutter_test.dart';

/// One round of what the service does for a bill: write the local bill into the document, then (after the exchange) read it back.
int _exchange(LwwDoc a, LwwDoc b) {
  var n = 0;
  for (final e in a.entries.toList()) {
    if (b.apply(e)) n++;
  }
  for (final e in b.entries.toList()) {
    if (a.apply(e)) n++;
  }
  return n;
}

void main() {
  Bill start() => Bill(id: 'q', created: DateTime(2026, 11, 10), total: 6000, people: [Person('Ana', 0), Person('Ben', 1), Person('Cleo', 2)], items: [
        BillItem(name: 'Pizza', amount: 2000, shares: {0: 1, 1: 1}),
        BillItem(name: 'Cola', amount: 1000, qty: 2, shares: {0: 1}),
        BillItem(name: 'Salat', amount: 1000, shares: {0: 1, 2: 1}, maybe: {1: 'pubC'}),
        BillItem(name: 'Wein', amount: 2000, shares: {1: 1}, fixed: {1: 500}),
      ]);

  test('zwei Geräte kommen zur Ruhe: gleichzeitig Person hinzufügen, Posten ändern, danach kein Schreiben mehr', () {
    final docA = LwwDoc('aa'), docB = LwwDoc('bb');
    final a = start();
    BillSync.write(docA, a);
    _exchange(docA, docB);
    final b = BillSync.read(docB, id: 'q');
    // concurrent edits on both sides
    a.ps.add(Person('Dora', 3));
    a.its[0].togglePerson(3);
    b.ps.add(Person('Emil', 4));
    b.its[1].togglePerson(1);
    var quietRounds = 0, totalWrites = 0;
    for (var round = 0; round < 12 && quietRounds < 3; round++) {
      final wa = BillSync.write(docA, a), wb = BillSync.write(docB, b);
      final ex = _exchange(docA, docB);
      BillSync.read(docA, id: 'q', into: a);
      BillSync.read(docB, id: 'q', into: b);
      final noisy = wa || wb || ex > 0;
      totalWrites += noisy ? 1 : 0;
      quietRounds = noisy ? 0 : quietRounds + 1;
    }
    expect(quietRounds, greaterThanOrEqualTo(3), reason: 'still writing after $totalWrites rounds');
    expect(a.ps.map((p) => p.uid).toList(), b.ps.map((p) => p.uid).toList(), reason: 'same people in the same order');
    expect(a.perPerson(), b.perPerson());
  });
}
