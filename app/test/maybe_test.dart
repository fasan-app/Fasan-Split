// SPDX-License-Identifier: MPL-2.0
// Tentative „vllt“ assignments (Stellvertreter, Nutzer 06.11.): not counted, synced, remapped, confirmable. MPL-2.0
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lock_rules.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_core/bill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bill make() => Bill(id: 'm', created: DateTime(2026, 11, 10), total: 3000, people: [Person('Ana', 0), Person('Ben', 1), Person('Cleo', 2)], items: [
        BillItem(name: 'Pizza', amount: 2000, shares: {0: 1}, maybe: {1: 'pubC'}),
        BillItem(name: 'Salat', amount: 1000, shares: {0: 1, 2: 1}),
      ]);

  test('Vorschlag zählt in keiner Summe, auch nicht in der Prüfung', () {
    final b = make();
    final pp = b.perPerson();
    expect(pp[1] ?? 0, 0);
    expect(pp[0], 2500);
    expect(b.its.first.maybe, {1: 'pubC'});
  });

  test('JSON und Sync hin und zurück; Entfernen der Person räumt auf', () {
    final b = make();
    expect(Bill.fromJson(b.toJson()).its.first.maybe, {1: 'pubC'});
    final doc = LwwDoc('aa');
    BillSync.write(doc, b);
    expect(doc.keys('sv/').length, 1);
    final back = BillSync.read(doc, id: 'm');
    expect(back.its.first.maybe, {1: 'pubC'});
    expect(back.perPerson(), b.perPerson());
    // withdrawn: the key is cleared on the next write
    b.its.first.maybe.clear();
    BillSync.write(doc, b);
    expect(BillSync.read(doc, id: 'm').its.first.maybe, isEmpty);
    // index remap
    final c = make()..removePerson(0);
    expect(c.its.first.maybe, {0: 'pubC'});
    final d = make()..removePerson(1);
    expect(d.its.first.maybe, isEmpty);
  });

  test('Übernehmen verschiebt den Vorschlag in die Anteile; Sperre gilt auch für sv/', () {
    final b = make();
    final it = b.its.first;
    it.maybe.remove(1);
    it.togglePerson(1);
    expect(it.shares[1], greaterThan(0));
    expect(b.perPerson()[1], greaterThan(0));
    final doc = LwwDoc('aa');
    expect(itemOfKey('sv/abc/p1'), 'abc');
    doc.set('i/abc', {'name': 'x', 'amount': 1, 'lock': 'pubA'});
    expect(lockAllows(doc, 'sv/abc/p1', 'pubB'), isFalse);
    expect(lockAllows(doc, 'sv/abc/p1', 'pubA'), isTrue);
  });
}
