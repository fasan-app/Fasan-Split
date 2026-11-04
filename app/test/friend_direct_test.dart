// Fasan Split – friends without a group (Nutzer 04.11.: invite friends to chat and try the app; nothing shows up in
// groups or bills). Test relay only. MPL-2.0
import 'package:fasan_split/collab/group.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Freund einladen: verbunden ohne Gruppe, Chat in beide Richtungen, auch wenn der Einladende offline war', () async {
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Chris', vaultA = MemoryVault();
    final prefs = await SharedPreferences.getInstance();
    var chris = CollabService(store: storeA, vault: vaultA, prefs: prefs, relayFactory: (_) => MemoryRelay(hub));
    await chris.init();
    await chris.setName('Chris');
    final g = await chris.createDirect();
    final link = g.invitations!.create().link;
    expect(Invite.parse(link)!.direct, isTrue);
    expect(chris.directName(g), '', reason: 'noch niemand verbunden');
    await settle(500);
    chris.saveDocs();
    chris.dispose();

    final storeB = BillStore.memory()..me = 'Alex';
    final alex = CollabService(store: storeB, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await alex.init();
    expect(await alex.join(link, 'Alex'), isNull);
    await settle();
    final ga = alex.directs.single;
    expect(alex.directName(ga), 'Chris');
    expect(storeB.allGroups, isEmpty, reason: 'keine Gruppe in der Bon-Liste');
    alex.sendMessage(ga, 'Hallo Chris!');
    await settle();

    chris = CollabService(store: storeA, vault: vaultA, prefs: prefs, relayFactory: (_) => MemoryRelay(hub));
    await chris.init();
    await settle(2500);
    final gc = chris.directs.single;
    expect(chris.directName(gc), 'Alex');
    expect(chris.messages(gc).map((m) => m.text), contains('Hallo Chris!'));
    expect(storeA.allGroups, isEmpty);
    chris.sendMessage(gc, 'Hallo Alex!');
    await settle();
    expect(alex.messages(ga).map((m) => m.text), contains('Hallo Alex!'));
    chris.dispose();
    alex.dispose();
  });
}
