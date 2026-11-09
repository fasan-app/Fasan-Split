// SPDX-License-Identifier: MPL-2.0
// Vorhängeschloss zwischen zwei Telefonen (Nutzer 07.11.): A (Gründerin) sperrt einen Posten und danach die Rechnung; B kann nichts
// davon ändern, der Rest bleibt offen, Notizen gehen weiter; nach dem Aufheben geht wieder alles. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/group.dart' show GroupSession;
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle([int ms = 1400]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('Zwei Telefone: gesperrter Posten und gesperrte Rechnung bleiben, wie sie sind', () async {
    final hub = MemoryRelayHub();
    Relay factory(List<String> urls) => MemoryRelay(hub);
    final storeA = BillStore.memory(), storeB = BillStore.memory();
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: factory);
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: factory);
    await a.init();
    await b.init();
    await a.setName('Pia');
    await b.setName('Ole');
    final ga = await a.createGroup('Beispielstadt');
    final bill = Bill(id: 'bill-1', created: DateTime(2026, 11, 7), total: 1380, purpose: 'Mittag', people: [Person('Pia', 0), Person('Ole', 1)], items: [
      BillItem(name: 'Cola', amount: 960, qty: 3, shares: {0: 1, 1: 1}),
      BillItem(name: 'Wasser', amount: 420, shares: {0: 1}),
    ])
      ..payer = 0
      ..group = 'Beispielstadt';
    storeA.upsert(bill);
    final invite = ga.invitations!.create(auto: false);
    expect(await b.join(invite.link, 'Ole'), isNull);
    await settle(200);
    await a.approve(ga, ga.invitations!.pending.values.first);
    await settle();
    final billB = storeB.bills.single;
    expect(a.canLock(bill), isTrue);
    expect(b.canLock(billB), isTrue);

    // A locks the Cola item
    expect(a.toggleItemLock(bill, bill.its[0]), isTrue);
    await settle();
    expect(billB.its[0].lockBy, isNotNull, reason: 'B sieht das Schloss');
    expect(b.lockedAgainstMe(billB, billB.its[0].lockBy), isTrue);
    expect(b.toggleItemLock(billB, billB.its[0]), isFalse, reason: 'B kann fremde Sperre nicht aufheben');

    // B changes the locked item and the open one
    billB.its[0].shares = {1: 1};
    billB.its[1].shares = {1: 1};
    storeB.upsert(billB);
    await settle();
    expect(bill.its[0].shares, {0: 1, 1: 1}, reason: 'A: gesperrter Posten unverändert');
    expect(bill.its[1].shares, {1: 1}, reason: 'A: offener Posten geändert');
    expect(storeB.bills.single.its[0].shares, {0: 1, 1: 1}, reason: 'B: gesperrter Posten kommt zurück');

    // A locks the whole bill: B cannot change the total
    expect(a.toggleBillLock(bill), isTrue);
    await settle();
    expect(billB.lockBy, isNotNull);
    billB.purpose = 'Abendessen';
    storeB.upsert(billB);
    await settle();
    expect(bill.purpose, 'Mittag');
    expect(storeB.bills.single.purpose, 'Mittag', reason: 'B: kommt zurück');

    // a changed app of B ignores the rule and sends the change anyway: A's phone refuses it (incoming check)
    final gb = b.groups.values.first;
    final docB = gb.session.doc(GroupSession.bill('bill-1'));
    docB.set('meta/purpose', 'Heimlich');
    gb.session.touch(GroupSession.bill('bill-1'));
    await settle();
    expect(bill.purpose, 'Mittag', reason: 'A nimmt die Änderung nicht an');

    // A unlocks both: B can change again
    a.toggleBillLock(bill);
    a.toggleItemLock(bill, bill.its[0]);
    await settle();
    expect(billB.lockBy, isNull);
    storeB.bills.single.purpose = 'Abendessen';
    storeB.upsert(storeB.bills.single);
    await settle();
    expect(bill.purpose, 'Abendessen');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
