// Gruppenprotokoll gegen ein Test-Relay im Speicher: Einladung, Freigabe, gleichzeitiges Bearbeiten, Fremde, Manipulation.
// Öffentliche Relays werden nie angesprochen (Beschluss 02.11.).
import 'dart:async';
import 'dart:convert';

import 'package:fasan_split/collab/crypto.dart';
import 'package:fasan_split/collab/group.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test('NIP-06: Testvektor aus nips/06.md', () {
    final k = keyFromMnemonic('leader monkey parrot ring guide accident before fence cannon height naive bean');
    expect(k.priv, '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a');
    expect(k.pub, '17162c921dc4d2518f9a101db33695df1afb56ab82f5ff3e5da6eec3ca5cd917');
    expect(() => keyFromMnemonic('leader monkey parrot ring guide accident before fence cannon height naive nonsense'), throwsFormatException);
  });

  test('Identität: erzeugen, speichern, wiederherstellen aus 12 Wörtern', () async {
    final v = MemoryVault();
    final a = await Identity.loadOrCreate(v, defaultName: 'Chris');
    expect(a.mnemonic!.split(' ').length, 12);
    final again = await Identity.loadOrCreate(v);
    expect(again.pub, a.pub);
    final v2 = MemoryVault();
    final restored = await Identity.restore(v2, a.mnemonic!);
    expect(restored.pub, a.pub, reason: 'gleiche Wörter, gleicher Schlüssel');
  });

  test('Einladung: Kodierung, Ablauf; Gruppenschlüssel nur im offenen Link', () {
    final secret = GroupSecret(key: randomBytes(32), adminPub: KeyPair.generate().pub, name: 'Lissabon', relays: ['wss://example.invalid']);
    final hub = MemoryRelayHub();
    final invs = Invitations(secret: secret, me: KeyPair.generate(), relay: MemoryRelay(hub));
    // open link (default, 04.11.): carries the key, in the fragment only
    final open = invs.create();
    expect(Invite.parse(open.link)!.groupKey, secret.key);
    expect(open.link.split('#').first.contains(toHex(secret.key)), isFalse);
    // manual approval: no key in the link
    final inv = invs.create(auto: false);
    final parsed = Invite.parse(inv.link)!;
    expect(parsed.tag, secret.tag);
    expect(parsed.name, 'Lissabon');
    expect(inv.link.contains(toHex(secret.key)), isFalse);
    expect(toHex(base64Url.decode(base64Url.normalize(inv.encode()))).contains(toHex(secret.key)), isFalse);
    expect(Invite.parse('Quatsch'), isNull);
    final old = Invite(tag: 'x', secret: randomBytes(32), adminPub: 'a', relays: const [], expires: DateTime.now().subtract(const Duration(minutes: 1)), name: '');
    expect(old.expired, isTrue);
  });

  test('Ganzer Ablauf: Einladen, Anfrage, Freigabe, Live-Bearbeitung beider Seiten, gleiche Endstände', () async {
    final hub = MemoryRelayHub();
    final adminKey = KeyPair.generate(), anaKey = KeyPair.generate(), benKey = KeyPair.generate();
    final secret = GroupSecret(key: randomBytes(32), adminPub: adminKey.pub, name: 'Lissabon', relays: ['memory']);
    final adminRelay = MemoryRelay(hub, name: 'a');

    final admin = GroupSession(secret: secret, me: adminKey, relay: adminRelay, publishDelay: Duration.zero)..start();
    final invites = Invitations(secret: secret, me: adminKey, relay: adminRelay)..listen();
    final invite = invites.create();

    // Ana opens the invitation, asks to join – and cannot read anything yet
    final anaRelay = MemoryRelay(hub, name: 'ana');
    final anaJoin = JoinFlow(invite: Invite.parse(invite.link)!, me: anaKey, relay: anaRelay, name: 'Ana');
    final welcomeF = anaJoin.waitForWelcome();
    expect(await anaJoin.sendRequest(), isTrue);
    await settle();
    expect(invites.pending.keys, [anaKey.pub]);
    expect(invites.pending[anaKey.pub]!.name, 'Ana');

    // the relay operator sees only ciphertext
    final stored = hub.stored.map((e) => e.content).join();
    expect(stored.contains('Ana'), isFalse);
    expect(stored.contains('Lissabon'), isFalse);

    // admin approves
    admin.addMember(anaKey.pub, 'Ana');
    admin.doc('bill:b1').set('meta/purpose', 'Abendessen');
    admin.touch('bill:b1');
    await admin.flush();
    expect(await invites.welcome(anaKey.pub), isTrue);
    final anaSecret = await welcomeF;
    expect(toHex(anaSecret.key), toHex(secret.key));
    expect(anaSecret.tag, secret.tag);

    final ana = GroupSession(secret: anaSecret, me: anaKey, relay: anaRelay, publishDelay: Duration.zero)..start();
    await settle();
    expect(ana.doc('bill:b1').get('meta/purpose'), 'Abendessen');
    expect(ana.memberKeys, containsAll([adminKey.pub, anaKey.pub]));

    // both edit at the same time: different fields merge, the same field has one winner on both sides
    admin.doc('bill:b1').set('i/1/name', 'Wein');
    admin.doc('bill:b1').set('meta/total', 1000);
    admin.touch('bill:b1');
    ana.doc('bill:b1').set('i/2/name', 'Brot');
    ana.doc('bill:b1').set('meta/total', 1200);
    ana.touch('bill:b1');
    await settle();
    await admin.flush();
    await ana.flush();
    await settle();
    expect(admin.doc('bill:b1').fingerprint, ana.doc('bill:b1').fingerprint);
    expect(admin.doc('bill:b1').get('i/1/name'), 'Wein');
    expect(admin.doc('bill:b1').get('i/2/name'), 'Brot');
    expect([1000, 1200], contains(admin.doc('bill:b1').get('meta/total')));

    // chat
    ana.doc(GroupSession.chat).set('c/1', {'from': anaKey.pub, 'text': 'Wer zahlt?', 't': 1});
    ana.touch(GroupSession.chat);
    await settle();
    expect(admin.doc(GroupSession.chat).get('c/1'), isNotNull);

    // a stranger who has the group key (but is not a member) is not heard
    final eve = KeyPair.generate();
    final eveSession = GroupSession(secret: secret, me: eve, relay: MemoryRelay(hub, name: 'eve'), publishDelay: Duration.zero)..start();
    eveSession.doc('bill:b1').set('meta/purpose', 'GEHACKT');
    eveSession.touch('bill:b1');
    await settle();
    expect(admin.doc('bill:b1').get('meta/purpose'), 'Abendessen');
    expect(ana.doc('bill:b1').get('meta/purpose'), 'Abendessen');
    expect(admin.rejected, greaterThan(0));

    // a forged member list from a non-admin is dropped
    final forged = NostrEvent.create(anaKey, kind: kindData, tags: [['d', 'fs:${secret.tag}:members'], ['t', secret.tag]], content: aeadSeal(jsonEncode([Entry('m/${eve.pub}', {'name': 'Eve'}, 99, anaKey.pub).toJson()]), secret.key, 'fs:${secret.tag}:members'));
    await MemoryRelay(hub).publish(forged);
    await settle();
    expect(admin.memberKeys.contains(eve.pub), isFalse);
    expect(ana.memberKeys.contains(eve.pub), isFalse);

    // a damaged event is rejected without harm
    final bad = NostrEvent(id: hub.stored.first.id, pubkey: hub.stored.first.pubkey, createdAt: 1, kind: kindData, tags: hub.stored.first.tags, content: 'x', sig: hub.stored.first.sig);
    expect(bad.valid, isFalse);
    expect(hub.accept(bad), isFalse);

    // a new device with the same key gets everything back from the relay (recovery)
    final newPhone = GroupSession(secret: anaSecret, me: anaKey, relay: MemoryRelay(hub, name: 'new'), publishDelay: Duration.zero)..start();
    await settle();
    expect(newPhone.doc('bill:b1').get('i/2/name'), 'Brot');
    expect(newPhone.doc(GroupSession.chat).get('c/1'), isNotNull);

    await admin.close();
    await ana.close();
    await eveSession.close();
    await newPhone.close();
    await invites.close();
    expect(benKey.pub.length, 64);
  });

  test('Anfrage mit abgelaufener oder fremder Einladung wird ignoriert', () async {
    final hub = MemoryRelayHub();
    final adminKey = KeyPair.generate();
    final secret = GroupSecret(key: randomBytes(32), adminPub: adminKey.pub, name: 'G', relays: const []);
    final inv = Invitations(secret: secret, me: adminKey, relay: MemoryRelay(hub))..listen();
    final real = inv.create(valid: const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final late = KeyPair.generate();
    await JoinFlow(invite: real, me: late, relay: MemoryRelay(hub), name: 'Spät').sendRequest();
    final foreign = Invite(tag: secret.tag, secret: randomBytes(32), adminPub: adminKey.pub, relays: const [], expires: DateTime.now().add(const Duration(days: 1)), name: '');
    await JoinFlow(invite: foreign, me: KeyPair.generate(), relay: MemoryRelay(hub), name: 'Fremd').sendRequest();
    await settle();
    expect(inv.pending, isEmpty);
    inv.revokeAll();
    await inv.close();
  });

  test('Willkommen nur vom Admin der Einladung', () async {
    final hub = MemoryRelayHub();
    final adminKey = KeyPair.generate(), mallory = KeyPair.generate(), joiner = KeyPair.generate();
    final secret = GroupSecret(key: randomBytes(32), adminPub: adminKey.pub, name: 'G', relays: const []);
    final inv = Invitations(secret: secret, me: adminKey, relay: MemoryRelay(hub)).create();
    final flow = JoinFlow(invite: inv, me: joiner, relay: MemoryRelay(hub), name: 'J');
    final f = flow.waitForWelcome(timeout: const Duration(milliseconds: 200));
    // Mallory sends a welcome with her own group key
    final fake = GroupSecret(key: randomBytes(32), adminPub: mallory.pub, name: 'Falle', relays: const []);
    final body = nip44Encrypt(jsonEncode({'key': toHex(fake.key), 'name': 'Falle', 'admin': mallory.pub, 'relays': []}), nip44ConversationKey(mallory.priv, joiner.pub));
    await MemoryRelay(hub).publish(NostrEvent.create(mallory, kind: kindData, tags: [['d', 'fs:${secret.tag}:welcome:${joiner.pub}'], ['t', '${secret.tag}:welcome'], ['p', joiner.pub]], content: body));
    await expectLater(f, throwsA(isA<TimeoutException>()));
  });
}
