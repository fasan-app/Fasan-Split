// SPDX-License-Identifier: MPL-2.0
// Fasan Split – one invitation does everything (Nutzer 04.11.: „ich will aus der Gruppe heraus eine Einladung
// verschicken … automatisch in der Gruppe sein“; joined people were not listed as persons; two links were needed to
// chat). Test relay only. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Ein Link aus der Gruppe: Person in der Gruppe, im Bon zugeordnet, Freund, Nachricht ohne zweiten Link', () async {
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    final g = await a.createGroup('Stadt 26');
    storeA.upsert(Bill(id: 'r1', created: DateTime(2026, 11, 4), purpose: 'Kneipe Beispiel', total: 2000, done: true, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Essen', amount: 2000, shares: {0: 1, 1: 1}),
    ])
      ..payer = 0
      ..group = 'Stadt 26');
    final link = g.invitations!.create(valid: const Duration(days: 1)).link; // general link, no person chosen
    await settle(400);

    final storeB = BillStore.memory()..me = 'Lena';
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Lena');
    expect(await b.join(link, 'Lena'), isNull);
    await settle();

    // in the group as a person, matched to „Lena“ of the bill without linking by hand
    expect(a.peopleOf('Stadt 26'), contains('Lena'));
    expect(b.peopleOf(b.groups.values.single.localName), containsAll(['Pia', 'Lena']));
    expect(g.session.memberOfPerson('Lena'), b.identity!.pub);
    // a friend on both sides
    expect(a.memberFriends.values, contains('Lena'));
    expect(b.memberFriends.values, contains('Pia'));

    // Pia writes to Lena: no second link
    final d = await a.directWith(b.identity!.pub, 'Lena');
    a.sendMessage(d, 'Willkommen!');
    await settle(2000);
    final db = b.directWithPub(a.identity!.pub);
    expect(db, isNotNull, reason: 'Lena bekommt die Zweier-Verbindung von selbst');
    expect(b.messages(db!).map((m) => m.text), contains('Willkommen!'));
    expect(storeB.allGroups, ['Stadt 26'], reason: 'die Zweier-Verbindung ist keine Gruppe');
    a.dispose();
    b.dispose();
  });
}
