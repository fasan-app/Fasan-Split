// Fasan Split – a second device joins the same account without typing the 12 words (Nutzer 04.11.; research
// docs/recherche/2026-11-04-konto-wiederherstellung.md). Like linking a device in Signal/WhatsApp, without a server:
// 1. The new device makes a one-time key pair E and shows a QR code / link with E.pub and the relays.
// 2. The old device reads it; both show the same 6-digit check code (from E.pub) – the user compares them.
// 3. The old device sends the 12 words and the name, NIP-44 encrypted from its key to E.pub, as one event (kind 30078,
//    d „fs:pair:<E.pub>“). Only E can read it; E is thrown away afterwards.
// 4. The new device restores the account from the words and fetches the groups (CollabService.restoreIdentity). MPL-2.0
import 'dart:async';
import 'dart:convert';

import 'crypto.dart';
import 'group.dart' show kindData;
import 'nostr.dart';

class PairOffer {
  PairOffer(this.pub, this.relays);

  final String pub; // one-time key of the new device
  final List<String> relays;

  /// Same 6 digits on both devices: the user sees they talk to each other (no one swapped the QR code).
  String get check => (int.parse(toHex(sha256(utf8.encode('fasan-split/pair/v1:$pub'))).substring(0, 8), radix: 16) % 1000000).toString().padLeft(6, '0');

  /// Link for the QR code; opens nothing by itself (the part after „#“ is read by the app).
  String get link => 'https://fasan-app.github.io/Fasan-Split/join/#pair:${base64Url.encode(utf8.encode(jsonEncode({'v': 1, 'e': pub, 'r': relays}))).replaceAll('=', '')}';

  static PairOffer? parse(String text) {
    try {
      final i = text.indexOf('pair:');
      if (i < 0) return null;
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(text.substring(i + 5).trim())))) as Map<String, dynamic>;
      if (j['v'] != 1) return null;
      return PairOffer(j['e'] as String, [for (final r in j['r'] as List) '$r']);
    } catch (_) {
      return null;
    }
  }
}

String _d(String pub) => 'fs:pair:$pub';

/// Old device: sends the account to the new one.
Future<bool> sendAccount(Relay relay, KeyPair me, PairOffer offer, {required String words, required String name}) {
  final body = jsonEncode({'words': words, 'name': name});
  final ev = NostrEvent.create(me, kind: kindData, tags: [['d', _d(offer.pub)], ['t', 'fs:pair'], ['p', offer.pub]], content: nip44Encrypt(body, nip44ConversationKey(me.priv, offer.pub)));
  return relay.publish(ev);
}

/// New device: waits for the account sent to [eph]. Completes with the words and the name.
Future<({String words, String name})> waitForAccount(Relay relay, KeyPair eph, {Duration timeout = const Duration(minutes: 10)}) {
  final c = Completer<({String words, String name})>();
  late StreamSubscription<NostrEvent> sub;
  sub = relay.subscribe(Filter(kinds: const [kindData], tags: {'t': ['fs:pair'], 'p': [eph.pub]})).listen((e) {
    if (!e.valid || e.tag('d') != _d(eph.pub)) return;
    try {
      final j = jsonDecode(nip44Decrypt(e.content, nip44ConversationKey(eph.priv, e.pubkey))) as Map<String, dynamic>;
      if (!c.isCompleted) c.complete((words: j['words'] as String, name: j['name'] as String? ?? ''));
      sub.cancel();
    } catch (_) {}
  });
  return c.future.timeout(timeout, onTimeout: () {
    sub.cancel();
    throw TimeoutException('no account');
  });
}
