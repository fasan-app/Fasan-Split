// Fasan Split – the whole chain on three phones with the test relay (MemoryRelay, no public relays), as a user would do
// it (Nutzer 04.11.: „Einladen, Gruppen, Interaktion und Verknüpfung zwischen Benutzern, Bons und Gruppen prüfen“):
// local group with a bill → share live → invite a person of the bill by https link → join → approve → linked →
// both see the same bill and the same balances → edits flow both ways → second member linked by hand →
// a member removed → new key, the others keep working, the removed one sees nothing new. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/model/settle.dart';
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
    final (a, sa) = await phone(hub, 'Chris');
    final (b, sb) = await phone(hub, 'Angi');
    final (c, sc) = await phone(hub, 'Ben');

    // 1. Chris: local group with a bill, then shared live
    sa.addGroup('Lissabon');
    sa.upsert(Bill(id: 'r1', created: DateTime(2026, 10, 25), purpose: 'Ferreiras', total: 8690, done: true, people: [Person('Chris', 0), Person('Angi', 1), Person('Ben', 2)], items: [
      BillItem(name: 'Burrito', amount: 6000, shares: {0: 1, 1: 1}),
      BillItem(name: 'Tea', amount: 1900, shares: {2: 1}),
      BillItem(name: 'Ohne Postenzeile', amount: 790, proportional: true),
    ])
      ..payer = 0
      ..group = 'Lissabon');
    final ga = await a.shareLocalGroup('Lissabon');

    // 2. invitation for „Angi“ from the bill, as https link; Angi opens it
    final link = ga.invitations!.create(person: 'Angi', auto: false).link;
    expect(isInviteLink(Uri.parse(link)), isTrue);
    expect(await b.join(link, 'Angi'), isNull);
    await settle(300);
    final req = ga.invitations!.pending.values.single;
    expect(req.person, 'Angi');
    await a.approve(ga, req);
    await settle();
    final gb = b.groups.values.single;
    expect(gb.localName, 'Lissabon');
    expect(ga.session.memberOfPerson('Angi'), b.identity!.pub, reason: 'mit der Person aus dem Bon verknüpft');
    expect(gb.session.personOf(b.identity!.pub), 'Angi');

    // 3. Angi sees the same bill and the same numbers
    final billB = sb.bills.single;
    expect(billB.purpose, 'Ferreiras');
    expect(billB.perPerson(), sa.bills.single.perPerson());
    expect(billB.its.last.proportional, isTrue);
    final angiA = myDebts(sa.bills, (n) => n == 'Angi'), angiB = myDebts(sb.bills, (n) => gb.session.personsOf(b.identity!.pub).contains(n));
    expect(angiB, angiA, reason: 'Angis Stand ist auf beiden Telefonen gleich');
    expect(angiB['Chris'], lessThan(0), reason: 'Angi schuldet Chris');

    // 4. Angi changes a share, Chris sees it
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
    expect(gb.session.memberOfPerson('Ben'), c.identity!.pub, reason: 'Angi sieht die Verknüpfung');
    expect(sc.bills.single.perPerson(), sa.bills.single.perPerson());
    String keyOf(CollabGroup g, String n) => g.session.memberOfPerson(n) ?? n;
    expect(balances(sb.bills, key: (n) => keyOf(gb, n)), balances(sa.bills, key: (n) => keyOf(ga, n)), reason: 'Saldo je Mitglied gleich');

    // 6. Chris removes Ben: new key; Chris and Angi go on, Ben sees nothing new
    final ng = await a.removeMember(ga, c.identity!.pub);
    await settle();
    expect(b.groups.keys.single, ng.secret.tag);
    sb.upsert(Bill(id: 'r2', created: DateTime(2026, 10, 26), purpose: 'Café', total: 400, done: true, people: [Person('Chris', 0), Person('Angi', 1)], items: [
      BillItem(name: 'Café', amount: 400, shares: {0: 1, 1: 1}),
    ])
      ..payer = 1
      ..group = 'Lissabon');
    await settle();
    expect(sa.bills.map((x) => x.id), containsAll(['r1', 'r2']), reason: 'neuer Bon von Angi bei Chris');
    expect(sc.bills.map((x) => x.id), isNot(contains('r2')), reason: 'Ben ist raus');
    a.dispose();
    b.dispose();
    c.dispose();
  });
}
