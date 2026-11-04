// Zwei Telefone (Dienst + Rechnungsspeicher + Test-Relay): Gruppe, Einladung, Freigabe, Rechnung erscheint beim anderen,
// Änderungen laufen in beide Richtungen, Chat und Notizen, gleiche Beträge auf den Cent.

import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle([int ms = 1400]) async {
  // publish delay is 350 ms; give both phones time to publish and merge
  await Future<void>.delayed(Duration(milliseconds: ms));
}

void main() {
  test('Zwei Telefone: Einladen, Freigeben, gemeinsam abrechnen', () async {
    final hub = MemoryRelayHub();
    Relay factory(List<String> urls) => MemoryRelay(hub);

    final storeA = BillStore.memory();
    final storeB = BillStore.memory();
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: factory);
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: factory);
    await a.init();
    await b.init();
    await a.setName('Chris');
    await b.setName('Andi');

    // A: Gruppe, Rechnung hinein
    final ga = await a.createGroup('Lissabon');
    expect(storeA.allGroups, contains('Lissabon'));
    final bill = Bill(id: 'bill-1', created: DateTime(2026, 11, 3), total: 1380, purpose: 'Mittag', people: [Person('Chris', 0), Person('Andi', 1)], items: [
      BillItem(name: 'Coca Cola', amount: 960, qty: 3, shares: {0: 1, 1: 1}),
      BillItem(name: 'Wasser', amount: 420, shares: {0: 1}),
    ])
      ..payer = 0
      ..group = 'Lissabon';
    storeA.upsert(bill);

    // B öffnet die Einladung
    final invite = ga.invitations!.create(auto: false);
    expect(await b.join(invite.link, 'Andi'), isNull);
    await settle(200);
    expect(ga.invitations!.pending.length, 1);
    expect(storeB.bills, isEmpty, reason: 'vor der Freigabe sieht B nichts');
    await a.approve(ga, ga.invitations!.pending.values.first);
    await settle();
    expect(b.groups.length, 1);
    final gb = b.groups.values.first;
    expect(gb.localName, 'Lissabon');
    expect(storeB.bills.length, 1, reason: 'die Rechnung ist da');
    final billB = storeB.bills.single;
    expect(billB.purpose, 'Mittag');
    expect(billB.perPerson(), bill.perPerson());
    expect(billB.audit(), isEmpty);
    expect(billB.group, 'Lissabon');

    // B ändert: Wasser auch für Andi; A sieht es und rechnet gleich
    billB.its[1].shares = {0: 1, 1: 1};
    storeB.upsert(billB);
    await settle();
    final billA = storeA.bills.single;
    expect(billA.its[1].shares.keys.toSet(), {0, 1});
    expect(billA.perPerson(), billB.perPerson());
    expect(billA.perPerson().values.reduce((x, y) => x + y), 1380);

    // gleichzeitig: A fügt Eva hinzu, B ändert den Zweck
    billA.ps.add(Person('Eva', 2));
    billA.its[0].shares = {0: 1, 2: 1};
    storeA.upsert(billA);
    billB.purpose = 'Mittagessen';
    storeB.upsert(billB);
    await settle(2200);
    expect(storeA.bills.single.purpose, 'Mittagessen');
    expect(storeB.bills.single.ps.map((p) => p.name), ['Chris', 'Andi', 'Eva']);
    expect(storeA.bills.single.perPerson(), storeB.bills.single.perPerson());
    expect(storeA.bills.single.audit(), isEmpty);

    // Chat und Notizen
    a.sendMessage(ga, 'Wer zahlt?');
    b.sendMessage(gb, 'Ich!');
    final nid = a.newNote(ga, 'Plan');
    a.saveNote(ga, nid, text: 'Strand\nEssen');
    await settle();
    expect(a.messages(ga).map((m) => m.text), ['Wer zahlt?', 'Ich!']);
    expect(b.messages(gb).length, 2);
    expect(b.notes(gb).single.text, 'Strand\nEssen');
    b.saveNote(gb, nid, text: 'Strand\nEssen\nEis');
    await settle();
    expect(a.notes(ga).single.text, 'Strand\nEssen\nEis');

    // das Relay hat nur Verschlüsseltes gesehen
    final seen = hub.stored.map((e) => e.content + e.tags.map((t) => t.join()).join()).join();
    for (final secret in ['Lissabon', 'Coca', 'Mittag', 'Wer zahlt', 'Strand', 'Chris', 'Andi']) {
      expect(seen.contains(secret), isFalse, reason: secret);
    }

    // Neustart von B: alles ist lokal da (auch ohne Netz)
    expect(b.prefs, isNull); // Speicher im Test nur im Arbeitsspeicher: der Neustart-Pfad ist in der Gerätetest-Liste

    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(seconds: 40)));
}
