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
    // items: 1 done, 1 partial, 2 open; the payers of both bills (chosen = done) count like items
    expect((c.done, c.partial, c.open), (3, 1, 2));
    expect(itemCounts(const []).open, 0);
  });

  test('flattenItems: Überschrift je Bon, „nur offene“ lässt erledigte Posten und leere Bons weg', () {
    final a = bill('a', [ItemFill.complete, ItemFill.open]);
    final b = bill('b', [ItemFill.complete]);
    final all = flattenItems([a, b], onlyOpen: false);
    expect(all.length, 7); // heading a, payer, 2 items, heading b, payer, 1 item
    expect(all.where((e) => e.$2 == null).length, 2);
    final open = flattenItems([a, b], onlyOpen: true);
    // heading a + its open item; bill b has nothing open. The payer line of a shows too: nobody has it settled yet (Nutzer 11.11.: Bezahlt ist ein Posten)
    expect(open.map((e) => e.$2?.name), [null, 'Posten a1']);
  });

  test('flattenItems: Statusknopf „erledigt“ gewinnt gegen „Nur offene“ (sonst bleibt die Liste leer); Suche engt Posten ein', () {
    final a = bill('a', [ItemFill.complete, ItemFill.open]);
    final done = flattenItems([a], onlyOpen: true, fills: {ItemFill.complete});
    expect(done.map((e) => e.$2?.name), [null, '', 'Posten a0']); // '' = the payer line: paid, so it counts as done
    final found = flattenItems([a], onlyOpen: false, itemMatch: (b, i) => i.name.endsWith('1'));
    expect(found.map((e) => e.$2?.name), [null, 'Posten a1']);
    expect(flattenItems([a], onlyOpen: false, itemMatch: (b, i) => false), isEmpty);
  });

  test('Zahler-Zeile: ist ein Posten der Liste, folgt den Statusknöpfen und wird von der Suche gefunden (Bier, Bezahlt)', () {
    final paid = bill('a', [ItemFill.complete]); // payer chosen = done
    final unpaid = bill('b', [ItemFill.complete], paid: false); // nobody paid yet = open
    final pr = (List<(Bill, BillItem?)> l) => l.where((e) => identical(e.$2, kPayerRow)).map((e) => e.$1.id).toList();
    expect(pr(flattenItems([paid, unpaid], onlyOpen: false)), ['a', 'b']);
    expect(pr(flattenItems([paid, unpaid], onlyOpen: false, fills: {ItemFill.open})), ['b'], reason: 'open button shows the open payer line');
    expect(pr(flattenItems([paid, unpaid], onlyOpen: false, fills: {ItemFill.complete})), ['a']);
    expect(pr(flattenItems([paid, unpaid], onlyOpen: true)), ['b']);
    // a bill with one person has no payer line (nothing to settle)
    final solo = bill('c', [ItemFill.complete])..ps.removeLast();
    expect(pr(flattenItems([solo], onlyOpen: false)), isEmpty);
    // search: the item name finds the item; „Bier“ does not drag in other items
    final beer = bill('d', [ItemFill.complete, ItemFill.complete]);
    beer.its[0].name = 'Bier';
    final hit = flattenItems([beer], onlyOpen: false, itemMatch: (b, i) => itemSearchMatch(b, i, 'bier', true));
    expect(hit.map((e) => e.$2?.name), [null, 'Bier']);
    expect(itemSearchMatch(beer, beer.its[0], 'bier', true), isTrue);
    expect(itemSearchMatch(beer, beer.its[1], 'bier', true), isFalse);
  });

  test('Suche nach der Art: „Bier“ findet Super Bock und Cerveja, nicht die Pizza; „cerveja“ findet „Bier“ (Nutzer 12.11.)', () {
    final b = bill('e', [ItemFill.complete, ItemFill.complete, ItemFill.complete, ItemFill.complete]);
    b.its[0].name = 'Super Bock 0,5l';
    b.its[1].name = 'Cerveja Sagres';
    b.its[2].name = 'Pizza Margherita';
    b.its[3].name = 'Bier';
    bool hit(int n, String q) => itemSearchMatch(b, b.its[n], q, true);
    expect([hit(0, 'bier'), hit(1, 'bier'), hit(2, 'bier'), hit(3, 'bier')], [true, true, false, true]);
    expect([hit(0, 'cerveja'), hit(1, 'cerveja'), hit(2, 'cerveja'), hit(3, 'cerveja')], [true, true, false, true]);
    expect(billSearchText(b, true).contains('bier'), isTrue);
    expect(hit(2, 'pizza'), isTrue, reason: 'the own name still finds');
    expect(hit(2, 'x'), isFalse);
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

  testWidgets('Gruppenseite: Suche findet „Bier“ (Posten) und „Bezahlt“ (Zahler-Zeile), die Statusknöpfe gelten auch für die Zahler-Zeile', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final a = bill('a', [ItemFill.complete, ItemFill.open]);
    a.its[1].name = 'Bier';
    final store = BillStore.memory([a, bill('b', [ItemFill.complete], paid: false)])..onboarded = true;
    final q = ScanQueue(store, recognize: (_) => const Stream.empty());
    final ctl = FasanController(settings: FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ctl, home: GroupScreen(name: 'WG', queue: q)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Posten').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payer-b')), findsOneWidget, reason: 'the payer line is a row of the list');
    await tester.enterText(find.byKey(const ValueKey('group-search')), 'bier');
    await tester.pumpAndSettle();
    expect(find.textContaining('Bier'), findsWidgets, reason: 'Bier is found');
    expect(find.textContaining('Posten a0'), findsNothing, reason: 'other items are filtered out');
    expect(find.byKey(const ValueKey('payer-b')), findsNothing, reason: 'bill b has nothing with Bier');
    await tester.enterText(find.byKey(const ValueKey('group-search')), 'bezahlt');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payer-a')), findsOneWidget, reason: '„Bezahlt“ finds the payer lines');
    expect(find.byKey(const ValueKey('payer-b')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('group-search')), '');
    await tester.pumpAndSettle();
    // „open“ button: only the open payer line (bill b, nobody paid) and open items
    await tester.tap(find.byKey(const ValueKey('chip-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payer-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('payer-a')), findsNothing, reason: 'a has a payer: done');
  });
}
