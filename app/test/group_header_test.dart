// SPDX-License-Identifier: MPL-2.0
// Fasan Split – group header, counts, switch Rechnungen | Posten (ui/group_header.dart, GroupScreen). MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/category_ui.dart';
import 'package:fasan_split/ui/group_header.dart';
import 'package:fasan_split/ui/groups.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bill with one item per entry of [fills]: complete = shared by everyone, partial = one share short, open = nobody.
Bill bill(String id, List<ItemFill> fills, {String group = 'WG', bool paid = true}) {
  final b = Bill(id: id, created: DateTime(2026, 3, 11), purpose: 'Kneipe $id', total: 1000 * fills.length, done: false)
    ..group = group
    ..payer = paid ? 0 : null;
  b.ps.addAll([Person('Anna', 0), Person('Ben', 1)]);
  for (final (i, f) in fills.indexed) {
    final it = BillItem(name: 'Posten $id$i', amount: 1000);
    switch (f) {
      case ItemFill.complete:
        it.shares = {0: 1, 1: 1};
      case ItemFill.partial:
        it.qty = 2; // two units, only one person: not done yet
        it.shares = {0: 1};
      case ItemFill.open:
        it.shares = {};
    }
    b.its.add(it);
  }
  return b;
}

void main() {
  test('itemCounts zählt Posten nach Zustand, Überweisungen zählen nicht', () {
    final a = bill('a', [ItemFill.complete, ItemFill.open, ItemFill.open]);
    final c = itemCounts([a, bill('b', [ItemFill.partial])]);
    expect((c.done, c.partial, c.open), (1, 1, 2));
    expect(itemCounts(const []).open, 0);
  });

  test('flattenItems: Überschrift je Bon, „nur offene“ lässt erledigte Posten und leere Bons weg', () {
    final a = bill('a', [ItemFill.complete, ItemFill.open]);
    final b = bill('b', [ItemFill.complete]);
    final all = flattenItems([a, b], onlyOpen: false);
    expect(all.length, 5); // heading a, 2 items, heading b, 1 item
    expect(all.where((e) => e.$2 == null).length, 2);
    final open = flattenItems([a, b], onlyOpen: true);
    expect(open.length, 2); // heading a + its open item; bill b has nothing open
    expect(open.last.$2!.name, 'Posten a1');
  });

  test('billsWithoutPayer: nur Bons mit Posten und ohne Zahler', () {
    expect(billsWithoutPayer([bill('a', [ItemFill.open], paid: false), bill('b', [ItemFill.open])]), 1);
    expect(billsWithoutPayer([bill('c', [], paid: false)]), 0);
  });

  testWidgets('Kopf zeigt Anzahl, Preis, Personen; Umschalter zeigt alle Posten; „Nur offene“ filtert', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    // tall screen: the list is lazy, rows below the fold are not built
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final store = BillStore.memory([
      bill('a', [ItemFill.complete, ItemFill.open]),
      bill('b', [ItemFill.partial], paid: false),
    ])..onboarded = true;
    final q = ScanQueue(store, recognize: (_) => const Stream.empty());
    final ctl = FasanController(settings: FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ctl, home: GroupScreen(name: 'WG', queue: q)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2 Bons'), findsOneWidget);
    expect(find.text('30,00 €'), findsOneWidget, reason: 'Summe der Bons im Kopf');
    // one open + one partial item = 2 open; bill b has no payer
    expect(find.byKey(const ValueKey('chip-nopayer')), findsOneWidget, reason: 'Bon b hat keinen Zahler');
    // the open button filters the flat list to open items, tapping again switches it off
    await tester.tap(find.byKey(const ValueKey('chip-open')));
    await tester.pumpAndSettle();
    expect(find.text('Bon-a'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chip-open')));
    await tester.pumpAndSettle();
    // switch to the flat item list
    await tester.tap(find.text('Posten').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Posten a0'), findsOneWidget);
    expect(find.textContaining('Posten a1'), findsOneWidget);
    expect(find.textContaining('Posten b0'), findsOneWidget);
    // only open ones: the finished item disappears
    store.onlyOpen = true;
    await tester.pumpAndSettle();
    expect(find.textContaining('Posten a0'), findsNothing);
    expect(find.textContaining('Posten a1'), findsOneWidget);
  });
}
