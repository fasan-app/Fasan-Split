// SPDX-License-Identifier: MPL-2.0
// Fasan Split – group picker of the start page (Option A, Nutzer 08.11.): Alle | Ohne Gruppe | each group filter the Gruppe tab,
// Rechnungen | Posten switches the view, the tab Abrechnung follows the picked group. All names invented. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/group_header.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_split/ui/my_balance.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _dish = {'a': 'Pizza', 'b': 'Salat', 'c': 'Suppe', 'd': 'Kuchen'};

Bill _bill(String id, String name, {String? group, bool payer = true}) => Bill(
      id: id,
      created: DateTime(2026, 11, 2),
      purpose: name,
      total: 1000,
      people: [Person('Anna', 0), Person('Ben', 1)],
      items: [BillItem(name: _dish[id] ?? 'Gericht', amount: 1000)..shares = {0: 1, 1: 1}],
      done: true,
      group: group,
    )..payer = payer ? 0 : null;

Future<void> _app(WidgetTester tester, BillStore store) async {
  tester.view.physicalSize = const Size(1080, 4000); // tall: the list is lazy, rows below the fold are not built
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  const tilt = MethodChannel('app.fasan.ui/tilt');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, (_) async => null);
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, null));
  final q = ScanQueue(store, recognize: (_) => const Stream.empty());
  await tester.pumpWidget(SplitApp(store: store, ui: FasanController(settings: const FasanSettings(reduceMotion: true)), home: HomeScreen(queue: q)));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the group switch and picks [label] (the group switch replaced the chips, Nutzer 09.11.).
Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('scope-switch')));
  await _settle(tester);
  await tester.tap(find.widgetWithText(ListTile, label));
  await _settle(tester);
}

/// The switch Rechnungen | Posten is on the page itself (Nutzer 09.11.).
Future<void> _showItems(WidgetTester tester) async {
  await tester.tap(find.text('Posten').first);
  await _settle(tester);
}

