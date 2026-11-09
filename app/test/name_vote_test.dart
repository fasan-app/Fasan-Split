// SPDX-License-Identifier: MPL-2.0
// Name and quantity voting across read passes (06.11.): leftovers of neighbouring columns must never outvote the clean name,
// gibberish from text shining through the paper gives way to a readable name, and the quantity votes too. Cases are the real
// readings from the gate (Restaurant Beispiel geknickt, Bäckerei Probe, Strandbar Erfunden, Café Muster, Aldi). MPL-2.0
import 'package:fasan_reader/model.dart';
import 'package:fasan_reader/name_repair.dart';
import 'package:fasan_reader/reader.dart' show nameFrom;
import 'package:flutter_test/flutter_test.dart';

List<Item> one(String name, int amount, {num qty = 1}) => [Item(name: name, amount: amount, qty: qty)];

void main() {
  test('Reste aus Nachbarspalten überstimmen den sauberen Namen nicht', () {
    for (final (clean, junk) in [('TULIPA', 'TULIPA 238'), ('AZEITONAS', 'Jn AZEITONAS'), ('Cafe Duplo', 'Cafe Duplo nm'), ('Cesta de pao', 'í Cesta de pao'), ('Vinho de Casa', 't Vinho de Casa')]) {
      final w = one(clean, 300);
      voteNames(w, [one(junk, 300), one(junk, 300), one(junk, 300)]);
      expect(w.first.name, clean, reason: '$junk darf $clean nicht ersetzen');
    }
  });

  test('Gewinner mit Rest nimmt die sauberste Schreibweise derselben Gruppe', () {
    final w = one('TULIPA 238', 350);
    voteNames(w, [one('TULIPA', 350), one('TULIPA 238', 350)]);
    expect(w.first.name, 'TULIPA');
  });

  test('Zusammengeklebter Kauderwelsch weicht einem lesbaren Namen, auch mit einer Stimme', () {
    final w = one('Bio SpaghettiioTnsldanAstnen', 85);
    voteNames(w, [one('Bio Spaghetti', 85)]);
    expect(w.first.name, 'Bio Spaghetti');
    expect(wordLikeness('SpaghettiioTnsldanAstnen'), lessThan(0.5));
    expect(wordLikeness('Bio Spaghetti'), 1.0);
    expect(wordLikeness('Croissant c/ N'), 1.0);
    // known limit (06.11.): text of the reverse side read mirrored has normal vowels and is not recognised as gibberish
    expect(wordLikeness('oxaaue bnu nedtelwol (Ü'), greaterThan(0.5));
  });

  test('Menge stimmt mit: zwei Durchläufe sagen 2, der Gewinner las keine', () {
    final w = one('Coca cola', 600);
    voteNames(w, [one('Coca cola', 600, qty: 2), one('Coca cola', 600, qty: 2), one('Coca cola', 600)]);
    expect(w.first.qty, 2);
    expect(w.first.unit, 300);
    // one pass alone is not enough
    final v = one('Coca cola', 600);
    voteNames(v, [one('Coca cola', 600, qty: 2)]);
    expect(v.first.qty, 1);
  });

  test('Echte Namensänderung durch Mehrheit bleibt möglich', () {
    final w = one('PAD', 200);
    voteNames(w, [one('PAO', 200), one('PAO', 200)]);
    expect(w.first.name, 'PAO');
  });

  test('Leser: Steuersatz-Rest am Namensende weg, echte Namen bleiben', () {
    expect(nameFrom('Uni TULIPA 238 '), 'TULIPA');
    expect(nameFrom('Un1 TABUA QUEIJOS P P13 '), allOf(startsWith('TABUA QUEIJOS'), isNot(contains('13'))));
    expect(nameFrom('814998 Bio Spaghetti '), 'Bio Spaghetti');
    // weight/count detail lines carry no name (Weltkorpus 06.11.: „NET“ and „1.000ea“ became names)
    expect(nameFrom('0.482 kg NET @ \$'), '');
    expect(nameFrom('1.000Ea @\$ '), '');
    expect(nameFrom('0.375kg @ \$ 5.99/kg \$ '), '');
    expect(nameFrom('2 @ \$0.25 EACH'), '');
    expect(nameFrom('Mango Calypso '), 'Mango Calypso');
    expect(nameFrom('2 Galao '), 'Galao');
    expect(nameFrom('Korean Chicken Wings 1 item(s) \$'), 'Korean Chicken Wings');
    expect(nameFrom('1 item(s) \$'), '');
    expect(nameFrom('2Uni Croisssant c/ N 13x '), 'Croissant c/ N');
    expect(nameFrom('1.00 Pedras 25 cl '), contains('Pedras 25 cl'));
    expect(nameFrom('1 Uni Agua 50cl '), 'Agua 50cl');
    expect(nameFrom('1.00 Cafe Duplo nm '), 'Cafe Duplo');
    expect(nameFrom('1.00 Cafe Duplo nm € '), 'Cafe Duplo');
    expect(nameFrom('1.00 Coca-Cola 33 cl '), 'Coca-Cola 33 cl');
  });

  test('Durchlauf mit um eine Zeile verschobener Betragsspalte stimmt nicht mit (Weltkorpus b2-084, 07.11.)', () {
    List<Item> pass(List<String> names) => [
          for (final (k, a) in [634, 499, 1499, 299, 299, 170].indexed) Item(name: names[k], amount: a),
        ];
    const right = ['POTATO SWEET WHITE PREMIUM', 'Shrimp Rice Rolls 1KG TTC', 'Pork Sausages 375GM TRANS FOOD', 'BERRIES STRAWBERRIES 250g', 'BERRIES BLUEBERRIES 125G', 'AVOCADO HASS LARGE'];
    // amount column one row up: every amount gets the name of the next item
    final shifted = [...right.skip(1), 'Number of Items'];
    final w = pass(right);
    voteNames(w, [pass(shifted), pass(shifted), pass(shifted)]);
    expect([for (final p in w) p.name], right);
    // a pass with one extra item above only moves the index, the pairing is right: it still votes (fixes a slip)
    final slip = pass(right)..[1].name = 'Shrimp Rice Rols 1KG TTC';
    final extra = [Item(name: 'Beispielort', amount: 5), ...pass(right)];
    voteNames(slip, [extra, extra]);
    expect(slip[1].name, 'Shrimp Rice Rolls 1KG TTC');
  });

  test('Name eines Nachbarpostens ist keine Stimme (örtlich verschoben, Target b3-013); gleicher Name zweimal bleibt', () {
    List<Item> pass(List<(String, int)> x) => [for (final (n, a) in x) Item(name: n, amount: a)];
    final w = pass([('HEINZ', 177), ('2CT L PAPER', 369), ('MAYB MASC', 524)]);
    final local = pass([('HEINZ', 177), ('HEINZ', 369), ('2CT L PAPER', 524)]);
    voteNames(w, [local, local, local]);
    expect([for (final p in w) p.name], ['HEINZ', '2CT L PAPER', 'MAYB MASC']);
    final twice = pass([('CGIRL LIPSTK', 687), ('CGIRL LIPSTIK', 488)]);
    voteNames(twice, [pass([('CGIRL LIPSTK', 687), ('CGIRL LIPSTK', 488)]), pass([('CGIRL LIPSTK', 687), ('CGIRL LIPSTK', 488)])]);
    expect(twice[1].name, 'CGIRL LIPSTK');
  });
}
