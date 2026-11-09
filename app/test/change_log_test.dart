// SPDX-License-Identifier: MPL-2.0
// Fasan Split – what exactly changed (Nutzer 07.11.: „nur dass jemand etwas geändert hat, aber nicht was“). Test relay only. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/collab/activity.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Änderungen kommen mit Inhalt an: Menge, Eintragen, Betrag; Neuigkeit nennt es', () async {
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: storeA, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    final g = await a.createGroup('Stadt 26');
    final water = BillItem(name: 'Sprudel', amount: 700, qty: 2);
    final bill = Bill(id: 'r1', created: DateTime(2026, 11, 7), purpose: 'Strandbar Erfunden', total: 700, people: [Person('Pia', 0), Person('Lena', 1)], items: [water])..group = 'Stadt 26';
    storeA.upsert(bill);
    final link = g.invitations!.create().link;
    await settle(400);
    SharedPreferences.setMockInitialValues({});
    final storeB = BillStore.memory()..me = 'Lena';
    final b = CollabService(store: storeB, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Lena');
    await b.join(link, 'Lena');
    await settle(9000);
    expect(b.changeLog, isEmpty, reason: 'first sync of a bill is not a change');

    water
      ..qty = 3
      ..amount = 1050
      ..shares = {1: 1};
    bill.total = 1050;
    storeA.upsert(bill);
    await settle(3000);

    final lines = [for (final r in b.changesOfBill('r1')) ...r.lines.map((l) => l.de)];
    expect(lines, contains('Sprudel: Menge 2 → 3'));
    expect(lines.any((l) => l.startsWith('Sprudel: Betrag 7,00')), isTrue, reason: lines.join(' | '));
    expect(lines, contains('Lena bei „Sprudel“ eingetragen'));
    expect(b.changeLog.first.who, 'Pia');
    final n = b.activity.firstWhere((x) => x.kind == ActivityKind.billChanged);
    expect(n.text, contains('Menge 2 → 3'), reason: 'Neuigkeit nennt, was sich geändert hat');
    expect(a.changesOfBill('r1'), isNotEmpty, reason: 'eigene Änderungen stehen auch im Verlauf');
    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 1)));
}
