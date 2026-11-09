// SPDX-License-Identifier: MPL-2.0
// Fasan Split – admin side of the browser end-to-end test (runs only with FASAN_E2E_RELAY=ws://127.0.0.1:<port>, a
// local relay; never public relays). Creates a group with a bill, writes an invitation link to FASAN_E2E_DIR/link.txt
// and goes OFFLINE (the hard case, Nutzer 04.11.: people join while the inviting phone is off). The web app joins
// (tool/e2e/joiner.js, one line per joiner in joined.txt). Then the admin starts again and must see every joiner as a
// member, adopted, and linked to „Lena“. FASAN_E2E_JOINERS = how many browser runs to wait for (default 1). MPL-2.0
import 'dart:io';

import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final relayUrl = Platform.environment['FASAN_E2E_RELAY'];
  final dir = Platform.environment['FASAN_E2E_DIR'] ?? '/tmp';
  final joiners = int.tryParse(Platform.environment['FASAN_E2E_JOINERS'] ?? '') ?? 1;
  test('Web-Einladung Ende zu Ende (Admin-Seite, Admin offline)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BillStore.memory()..me = 'Pia';
    final vault = MemoryVault();
    final prefs = await SharedPreferences.getInstance();
    CollabService start() => CollabService(store: store, vault: vault, prefs: prefs, relayFactory: (_) => RelayPool([WsRelay(relayUrl!)]));
    var a = start();
    await a.init();
    await a.setName('Pia');
    final g = await a.createGroup('Beispielstadt', relays: [relayUrl!]);
    store.upsert(Bill(id: 'r1', created: DateTime(2026, 11, 4), purpose: 'Pizza Napoli', total: 2400, people: [Person('Pia', 0), Person('Lena', 1)], items: [
      BillItem(name: 'Pizza', amount: 2400, shares: {0: 1, 1: 1}),
    ])
      ..payer = 0
      ..group = 'Beispielstadt');
    final link = g.invitations!.create(person: 'Lena').link;
    await Future<void>.delayed(const Duration(seconds: 1));
    await g.session.flush();
    a.saveDocs();
    a.dispose(); // offline from here
    File('$dir/link.txt').writeAsStringSync(link);

    final flag = File('$dir/joined.txt');
    final until = DateTime.now().add(Duration(minutes: 3 * joiners + 2));
    while (joiners > 0 && DateTime.now().isBefore(until) && (!flag.existsSync() || flag.readAsLinesSync().where((x) => x.isNotEmpty).length < joiners)) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final reported = flag.existsSync() ? flag.readAsLinesSync().where((x) => x.isNotEmpty).length : 0;

    // the admin's phone starts again: reads the requests, adopts the self-joined members
    a = start();
    await a.init();
    final g2 = a.groups.values.single;
    final want = joiners + 1;
    final until2 = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(until2) && (g2.session.memberKeys.length < want || g2.session.memberKeys.any(g2.session.isSelfJoined))) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final members = g2.session.memberKeys.length - 1;
    final adopted = !g2.session.memberKeys.any(g2.session.isSelfJoined);
    final linked = g2.session.memberOfPerson('Lena') != null;
    File('$dir/admin.txt').writeAsStringSync('reported=$reported members=$members adopted=$adopted linked=$linked');
    expect(reported, joiners, reason: 'jeder Browser-Lauf meldet „in der Gruppe“');
    expect(members, joiners);
    expect(adopted, isTrue);
    if (joiners > 0) expect(linked, isTrue);

    // phase 2: friend link without a group (Nutzer 04.11.), the browser connects and writes while the admin is offline
    final friends = Platform.environment['FASAN_E2E_FRIEND'] == '1';
    if (friends) {
      final d = await a.createDirect(relays: [relayUrl]);
      final flink = d.invitations!.create().link;
      await Future<void>.delayed(const Duration(seconds: 1));
      await d.session.flush();
      a.saveDocs();
      a.dispose();
      File('$dir/friend.txt').writeAsStringSync(flink);
      final f = File('$dir/friend-done.txt');
      final until3 = DateTime.now().add(const Duration(minutes: 4));
      while (DateTime.now().isBefore(until3) && !f.existsSync()) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      a = start();
      await a.init();
      final d2 = a.directs.single;
      final until4 = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(until4) && !a.messages(d2).any((m) => m.text == 'Hallo aus dem Browser')) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final got = a.messages(d2).any((m) => m.text == 'Hallo aus dem Browser');
      File('$dir/admin.txt').writeAsStringSync(' friend=${a.directName(d2)} message=$got', mode: FileMode.append);
      expect(a.directName(d2), 'Lena');
      expect(got, isTrue);
      expect(store.allGroups, ['Beispielstadt'], reason: 'die Freundesverbindung ist keine Gruppe');
    }
    a.dispose();
  }, skip: relayUrl == null ? 'nur mit lokalem Relay (FASAN_E2E_RELAY)' : false, timeout: const Timeout(Duration(minutes: 20)));
}
