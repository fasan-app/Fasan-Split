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
    final storeA = BillStore.memory()..me = 'Chris';
    final vaultA = MemoryVault();
    var a = CollabService(store: storeA, vault: vaultA, prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    final g = await a.createGroup('Lisboa 26'); // the account had no name yet: the group showed „—“
    await settle(300);
    a.saveDocs();
    a.dispose();
    a = CollabService(store: storeA, vault: vaultA, prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    expect(a.identity!.name, 'Chris', reason: 'Konto übernimmt „Ich bin“');
    final ga = a.groups.values.single;
    expect(ga.session.nameOf(a.identity!.pub), 'Chris');

    final storeB = BillStore.memory()..me = 'Angi';
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Angi');
    expect(await b.join(ga.invitations!.create().link, 'Angi'), isNull);
    await settle();
    final gb = b.groups.values.single;
    expect(gb.session.nameOf(a.identity!.pub), 'Chris', reason: 'Angi sieht Chris statt „—“');

    await b.setName('Angela');
    expect(storeB.me, 'Angela', reason: '„Ich bin“ folgt dem Kontonamen');
    await settle();
    expect(ga.session.nameOf(b.identity!.pub), 'Angela');

    // Mallory (has the group key) tries to rename Chris
    final mallory = KeyPair.generate();
    final id = GroupSession.profile(a.identity!.pub);
    final doc = LwwDoc(mallory.pub)..set('name', 'Böse');
    final d = 'fs:${g.secret.tag}:$id';
    await MemoryRelay(hub).publish(NostrEvent.create(mallory, kind: kindData, tags: [['d', d], ['t', g.secret.tag]], content: aeadSeal(doc.encode(), g.secret.key, d)));
    await settle(500);
    expect(gb.session.nameOf(a.identity!.pub), 'Chris');
    a.dispose();
    b.dispose();
  });
}
