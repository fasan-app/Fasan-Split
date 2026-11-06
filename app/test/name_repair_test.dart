// Fasan Split – item names after reading, with the readings from the S23 log of 04.11. (Ferreiras LX Factory). MPL-2.0
import 'package:fasan_reader/model.dart';
import 'package:fasan_reader/name_repair.dart';
import 'package:flutter_test/flutter_test.dart';

List<Item> pass(List<(String, int, num)> l) => [for (final (n, a, q) in l) Item(name: n, amount: a)..qtyRead = q];

void main() {
  test('Ferreiras: Steuerspalte und e weg, z = 2, verlesener Name von der Mehrheit', () {
    final gerade = pass([
      ('Caneca 23 e', 300, 1), ('Tea 13 e', 350, 1), ('nrezaenrzzeu 23 e', 300, 1), ('z Coca cola 23 e', 600, 0),
      ('Imperial 23 e', 150, 0), ('Burrito Pollo 13 e', 2760, 2), ('Taco Pollo 13 e', 1300, 1), ('Burrito Veg s e', 1250, 1),
      ('Canasta Mex 13 e', 690, 1), ('Cafe exp 13 e', 200, 1),
    ]);
    List<Item> other(String third) => pass([
          ('Caneca 23 e', 300, 1), ('Tea 13 e', 350, 1), (third, 300, 1), ('Coca cola 23 e', 600, 2), ('Imperial 23 e', 150, 1),
          ('Burrito Pollo 13 e', 2760, 2), ('Taco Pollo 13 e', 1300, 1), ('Burrito Veg 13 e', 1250, 1), ('Canasta Mex 13 e', 690, 1),
          ('Cafe exp 13 e', 200, 1),
        ]);
    final others = [other('Coca cola zero 23 e'), other('Coca cola zero 23 e'), other('neaenzzecu e'), other('Coca cola zero as e')];
    for (final o in [gerade, ...others]) {
      cleanColumns(o);
      fixQuantityLetters(o);
    }
    voteNames(gerade, others);
    expect(gerade.map((p) => p.name), [
      'Caneca', 'Tea', 'Coca cola zero', 'Coca cola', 'Imperial', 'Burrito Pollo', 'Taco Pollo', 'Burrito Veg', 'Canasta Mex', 'Cafe exp',
    ]);
    expect(gerade[3].qty, 2);
    expect(gerade.map((p) => p.amount).fold<int>(0, (a, x) => a + x), 7900, reason: 'Beträge bleiben');
  });

  test('Normale Namen bleiben (keine Spalte, keine Mengenbuchstaben)', () {
    final l = pass([('Pizza Margherita', 900, 1), ('Menu XL', 1200, 1), ('Wasser 0,5 l', 300, 1)]);
    cleanColumns(l);
    fixQuantityLetters(l);
    expect(l.map((p) => p.name), ['Pizza Margherita', 'Menu XL', 'Wasser 0,5 l']);
  });
}
