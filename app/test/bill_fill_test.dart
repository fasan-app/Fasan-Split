// SPDX-License-Identifier: MPL-2.0
// Rechnungsstatus wie bei den Posten, Sortierung nach Status dann Datum, „nur offene Posten“ (Nutzer 07.11.). MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/category_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Bill bill(String id, DateTime d, List<Map<int, double>> shares) => Bill(
      id: id,
      created: d,
      purpose: id,
      people: [Person('A', 0), Person('B', 1)],
      items: [for (final (i, s) in shares.indexed) BillItem(name: 'x$i', amount: 100, shares: s)],
    );

void main() {
  final d = DateTime(2026, 11, 1);
  final open = bill('open', d.add(const Duration(days: 1)), [{}, {}]);
  final partial = bill('partial', d.add(const Duration(days: 2)), [{0: 1}, {}]);
  final complete = bill('complete', d.add(const Duration(days: 3)), [{0: 1}, {1: 1}])..payer = 0;
  final open2 = bill('open2', d.add(const Duration(days: 4)), [{}]);

  test('Status der Rechnung aus den Posten: offen, teilweise, vollständig', () {
    expect(open.fill, ItemFill.open);
    expect(partial.fill, ItemFill.partial);
    expect(complete.fill, ItemFill.complete);
    expect(Bill(id: 'e', created: d, items: []).fill, ItemFill.open, reason: 'ohne Posten noch offen');
  });

  test('Zahler fehlt: Rechnung ist nicht grün (Nutzer 08.11.), mehrere Zahler mit Lücke teilweise', () {
    final noPayer = bill('np', d, [{0: 1}, {1: 1}]);
    expect(noPayer.itemsFill, ItemFill.complete);
    expect(noPayer.payFill, ItemFill.open);
    expect(noPayer.fill, ItemFill.partial, reason: 'Posten fertig, Zahler fehlt: gelb, nicht grün');
    expect(bill('np2', d, [{}, {}]).fill, ItemFill.open, reason: 'beides offen');
    expect((bill('p', d, [{0: 1}, {1: 1}])..payer = 1).fill, ItemFill.complete);
    final two = bill('two', d, [{0: 1}, {1: 1}])
      ..payer = 0
      ..paid = {0: 100, 1: 50}; // receipt is 200
    expect(two.payFill, ItemFill.partial);
    expect(two.fill, ItemFill.partial);
    two.paid = {0: 150, 1: 50};
    expect(two.fill, ItemFill.complete);
  });

  test('Sortierung nach Status: offen, teilweise, vollständig; innerhalb des Status das neueste zuerst', () {
    final l = [complete, open, partial, open2];
    expect(arrange(l, BillSort.status, null).map((b) => b.id), ['open2', 'open', 'partial', 'complete']);
  });

  test('Standard ist Status; „nur offene Posten“ blendet vollständige Rechnungen aus', () {
    expect(BillStore.memory().sortMode, BillSort.status);
    final l = [complete, open, partial];
    expect(arrange(l, BillSort.status, null, onlyOpen: true).map((b) => b.id), ['open', 'partial']);
    expect(arrange(l, BillSort.status, null).length, 3);
    final s = BillStore.memory();
    expect(s.onlyOpen, isFalse);
    s.onlyOpen = true;
    expect(s.onlyOpen, isTrue);
  });
}
