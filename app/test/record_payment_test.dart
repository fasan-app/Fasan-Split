// SPDX-License-Identifier: MPL-2.0
// „bezahlt eintragen“ for one settlement payment (Kosten 2, Beschluss 06.11.): the balance moves by exactly that amount. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/groups.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Bill _dinner() => Bill(id: 'd', created: DateTime(2026, 11, 6), total: 2400, people: [Person('Pia', 0), Person('Lena', 1)], payer: 0, items: [
      BillItem(name: 'Pizza', amount: 1400, shares: {0: 1}),
      BillItem(name: 'Wein', amount: 1000, shares: {1: 1}),
    ])
      ..group = 'Beispielstadt'
      ..done = true;

void main() {
  test('Ausgleich eintragen: Saldo danach null, Teilbetrag bleibt als Rest', () {
    final store = BillStore.memory([_dinner()]);
    expect(store.groupBalance('Beispielstadt'), {'Pia': 1000, 'Lena': -1000});
    final part = store.recordPayment('Beispielstadt', 'Lena', 'Pia', 400, purpose: 'Ausgleich', item: 'Ausgleichszahlung');
    expect(store.groupBalance('Beispielstadt'), {'Pia': 600, 'Lena': -600});
    store.recordPayment('Beispielstadt', 'Lena', 'Pia', 600, purpose: 'Ausgleich', item: 'Ausgleichszahlung');
    expect(store.groupBalance('Beispielstadt').values.every((v) => v == 0), isTrue);
    // a settlement payment is no spending: not in the per-person spending (Freunde) and not a receipt of its own there
    final lena = store.friends.firstWhere((f) => f.name == 'Lena');
    expect((lena.bills, lena.sum), (1, 1000));
    expect(part.isTransfer, isTrue);
    store.remove(part); // undo of one booking
    expect(store.groupBalance('Beispielstadt'), {'Pia': 400, 'Lena': -400});
  });

  testWidgets('Gruppe: Häkchen an der Ausgleichszeile, bestätigen, Zeile verschwindet', (tester) async {
    final store = BillStore.memory([_dinner()]);
    final svc = CollabService(store: store, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(MemoryRelayHub()));
    addTearDown(svc.dispose);
    await tester.pumpWidget(CollabScope(
      service: svc,
      child: StoreScope(
        store: store,
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: const [Locale('de'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(body: SingleChildScrollView(child: GroupPeople(name: 'Beispielstadt'))),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('Lena zahlt Pia'), findsOneWidget);
    await tester.tap(find.text('Als bezahlt eintragen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wie viel hat Lena an Pia gezahlt? Offen sind 10,00'), findsOneWidget);
    // a part only: 4,00 now
    await tester.enterText(find.byType(TextField), '4,00');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Bezahlt'));
    await tester.pumpAndSettle();
    expect(store.groupBalance('Beispielstadt'), {'Pia': 600, 'Lena': -600});
    expect(find.textContaining('Lena zahlt Pia 6,00'), findsOneWidget, reason: 'Rest bleibt offen, Bereich bleibt offen');
    // the rest, more than open is refused
    await tester.tap(find.text('Als bezahlt eintragen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '7,00');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Bezahlt')).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '6,00');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Bezahlt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lena zahlt Pia'), findsNothing);
    expect(store.groupBalance('Beispielstadt').values.every((v) => v == 0), isTrue);
  });
}
