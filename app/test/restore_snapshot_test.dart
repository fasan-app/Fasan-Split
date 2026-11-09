// SPDX-License-Identifier: MPL-2.0
// Nutzer 08.11.: Ein Kassenzettel wurde zerschossen (Posten roh benannt, Mengen 1). Prüft: Jedes Mitglied hat seinen letzten Stand
// beim Relay hinterlegt; „Früheren Stand holen“ liest diese Stände (snapshotsOf) und bringt den gewählten zurück – als neue Änderung,
// bei allen sichtbar. Test relay only. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('Zerschossener Zettel: Stand eines anderen Mitglieds kommt zurück', () async {
    SharedPreferences.setMockInitialValues({});
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    storeA.addGroup('G');
    storeA.upsert(Bill(id: 'b1', created: DateTime(2026, 11, 8), purpose: 'Café Muster', total: 1920, people: [Person('Pia', 0), Person('Rosa', 1)], items: [
      BillItem(name: 'Coca Cola', amount: 960, qty: 2, shares: {0: 1, 1: 1}),
      BillItem(name: 'Törtchen', amount: 960, qty: 4, shares: {0: 1}),
    ])
      ..group = 'G');
    final g = await a.shareLocalGroup('G');
    final link = g.invitations!.create().link;
    await settle();

    final storeB = BillStore.memory()..me = 'Rosa';
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    expect(await b.join(link, 'Rosa'), isNull);
    for (var i = 0; i < 20 && storeB.bills.isEmpty; i++) {
      await settle(300);
    }
    // B writes something small, so its good state lies at the relay
    storeB.bills.single.purpose = 'Café Muster Zwei';
    storeB.upsert(storeB.bills.single);
    await settle();

    // the damage, written by A: raw names, quantities 1
    final billA = storeA.bills.single;
    billA.its.first
      ..name = 'z Coca cola 23 e'
      ..qty = 1;
    billA.its.last
      ..name = 'x'
      ..qty = 1;
    storeA.upsert(billA);
    await settle();
    expect(storeB.bills.single.its.first.name, 'z Coca cola 23 e', reason: 'der Schaden ist angekommen');

    final snaps = await a.snapshotsOfBill(storeA.bills.single);
    final byB = snaps.where((s) => a.snapshotWho(storeA.bills.single, s) == 'Rosa');
    expect(byB, isNotEmpty, reason: 'der Stand von B liegt beim Relay');
    final good = byB.first.bill('b1');
    expect([for (final i in good.its) [i.name, i.qty]], [['Coca Cola', 2], ['Törtchen', 4]]);

    a.restoreSnapshot(storeA.bills.single, byB.first);
    await settle();
    for (final s in [storeA, storeB]) {
      expect([for (final i in s.bills.single.its) [i.name, i.qty, i.amount]], [['Coca Cola', 2, 960], ['Törtchen', 4, 960]]);
    }
    a.dispose();
    b.dispose();
  });
}
