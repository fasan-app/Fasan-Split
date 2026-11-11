// SPDX-License-Identifier: MPL-2.0
// Fasan Split – phone side of the browser end-to-end test for hidden bills (Paket G). The web build derives the per-bill key
// exchange (NIP-44 via curve_web.dart) differently from the phone, so only a real browser proves it. Runs only with
// FASAN_E2E_RELAY (local relay, never public ones). Invented names. Flow: phone shares a group and writes link.txt; the
// browser joins as „Lena“ and writes joined.txt; the phone then creates bill A (Pia + Lena) and bill B (Pia + Max), both hidden;
// bill C is hidden with „nur Beträge“ (browser sees sums only); the browser must read A and not see B; when it wrote a-seen.txt the phone puts Lena on B and the browser must get it too.
// The phone stays online until tool/e2e/hidden.js wrote hidden-done.txt. MPL-2.0
import 'dart:io';

import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<bool> _waitFile(String path, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    if (File(path).existsSync()) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

void main() {
  final env = Platform.environment;
  final relayUrl = env['FASAN_E2E_RELAY'];
  final dir = env['FASAN_E2E_DIR'] ?? '/tmp';
  test('Verborgene Bons: Browser liest den eigenen, sieht den fremden nicht, bekommt ihn nach dem Eintragen (Telefon-Seite)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BillStore.memory()..me = 'Pia';
    final a = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => RelayPool([WsRelay(relayUrl!)]));
    await a.init();
    await a.setName('Pia');
    final g = await a.createGroup('Beispielstadt', relays: [relayUrl!]);
    final link = g.invitations!.create(person: 'Lena').link;
    await g.session.flush();
    File('$dir/link.txt').writeAsStringSync(link);
    expect(await _waitFile('$dir/joined.txt', 240), isTrue, reason: 'Browser ist der Gruppe nicht beigetreten');
    await Future<void>.delayed(const Duration(seconds: 6)); // the join must have reached us (members doc)

    Bill mk(String id, String purpose, String item, String other, int otherIdx) => Bill(
          id: id, created: DateTime(2026, 11, 11), purpose: purpose, total: 3000,
          people: [Person('Pia', 0), Person(other, 1)], payer: 0,
          items: [BillItem(name: item, amount: 3000, shares: {0: 1, 1: 1})],
        )..group = 'Beispielstadt';
    final ba = mk('e2e-hid-a', 'Versteckt-A', 'Cocktail Aqua', 'Lena', 1);
    final bb = mk('e2e-hid-b', 'Versteckt-B', 'Geheimposten', 'Max', 1);
    store.upsert(ba);
    store.upsert(bb);
    expect(a.hideBill(ba), isTrue);
    expect(a.hideBill(bb), isTrue);
    await g.session.flush();
    // bill C: hidden with „nur Beträge“ – the browser may see the sums, never the item name
    final bc = mk('e2e-hid-c', 'Versteckt-C', 'Sparposten', 'Max', 1);
    store.upsert(bc);
    expect(a.hideBill(bc, sums: true), isTrue);
    await g.session.flush();
    // bill D stays visible for all: the browser hides it itself through the ⋮ menu and the dialog (web = app check)
    final bd = mk('e2e-hid-d', 'Sichtbar-D', 'Tagesgericht', 'Lena', 1);
    store.upsert(bd);
    await g.session.flush();
    File('$dir/bills.txt').writeAsStringSync('A+B+C angelegt');

    if (await _waitFile('$dir/a-seen.txt', 240)) {
      // put Lena on B: she must now get the key and the bill
      bb.people!.add(Person('Lena', 2));
      store.upsert(bb);
      await g.session.flush();
      File('$dir/lena-on-b.txt').writeAsStringSync('ok');
    }
    // the browser hid bill D with „Beträge sichtbar“: the flags must come back to the phone
    if (await _waitFile('$dir/d-done.txt', 240)) {
      for (var i = 0; i < 60 && !(bd.hidden && bd.sums); i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      File('$dir/d-phone.txt').writeAsStringSync('hidden=${bd.hidden} sums=${bd.sums}');
      expect(bd.hidden && bd.sums, isTrue, reason: 'der Browser hat D verborgen, das Telefon hat es nicht übernommen');
    }
    expect(await _waitFile('$dir/hidden-done.txt', 300), isTrue);
    a.dispose();
  }, skip: relayUrl == null ? 'nur mit FASAN_E2E_RELAY' : false, timeout: const Timeout(Duration(minutes: 12)));
}
