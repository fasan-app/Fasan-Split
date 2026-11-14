// SPDX-License-Identifier: MPL-2.0
// Fasan Split – hatching per person (Bon 3.9): every person colour has its own pattern, the first stays plain. MPL-2.0
import 'package:fasan_split/ui/person_avatar.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Schraffur je Person: acht Farben, acht verschiedene Muster, die erste Person bleibt glatt, danach wiederholt es sich wie die Farben', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Wrap(children: [for (var i = 0; i < 10; i++) PersonAvatar(key: ValueKey('av$i'), name: 'Person $i', index: i)]),
      ),
    ));
    int? kindOf(int i) {
      final f = find.descendant(of: find.byKey(ValueKey('av$i')), matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is HatchPainter));
      return f.evaluate().isEmpty ? null : ((tester.widget<CustomPaint>(f).painter) as HatchPainter).kind;
    }
    expect(kindOf(0), isNull, reason: 'erste Person glatt');
    expect([for (var i = 1; i < kHatchCount; i++) kindOf(i)], [1, 2, 3, 4, 5, 6, 7], reason: 'jede weitere Farbe hat ihr eigenes Muster');
    expect(kindOf(8), isNull);
    expect(kindOf(9), 1, reason: 'wie die Farben nach acht Personen von vorn');
    expect(find.byType(FasanAvatar), findsNWidgets(10));
  });
}
