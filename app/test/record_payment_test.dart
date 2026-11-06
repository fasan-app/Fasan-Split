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

Bill _dinner() => Bill(id: 'd', created: DateTime(2026, 11, 6), total: 2400, people: [Person('Chris', 0), Person('Angi', 1)], payer: 0, items: [
      BillItem(name: 'Pizza', amount: 1400, shares: {0: 1}),
      BillItem(name: 'Wein', amount: 1000, shares: {1: 1}),
    ])
      ..group = 'Lissabon'
      ..done = true;

void main() {
  test('Ausgleich eintragen: Saldo danach null, Teilbetrag bleibt als Rest', () {
    final store = BillStore.memory([_dinner()]);
    expect(store.groupBalance('Lissabon'), {'Chris': 1000, 'Angi': -1000});
    final part = store.recordPayment('Lissabon', 'Angi', 'Chris', 400, purpose: 'Ausgleich', item: 'Ausgleichszahlung');
    expect(store.groupBalance('Lissabon'), {'Chris': 600, 'Angi': -600});
    store.recordPayment('Lissabon', 'Angi', 'Chris', 600, purpose: 'Ausgleich', item: 'Ausgleichszahlung');
    expect(store.groupBalance('Lissabon').values.every((v) => v == 0), isTrue);
    // a settlement payment is no spending: not in the per-person spending (Freunde) and not a receipt of its own there
    final angi = store.friends.firstWhere((f) => f.name == 'Angi');
    expect((angi.bills, angi.sum), (1, 1000));
    expect(part.isTransfer, isTrue);
    store.remove(part); // undo of one booking
    expect(store.groupBalance('Lissabon'), {'Chris': 400, 'Angi': -400});
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
          home: const Scaffold(body: SingleChildScrollView(child: GroupPeople(name: 'Lissabon'))),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('Angi zahlt Chris'), findsOneWidget);
    await tester.tap(find.text('Als bezahlt eintragen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hat Angi an Chris 10,00'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Bezahlt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Angi zahlt Chris'), findsNothing);
    expect(store.groupBalance('Lissabon').values.every((v) => v == 0), isTrue);
  });
}
