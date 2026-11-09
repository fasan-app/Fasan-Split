// SPDX-License-Identifier: MPL-2.0
// Fasan Split – second device joins the account by QR (collab/pairing.dart), test relay only. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/pairing.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Link, Prüfcode, Übertragung: neues Gerät hat dasselbe Konto und die Gruppe', () async {
    final hub = MemoryRelayHub();
    Future<CollabService> phone() async {
      final s = CollabService(store: BillStore.memory(), vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
      await s.init();
      return s;
    }

    final old = await phone();
    await old.setName('Pia');
    final g = await old.createGroup('Beispielstadt');
    await Future<void>.delayed(const Duration(milliseconds: 800));

    final neu = await phone();
    final (offer, done) = neu.startPairing();
    // the link opens the app on the old device (App Link) and parses back to the same offer and check code
    final read = PairOffer.parse(Uri.parse(offer.link).fragment)!;
    expect(isInviteLink(Uri.parse(offer.link)), isTrue);
    expect(read.check, offer.check);
    expect(read.check.length, 6);
    expect(await old.sendPairing(read), isTrue);
    final n = await done;
    expect(n, 1);
    expect(neu.identity!.pub, old.identity!.pub);
    expect(neu.identity!.name, 'Pia');
    expect(neu.groups.keys.single, g.secret.tag);
    old.dispose();
    neu.dispose();
  });
}
