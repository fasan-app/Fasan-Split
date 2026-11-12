// SPDX-License-Identifier: MPL-2.0
// Balance history: a change can be taken back with the values it replaced; what changed again since stays (Nutzer 12.11.). MPL-2.0
import 'package:fasan_split/collab/bill_changes.dart';
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_core/bill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bill make() => Bill(id: 'u', created: DateTime(2026, 11, 10), total: 3000, people: [Person('Ana', 0), Person('Ben', 1)], items: [
        BillItem(name: 'Pizza', amount: 2000, shares: {0: 1}),
        BillItem(name: 'Salat', amount: 1000, shares: {0: 1, 1: 1}),
      ]);

  /// The pairs a burst collects (old entry, new entry), like the service does with LwwDoc.onApplied.
  List<UndoOp> record(LwwDoc doc, void Function() edit) {
    final pairs = <EntryChange>[];
    doc.onApplied = (o, n) => pairs.add((o, n));
    edit();
    doc.onApplied = null;
    final first = <String, Object?>{}, last = <String, Object?>{};
    for (final p in pairs) {
      first.putIfAbsent(p.$2.key, () => p.$1?.value);
      last[p.$2.key] = p.$2.value;
    }
    return [for (final k in first.keys) UndoOp(k, first[k], last[k])];
  }

  test('Rückgängig: die ersetzten Werte kommen zurück, der Saldo auch', () {
    final doc = LwwDoc('aa');
    final b = make();
    BillSync.write(doc, b);
    final before = BillSync.read(doc, id: 'u').perPerson();
    final ops = record(doc, () {
      b.its[0].togglePerson(1); // Ben takes a share of the pizza
      BillSync.write(doc, b);
    });
    expect(ops, isNotEmpty);
    expect(BillSync.read(doc, id: 'u').perPerson(), isNot(before), reason: 'the change moved the balance');
    final skipped = applyUndo(doc, ops);
    expect(skipped, isEmpty);
    expect(BillSync.read(doc, id: 'u').perPerson(), before);
  });

  test('Seitdem weiter geändert: dieser Schlüssel bleibt, der Rest geht zurück', () {
    final doc = LwwDoc('aa');
    final b = make();
    BillSync.write(doc, b);
    final ops = record(doc, () {
      b.its[0].togglePerson(1);
      b.purpose = 'Kneipe';
      BillSync.write(doc, b);
    });
    // somebody changes the purpose afterwards
    doc.set('meta/purpose', 'Pizzeria');
    final skipped = applyUndo(doc, ops);
    expect(skipped, ['meta/purpose']);
    expect(doc.get('meta/purpose'), 'Pizzeria');
    expect(BillSync.read(doc, id: 'u').its[0].shares.keys.toSet(), {0}, reason: 'the share is taken back');
  });

  test('Sperre: ein gesperrter Schlüssel wird nicht zurückgesetzt', () {
    final doc = LwwDoc('aa');
    final b = make();
    BillSync.write(doc, b);
    final ops = record(doc, () {
      b.its[0].togglePerson(1);
      BillSync.write(doc, b);
    });
    final skipped = applyUndo(doc, ops, allow: (_) => false);
    expect(skipped.length, ops.length);
  });

  test('ChangeRecord behält Rückgängig-Daten und Eingangszeit über JSON', () {
    final r = ChangeRecord(at: DateTime(2026, 11, 12, 3), group: 'g', billId: 'u', title: 'Kneipe', who: 'Hugo', whoKey: 'k', lines: const [ChangeLine('a', 'b')], undo: const [UndoOp('s/x/y', null, 1.0)], rcvAt: DateTime(2026, 11, 12, 4));
    final back = ChangeRecord.decode(ChangeRecord.encode([r])).single;
    expect(back.undo.single.key, 's/x/y');
    expect(back.undo.single.old, isNull);
    expect(back.rcvAt, DateTime(2026, 11, 12, 4));
  });
}
