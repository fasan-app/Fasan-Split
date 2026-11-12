// SPDX-License-Identifier: MPL-2.0
// Fasan Split – what makes a balance uncertain (Nutzer 12.11.): unfinished bills and finished bills without a payer. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_core/settle.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

Bill bill(String id, {bool done = true, int? payer = 0, bool settled = false}) => Bill(id: id, created: DateTime(2026, 11, 4), purpose: 'Pizza', total: 1000, done: done, people: [Person('Pia', 0), Person('Lena', 1), Person('Max', 2)], items: [
      BillItem(name: 'Pizza', amount: 1000, shares: {0: 1, 1: 1}),
    ])
      ..payer = payer
      ..settled = settled
      ..group = 'Beispielstadt';

void main() {
  test('offene Bons und fehlender Zahler machen den Saldo ungewiss, fertige mit Zahler nicht', () {
    final gaps = balanceGaps([bill('a'), bill('b', done: false), bill('c', payer: null), bill('d', settled: true, payer: null)]);
    expect(gaps['Pia']!.openBills, 1);
    expect(gaps['Pia']!.noPayer, 1);
    expect(gaps['Pia']!.uncertain, isTrue);
    expect(balanceGaps([bill('a')]), isEmpty, reason: 'alles fertig, Zahler da: keine Lücke');
    expect(balanceGaps([bill('d', settled: true, payer: null)]), isEmpty, reason: 'ausgeglichene Bons zählen nicht');
  });

  test('Saldo bleibt nur aus fertigen Bons mit Zahler, Lücken stehen daneben', () {
    final store = BillStore.memory();
    store
      ..upsert(bill('a'))
      ..upsert(bill('b', done: false))
      ..upsert(bill('c', payer: null));
    expect(store.groupBalance('Beispielstadt')['Lena'], -500, reason: 'nur Bon a zählt');
    expect(store.groupGaps('Beispielstadt')['Lena']!.uncertain, isTrue);
    expect(store.groupGaps('Beispielstadt')['Max']!.uncertain, isTrue);
  });
}
