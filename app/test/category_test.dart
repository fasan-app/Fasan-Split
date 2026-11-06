// Fasan Split – category guess from the receipt, sorting and filtering of the lists. MPL-2.0
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/ui/category.dart';
import 'package:fasan_split/ui/category_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Bill b(String id, String shop, int cents, {String? cat, int day = 1, int step = 4}) =>
    Bill(id: id, created: DateTime(2026, 10, day), purpose: shop, total: cents, items: [BillItem(name: 'x', amount: cents)])
      ..category = cat
      ..step = step;

void main() {
  test('Kategorie aus dem Geschäftsnamen', () {
    expect(guessCategory(b('1', 'REWE Markt', 100)), 'groceries');
    expect(guessCategory(b('2', 'Tasca De Noticias', 100)), 'restaurant');
    expect(guessCategory(b('3', 'Uber', 100)), 'transport');
    expect(guessCategory(b('4', 'Hotel Lisboa Bar', 100)), 'stay', reason: 'Hotel vor Bar');
    expect(guessCategory(b('5', 'Galp', 100)), 'fuel');
    expect(guessCategory(b('6', 'Xyz', 100)), isNull);
    expect(categoryById('c:Geschenke')?.label(true), 'Geschenke');
  });

  test('Sortieren und Filtern', () {
    final l = [b('a', 'Zeta', 500, day: 2, cat: 'bar', step: 2), b('b', 'alpha', 900, day: 1, cat: 'groceries'), b('c', 'Mitte', 100, day: 3)];
    expect(arrange(l, BillSort.date, null).map((x) => x.id), ['c', 'a', 'b']);
    expect(arrange(l, BillSort.amount, null).map((x) => x.id), ['b', 'a', 'c']);
    expect(arrange(l, BillSort.shop, null).map((x) => x.id), ['b', 'c', 'a']);
    expect(arrange(l, BillSort.category, null).map((x) => x.id), ['b', 'a', 'c']);
    expect(arrange(l, BillSort.status, null).first.id, 'a');
    expect(arrange(l, BillSort.own, 'bar').map((x) => x.id), ['a']);
  });
}
