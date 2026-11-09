// SPDX-License-Identifier: MPL-2.0
// English: the total field uses the same number format as the items (Bildschirmvergleich 06.11.: „24,00 €“ above „14.00 €“), and the
// bill title is not cut to „Rec…“. MPL-2.0
import 'package:fasan_split/main.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/bill_screen.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Englisch: Summe im Feld mit Punkt, Titel ganz', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final b = Bill(id: 'e', created: DateTime(2026, 11, 6), total: 2400, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Pizza', amount: 1400, shares: {0: 1}),
      BillItem(name: 'Wein', amount: 1000, shares: {1: 1}),
    ]);
    final store = BillStore.memory([b])..onboarded = true;
    await tester.pumpWidget(SplitApp(store: store, ui: FasanController(settings: const FasanSettings(reduceMotion: true)), home: ReviewScreen(bill: b)));
    await tester.pump(const Duration(milliseconds: 500));
    final total = tester.widgetList<TextField>(find.byType(TextField)).map((t) => t.controller?.text).toList();
    expect(total, contains('24.00'), reason: 'englisches Zahlenformat wie bei den Posten');
    expect(total, isNot(contains('24,00')));
    final title = tester.renderObject<RenderParagraph>(find.text('Receipt').first);
    expect(title.didExceedMaxLines, isFalse, reason: 'Titel nicht abgeschnitten');
  });
}
