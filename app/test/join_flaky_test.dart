// Joining over unreliable relays (05.11.: friends had to be invited several times). The relay refuses a share of the publishes and
// answers slowly; the friend joins right after the link was made. After a while both sides must show the same members – with the
// first link, without a second invitation. Test relay only. MPL-2.0
import 'dart:async';
import 'dart:math';

import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A relay that refuses [failRate] of the publishes and takes [delay] to answer; [online] false = nothing goes through.
class FlakyRelay implements Relay {
  FlakyRelay(this.inner, this.rnd, {this.failRate = 0.4, this.delay = const Duration(milliseconds: 80)});

  final Relay inner;
  final Random rnd;
  final double failRate;
  final Duration delay;
  bool online = true;
  int refused = 0, accepted = 0;

  @override
  String get name => 'flaky';

  @override
  Future<bool> publish(NostrEvent e) async {
    await Future<void>.delayed(delay);
    if (!online || rnd.nextDouble() < failRate) {
      refused++;
      return false;
    }
    accepted++;
    return inner.publish(e);
  }

  @override
  Stream<NostrEvent> subscribe(Filter f) => inner.subscribe(f);

  @override
  Future<void> close() => inner.close();

  int wakes = 0;

  @override
  void wake() => wakes++;
}

Future<bool> _until(bool Function() ok, {Duration limit = const Duration(seconds: 90)}) async {
  final end = DateTime.now().add(limit);
  while (DateTime.now().isBefore(end)) {
    if (ok()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return ok();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final seed in [1, 2, 3]) {
    test('Beitritt über unzuverlässige Relays: erster Link genügt, beide Seiten sehen dieselben Mitglieder (Seed $seed)', () async {
      final hub = MemoryRelayHub();
      final rnd = Random(seed);
      final relaysA = <FlakyRelay>[], relaysB = <FlakyRelay>[];
      final a = CollabService(store: BillStore.memory()..me = 'Chris', vault: MemoryVault(), relayFactory: (_) => FlakyRelay(MemoryRelay(hub), rnd)..also(relaysA.add));
      await a.init();
      await a.setName('Chris');
      final g = await a.createGroup('Lisboa 26');
      final link = g.invitations!.create().link;
      // the friend opens the link at once (a few hundred milliseconds), like in real life
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final b = CollabService(store: BillStore.memory()..me = 'Angi', vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => FlakyRelay(MemoryRelay(hub), rnd)..also(relaysB.add));
      await b.init();
      await b.setName('Angi');
      final err = await b.join(link, 'Angi');
      expect(err, isNull, reason: 'the join itself must not fail');
      final angi = b.identity!.pub;
      final seenByAdmin = await _until(() => a.groupByLocalName('Lisboa 26')!.session.memberKeys.contains(angi));
      final seenByFriend = await _until(() => b.groups.values.single.session.memberKeys.contains(a.identity!.pub));
      // ignore: avoid_print
      print('seed $seed: admin sees friend=$seenByAdmin, friend sees admin=$seenByFriend; refused A ${relaysA.fold<int>(0, (x, r) => x + r.refused)} B ${relaysB.fold<int>(0, (x, r) => x + r.refused)}');
      expect(seenByAdmin, isTrue, reason: 'the admin must see the friend without a second invitation');
      expect(seenByFriend, isTrue, reason: 'the friend must see the group');
      a.dispose();
      b.dispose();
    }, timeout: const Timeout(Duration(minutes: 4)));
  }

  test('Browser sofort geschlossen, Netz weg: beim erneuten Öffnen wird der Beitritt nachgesendet, ohne neue Einladung', () async {
    final hub = MemoryRelayHub();
    final rnd = Random(9);
    final a = CollabService(store: BillStore.memory()..me = 'Chris', vault: MemoryVault(), relayFactory: (_) => FlakyRelay(MemoryRelay(hub), rnd, failRate: 0));
    await a.init();
    await a.setName('Chris');
    final g = await a.createGroup('Lisboa 26');
    final link = g.invitations!.create().link;
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // the ticket is out

    // the friend's phone has no connection while joining
    final vault = MemoryVault(), store = BillStore.memory()..me = 'Angi';
    final offline = <FlakyRelay>[];
    var b = CollabService(store: store, vault: vault, prefs: await SharedPreferences.getInstance(), relayFactory: (_) => FlakyRelay(MemoryRelay(hub), rnd, failRate: 0)..online = false..also(offline.add));
    await b.init();
    await b.setName('Angi');
    final err = await b.join(link, 'Angi');
    expect(err, isNull);
    final angi = b.identity!.pub;
    expect(a.groupByLocalName('Lisboa 26')!.session.memberKeys.contains(angi), isFalse, reason: 'nothing got through yet');
    b.dispose(); // the tab is closed

    // reopened later, with a connection
    final prefs = await SharedPreferences.getInstance();
    final b2 = CollabService(store: store, vault: vault, prefs: prefs, relayFactory: (_) => FlakyRelay(MemoryRelay(hub), rnd, failRate: 0));
    await b2.init();
    expect(b2.groups.length, 1, reason: 'the group is still there after reopening');
    final seen = await _until(() => a.groupByLocalName('Lisboa 26')!.session.memberKeys.contains(angi), limit: const Duration(seconds: 30));
    expect(seen, isTrue, reason: 'the join is sent after reopening, no second invitation needed');
    a.dispose();
    b2.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Zurück in der App (wake): ein wartender Beitritt geht sofort raus, ohne die Wartezeiten der Wiederholung', () async {
    final hub = MemoryRelayHub();
    final rnd = Random(11);
    final a = CollabService(store: BillStore.memory()..me = 'Chris', vault: MemoryVault(), relayFactory: (_) => FlakyRelay(MemoryRelay(hub), rnd, failRate: 0));
    await a.init();
    await a.setName('Chris');
    final g = await a.createGroup('Lisboa 26');
    final link = g.invitations!.create().link;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final relays = <FlakyRelay>[];
    final b = CollabService(store: BillStore.memory()..me = 'Angi', vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => FlakyRelay(MemoryRelay(hub), rnd, failRate: 0)..online = false..also(relays.add));
    await b.init();
    await b.setName('Angi');
    expect(await b.join(link, 'Angi'), isNull);
    final angi = b.identity!.pub;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(a.groupByLocalName('Lisboa 26')!.session.memberKeys.contains(angi), isFalse);
    // the phone is in front again with a connection
    for (final r in relays) {
      r.online = true;
    }
    b.setForeground(false);
    b.setForeground(true); // away and back
    expect(relays.any((r) => r.wakes > 0), isTrue, reason: 'the relays are told to connect again');
    final seen = await _until(() => a.groupByLocalName('Lisboa 26')!.session.memberKeys.contains(angi), limit: const Duration(milliseconds: 2500));
    expect(seen, isTrue, reason: 'sent at once on return, not after the 3 s / 6 s / 12 s retry');
    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 1)));
}

extension on FlakyRelay {
  void also(void Function(FlakyRelay) f) => f(this);
}
