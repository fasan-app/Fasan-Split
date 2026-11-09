// SPDX-License-Identifier: MPL-2.0
// Nutzer 08.11.: Beim Öffnen eines Bons sieht man nicht, was von wem geändert wurde. Prüft: Änderungen anderer zählen als „neu“, bis
// man den Bon geöffnet hat; der Zähler an der Vorschau und die Liste im Bon kommen aus dem Änderungsprotokoll. Test relay only. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('Änderungen anderer: Zähler und Liste, nach dem Öffnen weg, spätere Änderung wieder da', () async {
    SharedPreferences.setMockInitialValues({});
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    storeA.addGroup('G');
    storeA.upsert(Bill(id: 'b1', created: DateTime(2026, 11, 8), purpose: 'Café Muster', total: 1920, people: [Person('Pia', 0), Person('Rosa', 1)], items: [
      BillItem(name: 'Cola', amount: 960, qty: 2, shares: {0: 1}),
    ])
      ..group = 'G');
    final g = await a.shareLocalGroup('G');
    final link = g.invitations!.create().link;
    await settle();
    final storeB = BillStore.memory()..me = 'Rosa';
    final prefsB = await SharedPreferences.getInstance();
    final b = CollabService(store: storeB, vault: MemoryVault(), prefs: prefsB, relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    expect(await b.join(link, 'Rosa'), isNull);
    for (var i = 0; i < 20 && storeB.bills.isEmpty; i++) {
      await settle(300);
    }
    b.billSeen('b1'); // B opens the bill: everything so far is seen
    await settle(8600); // the first 8 seconds after joining are quiet (no marks for the initial sync)

    storeA.bills.single.its.single.qty = 3;
    storeA.upsert(storeA.bills.single);
    await settle(2800); // publish delay + the 800 ms the change log waits for more entries
    expect(b.changedBills, contains('b1'));
    expect(b.unseenCount('b1'), greaterThan(0), reason: 'Zähler an der Vorschau');
    expect(b.unseenChanges('b1').every((r) => r.who == 'Pia'), isTrue, reason: 'wer');
    expect(a.unseenCount('b1'), 0, reason: 'eigene Änderungen zählen nicht');

    b.billSeen('b1');
    // while the bill is open the list stays (it is what the banner shows) ...
    expect(b.unseenChanges('b1'), isNotEmpty);
    // ... and the next opening, with nothing new in between, starts clean
    await settle(50);
    b.billSeen('b1');
    expect(b.unseenChanges('b1'), isEmpty);
    a.dispose();
    b.dispose();
  });
}
