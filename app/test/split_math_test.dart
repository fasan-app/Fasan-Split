import 'dart:math';

import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/model/split_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// Property tests: thousands of random cases. A calculation error stops the build (Beschluss 03.11.).
void main() {
  test('3 Cola auf 2 Personen: 1,5 Stück je Person, 4,80 € je Person', () {
    final s = {0: 1.0, 1: 1.0};
    expect(SplitMath.pieces(3, s, 0), (3, 2));
    expect(SplitMath.split(960, s), {0: 480, 1: 480});
  });

  test('Rest-Cent wandert reihum', () {
    final a = SplitMath.split(1000, {0: 1, 1: 1, 2: 1}, rotate: 0);
    final b = SplitMath.split(1000, {0: 1, 1: 1, 2: 1}, rotate: 1);
    final c = SplitMath.split(1000, {0: 1, 1: 1, 2: 1}, rotate: 2);
    expect([a[0], b[0], c[0]].where((x) => x == 334).length, 1, reason: 'jeder bekommt den Cent genau einmal');
    expect([a[1], b[1], c[1]].where((x) => x == 334).length, 1);
    expect([a[2], b[2], c[2]].where((x) => x == 334).length, 1);
  });

  test('Zufall: Summe stimmt immer, beide Verfahren stimmen überein (20 000 Fälle)', () {
    final r = Random(42);
    for (var i = 0; i < 20000; i++) {
      final n = 1 + r.nextInt(7);
      final amount = (r.nextBool() ? 1 : -1) * r.nextInt(500000);
      final shares = {for (var k = 0; k < n; k++) if (r.nextInt(5) > 0 || k == 0) k: 0.5 * (1 + r.nextInt(8))};
      final a = SplitMath.split(amount, shares, rotate: r.nextInt(50));
      final b = SplitMath.splitCumulative(amount, shares);
      expect(a.values.fold<int>(0, (x, y) => x + y), amount, reason: '$amount $shares');
      expect(b.values.fold<int>(0, (x, y) => x + y), amount, reason: '$amount $shares');
      expect(SplitMath.agree(a, b), isTrue, reason: '$amount $shares $a $b');
    }
  });

  test('Zufall: ganze Rechnung, Σ Personen = zugeordnete Posten + Differenz, Prüfung leer (3 000 Rechnungen)', () {
    final r = Random(7);
    for (var i = 0; i < 3000; i++) {
      final n = 2 + r.nextInt(5);
      final people = [for (var k = 0; k < n; k++) Person('P$k', k)];
      final items = [
        for (var k = 0; k < 1 + r.nextInt(15); k++)
          BillItem(name: 'x$k', amount: 1 + r.nextInt(6000) * (r.nextInt(12) == 0 ? -1 : 1), qty: 1 + r.nextInt(4), shares: {
            if (r.nextInt(6) > 0)
              for (var p = 0; p < n; p++)
                if (r.nextBool()) p: 0.5 * (1 + r.nextInt(6)),
          }),
      ];
      final sum = items.fold<int>(0, (a, p) => a + p.amount);
      final b = Bill(id: '$i', created: DateTime(2026), total: sum + r.nextInt(2000) - 500, people: people, items: items)..payer = r.nextInt(n);
      expect(b.audit(), isEmpty, reason: 'Rechnung $i: ${b.audit()}');
    }
  });

  test('Geld ohne Kommazahlen: 0,1 + 0,2 Falle', () {
    expect(SplitMath.split(30, {0: 0.1, 1: 0.2}), {0: 10, 1: 20});
  });
}
