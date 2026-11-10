// SPDX-License-Identifier: MPL-2.0
// The one bill screen (Nutzer 05.11.): item sheet (edit + assign at once), payers sheet, person picker with live filter, group
// suggestions, inviting a friend from the picker and taking it back. English locale (the test default). MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/common.dart' show ItemTitle;
import 'package:fasan_split/ui/flow.dart';
import 'package:fasan_split/ui/marquee_text.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Bill _bill({String? group, List<String> people = const []}) => Bill(
      id: 'b',
      created: DateTime(2026, 11, 5),
      purpose: 'Dinner',
      total: 4000,
      group: group,
      items: [BillItem(name: 'Pizza', amount: 2400), BillItem(name: 'Wine', amount: 1600)],
      people: [for (final (i, n) in people.indexed) Person(n, i)],
    );

Future<void> _pump(WidgetTester tester, Bill b, {BillStore? store, CollabService? collab}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final s = store ?? BillStore.memory();
  s.upsert(b);
  await tester.pumpWidget(SplitApp(store: s, ui: FasanController(settings: const FasanSettings(reduceMotion: true)), collab: collab, home: ReviewScreen(bill: b)));
  await tester.pumpAndSettle();
}

Finder _nameField() => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Type a name');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Filter „Nur offene Posten“ wechselt beim Einschalten die Beschriftung auf „Alle Posten“ und zurück', (tester) async {
    final b = _bill(people: ['Anna', 'Jo']);
    await _pump(tester, b);
    expect(find.text('Only open items'), findsOneWidget);
    expect(find.text('All items'), findsNothing);
    await tester.tap(find.text('Only open items'));
    await tester.pumpAndSettle();
    expect(find.text('All items'), findsOneWidget);
    expect(find.text('Only open items'), findsNothing);
    await tester.tap(find.text('All items'));
    await tester.pumpAndSettle();
    expect(find.text('Only open items'), findsOneWidget);
  });

  testWidgets('Posten-Blatt: Name, Betrag und Menge ändern UND zuordnen im selben Blatt, sofort gespeichert', (tester) async {
    final b = _bill(people: ['Anna', 'Jo']);
    await _pump(tester, b);
    await tester.tap(find.textContaining('Pizza'));
    await tester.pumpAndSettle();
    // edit …
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Name'), 'Pizza Diavola');
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Amount'), '25,00');
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Quantity'), '2');
    await tester.pumpAndSettle();
    expect(b.its[0].name, 'Pizza Diavola');
    expect(b.its[0].amount, 2500);
    expect(b.its[0].qty, 2);
    // … and assign, in the same sheet
    await tester.tap(find.widgetWithText(FasanPersonChip, 'Anna'));
    await tester.pumpAndSettle();
    expect(b.its[0].shares.keys, [0]);
    await tester.tap(find.widgetWithText(FasanPersonChip, 'Jo'));
    await tester.pumpAndSettle();
    expect(b.its[0].shares.keys.toSet(), {0, 1});
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(find.text('Pizza Diavola'), findsWidgets);
    expect(b.unassigned, 1, reason: 'the wine is still open');
  });

  testWidgets('Posten löschen: Wischen oder Blatt, Rückgängig bringt ihn an dieselbe Stelle zurück', (tester) async {
    final b = _bill(people: ['Anna', 'Jo']);
    await _pump(tester, b);
    await tester.drag(find.textContaining('Pizza'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(b.its.map((i) => i.name), ['Wine']);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(b.its.map((i) => i.name), ['Pizza', 'Wine']);
    // via the sheet
    await tester.tap(find.text('Wine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(b.its.map((i) => i.name), ['Pizza']);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(b.its.map((i) => i.name), ['Pizza', 'Wine']);
  });

  testWidgets('Löschen rückgängig nach Entfernen einer Person: Anteile folgen den Personen, keine Anteile von Abwesenden (Monkey-Test seed 2)', (tester) async {
    final b = _bill(people: ['Anna', 'Jo', 'Mia']);
    b.its[0].shares = {0: 1, 1: 1, 2: 1};
    b.its[0].fixed = {};
    await _pump(tester, b);
    await tester.drag(find.textContaining('Pizza'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    b.removePerson(0); // Anna leaves while the item is deleted: Jo becomes 0, Mia 1
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final pizza = b.its.firstWhere((i) => i.name == 'Pizza');
    expect(pizza.shares.keys.toSet(), {0, 1}, reason: 'only Jo and Mia are left, at their new indices');
    expect(pizza.shares.keys.every((k) => k < b.ps.length), isTrue);
  });

  testWidgets('Mehrere Zahler mit ungleichen Anteilen im Bon-Bildschirm; Lücke wird gemeldet und lässt sich gleich verteilen', (tester) async {
    final b = _bill(people: ['Anna', 'Jo', 'Mia']);
    await _pump(tester, b);
    expect(find.text('Who paid?'), findsOneWidget, reason: 'the line asks until someone is chosen');
    await tester.tap(find.byKey(const ValueKey('payer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Several people paid'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FasanPersonChip, 'Anna'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FasanPersonChip, 'Jo'));
    await tester.pumpAndSettle();
    expect(b.paid.keys.toSet(), {0, 1});
    expect(b.paid.values.fold(0, (a, c) => a + c), 4000, reason: 'split equally to start with');
    // unequal: Anna 30, Jo 5 → 5 missing
    Finder paid(int i) => find.byWidgetPredicate((w) => w is TextField && w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith('paid-$i-'));
    await tester.enterText(paid(0), '30,00');
    await tester.enterText(paid(1), '5,00');
    await tester.pumpAndSettle();
    expect(b.paid, {0: 3000, 1: 500});
    expect(b.paidGap, 500);
    expect(find.textContaining('still missing'), findsOneWidget);
    await tester.enterText(paid(1), '10,00');
    await tester.pumpAndSettle();
    expect(b.paidGap, 0);
    expect(find.textContaining('Fits'), findsOneWidget);
    expect(b.payer, 0, reason: 'the one who paid most stands for the bill');
    await tester.tap(find.text('Split equally'));
    await tester.pumpAndSettle();
    expect(b.paid, {0: 2000, 1: 2000});
    // back to one person
    await tester.tap(find.text('Only one person'));
    await tester.pumpAndSettle();
    expect(b.paid, isEmpty);
    await tester.tap(find.widgetWithText(FasanPersonChip, 'Mia'));
    await tester.pumpAndSettle();
    expect(b.payer, 2);
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'Mia'), findsOneWidget);
  });

  testWidgets('Personenauswahl: wird beim Tippen gefiltert, ohne Akzente, „Neu:“ am Ende, Enter nimmt den ersten Treffer', (tester) async {
    // names come from earlier bills
    final store = BillStore.memory([Bill(id: 'o', created: DateTime(2026, 11, 1), items: [], people: [Person('José', 0), Person('Joana', 1), Person('Müller', 2), Person('Anna', 3)])]);
    final b = _bill(people: ['Anna']);
    await _pump(tester, b, store: store);
    await tester.tap(find.byKey(const ValueKey('add-person')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-Anna')), findsNothing, reason: 'already on the bill');
    expect(find.byKey(const ValueKey('pick-José')), findsOneWidget);
    await tester.enterText(_nameField(), 'jo');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-José')), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-Joana')), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-Müller')), findsNothing);
    await tester.enterText(_nameField(), 'muller');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-Müller')), findsOneWidget, reason: 'ü found by u');
    await tester.enterText(_nameField(), 'Zoe');
    await tester.pumpAndSettle();
    expect(find.text('New: Zoe'), findsOneWidget);
    await tester.enterText(_nameField(), 'jos');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(b.ps.map((p) => p.name), ['Anna', 'José'], reason: 'Enter takes the first match');
  });

  testWidgets('Aktive Person: Antippen der Posten schaltet sie um; langes Drücken öffnet das Blatt', (tester) async {
    final b = _bill(people: ['Anna', 'Jo']);
    await _pump(tester, b);
    await tester.tap(find.byKey(const ValueKey('person-1')));
    await tester.pumpAndSettle();
    expect(find.text('Tap the items of Jo'), findsOneWidget);
    await tester.tap(find.textContaining('Pizza'));
    await tester.tap(find.text('Wine'));
    await tester.pumpAndSettle();
    expect(b.its[0].shares.keys, [1]);
    expect(b.its[1].shares.keys, [1]);
    await tester.longPress(find.text('Wine'));
    await tester.pumpAndSettle();
    expect(find.text('Who had this?'), findsOneWidget);
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('active-stop')));
    await tester.pumpAndSettle();
    expect(find.text('Tap the items of Jo'), findsNothing);
  });

  testWidgets('Gruppe: Mitglieder werden vorgeschlagen, „Alle aus der Gruppe“ übernimmt sie, Freund außerhalb → einladen → zurückziehen', (tester) async {
    final hub = MemoryRelayHub();
    late CollabService a, c;
    late CollabGroup g2;
    late String lena;
    await tester.runAsync(() async {
      a = CollabService(store: BillStore.memory()..me = 'Pia', vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
      await a.init();
      await a.setName('Pia');
      final g1 = await a.createGroup('Stadt 26');
      g2 = await a.createGroup('Hütte');
      final link = g1.invitations!.create().link;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      c = CollabService(store: BillStore.memory()..me = 'Lena', vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
      await c.init();
      await c.setName('Lena');
      await c.join(link, 'Lena');
      await Future<void>.delayed(const Duration(seconds: 3));
      lena = c.identity!.pub;
    });
    addTearDown(a.dispose);
    addTearDown(c.dispose);

    // bill of the first group: Pia and Lena are members → both suggested, one tap takes everyone
    final store = BillStore.memory()..me = 'Pia';
    final b1 = _bill(group: 'Stadt 26');
    await _pump(tester, b1, store: store, collab: a);
    expect(find.byKey(const ValueKey('suggest-Lena')), findsOneWidget);
    expect(find.byKey(const ValueKey('suggest-Pia')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('suggest-all')));
    await tester.pumpAndSettle();
    expect(b1.ps.map((p) => p.name).toSet(), {'Pia', 'Lena'});
    expect(find.byKey(const ValueKey('suggest-all')), findsNothing, reason: 'nobody left to suggest');

    // bill of the second group: Lena is a friend, not a member → listed, marked, and offered an invitation
    final b2 = _bill(group: 'Hütte', people: ['Pia']);
    await _pump(tester, b2, store: store, collab: a);
    await tester.tap(find.byKey(const ValueKey('add-person')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-Lena')), findsOneWidget);
    expect(find.text('not in the group'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick-Lena')));
    await tester.pumpAndSettle();
    expect(b2.ps.map((p) => p.name), ['Pia', 'Lena'], reason: 'on the bill either way');
    expect(find.text('Invite Lena?'), findsOneWidget);
    await tester.tap(find.text('Invite'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();
    expect(find.text('Invitation sent to Lena.'), findsOneWidget);
    expect(g2.invitations!.open.any((i) => i.person == 'Lena'), isTrue);
    final d = a.directWithPub(lena)!;
    expect(a.messages(d).where((m) => !m.deleted).length, 1, reason: 'the invitation is in the chat with Lena');
    // taking it back
    await tester.tap(find.text('Withdraw'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();
    expect(find.text('Invitation to Lena withdrawn.'), findsOneWidget);
    expect(g2.invitations!.open.any((i) => i.person == 'Lena'), isFalse);
    expect(a.messages(d).where((m) => !m.deleted), isEmpty);
    expect(b2.ps.map((p) => p.name), ['Pia', 'Lena'], reason: 'she stays on this bill');

    // declining: only on this bill, nothing is sent
    final b3 = _bill(group: 'Hütte', people: ['Pia']);
    await _pump(tester, b3, store: store, collab: a);
    await tester.tap(find.byKey(const ValueKey('add-person')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-Lena')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only on this receipt'));
    await tester.pumpAndSettle();
    expect(b3.ps.map((p) => p.name), ['Pia', 'Lena']);
    expect(g2.invitations!.open.any((i) => i.person == 'Lena'), isFalse);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('Posten wischen: rechts = für alle / niemand (die Zeile federt zurück und bleibt), links = löschen mit Rückgängig', (tester) async {
    final b = _bill(people: ['Anna', 'Jo', 'Mia']);
    await _pump(tester, b);
    await tester.drag(find.textContaining('Pizza'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(b.its.map((i) => i.name), ['Pizza', 'Wine'], reason: 'the row is still there');
    expect(b.its[0].shares.keys.toSet(), {0, 1, 2}, reason: 'everyone has it');
    expect(find.textContaining('Pizza'), findsOneWidget);
    await tester.drag(find.textContaining('Pizza'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(b.its[0].shares, isEmpty, reason: 'swiping again: nobody');
    // delete to the left, undo
    await tester.drag(find.text('Wine'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(b.its.map((i) => i.name), ['Pizza']);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(b.its.map((i) => i.name), ['Pizza', 'Wine']);
    // many swipes in a row do not break anything
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.text('Wine'), Offset(i.isEven ? 500 : 80, 0));
      await tester.pumpAndSettle(); // the row springs back before the next swipe
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Wischen ohne Personen: freundlicher Hinweis statt Fehler', (tester) async {
    final b = _bill();
    await _pump(tester, b);
    await tester.drag(find.textContaining('Pizza'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Add at least two people.'), findsOneWidget);
    expect(b.its[0].shares, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Person lang drücken: hat bezahlt, alle offenen Posten, vom Bon entfernen', (tester) async {
    final b = _bill(people: ['Anna', 'Jo']);
    await _pump(tester, b);
    await tester.longPress(find.byKey(const ValueKey('person-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paid'));
    await tester.pumpAndSettle();
    expect(b.payer, 1);
    await tester.longPress(find.byKey(const ValueKey('person-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All open items'));
    await tester.pumpAndSettle();
    expect(b.its.every((i) => (i.shares[0] ?? 0) > 0), isTrue);
    await tester.longPress(find.byKey(const ValueKey('person-0')));
    await tester.pumpAndSettle();
    expect(find.text('All open items'), findsOneWidget);
    await tester.tap(find.text('Remove from receipt'));
    await tester.pumpAndSettle();
    expect(b.ps.map((p) => p.name), ['Jo']);
    expect(b.payer, 0, reason: 'Jo moved up and is still the payer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sehr langer Postenname: läuft als Laufschrift, Antippen öffnet das Blatt, Wischen nach rechts ordnet allen zu', (tester) async {
    final b = _bill(people: ['Anna', 'Jo']);
    b.its[0].name = 'Gin Tonico Martini Bianco mit Zitrone, Eis, Rosmarin und einem sehr langen Namen der nicht passt';
    await _pump(tester, b);
    expect(find.byType(ShaderMask), findsWidgets, reason: 'the long name fades out at the edge instead of ending in „…“');
    final longName = find.descendant(of: find.byType(ItemTitle).first, matching: find.byType(MarqueeText)).last; // the receipt name under the plain name
    await tester.tap(longName); // the visible part, where a finger would hit
    await tester.pumpAndSettle();
    expect(find.text('Who had this?'), findsOneWidget, reason: 'a tap on the long name opens the sheet');
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    await tester.drag(longName, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(b.its[0].shares.keys.toSet(), {0, 1}, reason: 'the swipe on the long name reaches the row');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 12)); // the marquee plays and rests without errors
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ohne Foto (Bon aus der Gruppe, Browser): ⋮-Menü zeigt alle Einträge, nicht Mögliches mit Grund; Bon-Knopf da', (tester) async {
    // Nutzer 06.11.: im Browser zeigte das ⋮-Menü nur einen Eintrag oder gar keinen, der Knopf für Scan/Original/Digital fehlte
    final b = _bill(people: ['Anna']);
    await _pump(tester, b);
    expect(find.byTooltip('Receipt'), findsOneWidget, reason: 'digitaler Bon geht immer');
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    for (final t in ['Read receipt again', 'Split everything evenly', 'Receipt snippets under the items', 'Assign on the original']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('The photo is only on the device that scanned the receipt.'), findsNWidgets(3));
    expect(find.text('Add two people and items first.'), findsOneWidget);
    // disabled entries do nothing (the menu stays; close it by tapping outside)
    await tester.tap(find.text('Read receipt again'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    Navigator.of(tester.element(find.text('Read receipt again'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Read receipt again'), findsNothing);
    // the receipt button opens the digital receipt and says why scan and original are missing
    await tester.tap(find.byTooltip('Receipt'));
    await tester.pumpAndSettle();
    expect(find.text('The photo is only on the device that scanned the receipt.'), findsOneWidget);
    expect(find.text('Digital'), findsOneWidget);
  });

  testWidgets('Vorhängeschloss ohne geteilte Gruppe: Menü und Posten zeigen den Grund statt zu sperren', (tester) async {
    final b = _bill(people: ['Anna', 'Jo']);
    await _pump(tester, b);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Lock bill'), findsOneWidget);
    expect(find.text('Only works in a shared group.'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // closes the menu
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pizza'));
    await tester.pumpAndSettle();
    expect(find.text('Lock item'), findsOneWidget);
    expect(find.text('Only works in a shared group.'), findsOneWidget);
    expect(b.lockBy, isNull);
    expect(b.its[0].lockBy, isNull);
  });

  testWidgets('Fremd gesperrte Rechnung: Banner da, Posten lassen sich nicht öffnen; eigene Sperre: Banner „Du hast gesperrt“', (tester) async {
    late CollabService c;
    await tester.runAsync(() async {
      c = CollabService(store: BillStore.memory()..me = 'Pia', vault: MemoryVault(), relayFactory: (_) => MemoryRelay(MemoryRelayHub()));
      await c.init();
      await c.setName('Pia');
    });
    final b = _bill(people: ['Anna', 'Jo'])..lockBy = 'ff' * 32;
    await _pump(tester, b, collab: c);
    expect(find.textContaining('Locked by'), findsOneWidget);
    await tester.tap(find.textContaining('Pizza'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Lock item'), findsNothing, reason: 'Posten-Blatt öffnet nicht');
    b.lockBy = c.identity!.pub;
    await _pump(tester, b, collab: c);
    expect(find.textContaining('You locked this bill'), findsOneWidget);
    await tester.tap(find.textContaining('Pizza'));
    await tester.pumpAndSettle();
    expect(find.text('Lock item'), findsOneWidget, reason: 'der Sperrer darf weiter ändern');
  });
}
