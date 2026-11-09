// SPDX-License-Identifier: MPL-2.0
// The lines of „So ergibt sich dein Stand“ and of the group page add up to exactly the balance (Nutzer 07.11.).
import 'package:fasan_core/bill.dart';
import 'package:fasan_core/settle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bill bill(String id, int payer, List<int> amounts) => Bill(id: id, created: DateTime(2026, 11, 7), purpose: id, total: amounts.fold<int>(0, (a, x) => a + x), people: [Person('Pia', 0), Person('Lena', 1), Person('Hugo', 2)], items: [
        for (var i = 0; i < amounts.length; i++) BillItem(name: 'P$i', amount: amounts[i], shares: {i % 3: 1}),
      ])
    ..payer = payer
    ..done = true;

  test('Zeilen je Rechnung ergeben genau den Saldo, und der Ausgleich gleicht ihn aus', () {
    final bills = [bill('a', 0, [1000, 700, 333]), bill('b', 1, [1250, 999, 501]), bill('c', 2, [400, 400, 400])];
    final bal = balances(bills);
    final fromLines = <String, int>{};
    for (final bm in billMoves(bills)) {
      for (final (f, t, c) in bm.moves) {
        fromLines.update(f, (x) => x - c, ifAbsent: () => -c);
        fromLines.update(t, (x) => x + c, ifAbsent: () => c);
      }
    }
    fromLines.removeWhere((_, v) => v == 0);
    final b2 = Map.of(bal)..removeWhere((_, v) => v == 0);
    expect(fromLines, b2);
    final after = Map.of(bal);
    for (final (f, t, c) in settle(bal)) {
      after.update(f, (x) => x + c);
      after.update(t, (x) => x - c);
    }
    expect(after.values.every((v) => v == 0), isTrue, reason: 'settling the transfers leaves nobody with a balance');
    expect(bal.values.fold(0, (a, x) => a + x), 0);
  });
}
