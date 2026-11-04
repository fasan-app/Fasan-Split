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
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

/// One phone. Only the admin keeps preferences (the test has one shared SharedPreferences; separate phones must not
/// see each other's stored documents).
Future<(CollabService, BillStore)> device(MemoryRelayHub hub, String name, {MemoryVault? vault, BillStore? store0}) async {
  final store = store0 ?? (BillStore.memory()..me = name);
  final s = CollabService(store: store, vault: vault ?? MemoryVault(), prefs: name == 'Chris' ? await SharedPreferences.getInstance() : null, relayFactory: (_) => MemoryRelay(hub));
  await s.init();
  await s.setName(name);
  return (s, store);
}

Bill pizza() => Bill(id: 'r1', created: DateTime(2026, 11, 4), purpose: 'Pizza', total: 1200, people: [Person('Chris', 0), Person('Angi', 1), Person('Bo', 2)], items: [
      BillItem(name: 'Pizza', amount: 1200, shares: {0: 1, 1: 1, 2: 1}),
    ])
      ..group = 'Lissabon';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Offener Link: zwei Leute treten bei, während der Admin aus ist, und bearbeiten gemeinsam', () async {
    final hub = MemoryRelayHub();
    final vaultA = MemoryVault();
    var (a, storeA) = await device(hub, 'Chris', vault: vaultA);
    final ga = await a.createGroup('Lissabon');
    storeA.upsert(pizza());
    final linkAngi = ga.invitations!.create(person: 'Angi').link;
    final linkBo = ga.invitations!.create(person: 'Bo').link;
    expect(Invite.parse(linkAngi)!.groupKey, isNotNull);
    await settle(500);
    a.saveDocs();
    a.dispose(); // Chris's phone is off from here on

    final (angi, storeAngi) = await device(hub, 'Angi');
    final (bo, storeBo) = await device(hub, 'Bo');
    expect(await angi.join(linkAngi, 'Angi'), isNull);
    expect(await bo.join(linkBo, 'Bo'), isNull);
    await settle();
    expect(angi.groups.length, 1);
    expect(bo.groups.length, 1);
    expect(storeAngi.bills.map((x) => x.id), contains('r1'));
    final gAngi = angi.groups.values.single, gBo = bo.groups.values.single;
    expect(gBo.session.memberKeys, contains(angi.identity!.pub), reason: 'Bo prüft Angis Ticket und lässt sie schreiben');
    expect(gAngi.session.memberOfPerson('Angi'), angi.identity!.pub, reason: 'mit der Person im Link verknüpft');

    // Angi takes the whole pizza, Bo sees it (no admin online)
    final bill = storeAngi.bills.firstWhere((x) => x.id == 'r1');
    bill.its.single.shares = {1: 1};
    storeAngi.upsert(bill);
    await settle();
    expect(storeBo.bills.firstWhere((x) => x.id == 'r1').its.single.shares, {1: 1});

    // Chris comes back: sees the change, adopts both
    (a, storeA) = await device(hub, 'Chris', vault: vaultA, store0: storeA);
    await settle(2500);
    final ga2 = a.groups.values.single;
    expect(storeA.bills.firstWhere((x) => x.id == 'r1').its.single.shares, {1: 1});
    expect(ga2.session.memberKeys, containsAll([angi.identity!.pub, bo.identity!.pub]));
    expect(ga2.session.isSelfJoined(angi.identity!.pub), isFalse);
    expect(ga2.session.isSelfJoined(bo.identity!.pub), isFalse);
    for (final s in [a, angi, bo]) {
      s.dispose();
    }
  });

  test('Fälschungen zählen nicht: ohne Ticket, mit Admin-Flag, für fremden Schlüssel', () async {
    final hub = MemoryRelayHub();
    final (a, _) = await device(hub, 'Chris');
    final ga = await a.createGroup('Lissabon');
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
    await publishMembers({'name': 'M', 'i': real.ticketId, 'persons': ['Chris']}); // a person the ticket is not for
    await settle(500);
    expect(ga.session.memberKeys, isNot(contains(mallory.pub)));
    expect(ga.session.memberKeys, isNot(contains(other.pub)));
    expect(ga.session.admins, {a.identity!.pub});
    a.dispose();
    expect(jsonEncode(1), '1');
  });

  test('Links zurückziehen: neuer Gruppenschlüssel, alter Link führt ins Leere, Mitglieder bleiben', () async {
    final hub = MemoryRelayHub();
    final (a, storeA) = await device(hub, 'Chris');
    final ga = await a.createGroup('Lissabon');
    final link1 = ga.invitations!.create(person: 'Angi').link;
    await settle(300);
    final (angi, storeAngi) = await device(hub, 'Angi');
    expect(await angi.join(link1, 'Angi'), isNull);
    await settle();
    final link2 = ga.invitations!.create().link;
    await settle(300);
    final ng = await a.revokeInvites(ga);
    await settle(1500);
    expect(ng.secret.tag, isNot(ga.secret.tag));
    expect(ng.session.memberKeys, contains(angi.identity!.pub), reason: 'Angi bleibt (vorher übernommen)');
    expect(angi.groups.values.single.secret.tag, ng.secret.tag, reason: 'Angi bekam den neuen Schlüssel');

    // someone with the withdrawn link joins: does not see what comes after
    final (eve, storeEve) = await device(hub, 'Eve');
    await eve.join(link2, 'Eve');
    storeA.upsert(pizza()..group = ng.localName);
    await settle();
    expect(storeAngi.bills.map((x) => x.id), contains('r1'));
    expect(storeEve.bills, isEmpty);
    for (final s in [a, angi, eve]) {
      s.dispose();
    }
  });
}
