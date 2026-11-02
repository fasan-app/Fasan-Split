// Posten-Namen: Störzeichen vor der Einheitenspalte („Uni“) gehören nicht in den Namen (Nutzer 02.11.: „P Pizza Peperoni“).
import 'package:fasan_split/recognition/reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  checkNames();
  test('ein Fleck vor „Uni“ bleibt nicht im Namen', () {
    expect(nameFrom('2 P Uni PIZZA PEPPERONI 13%'), 'PIZZA PEPPERONI');
    expect(nameFrom('2 \\ Uni PIZZA PEPPERONI'), 'PIZZA PEPPERONI');
    expect(nameFrom('1 í Uni CANECA 23%'), 'CANECA');
  });
  test('normale Namen bleiben unverändert', () {
    expect(nameFrom('1 Uni TULIPA 23%'), 'TULIPA');
    expect(nameFrom('Uni Agua com Gas 23%'), 'Agua com Gas');
    expect(nameFrom('3 Uni COCA COLA'), 'COCA COLA');
    expect(nameFrom('2 Pizza Margherita'), 'Pizza Margherita');
    expect(nameFrom('1 Un Pao'), 'Pao');
  });
}

void checkNames() {
  group('verdächtige Namen und Alternativen', () {
    test('verdächtig: einzelner Konsonant vorn', () {
      expect(suspiciousName('P PIZZA PEPPERONI'), isTrue);
      expect(suspiciousName('PIZZA PEPPERONI'), isFalse);
      expect(suspiciousName('A Bifana'), isFalse);
      expect(suspiciousName('Agua com Gas'), isFalse);
      expect(suspiciousName('Sopa #~ €x'), isTrue);
    });
    test('Alternativen: ohne Fleck vorn, lesbare Schreibweise', () {
      expect(nameAlternatives('P PIZZA PEPPERONI'), ['PIZZA PEPPERONI', 'Pizza Pepperoni']);
      expect(nameAlternatives('Cafe'), isEmpty);
    });
  });
}
