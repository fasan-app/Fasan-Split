// SPDX-License-Identifier: MPL-2.0
// Fasan Split – open invitation links (group.dart step 4b, Nutzer 04.11.: „muss sofort funktionieren“). Test relay only.
// The link carries the group key and a ticket: the person is in at once, even with every admin offline. Everyone checks
// self entries (ticket from an admin, own author, no admin flag); withdrawing links rotates the group key. MPL-2.0
import 'dart:convert';

import 'package:fasan_split/collab/crypto.dart';
import 'package:fasan_split/collab/group.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

/// One phone. Only the admin keeps preferences (the test has one shared SharedPreferences; separate phones must not
/// see each other's stored documents).
Future<(CollabService, BillStore)> device(MemoryRelayHub hub, String name, {MemoryVault? vault, BillStore? store0}) async {
  final store = store0 ?? (BillStore.memory()..me = name);
  final s = CollabService(store: store, vault: vault ?? MemoryVault(), prefs: name == 'Pia' ? await SharedPreferences.getInstance() : null, relayFactory: (_) => MemoryRelay(hub));
  await s.init();
  await s.setName(name);
  return (s, store);
}

Bill pizza() => Bill(id: 'r1', created: DateTime(2026, 11, 4), purpose: 'Pizza', total: 1200, people: [Person('Pia', 0), Person('Lena', 1), Person('Bo', 2)], items: [
      BillItem(name: 'Pizza', amount: 1200, shares: {0: 1, 1: 1, 2: 1}),
    ])
      ..group = 'Beispielstadt';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Offener Link: zwei Leute treten bei, während der Admin aus ist, und bearbeiten gemeinsam', () async {
    final hub = MemoryRelayHub();
    final vaultA = MemoryVault();
    var (a, storeA) = await device(hub, 'Pia', vault: vaultA);
    final ga = await a.createGroup('Beispielstadt');
    storeA.upsert(pizza());
    final linkLena = ga.invitations!.create(person: 'Lena').link;
    final linkBo = ga.invitations!.create(person: 'Bo').link;
    expect(Invite.parse(linkLena)!.groupKey, isNotNull);
    await settle(500);
    a.saveDocs();
    a.dispose(); // Pia's phone is off from here on

    final (lena, storeLena) = await device(hub, 'Lena');
    final (bo, storeBo) = await device(hub, 'Bo');
    expect(await lena.join(linkLena, 'Lena'), isNull);
    expect(await bo.join(linkBo, 'Bo'), isNull);
    await settle();
    expect(lena.groups.length, 1);
    expect(bo.groups.length, 1);
    expect(storeLena.bills.map((x) => x.id), contains('r1'));
    final gLena = lena.groups.values.single, gBo = bo.groups.values.single;
    expect(gBo.session.memberKeys, contains(lena.identity!.pub), reason: 'Bo prüft Lenas Ticket und lässt sie schreiben');
    expect(gLena.session.memberOfPerson('Lena'), lena.identity!.pub, reason: 'mit der Person im Link verknüpft');

    // Lena takes the whole pizza, Bo sees it (no admin online)
    final bill = storeLena.bills.firstWhere((x) => x.id == 'r1');
    bill.its.single.shares = {1: 1};
    storeLena.upsert(bill);
    await settle();
    expect(storeBo.bills.firstWhere((x) => x.id == 'r1').its.single.shares, {1: 1});

    // Pia comes back: sees the change, adopts both
    (a, storeA) = await device(hub, 'Pia', vault: vaultA, store0: storeA);
    await settle(2500);
    final ga2 = a.groups.values.single;
    expect(storeA.bills.firstWhere((x) => x.id == 'r1').its.single.shares, {1: 1});
    expect(ga2.session.memberKeys, containsAll([lena.identity!.pub, bo.identity!.pub]));
    expect(ga2.session.isSelfJoined(lena.identity!.pub), isFalse);
    expect(ga2.session.isSelfJoined(bo.identity!.pub), isFalse);
    for (final s in [a, lena, bo]) {
      s.dispose();
    }
  });

  test('Fälschungen zählen nicht: ohne Ticket, mit Admin-Flag, für fremden Schlüssel', () async {
    final hub = MemoryRelayHub();
    final (a, _) = await device(hub, 'Pia');
    final ga = await a.createGroup('Beispielstadt');
    await ga.session.flush();
    final secret = ga.secret;
    final mallory = KeyPair.generate(), other = KeyPair.generate();
    Future<void> publishMembers(Map<String, Object?> value, {String? forPub}) async {
      final doc = LwwDoc(mallory.pub)..set('m/${forPub ?? mallory.pub}', value);
      final d = 'fs:${secret.tag}:${GroupSession.members}';
      await MemoryRelay(hub).publish(NostrEvent.create(mallory, kind: kindData, tags: [['d', d], ['t', secret.tag]], content: aeadSeal(doc.encode(), secret.key, d)));
    }

    await publishMembers({'name': 'M', 'i': 'deadbeefdeadbeefdeadbeefdeadbeef'}); // unknown ticket
    final real = ga.invitations!.create();
    await ga.session.flush();
    await publishMembers({'name': 'M', 'i': real.ticketId, 'admin': true}); // admin flag
    await publishMembers({'name': 'M', 'i': real.ticketId}, forPub: other.pub); // someone else's key
    await publishMembers({'name': 'M', 'i': real.ticketId, 'persons': ['Pia']}); // a person the ticket is not for
    await settle(500);
    expect(ga.session.memberKeys, isNot(contains(mallory.pub)));
    expect(ga.session.memberKeys, isNot(contains(other.pub)));
    expect(ga.session.admins, {a.identity!.pub});
    a.dispose();
    expect(jsonEncode(1), '1');
  });

  test('Links zurückziehen: neuer Gruppenschlüssel, alter Link führt ins Leere, Mitglieder bleiben', () async {
    final hub = MemoryRelayHub();
    final (a, storeA) = await device(hub, 'Pia');
    final ga = await a.createGroup('Beispielstadt');
    final link1 = ga.invitations!.create(person: 'Lena').link;
    await settle(300);
    final (lena, storeLena) = await device(hub, 'Lena');
    expect(await lena.join(link1, 'Lena'), isNull);
    await settle();
    final link2 = ga.invitations!.create().link;
    await settle(300);
    final ng = await a.revokeInvites(ga);
    await settle(1500);
    expect(ng.secret.tag, isNot(ga.secret.tag));
    expect(ng.session.memberKeys, contains(lena.identity!.pub), reason: 'Lena bleibt (vorher übernommen)');
    expect(lena.groups.values.single.secret.tag, ng.secret.tag, reason: 'Lena bekam den neuen Schlüssel');

    // someone with the withdrawn link joins: does not see what comes after
    final (eve, storeEve) = await device(hub, 'Eve');
    await eve.join(link2, 'Eve');
    storeA.upsert(pizza()..group = ng.localName);
    await settle();
    expect(storeLena.bills.map((x) => x.id), contains('r1'));
    expect(storeEve.bills, isEmpty);
    for (final s in [a, lena, eve]) {
      s.dispose();
    }
  });
}
