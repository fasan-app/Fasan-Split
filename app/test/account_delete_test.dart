// Fasan Split – deleting an account (Nutzer 04.11.): Test deletes, Chris sees „Konto gelöscht“ and can remove him.
// Test relay only. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Konto löschen: überall „gelöscht“, Lösch-Bitte an die Relays, Chris kann ihn entfernen', () async {
    final hub = MemoryRelayHub();
    final a = CollabService(store: BillStore.memory()..me = 'Chris', vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Chris');
    final g = await a.createGroup('Lisboa 26');
    final link = g.invitations!.create().link;
    final vaultT = MemoryVault();
    final t = CollabService(store: BillStore.memory()..me = 'Test', vault: vaultT, relayFactory: (_) => MemoryRelay(hub));
    await t.init();
    await t.setName('Test');
    await t.join(link, 'Test');
    await settle();
    final pubT = t.identity!.pub;
    expect(a.memberFriends.keys, contains(pubT));

    await t.deleteAccount();
    await settle(1500);
    expect(t.identity, isNull);
    expect(t.groups, isEmpty);
    expect(await vaultT.read('fasan.identity.priv'), isNull, reason: 'Schlüssel ist vom Gerät');
    expect(hub.stored.any((e) => e.kind == 5 && e.pubkey == pubT), isTrue, reason: 'Lösch-Bitte (NIP-09) ging an die Relays');

    expect(a.isDeleted(pubT), isTrue);
    expect(a.deletedFriends[pubT], 'Test');
    await a.forgetFriendPub(pubT);
    expect(a.deletedFriends, isEmpty);
    expect(a.memberFriends.keys, isNot(contains(pubT)));
    a.dispose();
    t.dispose();
  });
}
