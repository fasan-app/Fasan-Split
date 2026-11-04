// Fasan Split – payment helpers (model/pay.dart). MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/model/pay.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('IBAN-Prüfung, SEPA-QR-Text, PayPal.Me-Link', () {
    expect(validIban('DE89 3704 0044 0532 0130 00'), isTrue); // well-known example IBAN
    expect(validIban('DE89 3704 0044 0532 0130 01'), isFalse);
    final q = epcPayload(name: 'Angi Muster', iban: 'de89 3704 0044 0532 0130 00', cents: 1230, text: 'Fasan Split: Lisboa 26');
    expect(q.split('\n'), ['BCD', '002', '1', 'SCT', '', 'Angi Muster', 'DE89370400440532013000', 'EUR12.30', '', '', 'Fasan Split: Lisboa 26']);
    expect(paypalUri('AngiM', 1230, 'eur').toString(), 'https://paypal.me/AngiM/12.30EUR');
    expect(validPaypal('Angi-M'), isFalse);
    expect(PayInfo.fromJson(PayInfo(iban: 'X', paypal: 'Y').toJson()).paypal, 'Y');
  });

  test('Bezahl-Angaben: nur in der Gruppe geteilt, beim anderen lesbar', () async {
    SharedPreferences.setMockInitialValues({});
    final hub = MemoryRelayHub();
    final a = CollabService(store: BillStore.memory()..me = 'Chris', vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Chris');
    final g = await a.createGroup('Lisboa 26');
    final link = g.invitations!.create().link;
    final b = CollabService(store: BillStore.memory()..me = 'Angi', vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.join(link, 'Angi');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    b.myPay = PayInfo(iban: 'DE89370400440532013000', holder: 'Angi Muster', paypal: 'AngiM');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final got = a.payOf(b.identity!.pub);
    expect(got?.paypal, 'AngiM');
    expect(got?.iban, 'DE89370400440532013000');
    expect(hub.stored.any((e) => e.content.contains('AngiM')), isFalse, reason: 'auf dem Relay nur verschlüsselt');
    a.dispose();
    b.dispose();
  });
}
