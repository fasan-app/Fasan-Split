// SPDX-License-Identifier: MPL-2.0
// Rights of the group between two phones (Paket 5b, 14.11.): Pia (founder) sets „only admins change bills“; Ole (member) cannot change
// a bill – his change is not written and comes back, and a changed app that writes anyway is refused on Pia's phone; „only admins add
// bills“ keeps Ole's new bill on his phone; only an admin can set the rights; back to „all“, Ole can change again. Invented data. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/group.dart' show GroupSession;
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle([int ms = 1400]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('Zwei Telefone: „Nur Admins ändern Rechnungen“ und „Nur Admins legen an“ wirken; nur Admins setzen das', () async {
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
    final bill = Bill(id: 'bill-1', created: DateTime(2026, 11, 14), total: 1380, purpose: 'Mittag', people: [Person('Pia', 0), Person('Ole', 1)], items: [
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
    final gb = b.groups.values.first;
    final billB = storeB.bills.single;

    expect(() => gb.session.setRight('edit', true), throwsStateError, reason: 'Ole ist kein Admin');
    a.setRight(ga, 'edit', true);
    a.setRight(ga, 'bills', true);
    await settle();
    expect(gb.session.rights, {'edit': 'admins', 'bills': 'admins'}, reason: 'Ole sieht die Regeln');
    expect(b.mayEditBill(billB), isFalse);
    expect(a.mayEditBill(bill), isTrue);

    // Ole changes anyway (the screen would stop him): not written, comes back
    billB.purpose = 'Abendessen';
    storeB.upsert(billB);
    await settle();
    expect(bill.purpose, 'Mittag');
    expect(storeB.bills.single.purpose, 'Mittag', reason: 'kommt bei Ole zurück');

    // a changed app writes into the document directly: Pia's phone drops it
    gb.session.doc(GroupSession.bill('bill-1')).set('meta/purpose', 'Heimlich');
    gb.session.touch(GroupSession.bill('bill-1'));
    await settle();
    expect(bill.purpose, 'Mittag', reason: 'Pia nimmt es nicht an');

    // Ole adds a bill to the group: stays on his phone only
    storeB.upsert(Bill(id: 'bill-2', created: DateTime(2026, 11, 14), total: 500, purpose: 'Eis', people: [Person('Ole', 0)], items: [BillItem(name: 'Eis', amount: 500, shares: {0: 1})])..group = gb.localName);
    await settle();
    expect(storeA.bills.where((x) => x.id == 'bill-2'), isEmpty, reason: '„Nur Admins legen an“');

    // back to everyone
    a.setRight(ga, 'edit', false);
    await settle();
    expect(b.mayEditBill(storeB.bills.firstWhere((x) => x.id == 'bill-1')), isTrue);
    final again = storeB.bills.firstWhere((x) => x.id == 'bill-1')..purpose = 'Abendessen';
    storeB.upsert(again);
    await settle();
    expect(bill.purpose, 'Abendessen', reason: 'wieder erlaubt');
    a.dispose();
    b.dispose();
  });
}
