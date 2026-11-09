// SPDX-License-Identifier: MPL-2.0
// Fasan Split – online / zuletzt online and „gelesen“ (Nutzer 04.11.), switchable. Test relay only. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Online, gelesen, und aus heißt wirklich aus', () async {
    final hub = MemoryRelayHub();
    final a = CollabService(store: BillStore.memory()..me = 'Pia', vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    final g = await a.createGroup('Stadt 26');
    final link = g.invitations!.create().link;
    final b = CollabService(store: BillStore.memory()..me = 'Lena', vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Lena');
    await b.join(link, 'Lena');
    a.setForeground(true);
    b.setForeground(true);
    await settle(1500);
    final pubB = b.identity!.pub;
    expect(a.isOnline(pubB), isTrue);

    a.sendMessage(g, 'Hallo');
    await settle();
    final gb = b.groups.values.single;
    b.markRead(gb);
    await settle();
    final msg = a.messages(g).single;
    expect(a.readUntil(g, pubB)!.millisecondsSinceEpoch, greaterThanOrEqualTo(msg.at.millisecondsSinceEpoch));

    b.presence = false; // Lena switches it off
    await settle();
    expect(a.lastSeen(pubB), isNull);
    expect(a.readUntil(g, pubB), isNull);
    expect(b.lastSeen(a.identity!.pub), isNull, reason: 'wer es abschaltet, sieht es auch bei anderen nicht');
    a.dispose();
    b.dispose();
  });
}