void main() {
  late BillStore store;
  setUp(() {
    store = BillStore.memory([
      _bill('a', 'Kneipe', group: 'Urlaub'),
      _bill('b', 'Fähre', group: 'Urlaub', payer: false),
      _bill('c', 'Taxi'),
      _bill('d', 'Bäcker', group: 'WG'),
    ])..onboarded = true;
  });

  testWidgets('Gruppenwähler filtert: Alle, Ohne Gruppe, eine Gruppe mit Kopf und Zählzeile', (tester) async {
    await _app(tester, store);
    for (final n in ['Kneipe', 'Fähre', 'Taxi', 'Bäcker']) {
      expect(find.text(n), findsOneWidget, reason: 'Alle zeigt $n');
    }
    expect(find.byType(GroupHeader), findsOneWidget, reason: 'der Rahmen steht auch bei Alle Gruppen');
    expect(find.text('4 Bons'), findsOneWidget);
    await _pick(tester, 'Ohne Gruppe');
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('Kneipe'), findsNothing);
    expect(find.text('1 Bon'), findsOneWidget, reason: 'Rahmen auch bei Ohne Gruppe');
    await _pick(tester, 'Urlaub');
    expect(find.text('Kneipe'), findsOneWidget);
    expect(find.text('Fähre'), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);
    expect(find.text('Bäcker'), findsNothing);
    expect(find.byType(GroupHeader), findsOneWidget);
    expect(find.text('2 Bons'), findsOneWidget);
    expect(find.byKey(const ValueKey('chip-nopayer')), findsOneWidget, reason: 'Fähre hat keinen Zahler');
  });

  testWidgets('Rechnungen | Posten: Posten der gewählten Gruppe, nur dort', (tester) async {
    await _app(tester, store);
    await _pick(tester, 'Urlaub');
    await _showItems(tester);
    final names = tester.widgetList<GroupItemRow>(find.byType(GroupItemRow)).map((r) => r.item.name).toSet();
    expect(names, {'Pizza', 'Salat'}, reason: 'nur die Posten der Gruppe Urlaub');
    expect(find.byType(GroupItemRow), findsNWidgets(2));
  });

  testWidgets('Abrechnung folgt der Gruppe: ohne Wahl die Übersicht, mit Wahl Personen der Gruppe', (tester) async {
    await _app(tester, store);
    await tester.tap(find.text('Abrechnung').last);
    await _settle(tester);
    expect(find.text('WG'), findsWidgets);
    await _pick(tester, 'Urlaub');
    expect(find.text('Anna'), findsWidgets, reason: 'Personen der Gruppe Urlaub');
    expect(find.text('Bäcker'), findsNothing);
  });

  testWidgets('Gelöschte Gruppe: der Wähler fällt auf Alle zurück', (tester) async {
    await _app(tester, store);
    await _pick(tester, 'WG');
    expect(find.text('Taxi'), findsNothing);
    store.deleteGroup('WG');
    await _settle(tester);
    expect(find.text('Taxi'), findsOneWidget, reason: 'zurück auf Alle');
  });

  testWidgets('Gruppenwahl skaliert: ab 8 Gruppen eine Suche im Fenster, sie filtert die Liste', (tester) async {
    final many = BillStore.memory([for (var i = 0; i < 9; i++) _bill(i < 4 ? 'abcd'[i] : 'e$i', 'Bon$i', group: 'Gruppe$i')])..onboarded = true;
    await _app(tester, many);
    await tester.tap(find.byKey(const ValueKey('scope-switch')));
    await _settle(tester);
    expect(find.byType(TextField), findsOneWidget, reason: 'Suchfeld ab 8 Gruppen');
    await tester.enterText(find.byType(TextField), 'Gruppe7');
    await _settle(tester);
    expect(find.widgetWithText(ListTile, 'Gruppe7'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Gruppe3'), findsNothing);
  });

  testWidgets('Filterfenster enthält Sortierung, nur offene Posten und Anzeigen; die Kopfzeile hat kein Sortiersymbol mehr', (tester) async {
    await _app(tester, store);
    expect(find.byIcon(Icons.sort_rounded), findsNothing);
    expect(find.byIcon(Icons.checklist_rounded), findsNothing, reason: 'Auswählen steht im ⋮-Menü');
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await _settle(tester);
    expect(find.text('Filtern und sortieren'), findsOneWidget);
    expect(find.text('Nur offene Posten'), findsOneWidget);
    expect(find.text('Sortieren nach'), findsOneWidget);
  });

  testWidgets('Kopfzeile: Fasan-Symbol links, kein Titeltext, Einstellungen nur im Profil', (tester) async {
    await _app(tester, store);
    expect(find.bySemanticsLabel('Fasan'), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    await tester.tap(find.byType(MyBalanceBadge));
    await _settle(tester);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget, reason: 'Einstellungen oben rechts im Profil');
    expect(find.byKey(const ValueKey('profile-standin')), findsOneWidget, reason: 'Stellvertretung im Profil sichtbar');
  });

  testWidgets('Statusknöpfe filtern Posten an/aus; Rechnungen | Posten ist sichtbar; keine doppelte Gruppenzeile', (tester) async {
    await _app(tester, store);
    await _pick(tester, 'Urlaub');
    expect(find.text('Rechnungen'), findsOneWidget, reason: 'Umschalter sichtbar auf der Seite');
    expect(find.text('2 · 20,00 €'), findsNothing, reason: 'Gruppenname, Anzahl und Summe stehen nur im Rahmen');
    expect(find.byKey(const ValueKey('chip-done')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chip-open')));
    await _settle(tester);
    // Kneipe and Fähre are complete: open filter leaves nothing
    expect(find.text('Kneipe'), findsNothing);
    expect(find.text('Keine Treffer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chip-open'))); // off again
    await tester.tap(find.byKey(const ValueKey('chip-done')));
    await _settle(tester);
    expect(find.text('Kneipe'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chip-nopayer')));
    await _settle(tester);
    expect(find.text('Fähre'), findsOneWidget, reason: 'nur Bons ohne Zahler');
    expect(find.text('Kneipe'), findsNothing);
  });

  testWidgets('Suche: Name, Betrag; leere Suche zeigt wieder alles', (tester) async {
    await _app(tester, store);
    await tester.tap(find.byTooltip('Suche'));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'kneip');
    await _settle(tester);
    expect(find.text('Kneipe'), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('search-field')), '');
    await _settle(tester);
    expect(find.text('Taxi'), findsOneWidget);
  });

  testWidgets('Einstellungen: ruhige Liste, jede Gruppe eine Unterseite', (tester) async {
    await _app(tester, store);
    await tester.tap(find.byType(MyBalanceBadge));
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await _settle(tester);
    for (var i = 0; i < 11; i++) {
      expect(find.byKey(ValueKey('settings-$i')), findsOneWidget, reason: 'Zeile $i');
    }
    await tester.tap(find.byKey(const ValueKey('settings-0')));
    await _settle(tester);
    expect(find.text('Deutsch'), findsOneWidget, reason: 'Sprache liegt auf ihrer Unterseite');
  });
}
