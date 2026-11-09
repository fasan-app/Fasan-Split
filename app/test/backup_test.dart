// SPDX-License-Identifier: MPL-2.0
// Fasan Split – backup file: everything out, into a fresh install back (Nutzer 03.11.: key switch needs one uninstall).
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/flows/backup.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Sicherung: Bons und Konto kommen in eine leere Installation, doppelte Bons nicht', () async {
    final old = BillStore.memory([
      Bill(id: 'x1', created: DateTime(2026, 11, 3), purpose: 'Pizza', total: 1000, items: [BillItem(name: 'Pizza', amount: 1000)])..group = 'WG',
    ]);
    old.me = 'Pia';
    final oldCollab = CollabService(store: old, vault: MemoryVault());
    final id = await oldCollab.ensureIdentity(name: 'Pia');
    final file = await makeBackup(old, collab: oldCollab);

    final fresh = BillStore.memory();
    final vault = MemoryVault();
    final freshCollab = CollabService(store: fresh, vault: vault);
    final r = await restoreBackup(fresh, file, collab: freshCollab);
    expect(r.added, 1);
    expect(r.secret, isTrue);
    expect(fresh.bills.single.purpose, 'Pizza');
    expect(fresh.bills.single.group, 'WG');
    expect(fresh.me, 'Pia');
    expect((await Identity.loadOrCreate(vault)).pub, id.pub, reason: 'gleiches Konto nach dem Neustart');

    final again = await restoreBackup(fresh, file, collab: freshCollab);
    expect((again.added, again.skipped), (0, 1));
    expect(() => restoreBackup(fresh, Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('Sicherung mit geteilter Gruppe (Speicher mit Listen): Gruppe kommt nach Neustart zurück', () async {
    SharedPreferences.setMockInitialValues({});
    final hub = MemoryRelayHub();
    final store = BillStore.memory();
    final c = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await c.init();
    await c.ensureIdentity(name: 'Pia');
    final g = await c.createGroup('WG');
    c.saveDocs();
    final file = await makeBackup(store, collab: c);
    c.dispose();

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final vault = MemoryVault();
    final store2 = BillStore.memory();
    final c2 = CollabService(store: store2, vault: vault, prefs: prefs, relayFactory: (_) => MemoryRelay(hub));
    expect((await restoreBackup(store2, file, collab: c2)).secret, isTrue);
    expect(prefs.getStringList('collab.doc.${g.secret.tag}.ids'), isNotEmpty);
    // „restart“: a new service on the same vault and prefs has the group again
    final c3 = CollabService(store: store2, vault: vault, prefs: prefs, relayFactory: (_) => MemoryRelay(hub));
    await c3.init();
    expect(c3.groups.values.single.secret.tag, g.secret.tag);
    c2.dispose();
    c3.dispose();
  });

  test('Sicherung mit Passwort: richtiges Passwort öffnet, falsches nicht, ohne Passwort gesperrt', () async {
    final old = BillStore.memory([Bill(id: 'x2', created: DateTime(2026, 11, 4), purpose: 'Taxi', total: 900, items: [BillItem(name: 'Taxi', amount: 900)])]);
    final plain = await makeBackup(old);
    final locked = await lockBackup(plain, 'Fasan 2026');
    expect(isLockedBackup(locked), isTrue);
    expect(() => restoreBackup(BillStore.memory(), locked), throwsA(isA<BackupLocked>()));
    expect(() => unlockBackup(locked, 'falsch'), throwsFormatException);
    final fresh = BillStore.memory();
    final r = await restoreBackup(fresh, await unlockBackup(locked, 'Fasan 2026'));
    expect((r.added, fresh.bills.single.purpose), (1, 'Taxi'));
  });
}
