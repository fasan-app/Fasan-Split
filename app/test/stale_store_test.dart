// SPDX-License-Identifier: MPL-2.0
// Fehler 08.11. 10:56 und 11:58: Beim Start schrieb ein Gerät seine ÄLTERE lokale Rechnung als „eigene Änderung“ mit neuerem Zähler in
// den gemeinsamen Zettel zurück: Posten wieder roh benannt, Mengen 1, Personen weg. Prüft: Der Zettel auf dem Gerät ist neuer als
// die lokal gespeicherte Rechnung (Speicher nicht nachgekommen, Browser-Speicher voll, Absturz) – nach dem Start gilt der Zettel.
// Test relay only. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

Bill _bill() => Bill(id: 'b1', created: DateTime(2026, 11, 8), purpose: 'Café Muster', total: 960, people: [Person('Pia', 0), Person('Tilda', 1)], items: [
      BillItem(name: 'z Coca cola 23 e', amount: 960, qty: 1, shares: {0: 1}),
    ])
      ..group = 'G';

void main() {
  test('Lokal gespeicherte Rechnung älter als der Zettel: Neustart überschreibt den Zettel nicht', () async {
    SharedPreferences.setMockInitialValues({});
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    storeA.addGroup('G');
    storeA.upsert(_bill());
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
    // B keeps the OLD bill as its local copy (what its store held)
    final old = Bill.fromJson(storeB.bills.single.toJson());
    // the corrected state arrives and is saved as document on B's disk, but the store of B does not keep up
    final ia = storeA.bills.single.its.single;
    ia
      ..name = 'Coca Cola'
      ..qty = 2;
    storeA.upsert(storeA.bills.single);
    await settle();
    expect(storeB.bills.single.its.single.qty, 2, reason: 'B hat die Änderung bekommen');
    b.saveDocs();
    b.dispose();

    // B starts again: documents from the disk are new, the local bill from the store is old
    final storeB2 = BillStore.memory([old])..me = 'Rosa';
    b = CollabService(store: storeB2, vault: vaultB, prefs: prefsB, relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await settle(2500);
    // any later change in the store (opening a bill, a thumbnail, a photo) lets the phone compare ALL its bills with the documents
    storeB2.upsert(storeB2.bills.single, record: false);
    await settle(1500);
    final ib = storeB2.bills.single.its.single, ia2 = storeA.bills.single.its.single;
    expect([ia2.name, ia2.qty], ['Coca Cola', 2], reason: 'A: der neuere Stand wurde nicht überschrieben');
    expect([ib.name, ib.qty], ['Coca Cola', 2], reason: 'B: übernimmt den Stand des Zettels');
    a.dispose();
    b.dispose();
  });
}
