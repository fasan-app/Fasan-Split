// Fasan Split – admin side of the browser end-to-end test (runs only with FASAN_E2E_RELAY=ws://127.0.0.1:<port>, a
// local relay; never public relays). Creates a group with a bill, writes an invitation link to FASAN_E2E_DIR/link.txt,
// waits until the web app (Playwright) joined, checks the member, writes the result. MPL-2.0
import 'dart:io';

import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final relayUrl = Platform.environment['FASAN_E2E_RELAY'];
  final dir = Platform.environment['FASAN_E2E_DIR'] ?? '/tmp';
  test('Web-Einladung Ende zu Ende (Admin-Seite)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BillStore.memory()..me = 'Chris';
    final a = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => RelayPool([WsRelay(relayUrl!)]));
    await a.init();
    await a.setName('Chris');
    final g = await a.createGroup('Lissabon', relays: [relayUrl!]);
    store.upsert(Bill(id: 'r1', created: DateTime(2026, 11, 4), purpose: 'Pizza Napoli', total: 2400, people: [Person('Chris', 0), Person('Angi', 1)], items: [
      BillItem(name: 'Pizza', amount: 2400, shares: {0: 1, 1: 1}),
    ])
      ..payer = 0
      ..group = 'Lissabon');
    await g.session.flush();
    File('$dir/link.txt').writeAsStringSync(g.invitations!.create(person: 'Angi').link);
    final until = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(until) && g.session.memberKeys.length < 3) {
      // founder + m/founder + Angi: memberKeys holds founder once; Angi makes it 2
      if (g.session.memberKeys.length >= 2) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final joined = g.session.memberKeys.length >= 2;
    final angi = g.session.memberOfPerson('Angi');
    // wait for an edit from the web app (Angi takes the whole pizza) – optional
    var edited = false;
    final until2 = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(until2)) {
      final b = store.bills.firstWhere((x) => x.id == 'r1');
      if (b.its.single.shares.length == 1) {
        edited = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    File('$dir/admin.txt').writeAsStringSync('joined=$joined linked=${angi != null} edited=$edited');
    expect(joined, isTrue);
    a.dispose();
  }, skip: relayUrl == null ? 'nur mit lokalem Relay (FASAN_E2E_RELAY)' : false, timeout: const Timeout(Duration(minutes: 8)));
}
