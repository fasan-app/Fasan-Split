// Fasan Split – everyone sees the same bills (Nutzer 04.11.: „Bons müssen immer auf dem gleichen Stand sein“). A relay
// that refuses a burst (like public relays with rate limits) must not leave bills behind; the trash is shared too.
// Test relay only. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Refuses every second publish for a while, like a relay that limits bursts.
class FlakyRelay implements Relay {
  FlakyRelay(this.inner, this.refuse);
  final Relay inner;
  int refuse; // how many publishes are refused
  var _n = 0;
  @override
  Future<bool> publish(NostrEvent e) async {
    if (refuse > 0 && _n++ % 2 == 0) {
      refuse--;
      return false;
    }
    return inner.publish(e);
  }

  @override
  Stream<NostrEvent> subscribe(Filter f) => inner.subscribe(f);
  @override
  Future<void> close() => inner.close();
  @override
  String get name => 'flaky';
}

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

Bill bill(String id, String p) => Bill(id: id, created: DateTime(2026, 10, 24), purpose: p, total: 1000, people: [Person('Chris', 0), Person('Angi', 1)], items: [
      BillItem(name: 'Essen', amount: 1000, shares: {0: 1, 1: 1}),
    ])
      ..group = 'Lisboa 26';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Abgelehnte Sendungen kommen von selbst nach; Papierkorb wird geteilt', () async {
    final hub = MemoryRelayHub();
    final flaky = FlakyRelay(MemoryRelay(hub), 8);
    final storeA = BillStore.memory()..me = 'Chris';
    final a = CollabService(store: storeA, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => flaky);
    await a.init();
    await a.setName('Chris');
    storeA.addGroup('Lisboa 26');
    for (var i = 0; i < 9; i++) {
      storeA.upsert(bill('b$i', 'Bon $i'));
    }
    final g = await a.shareLocalGroup('Lisboa 26'); // nine bills at once, half of the sends refused
    final link = g.invitations!.create().link;
    await settle(500);

    final storeB = BillStore.memory()..me = 'Angi';
    final b = CollabService(store: storeB, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    expect(await b.join(link, 'Angi'), isNull);
    // no further change on Chris's phone: the retries alone must bring every bill
    for (var i = 0; i < 30 && storeB.bills.length < 9; i++) {
      await settle(500);
    }
    expect(storeB.bills.map((x) => x.id).toSet(), {for (var i = 0; i < 9; i++) 'b$i'});

    // Chris throws one away: Angi's copy goes to her trash
    storeA.trash([storeA.bills.firstWhere((x) => x.id == 'b3')]);
    await settle(1500);
    expect(storeB.bills.firstWhere((x) => x.id == 'b3').trashedAt, isNotNull);
    storeA.untrash([storeA.bills.firstWhere((x) => x.id == 'b3')]);
    await settle(1500);
    expect(storeB.bills.firstWhere((x) => x.id == 'b3').trashedAt, isNull);
    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
