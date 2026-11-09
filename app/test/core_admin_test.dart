// SPDX-License-Identifier: MPL-2.0
// Fasan Split – core 04.11. on three phones with the test relay (MemoryRelay, no public relays): several admins (group
// survives the founder leaving, the founder can be invited again), new group key when a member is removed, changes about
// me from people I do not trust wait for me. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1400]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<(CollabService, BillStore)> phone(MemoryRelayHub hub, String name) async {
  final store = BillStore.memory()..me = name;
  final s = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
  await s.init();
  await s.setName(name);
  return (s, store);
}

Future<void> invite(CollabService admin, CollabGroup g, CollabService joiner, String name) async {
  expect(await joiner.join(g.invitations!.create(auto: false).link, name), isNull);
  await settle(200);
  await admin.approve(g, g.invitations!.pending.values.single);
  await settle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Zweite Verwaltung: Gründer geht, Gruppe bleibt, Gründer wird wieder eingeladen', () async {
    final hub = MemoryRelayHub();
    final (a, _) = await phone(hub, 'Anna');
    final (b, _) = await phone(hub, 'Ben');
    final (c, _) = await phone(hub, 'Ali');
    final ga = await a.createGroup('WG');
    await invite(a, ga, b, 'Ben');
    final gb = b.groups.values.single;
    expect(gb.isAdmin, isFalse);
    a.setAdmin(ga, b.identity!.pub, true);
    await settle();
    expect(gb.isAdmin, isTrue, reason: 'B ist jetzt Verwaltung');
    expect(gb.invitations, isNotNull, reason: 'B kann einladen');
    await a.leave(ga);
    await invite(b, gb, c, 'Ali'); // B invites without the founder
    expect(c.groups.values.single.secret.adminPub, ga.secret.adminPub, reason: 'Gründer bleibt im Gruppengeheimnis');
    expect(gb.session.memberKeys, contains(c.identity!.pub));
    a.dispose();
    b.dispose();
    c.dispose();
  });

  test('Mitglied entfernen: alle anderen bekommen einen neuen Schlüssel, der Entfernte nicht', () async {
    final hub = MemoryRelayHub();
    final (a, sa) = await phone(hub, 'Anna');
    final (b, _) = await phone(hub, 'Ben');
    final (c, sc) = await phone(hub, 'Ali');
    final ga = await a.createGroup('WG');
    await invite(a, ga, b, 'Ben');
    await invite(a, ga, c, 'Ali');
    final oldTag = ga.secret.tag;
    final ng = await a.removeMember(ga, b.identity!.pub);
    await settle();
    expect(ng.secret.tag, isNot(oldTag));
    expect(c.groups.keys.single, ng.secret.tag, reason: 'C ist umgezogen');
    expect(b.groups.keys.single, oldTag, reason: 'B hat den neuen Schlüssel nicht');
    sa.upsert(Bill(id: 'n1', created: DateTime(2026, 11, 4), purpose: 'Neu', total: 500, people: [Person('Anna', 0), Person('Ali', 1)], items: [
      BillItem(name: 'x', amount: 500, shares: {0: 1, 1: 1}),
    ])
      ..group = 'WG');
    await settle();
    expect(sc.bills.map((x) => x.id), contains('n1'));
    a.dispose();
    b.dispose();
    c.dispose();
  });

  test('Vertrauen: Änderung an meinem Anteil von Ben wartet, bis ich sie annehme', () async {
    final hub = MemoryRelayHub();
    final (a, sa) = await phone(hub, 'Anna');
    final (b, sb) = await phone(hub, 'Ben');
    final ga = await a.createGroup('WG');
    sa.upsert(Bill(id: 'p1', created: DateTime(2026, 11, 4), purpose: 'Pizza', total: 1000, people: [Person('Anna', 0), Person('Ben', 1)], items: [
      BillItem(name: 'Pizza', amount: 1000, shares: {0: 1, 1: 1}),
    ])
      ..payer = 0
      ..group = 'WG');
    await invite(a, ga, b, 'Ben');
    a.setTrusted(b.identity!.pub, false);
    final billB = sb.bills.single;
    billB.its.single.shares = {0: 3, 1: 1}; // Ben gives Anna three quarters
    sb.upsert(billB);
    await settle();
    expect(sa.bills.single.its.single.shares, {0: 1, 1: 1}, reason: 'noch nicht angenommen');
    expect(a.held, isNotEmpty);
    for (final h in a.held.toList()) {
      a.decideHeld(h, true);
    }
    expect(sa.bills.single.its.single.shares, {0: 3, 1: 1});
    a.dispose();
    b.dispose();
  });
}
