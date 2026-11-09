// SPDX-License-Identifier: MPL-2.0
// Fasan Split – invitations that just work (Nutzer 04.11.: „muss out of the box sofort funktionieren“). Test relay only.
// 1. The inviting phone restarts (update) between sending the link and the request: the request is still read.
// 2. Default invitations let the person in at once, without the admin tapping „Annehmen“.
// 3. A member who asks again (reinstall) gets the welcome again. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1500]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Einladung übersteht Neustart der einladenden App; Person ist sofort drin und sieht die Bons', () async {
    final hub = MemoryRelayHub();
    final prefs = await SharedPreferences.getInstance();
    final vaultA = MemoryVault();
    final storeA = BillStore.memory()..me = 'Pia';
    var a = CollabService(store: storeA, vault: vaultA, prefs: prefs, relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    final ga = await a.createGroup('Beispielstadt');
    storeA.upsert(Bill(id: 'r1', created: DateTime(2026, 11, 4), purpose: 'Pizza', total: 1000, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Pizza', amount: 1000, shares: {0: 1, 1: 1}),
    ])
      ..group = 'Beispielstadt');
    final link = ga.invitations!.create(person: 'Lena').link; // default: let in at once
    await settle(500);
    a.saveDocs();
    a.dispose(); // app updated / closed

    // Lena opens the link while Pia's app is closed
    final storeB = BillStore.memory()..me = 'Lena';
    final b = CollabService(store: storeB, vault: MemoryVault(), prefs: prefs, relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    expect(await b.join(link, 'Lena'), isNull);
    await settle(300);
    // open link (04.11.): in at once, although Pia's phone is off
    expect(b.groups.length, 1, reason: 'offener Link: sofort drin');
    expect(storeB.bills.map((x) => x.id), contains('r1'));
    expect(b.groups.values.single.session.isSelfJoined(b.identity!.pub), isTrue);

    // Pia opens the app again: the stored invitation reads the request and lets Lena in, without tapping
    a = CollabService(store: storeA, vault: vaultA, prefs: prefs, relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await settle(2500);
    expect(b.groups.length, 1, reason: 'Lena ist in der Gruppe');
    expect(storeB.bills.map((x) => x.id), contains('r1'), reason: 'und sieht die Bons');
    final ga2 = a.groups.values.single;
    expect(ga2.session.memberOfPerson('Lena'), b.identity!.pub);
    expect(ga2.session.isSelfJoined(b.identity!.pub), isFalse, reason: 'vom Admin übernommen');

    // Lena edits, Pia sees it
    final billB = storeB.bills.firstWhere((x) => x.id == 'r1');
    billB.its.single.shares = {1: 1};
    storeB.upsert(billB);
    await settle();
    expect(storeA.bills.firstWhere((x) => x.id == 'r1').its.single.shares, {1: 1});
    a.dispose();
    b.dispose();
  });
}
