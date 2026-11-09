// SPDX-License-Identifier: MPL-2.0
// Vorhängeschloss (Nutzer 07.11.): gesperrte Posten und Rechnungen ändert nur, wer sie gesperrt hat, und der Gruppen-Admin. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lock_rules.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:flutter_test/flutter_test.dart';

Bill sample() => Bill(id: 'b', created: DateTime(2026, 11, 7), total: 1380, people: [Person('Pia', 0), Person('Ole', 1)], items: [
      BillItem(name: 'Cola', amount: 960, qty: 3, shares: {0: 1, 1: 1}),
      BillItem(name: 'Wasser', amount: 420, shares: {0: 1}),
    ])
  ..payer = 0;

void main() {
  test('Posten gesperrt: andere dürfen ihn nicht ändern, den anderen Posten schon; der Sperrer und der Admin dürfen', () {
    final doc = LwwDoc('aa');
    final b = sample();
    b.its[0].lockBy = 'aa';
    BillSync.write(doc, b);
    final uid0 = b.its[0].uid, uid1 = b.its[1].uid;
    for (final k in ['i/$uid0', 's/$uid0/${b.ps[0].uid}', 'f/$uid0/${b.ps[1].uid}']) {
      expect(lockAllows(doc, k, 'bb'), isFalse, reason: k);
      expect(lockAllows(doc, k, 'aa'), isTrue);
      expect(lockAllows(doc, k, 'bb', adminPub: 'bb'), isTrue, reason: 'Admin darf');
    }
    expect(lockAllows(doc, 'i/$uid1', 'bb'), isTrue, reason: 'anderer Posten bleibt offen');
    expect(lockAllows(doc, 'meta/total', 'bb'), isTrue);
  });

  test('Rechnung gesperrt: nichts außer Notizen von anderen; Entsperren nur durch den Sperrer', () {
    final doc = LwwDoc('aa');
    final b = sample()..lockBy = 'aa';
    BillSync.write(doc, b);
    expect(BillSync.read(doc, id: 'b').lockBy, 'aa');
    for (final k in ['meta/total', 'meta/lock', 'meta/payer', 'p/x', 'i/${b.its[0].uid}']) {
      expect(lockAllows(doc, k, 'bb'), isFalse, reason: k);
    }
    expect(lockAllows(doc, 'n/1', 'bb'), isTrue, reason: 'Notizen bleiben offen');
    expect(lockAllows(doc, 'meta/lock', 'aa'), isTrue);
  });

  test('Eigener Schreibweg: gesperrte Teile werden nicht geschrieben und kommen aus dem Dokument zurück', () {
    final doc = LwwDoc('aa'); // the document as phone B sees it (author bb below only matters for the rule)
    final b = sample();
    b.its[0].lockBy = 'aa';
    BillSync.write(doc, b);
    final mine = BillSync.read(doc, id: 'b');
    mine.its[0].shares = {1: 1}; // B tries to change the locked item …
    mine.its[1].shares = {1: 1}; // … and the open one
    var blocked = false;
    BillSync.write(doc, mine, allow: (k) => lockAllows(doc, k, 'bb'), onBlocked: () => blocked = true);
    expect(blocked, isTrue);
    BillSync.read(doc, id: 'b', into: mine);
    expect(mine.its[0].shares, {0: 1, 1: 1}, reason: 'gesperrter Posten unverändert');
    expect(mine.its[1].shares, {1: 1}, reason: 'offener Posten geändert');
  });
}
