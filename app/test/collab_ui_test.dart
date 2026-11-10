// SPDX-License-Identifier: MPL-2.0
// Widget tests of the collaboration screens. They use MemoryRelay only: no public relay is contacted. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/activity.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/collab_ui.dart';
import 'package:fasan_split/ui/item_sheet.dart';
import 'package:fasan_split/ui/my_balance.dart';
import 'package:fasan_split/ui/resume.dart';
import 'package:fasan_split/ui/send_items.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MemoryRelayHub hub;
  late BillStore store;
  late CollabService svc;

  setUp(() {
    hub = MemoryRelayHub();
    store = BillStore.memory();
    svc = CollabService(store: store, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
  });

  tearDown(() => svc.dispose());

  /// The screen inside the same scopes as in main.dart.
  Widget host(Widget child) => CollabScope(service: svc, child: StoreScope(store: store, child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      )));

  testWidgets('Konto zeigt ohne Schlüssel den Hinweis und speichert den Namen', (tester) async {
    await tester.pumpWidget(host(const AccountScreen()));
    expect(find.text('Noch kein Konto. Es entsteht, sobald du eine Gruppe teilst oder beitrittst.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Anna');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(svc.identity?.name, 'Anna');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Profil: Name tippen und Seite schließen – überall gespeichert (Nutzer 04.11.)', (tester) async {
    store.me = 'Pia';
    await tester.pumpWidget(host(Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())), child: const Text('auf'))))));
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    expect(find.text('Pia'), findsWidgets, reason: 'Name aus „Ich bin“ vorbefüllt');
    await tester.enterText(find.byType(TextField).first, 'Pia');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(store.me, 'Pia');
    expect(svc.identity?.name, 'Pia');
  });

  testWidgets('Einladung erzeugt einen Link mit QR-Code, nur für den Admin', (tester) async {
    final g = await svc.createGroup('Hütte');
    await tester.pumpWidget(host(InviteScreen(group: g)));
    // the link is ready at once (Nutzer 04.11.: nothing to press before sharing), validity can be chosen
    expect(find.text('Link teilen'), findsOneWidget);
    expect(find.text('7 Tage'), findsOneWidget);
    expect(g.invitations!.open.length, 1);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.tap(find.text('30 Tage'));
    await tester.pump();
    expect(g.invitations!.open.any((i) => i.expires.isAfter(DateTime.now().add(const Duration(days: 29)))), isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Notiz anlegen, schreiben, und sie steht in der Gruppe', (tester) async {
    final g = await svc.createGroup('Hütte');
    await tester.pumpWidget(host(NotesScreen(group: g)));
    await tester.tap(find.text('Neue Notiz'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Einkauf');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // now in the editor: the second TextField is the body
    await tester.enterText(find.byType(TextField).last, 'Brot und Butter');
    await tester.pump(const Duration(milliseconds: 500)); // debounce of the editor
    final notes = svc.notes(g);
    expect(notes.length, 1);
    expect(notes.first.title, 'Einkauf');
    expect(notes.first.text, contains('Brot und Butter'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Chat: Nachricht senden erscheint in der Liste', (tester) async {
    final g = await svc.createGroup('Hütte');
    await tester.pumpWidget(host(ChatScreen(group: g)));
    expect(find.text('Noch keine Nachricht. Schreib die erste.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hallo');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(find.text('Hallo'), findsOneWidget);
    expect(svc.messages(g).single.text, 'Hallo');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Chat: lang drücken – reagieren, antworten, bearbeiten, löschen', (tester) async {
    final g = await svc.createGroup('Hütte');
    await tester.pumpWidget(host(ChatScreen(group: g)));
    await tester.enterText(find.byType(TextField), 'Pizza heute?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    // react: the same emoji twice takes it back
    await tester.longPress(find.text('Pizza heute?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(svc.messages(g).single.reactions.values, ['👍']);
    expect(find.text('👍 1'), findsOneWidget);

    // reply: quote shows in the bubble and in the input banner
    await tester.longPress(find.text('Pizza heute?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Antworten'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Antwort an'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ja, gern');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    final msgs = svc.messages(g);
    expect(msgs.length, 2);
    expect(msgs[1].reply, msgs[0].id);
    expect(find.textContaining('Antwort an'), findsNothing, reason: 'banner gone after sending');

    // edit the first message
    await tester.longPress(find.text('Pizza heute?').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pizza morgen?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(svc.messages(g)[0].text, 'Pizza morgen?');
    expect(svc.messages(g)[0].edited, isTrue);
    expect(svc.messages(g).length, 2, reason: 'editing does not add a message');

    // delete the reply: marker stays
    await tester.longPress(find.text('Ja, gern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Für alle löschen'));
    await tester.pump();
    expect(svc.messages(g)[1].deleted, isTrue);
    expect(find.text('Nachricht gelöscht'), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Chat: suchen, anpinnen, stumm schalten, jemanden erwähnen', (tester) async {
    final g = await svc.createGroup('Hütte');
    svc.sendMessage(g, 'Pizza heute?');
    svc.sendMessage(g, 'Nudeln morgen');
    await tester.pumpWidget(host(ChatScreen(group: g)));
    await tester.pump();

    // search filters the list
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    final searchField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Suchen');
    await tester.enterText(searchField, 'nudel');
    await tester.pump();
    expect(find.text('Nudeln morgen'), findsOneWidget);
    expect(find.text('Pizza heute?'), findsNothing);
    await tester.enterText(searchField, 'xyz');
    await tester.pump();
    expect(find.text('Nichts gefunden.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search_off_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Pizza heute?'), findsOneWidget);

    // pin: banner on top, the menu offers to unpin
    await tester.longPress(find.text('Pizza heute?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anpinnen'));
    await tester.pumpAndSettle();
    expect(svc.messages(g).where((m) => m.pinned).length, 1);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.textContaining('Du: Pizza heute?'), findsOneWidget);

    // mute toggles per chat
    expect(svc.isMuted(g), isFalse);
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pump();
    expect(svc.isMuted(g), isTrue);
    expect(find.byIcon(Icons.notifications_off_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    // mention: nobody else in the group yet – the sheet says so, nothing breaks
    await tester.tap(find.byIcon(Icons.alternate_email_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Niemand sonst in der Gruppe.'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Posten schicken: Auswahl mit Häkchen, Karte im Chat zeigt nur diese Posten', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final g = await svc.createGroup('Hütte');
    final bill = Bill(id: 'b1', created: DateTime(2026, 11, 2), purpose: 'Abendessen', total: 3000, group: 'Hütte', items: [BillItem(name: 'Pizza', amount: 1400), BillItem(name: 'Salat', amount: 800), BillItem(name: 'Wein', amount: 800)]);
    store.upsert(bill);
    await tester.pumpWidget(host(Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => sendItemsFlow(c, bill, preselected: {0}), child: const Text('senden')))))));
    await tester.tap(find.text('senden'));
    await tester.pumpAndSettle();
    expect(find.text('Schicken (1)'), findsOneWidget, reason: 'der Posten, von dem aus geöffnet wurde, ist angehakt');
    await tester.tap(find.byKey(const ValueKey('send-item-2')));
    await tester.pump();
    expect(find.text('Schicken (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-go')));
    await tester.pumpAndSettle();
    final m = svc.messages(g).single;
    expect(m.bill, 'b1');
    expect(m.items, [0, 2]);
    await tester.pumpWidget(host(ChatScreen(group: g)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Pizza'), findsWidgets);
    expect(find.textContaining('Wein'), findsWidgets);
    expect(find.text('Salat'), findsNothing, reason: 'nicht geschickt');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Neuigkeiten: ein Tipp auf einen Bon führt in den Bon, auf eine Nachricht in den Chat an genau diese Stelle', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final g = await svc.createGroup('Hütte');
    store.upsert(Bill(id: 'b1', created: DateTime(2026, 11, 2), purpose: 'Abendessen', total: 1000, group: 'Hütte', items: [BillItem(name: 'Pizza', amount: 1000)]));
    final mid = svc.sendMessage(g, 'Wer zahlt?')!;
    svc.activity.insert(0, Activity(ActivityKind.billNew, DateTime.now(), g.secret.tag, 'Neuer Bon', ref: 'b1'));
    svc.activity.insert(0, Activity(ActivityKind.message, DateTime.now(), g.secret.tag, 'Nachricht', ref: mid));
    await tester.pumpWidget(host(const ActivityScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Neuer Bon'));
    await tester.pumpAndSettle();
    expect(find.byType(ResumeFlow), findsOneWidget, reason: 'der Bon selbst, nicht nur die Gruppe');
    Navigator.of(tester.element(find.byType(ResumeFlow))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nachricht'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.focusMessage, mid);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('vllt: Vorschlag im Posten-Blatt übernehmen oder ablehnen, erst dann zählt er', (tester) async {
    final b = Bill(id: 'v', created: DateTime(2026, 11, 10), total: 2000, people: [Person('Ana', 0), Person('Ben', 1), Person('Cleo', 2)], items: [
      BillItem(name: 'Pizza', amount: 2000, shares: {0: 1}, maybe: {1: 'x', 2: 'y'}),
    ]);
    tester.view.physicalSize = const Size(1080, 2400); // 360 dp wide like a phone
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(Builder(builder: (c) => Scaffold(body: Center(child: TextButton(
        onPressed: () => showItemSheet(c, b, b.its.first, changed: () {}, onDelete: () {}), child: const Text('auf')))))));
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('maybe-accept-1')), findsOneWidget);
    expect(b.perPerson()[1] ?? 0, 0);
    await tester.tap(find.byKey(const ValueKey('maybe-accept-1')));
    await tester.pumpAndSettle();
    expect(b.its.first.maybe.keys, [2]);
    expect(b.perPerson()[1], greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('maybe-decline-2')));
    await tester.pumpAndSettle();
    expect(b.its.first.maybe, isEmpty);
    expect(b.its.first.shares[2] ?? 0, 0);
  });

  testWidgets('Mitglied: Stufe „Nicht erlaubt“ im Menü wählen wirkt und steht in der Mitgliederliste', (tester) async {
    SharedPreferences.setMockInitialValues({});
    svc.dispose();
    svc = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub)); // the level is stored in the preferences
    await svc.init();
    final g = await svc.createGroup('WG');
    final other = 'ab' * 32;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => memberActions(c, g, other), child: const Text('auf')))))));
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-trust')));
    await tester.pumpAndSettle();
    expect(find.text('Trägt direkt ein'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trust-block')));
    await tester.pumpAndSettle();
    expect(svc.trustOf(other), TrustLevel.block);
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    expect(find.text('Nicht erlaubt'), findsOneWidget, reason: 'die gewählte Stufe steht im Menü');
  });
}
