// SPDX-License-Identifier: MPL-2.0
// Fasan Split – a search hit leads INTO the bill: the bill screen with focusItem scrolls that item to the middle and pulses it.
// Invented data only. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/bill_screen.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reduce in [true, false]) {
    testWidgets('ReviewScreen mit focusItem: Posten 25 von 40 liegt in der Mitte (Animationen ${reduce ? 'aus' : 'an'})', (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 2.75; // 800 dp high
      addTearDown(tester.view.reset);
      tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final b = Bill(
        id: 'f',
        created: DateTime(2026, 11, 2),
        purpose: 'Eck',
        total: 40 * 100,
        people: [Person('Anna', 0), Person('Ben', 1)],
        items: [for (var i = 0; i < 40; i++) BillItem(name: 'Gericht ${i.toString().padLeft(2, '0')}', amount: 100)],
        done: true,
      )..payer = 0;
      final store = BillStore.memory([b])..onboarded = true;
      await tester.pumpWidget(SplitApp(store: store, ui: FasanController(settings: FasanSettings(reduceMotion: reduce)), home: ReviewScreen(bill: b, focusItem: 25)));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final f = find.textContaining('Gericht 25');
      expect(f, findsWidgets, reason: 'the item is on the screen');
      final y = tester.getCenter(f.first).dy;
      expect(y, inInclusiveRange(250, 550), reason: 'near the middle of the 800 dp screen, got $y');
    });
  }
}
