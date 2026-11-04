// Fasan Split – backup file: everything out, into a fresh install back (Nutzer 03.11.: key switch needs one uninstall).
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/backup.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sicherung: Bons und Konto kommen in eine leere Installation, doppelte Bons nicht', () async {
    final old = BillStore.memory([
      Bill(id: 'x1', created: DateTime(2026, 11, 3), purpose: 'Pizza', total: 1000, items: [BillItem(name: 'Pizza', amount: 1000)])..group = 'WG',
    ]);
    old.me = 'Chris';
    final oldCollab = CollabService(store: old, vault: MemoryVault());
    final id = await oldCollab.ensureIdentity(name: 'Chris');
    final file = await makeBackup(old, collab: oldCollab);

    final fresh = BillStore.memory();
    final vault = MemoryVault();
    final freshCollab = CollabService(store: fresh, vault: vault);
    final r = await restoreBackup(fresh, file, collab: freshCollab);
    expect(r.added, 1);
    expect(r.secret, isTrue);
    expect(fresh.bills.single.purpose, 'Pizza');
    expect(fresh.bills.single.group, 'WG');
    expect(fresh.me, 'Chris');
    expect((await Identity.loadOrCreate(vault)).pub, id.pub, reason: 'gleiches Konto nach dem Neustart');

    final again = await restoreBackup(fresh, file, collab: freshCollab);
    expect((again.added, again.skipped), (0, 1));
    expect(() => restoreBackup(fresh, Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });
}
