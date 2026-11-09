// SPDX-License-Identifier: MPL-2.0
// Undo / redo through the history of a bill (Beschluss 06.11.: Rückgängig/Wiederholen beliebig vieler Schritte). MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Rückgängig und Wiederholen über mehrere Schritte, neue Änderung verwirft Wiederholen', () {
    final store = BillStore.memory();
    final b = Bill(id: 'u', created: DateTime(2026, 11, 6), total: 1000, people: [Person('A', 0), Person('B', 1)], items: [BillItem(name: 'Pizza', amount: 600), BillItem(name: 'Wein', amount: 400)]);
    store.upsert(b);
    store.watchHistory(b);
    expect(store.canUndo(b), isFalse);
    b.its[0].shares = {0: 1};
    store.upsert(b);
    b.its[1].amount = 450;
    b.total = 1050;
    store.upsert(b);
    b.ps.add(Person('C', 2));
    store.upsert(b);
    expect(store.canUndo(b), isTrue);
    expect(store.stepHistory(b, -1), isTrue);
    expect(b.ps.length, 2);
    expect(store.stepHistory(b, -1), isTrue);
    expect(b.its[1].amount, 400);
    expect(b.total, 1000);
    expect(b.its[0].shares, {0: 1});
    expect(store.canRedo(b), isTrue);
    expect(store.stepHistory(b, 1), isTrue);
    expect(b.its[1].amount, 450);
    b.purpose = 'Neu';
    store.upsert(b);
    expect(store.canRedo(b), isFalse, reason: 'neue Änderung verwirft den Wiederholen-Zweig');
    expect(store.stepHistory(b, -1), isTrue);
    expect(b.purpose, '');
    expect(b.its[1].amount, 450);
    while (store.stepHistory(b, -1)) {}
    expect(b.its[0].shares, isEmpty);
    expect(store.canUndo(b), isFalse);
  });
}
