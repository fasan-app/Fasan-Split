// SPDX-License-Identifier: MPL-2.0
// Items with several pieces (Nutzer 07.11.): „3 × Cola“ for one person must not close the item.
import 'package:fasan_core/bill.dart';
import 'package:flutter_test/flutter_test.dart';

Bill _bill(List<BillItem> items, {int? total}) => Bill(
      id: 'p',
      created: DateTime(2026),
      total: total ?? items.fold<int>(0, (a, i) => a + i.amount),
      people: [Person('A', 0), Person('B', 1), Person('C', 2), Person('D', 3)],
      items: items,
    );

void main() {
  overTests();
  test('Wasserflaschen: A trank 2 allein, die dritte teilten B, C, D – jeder Cent verteilt, Posten komplett', () {
    final it = BillItem(name: 'Wasser', amount: 600, qty: 3, perUnit: true, shares: {0: 2, 1: 1 / 3, 2: 1 / 3, 3: 1 / 3});
    final b = _bill([it]);
    expect(it.fill, ItemFill.complete);
    expect(it.coveredAmount, 600);
    final pp = b.perPerson();
    expect(pp[0], 400);
    expect({pp[1], pp[2], pp[3]}.every((v) => v == 66 || v == 67), isTrue);
    expect(pp.values.fold<int>(0, (a, v) => a + v), 600);
    expect(b.audit(), isEmpty);
  });

  test('3 × Cola, nur 1 Stück an A: teilweise, A zahlt nur 1/3, Rest bleibt offen', () {
    final it = BillItem(name: 'Cola', amount: 900, qty: 3, perUnit: true, shares: {0: 1});
    final b = _bill([it]);
    expect(it.fill, ItemFill.partial);
    expect(it.coveredAmount, 300);
    expect(b.perPerson()[0], 300, reason: 'nur das zugeteilte Stück, nicht alle drei');
    expect(b.notComplete, 1);
    expect(b.audit(), isEmpty);
  });

  test('Nichts zugeteilt = offen; alle Stücke = komplett; zu viele Stücke zählen nicht doppelt', () {
    expect(BillItem(name: 'x', amount: 300, qty: 3, perUnit: true).fill, ItemFill.open);
    final all = BillItem(name: 'x', amount: 300, qty: 3, perUnit: true, shares: {0: 1, 1: 2});
    expect(all.fill, ItemFill.complete);
    expect(all.coveredAmount, 300);
    final over = BillItem(name: 'x', amount: 300, qty: 3, perUnit: true, shares: {0: 3, 1: 3});
    expect(over.coveredAmount, 300);
    expect(_bill([over]).perPerson().values.fold<int>(0, (a, v) => a + v), 300);
  });

  test('Altdaten: Menge > 1 mit genau einer Person gilt als teilweise (zur Prüfung), Rechnung bleibt unverändert', () {
    final one = BillItem(name: 'Cola', amount: 900, qty: 3, shares: {0: 1});
    expect(one.fill, ItemFill.partial);
    expect(one.coveredAmount, 900, reason: 'bestehende Rechnungen rechnen wie bisher');
    expect(_bill([one]).perPerson()[0], 900);
    expect(BillItem(name: 'Cola', amount: 900, qty: 3, shares: {0: 1, 1: 1}).fill, ItemFill.complete);
    expect(BillItem(name: 'Brot', amount: 300, shares: {0: 1}).fill, ItemFill.complete);
  });

  test('Speichern und Laden behält den Stückmodus', () {
    final it = BillItem(name: 'Cola', amount: 900, qty: 3, perUnit: true, shares: {0: 1});
    final back = BillItem.fromJson(it.toJson());
    expect(back.perUnit, isTrue);
    expect(back.fill, ItemFill.partial);
    expect(BillItem.fromJson(BillItem(name: 'x', amount: 1).toJson()).perUnit, isFalse);
  });

  test('Trinkgeld/Differenz wird nur auf das Zugeteilte verteilt', () {
    final it = BillItem(name: 'Cola', amount: 900, qty: 3, perUnit: true, shares: {0: 1});
    final b = _bill([it], total: 1000); // 1,00 € Trinkgeld
    expect(b.perPerson().values.fold<int>(0, (a, v) => a + v), b.expectedShared);
    expect(b.audit(), isEmpty);
  });
}

void overTests() {
  test('Zu viele Stück verteilt (3 + 1 von 3, Nutzer 08.11.): nicht fertig, Überhang sichtbar', () {
    final it = BillItem(name: 'Sprudel', amount: 1050, qty: 3, perUnit: true, shares: {0: 3, 1: 1});
    expect(it.coveredUnits, 4);
    expect(it.overUnits, 1);
    expect(it.fill, ItemFill.partial, reason: 'darf nicht als vollständig gelten');
    it.shares = {0: 2, 1: 1};
    expect(it.overUnits, 0);
    expect(it.fill, ItemFill.complete);
  });
}
