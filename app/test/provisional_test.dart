// SPDX-License-Identifier: MPL-2.0
// Vorläufiger Saldo (Nutzer 06.11./07.11.): offene Rechnungen zählen mit dem, was schon verteilt ist – nie in Ausgleichsvorschlägen.
import 'package:fasan_core/bill.dart';
import 'package:fasan_core/settle.dart';
import 'package:flutter_test/flutter_test.dart';

Bill _open({int? payer, bool done = false, List<BillItem>? items, int total = 3000}) => Bill(
      id: 'o',
      created: DateTime(2026),
      total: total,
      people: [Person('Ich', 0), Person('Anna', 1), Person('Ben', 2)],
      items: items ??
          [
            BillItem(name: 'Pizza', amount: 1200, shares: {0: 1}),
            BillItem(name: 'Wein', amount: 900, shares: {1: 1}),
            BillItem(name: 'Rest', amount: 900), // not assigned yet
          ],
    )
      ..payer = payer
      ..done = done;

bool _me(String n) => n == 'Ich';

void main() {
  test('Zahler unbekannt: ich schulde meinen Teil, Empfänger offen', () {
    expect(myProvisional([_open()], _me), {'': -1200});
  });

  test('Ich habe bezahlt (halbfertige Rechnung): die anderen schulden mir, was ihnen schon zugeteilt ist', () {
    expect(myProvisional([_open(payer: 0)], _me), {'Anna': 900});
  });

  test('Anna hat bezahlt: ich schulde Anna meinen Teil', () {
    expect(myProvisional([_open(payer: 1)], _me), {'Anna': -1200});
  });

  test('Fertige Rechnungen zählen nicht doppelt; Papierkorb, bezahlt und nichts zugeteilt zählen nicht', () {
    expect(myProvisional([_open(payer: 0, done: true)], _me), isEmpty);
    expect(myProvisional([_open(payer: 0)..trashedAt = DateTime(2026)], _me), isEmpty);
    expect(myProvisional([_open(payer: 0)..settled = true], _me), isEmpty);
    expect(myProvisional([_open(payer: 0, items: [BillItem(name: 'x', amount: 500)])], _me), isEmpty);
  });

  test('Trinkgeld/Differenz wird nicht auf Verdacht verteilt; fest und vorläufig sind getrennte Summen', () {
    final b = _open(payer: 1, total: 3900);
    expect(b.difference, isNot(0));
    expect(myProvisional([b], _me)['Anna'], -1200, reason: 'ohne die 9,00 € Differenz');
    final fixed = _open(payer: 1, done: true, total: 3900);
    final confirmed = myDebts([fixed], _me);
    expect(confirmed['Anna'], isNot(0));
    expect(balances([b]), isEmpty, reason: 'Ausgleichsvorschläge nur aus fertigen Rechnungen');
  });

  test('Stück-Posten: nur das zugeteilte Stück zählt vorläufig', () {
    final b = _open(payer: 1, items: [BillItem(name: 'Cola', amount: 900, qty: 3, perUnit: true, shares: {0: 1})]);
    expect(myProvisional([b], _me), {'Anna': -300});
  });
}
