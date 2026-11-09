// SPDX-License-Identifier: MPL-2.0
// Fehler 08.11. 11:06: Posten wurden umbenannt und Mengen auf 1 gesetzt, nachdem die App um 10:56 gestartet wurde.
// Prüft: ein Telefon mit altem lokalem Stand startet neu, während das Dokument schon neuer ist – der neuere Stand muss bleiben.
// Test relay only. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('Neustart mit altem lokalem Stand überschreibt neuere Änderungen nicht', () async {
    SharedPreferences.setMockInitialValues({});
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    storeA.addGroup('G');
    storeA.upsert(Bill(id: 'b1', created: DateTime(2026, 11, 8), purpose: 'Das Beispiel', total: 960, people: [Person('Pia', 0)], items: [
      BillItem(name: 'Coca Cola', amount: 960, qty: 3, shares: {0: 1}),
    ])
      ..group = 'G');
    final g = await a.shareLocalGroup('G');
    final link = g.invitations!.create().link;
    await settle();

    final storeB = BillStore.memory()..me = 'Rosa';
    final vaultB = MemoryVault();
    final prefsB = await SharedPreferences.getInstance();
    var b = CollabService(store: storeB, vault: vaultB, prefs: prefsB, relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    expect(await b.join(link, 'Rosa'), isNull);
    for (var i = 0; i < 20 && storeB.bills.isEmpty; i++) {
      await settle(300);
    }
    expect(storeB.bills.single.its.single.qty, 3);
    b.saveDocs();
    b.dispose();

    // A changes while B is closed
    final ia = storeA.bills.single.its.single;
    ia
      ..name = 'Coca Cola 0,33'
      ..qty = 4;
    storeA.upsert(storeA.bills.single);
    await settle();

    // B starts again with what it had (old bill in the store, old documents from the disk)
    b = CollabService(store: storeB, vault: vaultB, prefs: prefsB, relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await settle(2500);
    final ib = storeB.bills.single.its.single, ia2 = storeA.bills.single.its.single;
    expect([ib.name, ib.qty], ['Coca Cola 0,33', 4], reason: 'B hat den neueren Stand übernommen');
    expect([ia2.name, ia2.qty], ['Coca Cola 0,33', 4], reason: 'A wurde nicht überschrieben');
    a.dispose();
    b.dispose();
  });
}
