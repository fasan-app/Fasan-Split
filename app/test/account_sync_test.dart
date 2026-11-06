// Fasan Split – one account on several devices and after a reinstall (Nutzer 04.11.): the 12 words bring the groups
// back from the relays; a second device gets new groups while it runs; a backup with account replaces a fresh empty
// account and works without restart. Test relay only (MemoryRelay). MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/flows/backup.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1500]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<(CollabService, BillStore)> phone(MemoryRelayHub hub, String me) async {
  final store = BillStore.memory()..me = me;
  final s = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
  await s.init();
  return (s, store);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Neuinstallation: 12 Wörter holen Gruppe und Bons zurück; zweites Gerät bekommt neue Gruppen live', () async {
    final hub = MemoryRelayHub();
    final (a, sa) = await phone(hub, 'Chris');
    await a.setName('Chris');
    final g = await a.createGroup('Lissabon');
    sa.upsert(Bill(id: 'r1', created: DateTime(2026, 10, 25), purpose: 'Ferreiras', total: 1000, people: [Person('Chris', 0)], items: [BillItem(name: 'x', amount: 1000, shares: {0: 1})])
      ..group = 'Lissabon');
    await settle();
    final words = a.identity!.mnemonic!;

    // „reinstall“: empty device, account from the words
    final (b, sb) = await phone(hub, 'Chris');
    final n = await b.restoreIdentity(words);
    await settle();
    expect(n, 1);
    expect(b.groups.keys.single, g.secret.tag);
    expect(b.identity!.pub, a.identity!.pub);
    expect(sb.bills.map((x) => x.id), contains('r1'), reason: 'Bons kommen aus der Gruppe zurück');

    // the first device makes a new group: the second one gets it while it runs
    await b.init(); // starts the account watch (has a group now)
    await a.createGroup('Porto');
    await settle(2500);
    expect(b.groups.values.map((x) => x.localName), containsAll(['Lissabon', 'Porto']));
    a.dispose();
    b.dispose();
  });

  test('Sicherung mit Konto auf frischem Gerät, das schon ein leeres Konto hat: ersetzt es, ohne Neustart', () async {
    final hub = MemoryRelayHub();
    final (a, sa) = await phone(hub, 'Chris');
    await a.setName('Chris');
    final g = await a.createGroup('WG');
    a.saveDocs();
    final file = await makeBackup(sa, collab: a);

    final (b, sb) = await phone(hub, 'Chris');
    await b.ensureIdentity(); // e.g. „Konto“ opened before the restore
    final r = await restoreBackup(sb, file, collab: b);
    expect(r.secret, isTrue);
    expect(b.identity!.pub, a.identity!.pub);
    expect(b.groups.keys.single, g.secret.tag, reason: 'Gruppe sofort da');
    a.dispose();
    b.dispose();
  });
}
