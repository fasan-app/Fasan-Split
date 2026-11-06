// Exact settlement with the fewest transfers (Kosten 2; Beschluss 06.11. „exakter Ausgleich“, vorher gierig). MPL-2.0
import 'dart:math';

import 'package:fasan_core/settle.dart';
import 'package:flutter_test/flutter_test.dart';

int _min(List<int> v) {
  // brute force: n − largest number of zero-sum groups
  final m = v.length;
  final memo = <int, int>{};
  int best(int mask) {
    if (mask == 0) return 0;
    return memo[mask] ??= () {
      var b = 0;
      for (var sub = mask; sub > 0; sub = (sub - 1) & mask) {
        if (sub & (mask & -mask) == 0) continue;
        var s = 0;
        for (var i = 0; i < m; i++) {
          if (sub & (1 << i) != 0) s += v[i];
        }
        if (s == 0) b = max(b, 1 + best(mask ^ sub));
      }
      return b;
    }();
  }

  return m - best((1 << m) - 1);
}

void check(Map<String, int> bal) {
  final t = settle(bal);
  final after = Map<String, int>.of(bal);
  for (final (from, to, c) in t) {
    expect(c, greaterThan(0));
    after[from] = after[from]! + c;
    after[to] = after[to]! - c;
  }
  expect(after.values.every((x) => x == 0), isTrue, reason: 'alles ausgeglichen: $bal → $t');
  final nz = [for (final x in bal.values) if (x != 0) x];
  expect(t.length, _min(nz), reason: 'wenigste Überweisungen für $bal');
}

void main() {
  test('Beispiel, bei dem der alte Weg 4 statt 3 Überweisungen brauchte', () {
    final bal = {'B': 300, 'C': 600, 'D': 600, 'E': -600, 'F': -900};
    expect(settle(bal).length, 3);
    check(bal);
  });

  test('Zufällige Salden: immer ausgeglichen und immer die wenigsten Überweisungen; gleiche Eingabe, gleiches Ergebnis', () {
    final r = Random(7);
    for (var t = 0; t < 400; t++) {
      final n = 2 + r.nextInt(7);
      final v = [for (var i = 0; i < n - 1; i++) (r.nextInt(13) - 6) * 100];
      v.add(-v.fold(0, (a, b) => a + b));
      final bal = {for (var i = 0; i < n; i++) 'P$i': v[i]};
      check(bal);
      expect(settle(bal), settle(Map.of(bal)));
    }
  });
}
