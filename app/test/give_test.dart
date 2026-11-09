// SPDX-License-Identifier: MPL-2.0
// Zwischendurch bezahlen und Geld leihen (Nutzer 07.11.): ein Eintrag zwischen zwei Personen, der Stand ändert sich sofort. MPL-2.0
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/groups.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Leihgabe eintragen: Geber bekommt Plus, Empfänger Minus; Rückgängig nimmt sie zurück', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory()..onboarded = true;
    store.addGroup('WG');
    store.addGroupMember('WG', 'Anna');
    store.addGroupMember('WG', 'Ben');
    final q = ScanQueue(store, recognize: (_) => const Stream.empty());
    final ctl = FasanController(settings: FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ctl, home: GroupScreen(name: 'WG', queue: q)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.group_outlined).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Zahlung oder Leihgabe eintragen'));
    await tester.tap(find.text('Zahlung oder Leihgabe eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Geliehen'));
    await tester.pump();
    await tester.tap(find.text('Wer hat das Geld gegeben?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anna').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('An wen?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ben').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '20'); // Betrag (das Betreff-Feld folgt danach)
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(store.groupBalance('WG'), {'Anna': 2000, 'Ben': -2000});
    final loan = store.bills.single;
    expect(loan.isTransfer, isTrue);
    expect(loan.purpose, 'Leihgabe Anna → Ben');
    expect(find.textContaining('Anna hat Ben'), findsOneWidget, reason: 'Hinweis nennt, wer wem geliehen hat');
    // undo
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(store.groupBalance('WG').values.every((v) => v == 0), isTrue);
  });

  testWidgets('Zahlung mit Betreff: der Betreff wird der Name des Eintrags (Nutzer 09.11.)', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory()..onboarded = true;
    store.addGroup('WG');
    store.addGroupMember('WG', 'Anna');
    store.addGroupMember('WG', 'Ben');
    final q = ScanQueue(store, recognize: (_) => const Stream.empty());
    final ctl = FasanController(settings: FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ctl, home: GroupScreen(name: 'WG', queue: q)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.group_outlined).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Zahlung oder Leihgabe eintragen'));
    await tester.tap(find.text('Zahlung oder Leihgabe eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Geliehen'));
    await tester.pump();
    await tester.tap(find.text('Wer hat das Geld gegeben?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anna').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('An wen?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ben').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '20');
    await tester.enterText(find.byKey(const ValueKey('give-subject')), 'Taxi vom Bahnhof');
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(store.groupBalance('WG'), {'Anna': 2000, 'Ben': -2000});
    final loan = store.bills.single;
    expect(loan.isTransfer, isTrue);
    expect(loan.purpose, 'Taxi vom Bahnhof');
  });
}
