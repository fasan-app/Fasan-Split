// SPDX-License-Identifier: MPL-2.0
// Cost history of „Mein Stand“ (Nutzer 07.11.): changes of a bill are booked as differences, with running totals.
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool isMe(String n) => n == 'Pia';

  Bill bill(String id, String group, int cola) => Bill(id: id, created: DateTime(2026, 11, 7), purpose: 'Strandbar Erfunden $id', total: 2000, people: [Person('Pia', 0), Person('Lena', 1)], items: [
        BillItem(name: 'Cola', amount: cola, shares: {1: 1}),
      ])
    ..payer = 0
    ..group = group;

  test('erster Blick ist Ausgangslage, danach werden Differenzen gebucht', () {
    final l = BalanceLedger();
    final a = bill('a', 'Beispielstadt', 300);
    expect(l.update([a], isMe), isTrue);
    expect(l.entries, isEmpty, reason: 'baseline is not a booking');

    a.its.first.amount = 450; // Lena owes 1.50 more
    expect(l.update([a], isMe, why: (_, _, _) => ('Hugo: Cola Betrag 3,00 → 4,50', 'x')), isTrue);
    expect(l.entries.single.delta, 150);
    expect(l.entries.single.total, 450);
    expect(l.entries.single.whyDe, contains('Hugo'));

    final b = bill('b', 'Algarve', 200); // new bill in another group
    l.update([a, b], isMe);
    expect(l.entries.first.delta, 200);
    expect(l.entries.first.total, 650, reason: 'global total');
    expect(l.entries.first.groupTotal, 200, reason: 'per group');
    expect(l.entries.first.group, 'Algarve');

    l.update([a], isMe); // bill b gone
    expect(l.entries.first.delta, -200);
    expect(l.entries.first.total, 450);

    expect(l.update([a], isMe), isFalse, reason: 'nothing changed, nothing booked');
    final back = BalanceLedger.decode(l.encode());
    expect(back.entries.length, l.entries.length);
    expect(back.update([a], isMe), isFalse, reason: 'baseline survives a restart');
  });
}
