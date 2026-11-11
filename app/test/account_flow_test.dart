// SPDX-License-Identifier: MPL-2.0
// Fasan Split – account flow as the user lived it (Nutzer 11.11.): founder „Chris“, members „Test“ and „Taddel“, removal and
// deletion of accounts, sign-out, sign-in with the 12 words on a fresh browser (no name), renaming. Test relay only, invented
// names. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_core/settle.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<(CollabService, BillStore)> phone(MemoryRelayHub hub, String name) async {
  final store = BillStore.memory()..me = name;
  final s = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
  await s.init();
  await s.setName(name);
  return (s, store);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Chris founds „Stadt 26“, Test and Taddel come in over links; one bill with all three.
  Future<({CollabService a, BillStore sa, CollabService b, CollabService c, MemoryRelayHub hub})> setup() async {
    final hub = MemoryRelayHub();
    final (a, sa) = await phone(hub, 'Chris');
    final g = await a.createGroup('Stadt 26');
    final l1 = g.invitations!.create().link, l2 = g.invitations!.create().link;
    await settle(400);
    final (b, _) = await phone(hub, 'Test');
    await b.join(l1, 'Test');
    final (c, _) = await phone(hub, 'Taddel');
    await c.join(l2, 'Taddel');
    await settle(9000);
    sa.upsert(Bill(id: 'x1', created: DateTime(2026, 11, 11), purpose: 'Bar', total: 3000, people: [Person('Chris', 0), Person('Test', 1), Person('Taddel', 2)], payer: 0, items: [
      BillItem(name: 'Cocktail', amount: 3000, shares: {0: 1, 1: 1, 2: 1}),
    ])
      ..group = 'Stadt 26');
    await settle(2000);
    return (a: a, sa: sa, b: b, c: c, hub: hub);
  }

  test('Konto löschen: auch wer per Link beigetreten ist (Verwaltung) verschwindet aus der Mitgliederliste und steht als gelöscht da', () async {
    final w = await setup();
    expect(w.a.memberFriends.values, containsAll(['Test', 'Taddel']));
    await w.c.deleteAccount();
    await settle(3000);
    expect(w.a.deletedFriends.values, contains('Taddel'));
    expect(w.a.memberFriends.values, isNot(contains('Taddel')), reason: 'ein gelöschtes Konto ist kein Mitglied mehr');
    expect(w.a.memberFriends.values, contains('Test'));
    w.a.dispose();
    w.b.dispose();
    w.c.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Gruppe verlassen (ausdrücklich): die anderen sehen es; Entfernte und Gegangene stehen unter „nicht mehr in deinen Gruppen“', () async {
    final w = await setup();
    await w.b.leave(w.b.groups.values.single, announce: true);
    await settle(3000);
    expect(w.a.memberFriends.values, isNot(contains('Test')));
    expect(w.a.leftFriends.values, contains('Test'));
    await w.a.removeMember(w.a.groups.values.single, w.c.identity!.pub);
    await settle(3000);
    expect(w.a.leftFriends.values, containsAll(['Test', 'Taddel']));
    expect(w.a.memberFriends, isEmpty);
    w.a.dispose();
    w.b.dispose();
    w.c.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Mit den 12 Wörtern anmelden: Gruppen, Bons und der Name kommen zurück (kein leerer Name)', () async {
    final w = await setup();
    final words = w.a.identity!.mnemonic!;
    final (d, sd) = await phone(w.hub, '');
    final n = await d.restoreIdentity(words);
    await settle(4000);
    expect(n, 1);
    expect(d.identity!.name, 'Chris');
    expect(sd.me, 'Chris');
    expect(sd.bills.map((b) => b.id), contains('x1'));
    w.a.dispose();
    w.b.dispose();
    w.c.dispose();
    d.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Umbenennen: der alte Name „Chris“ bleibt ich selbst, auch nach Anmeldung mit Wörtern und anderem Namen', () async {
    final w = await setup();
    await w.a.setName('Chris2');
    expect(w.a.ownNames, containsAll(['chris', 'chris2']));
    final (d, _) = await phone(w.hub, '');
    await d.restoreIdentity(w.a.identity!.mnemonic!, name: 'Chris3');
    expect(d.ownNames, containsAll(['chris2', 'chris3']), reason: 'der Gruppenname Chris2 bleibt ein Name von mir');
    w.a.dispose();
    w.b.dispose();
    w.c.dispose();
    d.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Abmelden: nichts wird gelöscht oder markiert; mit den Wörtern ist alles wieder da', () async {
    final w = await setup();
    final words = w.b.identity!.mnemonic!;
    await w.b.signOut(alsoBills: true);
    await settle(2500);
    expect(w.b.identity, isNull);
    expect(w.b.groups, isEmpty);
    expect(w.a.deletedFriends, isEmpty, reason: 'Abmelden ist kein Konto löschen');
    expect(w.a.memberFriends.values, contains('Test'), reason: 'die Gruppe sieht Test weiter als Mitglied');
    expect(w.a.leftFriends, isEmpty);
    final (b2, sb2) = await phone(w.hub, '');
    final n = await b2.restoreIdentity(words);
    await settle(4000);
    expect(n, 1);
    expect(b2.identity!.name, 'Test');
    expect(sb2.bills.map((b) => b.id), contains('x1'));
    w.a.dispose();
    w.b.dispose();
    w.c.dispose();
    b2.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Bons hängen an der festen Kennung: Umbenennen der Person im Bon ändert nicht, wer ich bin', () async {
    final hub = MemoryRelayHub();
    final (a, sa) = await phone(hub, 'Chris');
    Bill bill() => Bill(id: 'u1', created: DateTime(2026, 11, 11), purpose: 'Bar', total: 2000, people: [Person('Chris', 0), Person('Lena', 1)], payer: 0, items: [
          BillItem(name: 'Pizza', amount: 2000, shares: {0: 1, 1: 1}),
        ])
      ..done = true;
    final b = bill();
    sa.upsert(b);
    expect(a.learnOwnUids(), isTrue, reason: 'die Kennung von „Chris“ wird als meine gemerkt');
    expect(a.ownUids, contains(b.ps[0].uid));
    b.ps[0].name = 'Christopher'; // somebody renames the person on the bill
    expect(myDebts([b], a.isMeName), isEmpty, reason: 'nur über den Namen wäre ich hier fremd');
    expect(myDebts([b], a.isMeName, isMePerson: a.isMePerson), {'Lena': 1000}, reason: 'über die Kennung bin ich es weiterhin');
    a.dispose();
  });

  test('Stresstest: dreimal abmelden und mit den Wörtern zurück, dazwischen umbenennen – keine Doppelten, Bon und Name bleiben', () async {
    final w = await setup();
    final words = w.b.identity!.mnemonic!;
    var cur = w.b;
    for (var i = 0; i < 3; i++) {
      await cur.signOut();
      expect(cur.identity, isNull);
      final (next, sn) = await phone(w.hub, '');
      expect(await next.restoreIdentity(words), 1, reason: 'Lauf $i: die Gruppe kommt zurück');
      await settle(3500);
      expect(next.identity!.name, i == 0 ? 'Test' : 'Test$i', reason: 'Lauf $i: Name aus Konto/Gruppe');
      expect(sn.bills.map((b) => b.id), contains('x1'));
      await next.setName('Test${i + 1}');
      await settle(1500);
      cur.dispose();
      cur = next;
    }
    expect(w.a.memberFriends.values.where((n) => n.startsWith('Test')).length, 1, reason: 'ein Mitglied, nicht vier');
    expect(w.a.deletedFriends, isEmpty);
    expect(cur.ownNames, containsAll(['test', 'test1', 'test2', 'test3']));
    w.a.dispose();
    w.c.dispose();
    cur.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('Mitglied ↔ Person über die Kennung: wird die Person im Bon umbenannt, liest das Mitglied den verborgenen Bon weiter', () async {
    final w = await setup();
    w.b.learnOwnUids(); // (the ledger timer usually did it already)
    await settle(2500);
    final g = w.a.groups.values.first;
    final bill = w.sa.bills.firstWhere((b) => b.id == 'x1');
    final testPub = w.b.identity!.pub;
    expect(g.session.uidsOf(testPub), isNotEmpty, reason: 'die Kennung steht im Profil, die Gruppe liest sie');
    bill.ps[1].name = 'Tessa'; // someone renames the person
    expect(w.a.billReaders(g, bill), contains(testPub), reason: 'über die Kennung, nicht über den Namen');
    w.a.dispose();
    w.b.dispose();
    w.c.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
