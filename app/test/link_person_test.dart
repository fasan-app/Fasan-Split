// Fasan Split – person from a bill invited and linked to the member who joins (Nutzer 03.11.), link and unlink,
// on two phones with the test relay (MemoryRelay; no public relays). MPL-2.0
import 'package:fasan_split/collab/group.dart';
import 'package:fasan_split/collab/crypto.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle([int ms = 1400]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('Einladung trägt die Person, alter Link ohne Person geht weiter', () {
    final inv = Invite(tag: 't', secret: randomBytes(32), adminPub: 'ab' * 32, relays: const [], expires: DateTime(2030), name: 'WG', person: 'Mia');
    expect(Invite.parse(inv.link)?.person, 'Mia');
    final old = Invite(tag: 't', secret: randomBytes(32), adminPub: 'ab' * 32, relays: const [], expires: DateTime(2030), name: 'WG');
    expect(Invite.parse(old.link)?.person, isNull);
  });

  test('Person aus dem Bon einladen: neues Mitglied ist mit ihr verknüpft, beide Telefone sehen es; lösen und neu verknüpfen', () async {
    final hub = MemoryRelayHub();
    Relay factory(List<String> urls) => MemoryRelay(hub);
    final storeA = BillStore.memory(), storeB = BillStore.memory();
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: factory);
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: factory);
    await a.init();
    await b.init();
    await a.setName('Chris');
    final ga = await a.createGroup('WG');
    storeA.upsert(Bill(id: 'b1', created: DateTime(2026, 11, 3), total: 1000, purpose: 'Pizza', people: [Person('Chris', 0), Person('Mia', 1)], items: [
      BillItem(name: 'Pizza', amount: 1000, shares: {0: 1, 1: 1}),
    ])
      ..payer = 0
      ..group = 'WG'
      ..done = true);

    final inv = ga.invitations!.create(person: 'Mia');
    expect(await b.join(inv.link, 'Mia B.'), isNull);
    await settle(200);
    final req = ga.invitations!.pending.values.single;
    expect(req.person, 'Mia');
    await a.approve(ga, req);
    await settle();
    final mia = b.identity!.pub;
    expect(ga.session.memberOfPerson('Mia'), mia);
    final gb = b.groups.values.single;
    expect(gb.session.personOf(mia), 'Mia', reason: 'B sieht die Verknüpfung auch');

    // admin links itself to „Chris“, unlinks Mia, links her again
    a.linkPerson(ga, ga.secret.adminPub, 'Chris');
    a.linkPerson(ga, mia, null);
    await settle();
    expect(gb.session.memberOfPerson('Mia'), isNull);
    expect(gb.session.memberOfPerson('Chris'), ga.secret.adminPub);
    a.linkPerson(ga, mia, 'Chris'); // takes „Chris“ away from the admin: one person, one member
    expect(ga.session.memberOfPerson('Chris'), mia);
    expect(ga.session.personOf(ga.secret.adminPub), isNull);
    expect(() => gb.session.linkPerson(mia, 'Mia'), throwsStateError, reason: 'nur die Verwaltung ändert Mitglieder');
    a.dispose();
    b.dispose();
  });
}
