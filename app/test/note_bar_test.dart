// SPDX-License-Identifier: MPL-2.0
// Fasan Split – messages (Roadmap 1.3, 14.11.): a message with „Rückgängig“ runs out, the action stays beside the text, and an
// amount never breaks from its sign (browser walk 14.11.: the note stayed three pages, „6,00 / €“ broke). MPL-2.0
import 'package:fasan_split/ui/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('noteBar läuft immer aus, auch mit Aktion; Aktion bleibt bis 40 % neben dem Text', () {
    final b = noteBar('Eingetragen: Lena hat Pia 6,00 € gezahlt.', action: SnackBarAction(label: 'Rückgängig', onPressed: () {}));
    expect(b.persist, isFalse);
    expect(b.actionOverflowThreshold, 0.4);
    expect((b.content as Text).data, 'Eingetragen: Lena hat Pia 6,00 € gezahlt.');
  });

  test('Betrag und Währungszeichen bleiben zusammen, anderer Text bleibt gleich', () {
    expect(keepAmountsTogether('12,50 € und 3 CHF'), '12,50 € und 3 CHF');
    expect(keepAmountsTogether('Pia € Lena'), 'Pia € Lena');
  });

  testWidgets('Meldung mit „Rückgängig“ verschwindet nach ihrer Zeit von selbst', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showNote(c, 'Eingetragen: 6,00 €', actionLabel: 'Rückgängig', onAction: () {}), child: const Text('auf'))))));
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle(); // entrance; the messenger starts the timer at a build after it
    expect(find.text('Rückgängig'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Rückgängig'), findsNothing, reason: 'ohne persist:false bliebe sie stehen');
  });
}
