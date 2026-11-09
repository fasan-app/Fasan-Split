// SPDX-License-Identifier: MPL-2.0
// A bill opened from its tile keeps the soft ground like every other screen (Nutzer 06.11., Bildschirmvergleich App/Browser: the
// bill was flat because the container transform painted an opaque colour). MPL-2.0
import 'package:fasan_split/main.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Kachel öffnet den Bon ohne deckende Farbe', (tester) async {
    final b = Bill(id: 'o', created: DateTime(2026, 11, 6), total: 1000, people: [Person('A', 0)], items: [BillItem(name: 'Pizza', amount: 1000)])..done = true;
    final store = BillStore.memory([b])..onboarded = true;
    await tester.pumpWidget(SplitApp(store: store, ui: FasanController(), home: const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    // OpenContainer comes from package:animations (a dependency of fasan_ui): compare by name, read the colour dynamically
    final oc = find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('OpenContainer'));
    expect(oc, findsWidgets);
    for (final w in tester.widgetList(oc)) {
      expect((w as dynamic).openColor, Colors.transparent);
    }
  });
}
