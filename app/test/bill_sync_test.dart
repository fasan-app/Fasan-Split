// Rechnung über das replizierte Dokument: zwei Telefone, gleichzeitige Änderungen, gleiche Summen auf den Cent.
import 'dart:math';

import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_core/bill.dart';
import 'package:flutter_test/flutter_test.dart';

Bill sample() => Bill(id: 'b', created: DateTime(2026, 11, 3), total: 1380, people: [Person('Chris', 0), Person('Andi', 1)], items: [
      BillItem(name: 'Coca Cola', amount: 960, qty: 3, shares: {0: 1, 1: 1}),
      BillItem(name: 'Wasser', amount: 420, shares: {0: 1}),
    ])
  ..payer = 0
  ..purpose = 'Mittag';

void main() {
  test('Hin und zurück: gleiche Summen je Person', () {
    final a = LwwDoc('aa');
    final b = sample();
    expect(BillSync.write(a, b), isTrue);
    expect(BillSync.write(a, b), isFalse, reason: 'zweites Schreiben ändert nichts');
    final b2 = BillSync.read(a, id: 'b');
    expect(b2.perPerson(), b.perPerson());
    expect(b2.purpose, 'Mittag');
    expect(b2.payer, 0);
    expect(b2.audit(), isEmpty);
  });

  test('Zwei Telefone bearbeiten gleichzeitig, mischen, gleiche Endstände und Summen', () {
    final docA = LwwDoc('aa'), docB = LwwDoc('bb');
    final billA = sample();
    BillSync.write(docA, billA);
    docB.merge(docA.entries);
    final billB = BillSync.read(docB, id: 'b');
    // A: Andi bekommt auch das Wasser; B: neue Person Eva, Cola nur für Chris und Eva
    billA.its[1].shares = {0: 1, 1: 1};
    BillSync.write(docA, billA);
    final eva = Person('Eva', 2);
    billB.ps.add(eva);
    billB.its[0].shares = {0: 1, 2: 1};
    BillSync.write(docB, billB);
    docA.merge(docB.entries);
    docB.merge(docA.entries);
    expect(docA.fingerprint, docB.fingerprint);
    final ra = BillSync.read(docA, id: 'b', into: billA), rb = BillSync.read(docB, id: 'b', into: billB);
    expect(ra.ps.map((p) => p.name), rb.ps.map((p) => p.name));
    expect(ra.perPerson(), rb.perPerson());
    expect(ra.audit(), isEmpty);
    expect(ra.ps.map((p) => p.name), ['Chris', 'Andi', 'Eva']);
    // Cola: Chris + Eva; Wasser: Chris + Andi
    expect(ra.its[0].shares.keys.toSet(), {0, 2});
    expect(ra.its[1].shares.keys.toSet(), {0, 1});
  });

  test('Person entfernen verschiebt Anteile nicht (Zuordnung über uid)', () {
    final doc = LwwDoc('aa');
    final b = sample()..people!.add(Person('Eva', 2));
    b.its[0].shares = {0: 1, 2: 1};
    BillSync.write(doc, b);
    b.removePerson(1); // Andi geht, Eva rutscht von 2 auf 1
    BillSync.write(doc, b);
    final r = BillSync.read(doc, id: 'b');
    expect(r.ps.map((p) => p.name), ['Chris', 'Eva']);
    expect(r.its[0].shares.keys.toSet(), {0, 1});
    expect(r.perPerson(), b.perPerson());
  });

  test('CRDT-Eigenschaften: Reihenfolge egal, doppelt egal (500 Zufallsläufe)', () {
    final r = Random(3);
    for (var run = 0; run < 500; run++) {
      final authors = ['a1', 'b2', 'c3'];
      final ops = <Entry>[];
      final docs = [for (final a in authors) LwwDoc(a)];
      for (var i = 0; i < 20; i++) {
        final d = docs[r.nextInt(3)];
        if (r.nextInt(3) == 0) d.merge(docs[r.nextInt(3)].entries);
        final k = 'k${r.nextInt(5)}';
        d.set(k, r.nextBool() ? r.nextInt(100) : null);
        ops.add(d.entry(k) ?? Entry(k, null, 0, d.author));
      }
      final all = docs.expand((d) => d.entries).toList();
      final x = LwwDoc('x')..merge(all);
      final shuffled = [...all, ...all]..shuffle(r);
      final y = LwwDoc('y')..merge(shuffled);
      expect(x.fingerprint, y.fingerprint);
    }
  });
}
