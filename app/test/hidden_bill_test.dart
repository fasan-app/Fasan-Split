// SPDX-License-Identifier: MPL-2.0
// Sichtbarkeit je Rechnung (Paket G): a hidden bill has its own key. Members on the bill read it, a member who is not on it
// cannot, until they are added. Test relay only, invented names. MPL-2.0
import 'dart:convert';

import 'package:fasan_split/collab/group.dart';
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

  test('Verborgener Bon: Beteiligte lesen ihn, ein Mitglied ohne Eintrag nicht – bis es auf den Bon kommt', () async {
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    final g = await a.createGroup('Stadt 26');
    final linkB = g.invitations!.create().link;
    final linkC = g.invitations!.create().link;
    await settle(400);
    final storeB = BillStore.memory()..me = 'Lena';
    final b = CollabService(store: storeB, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Lena');
    await b.join(linkB, 'Lena');
    final storeC = BillStore.memory()..me = 'Karl';
    final c = CollabService(store: storeC, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await c.init();
    await c.setName('Karl');
    await c.join(linkC, 'Karl');
    await settle(9000);

    final bill = Bill(id: 'h1', created: DateTime(2026, 11, 10), purpose: 'Bar Beispiel', total: 3000, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Cocktail', amount: 3000, shares: {0: 1, 1: 1}),
    ])
      ..group = 'Stadt 26';
    storeA.upsert(bill);
    expect(a.hideBill(bill), isTrue);
    expect(bill.hidden, isTrue);
    await settle(3000);

    expect(storeB.bills.where((x) => x.id == 'h1'), hasLength(1), reason: 'Lena steht auf dem Bon und liest ihn');
    expect(storeB.bills.firstWhere((x) => x.id == 'h1').hidden, isTrue);
    expect(storeC.bills.where((x) => x.id == 'h1'), isEmpty, reason: 'Karl ist nicht auf dem Bon: er bekommt keinen Schlüssel');
    final gc = c.groups.values.single.session;
    expect(gc.hasBillKey('h1'), isFalse);
    expect(gc.doc(GroupSession.bill('h1')).keys('').isEmpty, isTrue, reason: 'der Inhalt blieb für Karl unlesbar');

    // Lena changes something: it reaches Pia; Karl still sees nothing
    final lb = storeB.bills.firstWhere((x) => x.id == 'h1');
    lb.its.first.name = 'Cocktail mit Schirm';
    storeB.upsert(lb);
    await settle(2500);
    expect(storeA.bills.firstWhere((x) => x.id == 'h1').its.first.name, 'Cocktail mit Schirm');
    expect(storeC.bills.where((x) => x.id == 'h1'), isEmpty);

    // Karl is put on the bill: he gets the key and the bill
    bill.people!.add(Person('Karl', 2));
    storeA.upsert(bill);
    await settle(4000);
    expect(gc.hasBillKey('h1'), isTrue);
    expect(storeC.bills.where((x) => x.id == 'h1'), hasLength(1));
    expect(storeC.bills.firstWhere((x) => x.id == 'h1').its.first.name, 'Cocktail mit Schirm');
    a.dispose();
    b.dispose();
    c.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Neustart ohne Netz: Lena hat Schlüssel und verborgenen Bon von der Platte', () async {
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    final g = await a.createGroup('Stadt 26');
    final link = g.invitations!.create().link;
    await settle(400);
    final storeB = BillStore.memory()..me = 'Lena';
    final vaultB = MemoryVault();
    final prefsB = await SharedPreferences.getInstance();
    var b = CollabService(store: storeB, vault: vaultB, prefs: prefsB, relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Lena');
    await b.join(link, 'Lena');
    await settle(9000);
    final bill = Bill(id: 'h2', created: DateTime(2026, 11, 10), purpose: 'Bar Beispiel', total: 3000, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Cocktail', amount: 3000, shares: {0: 1, 1: 1}),
    ])
      ..group = 'Stadt 26';
    storeA.upsert(bill);
    expect(a.hideBill(bill), isTrue);
    await settle(3000);
    expect(storeB.bills.where((x) => x.id == 'h2'), hasLength(1));
    b.saveDocs();
    b.dispose();

    // restart: new empty relay world (no network), empty store – everything must come from the disk
    final b2 = CollabService(store: BillStore.memory()..me = 'Lena', vault: vaultB, prefs: prefsB, relayFactory: (_) => MemoryRelay(MemoryRelayHub()));
    await b2.init();
    await settle(2500);
    final s2 = b2.groups.values.single.session;
    expect(s2.hasBillKey('h2'), isTrue, reason: 'der Schlüssel kommt aus dem keys-Dokument auf der Platte');
    expect(s2.doc(GroupSession.bill('h2')).keys('').isNotEmpty, isTrue, reason: 'der Bon war unter dem Bon-Schlüssel gespeichert und ist wieder lesbar');
    a.dispose();
    b2.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Standardstufe der Gruppe: neuer Bon ist gleich verborgen, nur Lena (auf dem Bon) bekommt ihn; fremde Bons bleiben unberührt', () async {
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    final g = await a.createGroup('Stadt 26');
    final linkB = g.invitations!.create().link, linkC = g.invitations!.create().link;
    a.setHideNewBills(g, true);
    expect(a.hidesNewBills(g), isTrue);
    await settle(400);
    final storeB = BillStore.memory()..me = 'Lena', storeC = BillStore.memory()..me = 'Karl';
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    final c = CollabService(store: storeC, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Lena');
    await b.join(linkB, 'Lena');
    await c.init();
    await c.setName('Karl');
    await c.join(linkC, 'Karl');
    await settle(9000);
    final bill = Bill(id: 'd1', created: DateTime(2026, 11, 10), purpose: 'Bar Beispiel', total: 3000, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Cocktail', amount: 3000, shares: {0: 1, 1: 1}),
    ])
      ..group = 'Stadt 26';
    storeA.upsert(bill);
    await settle(3500);
    expect(bill.hidden, isTrue, reason: 'Standardstufe verbirgt den neuen Bon');
    expect(storeB.bills.where((x) => x.id == 'd1'), hasLength(1));
    expect(storeC.bills.where((x) => x.id == 'd1'), isEmpty);
    a.dispose();
    b.dispose();
    c.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Nur Beträge: Karl (nicht auf dem Bon) sieht Summe und Anteile, aber keinen Postennamen; mit Schlüssel wird daraus der ganze Bon', () async {
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    final g = await a.createGroup('Stadt 26');
    final linkC = g.invitations!.create().link;
    await settle(400);
    final storeC = BillStore.memory()..me = 'Karl';
    final c = CollabService(store: storeC, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await c.init();
    await c.setName('Karl');
    await c.join(linkC, 'Karl');
    await settle(9000);
    final bill = Bill(id: 'sm1', created: DateTime(2026, 11, 10), purpose: 'Bar Beispiel', total: 3000, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Cocktail', amount: 3000, shares: {0: 1, 1: 1}),
    ])
      ..payer = 0
      ..group = 'Stadt 26';
    storeA.upsert(bill);
    expect(a.hideBill(bill, sums: true), isTrue);
    await settle(3500);
    final got = storeC.bills.where((x) => x.id == 'sm1').toList();
    expect(got, hasLength(1), reason: 'die Zusammenfassung kommt an');
    final sc = got.single;
    expect(sc.sumOnly, isTrue);
    expect(sc.effectiveTotal, 3000);
    expect(sc.its.map((i) => i.name).toSet(), {''}, reason: 'keine Postennamen');
    expect(sc.its.map((i) => i.amount).toList(), [1500, 1500]);
    expect(sc.ps.map((p) => p.name), ['Pia', 'Lena']);
    expect(sc.payer, 0);
    expect(sc.purpose, '•••');
    final gc = c.groups.values.single.session;
    expect(gc.doc(GroupSession.bill('sm1')).keys('').isEmpty, isTrue, reason: 'der eigentliche Bon bleibt unlesbar');
    expect(jsonEncode(gc.doc('sum:sm1').entries.map((e) => e.value).toList()).contains('Cocktail'), isFalse);

    // Karl is put on the bill: the full bill replaces the summary copy
    bill.people!.add(Person('Karl', 2));
    storeA.upsert(bill);
    await settle(4500);
    final full = storeC.bills.firstWhere((x) => x.id == 'sm1');
    expect(full.sumOnly, isFalse);
    expect(full.its.first.name, 'Cocktail');
    expect(full.purpose, 'Bar Beispiel');
    a.dispose();
    c.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
