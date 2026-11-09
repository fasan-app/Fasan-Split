// SPDX-License-Identifier: MPL-2.0
// „Freunde“ lists the people from my bills, but never myself (Bildschirmvergleich 06.11.: the browser user saw themself there). MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/groups.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Freunde zeigt die anderen Personen der Bons, nicht mich selbst', (tester) async {
    final b = Bill(id: 'f', created: DateTime(2026, 11, 6), total: 2400, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Pizza', amount: 1400, shares: {0: 1}),
      BillItem(name: 'Wein', amount: 1000, shares: {1: 1}),
    ])
      ..done = true;
    final store = BillStore.memory([b])..me = 'Lena';
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
          home: const Scaffold(body: FriendsPage()),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pia'), findsOneWidget);
    expect(find.text('Lena'), findsNothing, reason: 'ich selbst gehöre nicht in meine Freundesliste');
  });
}
