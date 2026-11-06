// Fasan Split – notes on a bill with pin and @mention (Nutzer 04.11.). Test relay only. MPL-2.0
import 'package:fasan_split/collab/activity.dart';
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

  test('Notiz im Bon: geteilt, angepinnt, Erwähnung kommt bei Angi als Neuigkeit an', () async {
    final hub = MemoryRelayHub();
    final storeA = BillStore.memory()..me = 'Chris';
    final a = CollabService(store: storeA, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Chris');
    final g = await a.createGroup('Lisboa 26');
    final bill = Bill(id: 'r1', created: DateTime(2026, 11, 4), purpose: 'Tasca', total: 2000, people: [Person('Chris', 0), Person('Angi', 1)], items: [
      BillItem(name: 'Essen', amount: 2000, shares: {0: 1, 1: 1}),
    ])
      ..group = 'Lisboa 26';
    storeA.upsert(bill);
    final link = g.invitations!.create().link;
    await settle(400);
    final storeB = BillStore.memory()..me = 'Angi';
    final b = CollabService(store: storeB, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Angi');
    await b.join(link, 'Angi');
    await settle(9000); // past the quiet start, when the first sync is not news

    bill.notes.add(BillNote(from: 'Chris', text: '@Angi bitte Trinkgeld prüfen', pinned: true, mentions: ['Angi']));
    storeA.upsert(bill);
    await settle(2000);
    final got = storeB.bills.firstWhere((x) => x.id == 'r1');
    expect(got.notes.single.text, '@Angi bitte Trinkgeld prüfen');
    expect(got.notes.single.pinned, isTrue);
    expect(b.activity.any((x) => x.kind == ActivityKind.mention && x.text.contains('erwähnt')), isTrue);
    expect(b.unseenActivity, greaterThan(0));
    expect(b.changedBills, contains('r1'), reason: 'der Bon ist als geändert markiert');
    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 1)));
}
