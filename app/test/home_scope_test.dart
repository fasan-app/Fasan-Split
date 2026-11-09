// SPDX-License-Identifier: MPL-2.0
// Fasan Split – group picker of the start page (Option A, Nutzer 08.11.): Alle | Ohne Gruppe | each group filter the Gruppe tab,
// Rechnungen | Posten switches the view, the tab Abrechnung follows the picked group. All names invented. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/group_header.dart';
import 'package:fasan_split/ui/home.dart';
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
    expect(find.byType(GroupHeader), findsNothing, reason: 'Alle hat keinen Gruppenkopf');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ohne Gruppe'));
    await _settle(tester);
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('Kneipe'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Urlaub'));
    await _settle(tester);
    expect(find.text('Kneipe'), findsOneWidget);
    expect(find.text('Fähre'), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);
    expect(find.text('Bäcker'), findsNothing);
    expect(find.byType(GroupHeader), findsOneWidget);
    expect(find.text('2 Bons'), findsOneWidget);
    expect(find.textContaining('1 ohne Zahler'), findsOneWidget, reason: 'Fähre hat keinen Zahler');
  });

  testWidgets('Rechnungen | Posten: Posten der gewählten Gruppe, nur dort', (tester) async {
    await _app(tester, store);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Urlaub'));
    await _settle(tester);
    await tester.tap(find.text('Posten').first);
    await _settle(tester);
    final names = tester.widgetList<GroupItemRow>(find.byType(GroupItemRow)).map((r) => r.item.name).toSet();
    expect(names, {'Pizza', 'Salat'}, reason: 'nur die Posten der Gruppe Urlaub');
    expect(find.byType(GroupItemRow), findsNWidgets(2));
  });

  testWidgets('Abrechnung folgt der Gruppe: ohne Wahl die Übersicht, mit Wahl Personen der Gruppe', (tester) async {
    await _app(tester, store);
    await tester.tap(find.text('Abrechnung').last);
    await _settle(tester);
    expect(find.text('WG'), findsWidgets);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Urlaub'));
    await _settle(tester);
    expect(find.text('Anna'), findsWidgets, reason: 'Personen der Gruppe Urlaub');
    expect(find.text('Bäcker'), findsNothing);
  });

  testWidgets('Gelöschte Gruppe: der Wähler fällt auf Alle zurück', (tester) async {
    await _app(tester, store);
    // the picker scrolls sideways and builds only the chips on screen
    await tester.dragUntilVisible(find.widgetWithText(ChoiceChip, 'WG'), find.byKey(const ValueKey('group-picker')), const Offset(-100, 0));
    await tester.drag(find.byKey(const ValueKey('group-picker')), const Offset(-150, 0)); // fully on screen, not at the edge
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'WG'));
    await _settle(tester);
    expect(find.text('Taxi'), findsNothing);
    store.deleteGroup('WG');
    await _settle(tester);
    expect(find.text('Taxi'), findsOneWidget, reason: 'zurück auf Alle');
  });
}
