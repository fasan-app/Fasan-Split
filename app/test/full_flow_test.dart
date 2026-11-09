// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the whole chain on three phones with the test relay (MemoryRelay, no public relays), as a user would do
// it (Nutzer 04.11.: „Einladen, Gruppen, Interaktion und Verknüpfung zwischen Benutzern, Bons und Gruppen prüfen“):
// local group with a bill → share live → invite a person of the bill by https link → join → approve → linked →
// both see the same bill and the same balances → edits flow both ways → second member linked by hand →
// a member removed → new key, the others keep working, the removed one sees nothing new. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_core/settle.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1500]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<(CollabService, BillStore)> phone(MemoryRelayHub hub, String name) async {
  final store = BillStore.memory()..me = name;
  final s = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
  await s.init();
  await s.setName(name);
  return (s, store);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Gesamtablauf: Gruppe, Einladung aus dem Bon, Verknüpfung, gleiche Salden, Änderungen, Entfernen', () async {
    final hub = MemoryRelayHub();
    final (a, sa) = await phone(hub, 'Pia');
    final (b, sb) = await phone(hub, 'Lena');
    final (c, sc) = await phone(hub, 'Ben');

    // 1. Pia: local group with a bill, then shared live
    sa.addGroup('Beispielstadt');
    sa.upsert(Bill(id: 'r1', created: DateTime(2026, 10, 25), purpose: 'Café Muster', total: 8690, done: true, people: [Person('Pia', 0), Person('Lena', 1), Person('Ben', 2)], items: [
      BillItem(name: 'Burrito', amount: 6000, shares: {0: 1, 1: 1}),
      BillItem(name: 'Tea', amount: 1900, shares: {2: 1}),
      BillItem(name: 'Ohne Postenzeile', amount: 790, proportional: true),
    ])
      ..payer = 0
      ..group = 'Beispielstadt');
    final ga = await a.shareLocalGroup('Beispielstadt');

    // 2. invitation for „Lena“ from the bill, as https link; Lena opens it
    final link = ga.invitations!.create(person: 'Lena', auto: false).link;
    expect(isInviteLink(Uri.parse(link)), isTrue);
    expect(await b.join(link, 'Lena'), isNull);
    await settle(300);
    final req = ga.invitations!.pending.values.single;
    expect(req.person, 'Lena');
    await a.approve(ga, req);
    await settle();
    final gb = b.groups.values.single;
    expect(gb.localName, 'Beispielstadt');
    expect(ga.session.memberOfPerson('Lena'), b.identity!.pub, reason: 'mit der Person aus dem Bon verknüpft');
    expect(gb.session.personOf(b.identity!.pub), 'Lena');

    // 3. Lena sees the same bill and the same numbers
    final billB = sb.bills.single;
    expect(billB.purpose, 'Café Muster');
    expect(billB.perPerson(), sa.bills.single.perPerson());
    expect(billB.its.last.proportional, isTrue);
    final lenaA = myDebts(sa.bills, (n) => n == 'Lena'), lenaB = myDebts(sb.bills, (n) => gb.session.personsOf(b.identity!.pub).contains(n));
    expect(lenaB, lenaA, reason: 'Lenas Stand ist auf beiden Telefonen gleich');
    expect(lenaB['Pia'], lessThan(0), reason: 'Lena schuldet Pia');

    // 4. Lena changes a share, Pia sees it
    billB.its[0].shares = {0: 2, 1: 1};
    sb.upsert(billB);
    await settle();
    expect(sa.bills.single.its[0].shares, {0: 2, 1: 1});

    // 5. Ben joins with a general invitation and is linked by hand
    expect(await c.join(ga.invitations!.create(auto: false).link, 'Ben'), isNull);
    await settle(300);
    await a.approve(ga, ga.invitations!.pending.values.single);
    await settle();
    a.linkPerson(ga, c.identity!.pub, 'Ben');
    await settle();
    expect(gb.session.memberOfPerson('Ben'), c.identity!.pub, reason: 'Lena sieht die Verknüpfung');
    expect(sc.bills.single.perPerson(), sa.bills.single.perPerson());
    String keyOf(CollabGroup g, String n) => g.session.memberOfPerson(n) ?? n;
    expect(balances(sb.bills, key: (n) => keyOf(gb, n)), balances(sa.bills, key: (n) => keyOf(ga, n)), reason: 'Saldo je Mitglied gleich');

    // 6. Pia removes Ben: new key; Pia and Lena go on, Ben sees nothing new
    final ng = await a.removeMember(ga, c.identity!.pub);
    await settle();
    expect(b.groups.keys.single, ng.secret.tag);
    sb.upsert(Bill(id: 'r2', created: DateTime(2026, 10, 26), purpose: 'Café', total: 400, done: true, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Café', amount: 400, shares: {0: 1, 1: 1}),
    ])
      ..payer = 1
      ..group = 'Beispielstadt');
    await settle();
    expect(sa.bills.map((x) => x.id), containsAll(['r1', 'r2']), reason: 'neuer Bon von Lena bei Pia');
    expect(sc.bills.map((x) => x.id), isNot(contains('r2')), reason: 'Ben ist raus');
    a.dispose();
    b.dispose();
    c.dispose();
  });
}
