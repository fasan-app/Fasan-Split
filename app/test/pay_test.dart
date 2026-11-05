// Fasan Split – payment helpers (model/pay.dart). MPL-2.0
import 'dart:math';

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

  /// What a wallet does with the query: split at & and =, percent-decode only (as Bitcoin per RFC 3986 / BIP 21 and Monero's
  /// convert_from_url_format do – „+“ stays „+“).
  Map<String, String> walletParse(Uri u) {
    final raw = u.toString();
    final q = raw.contains('?') ? raw.substring(raw.indexOf('?') + 1) : '';
    String dec(String v) => Uri.decodeComponent(v);
    return {for (final kv in q.split('&').where((x) => x.isNotEmpty)) dec(kv.split('=').first): dec(kv.substring(kv.indexOf('=') + 1))};
  }

  test('Bitcoin/Monero-Link: Leerzeichen als %20 (nie +), Name kommt in der Wallet unverändert an', () {
    const addr = '175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W';
    expect(bitcoinUri(addr, label: 'Angi Muster').toString(), 'bitcoin:$addr?label=Angi%20Muster');
    expect(moneroUri('44AFFq5kSiGBoZ', name: 'Angi Muster').toString(), 'monero:44AFFq5kSiGBoZ?recipient_name=Angi%20Muster');
    expect(bitcoinUri(' $addr ').toString(), 'bitcoin:$addr', reason: 'no name: no query');
    expect(bitcoinUri(addr, label: '  ').toString(), 'bitcoin:$addr');
    expect(walletParse(bitcoinUri(addr, label: 'Jörg & Co = 100% + #1?')), {'label': 'Jörg & Co = 100% + #1?'});
  });

  test('Bitcoin/Monero-Link: 2000 zufällige Namen bleiben beim Dekodieren gleich, keine Steuerzeichen im Link', () {
    final r = Random(7);
    const pieces = ['a', 'Z', '7', ' ', '+', '&', '=', '#', '?', '%', '/', 'ä', 'ß', '€', '😀', '你', '"', "'", '<', '>', '\\'];
    for (var i = 0; i < 2000; i++) {
      final name = [for (var k = 0; k < 1 + r.nextInt(12); k++) pieces[r.nextInt(pieces.length)]].join();
      if (name.trim().isEmpty) continue;
      final b = bitcoinUri('bc1qexample', label: name), m = moneroUri('44Aexample', name: name);
      expect(walletParse(b), {'label': name.trim()}, reason: 'bitcoin „$name“');
      expect(walletParse(m), {'recipient_name': name.trim()}, reason: 'monero „$name“');
      final query = b.toString().substring(b.toString().indexOf('?') + 1);
      expect(query.substring('label='.length).contains(RegExp(r'[&=# +?]')), isFalse, reason: 'raw separator in value „$query“');
    }
  });

  test('SEPA-QR: Zeilenumbrüche und Steuerzeichen in Name und Text verschieben keine Felder', () {
    final q = epcPayload(name: 'Angi\nMuster\r\n', iban: 'DE89370400440532013000', cents: 5, text: 'Zeile1\nZeile2\t\u0000x');
    final lines = q.split('\n');
    expect(lines.length, 11, reason: 'always 11 fields');
    expect(lines[5], 'Angi Muster');
    expect(lines[6], 'DE89370400440532013000');
    expect(lines[7], 'EUR0.05');
    expect(lines[10], 'Zeile1 Zeile2 x');
    // over-long values are cut in characters, not in the middle of a surrogate pair
    final long = epcPayload(name: '😀' * 100, iban: 'DE89370400440532013000', cents: 100);
    expect(long.split('\n')[5].runes.length, 70);
  });
}
