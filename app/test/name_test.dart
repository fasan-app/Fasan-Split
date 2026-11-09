// SPDX-License-Identifier: MPL-2.0
// Fasan Split – one name everywhere (Nutzer 04.11.: „Mein Name wird einfach nicht richtig übernommen“, „Verknüpft mit —“).
// The account takes „Ich bin“, a rename reaches every group (own profile document), nobody can rename someone else.
// Test relay only. MPL-2.0
import 'package:fasan_split/collab/crypto.dart';
import 'package:fasan_split/collab/group.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Name aus „Ich bin“, Umbenennen kommt überall an, fremdes Profil zählt nicht', () async {
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final vaultA = MemoryVault();
    var a = CollabService(store: storeA, vault: vaultA, prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    final g = await a.createGroup('Stadt 26'); // the account had no name yet: the group showed „—“
    await settle(300);
    a.saveDocs();
    a.dispose();
    a = CollabService(store: storeA, vault: vaultA, prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    expect(a.identity!.name, 'Pia', reason: 'Konto übernimmt „Ich bin“');
    final ga = a.groups.values.single;
    expect(ga.session.nameOf(a.identity!.pub), 'Pia');

    final storeB = BillStore.memory()..me = 'Lena';
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Lena');
    expect(await b.join(ga.invitations!.create().link, 'Lena'), isNull);
    await settle();
    final gb = b.groups.values.single;
    expect(gb.session.nameOf(a.identity!.pub), 'Pia', reason: 'Lena sieht Pia statt „—“');

    await b.setName('Angela');
    expect(storeB.me, 'Angela', reason: '„Ich bin“ folgt dem Kontonamen');
    await settle();
    expect(ga.session.nameOf(b.identity!.pub), 'Angela');

    // Mallory (has the group key) tries to rename Pia
    final mallory = KeyPair.generate();
    final id = GroupSession.profile(a.identity!.pub);
    final doc = LwwDoc(mallory.pub)..set('name', 'Böse');
    final d = 'fs:${g.secret.tag}:$id';
    await MemoryRelay(hub).publish(NostrEvent.create(mallory, kind: kindData, tags: [['d', d], ['t', g.secret.tag]], content: aeadSeal(doc.encode(), g.secret.key, d)));
    await settle(500);
    expect(gb.session.nameOf(a.identity!.pub), 'Pia');
    a.dispose();
    b.dispose();
  });

  test('Beitritt ohne Namen: nie ein leerer Name (Nutzer 07.11.)', () async {
    final hub = MemoryRelayHub();
    final a = CollabService(store: BillStore.memory()..me = 'Pia', vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.createGroup('Stadt 26');
    final s = a.groups.values.single.session;
    final stranger = KeyPair.generate().pub;
    s.doc(GroupSession.members).set('m/$stranger', {'name': '  '});
    expect(s.nameOf(stranger), isNotEmpty);
    expect(s.nameOf(stranger).trim(), stranger.substring(0, 8), reason: 'empty member name falls back to the key stub');
    expect(s.knownName(stranger), isNull, reason: 'the notification then says „Jemand Neues“');
    a.dispose();
  });
}
