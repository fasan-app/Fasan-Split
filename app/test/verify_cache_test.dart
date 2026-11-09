// SPDX-License-Identifier: MPL-2.0
// Signature check runs once per event (Nutzer 08.11.: the app stalls; one check costs tens of milliseconds on the screen thread in
// the browser, a relay sends every stored event again on each reconnect). The cache must never let a changed event through. MPL-2.0
import 'package:fasan_split/collab/crypto.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:flutter_test/flutter_test.dart';

NostrEvent _copy(NostrEvent e, {String? content, String? sig, String? pubkey}) => NostrEvent(id: e.id, pubkey: pubkey ?? e.pubkey, createdAt: e.createdAt, kind: e.kind, tags: e.tags, content: content ?? e.content, sig: sig ?? e.sig);

void main() {
  final key = KeyPair.fromPrivate(toHex(sha256([42])));
  final other = KeyPair.fromPrivate(toHex(sha256([43])));

  test('gültige Nachricht wird nur einmal geprüft, auch als zweite Kopie (Neuverbinden)', () {
    final e = NostrEvent.create(key, kind: 30078, tags: [['d', 'a']], content: 'hallo', createdAt: 1700000100);
    final before = cryptoStats.verifies;
    expect(e.valid, isTrue);
    expect(cryptoStats.verifies, before + 1);
    expect(e.valid, isTrue);
    expect(_copy(e).valid, isTrue); // the same event delivered again by another relay or after a reconnect
    expect(cryptoStats.verifies, before + 1, reason: 'weitere Lieferungen kosten keine Prüfung mehr');
  });

  test('verändert: anderer Inhalt, andere Signatur oder anderer Schreiber geht nie durch den Zwischenspeicher', () {
    final e = NostrEvent.create(key, kind: 30078, tags: [['d', 'b']], content: 'echt', createdAt: 1700000200);
    expect(e.valid, isTrue); // now cached
    expect(_copy(e, content: 'gefälscht').valid, isFalse, reason: 'Inhalt passt nicht mehr zur Kennung');
    final f = NostrEvent.create(key, kind: 30078, tags: [['d', 'c']], content: 'noch ein', createdAt: 1700000300);
    expect(_copy(e, sig: f.sig).valid, isFalse, reason: 'fremde Signatur');
    expect(_copy(e, pubkey: other.pub).valid, isFalse, reason: 'anderer Schreiber');
    expect(e.valid, isTrue);
  });

  test('ungültige Nachricht wird nicht gemerkt: jede Lieferung wird geprüft und abgelehnt', () {
    final e = NostrEvent.create(key, kind: 30078, tags: [['d', 'd']], content: 'x', createdAt: 1700000400);
    final bad = _copy(e, sig: '0' * 128);
    final before = cryptoStats.verifies;
    expect(bad.valid, isFalse);
    expect(bad.valid, isFalse);
    expect(cryptoStats.verifies, before + 2);
  });

  test('Zähler erfassen Signatur, Prüfung und Schlüsseltausch', () {
    final s0 = cryptoStats.signs, v0 = cryptoStats.verifies, x0 = cryptoStats.ecdhs;
    final e = NostrEvent.create(key, kind: 30078, tags: [['d', 'e']], content: 'z', createdAt: 1700000500);
    e.valid;
    nip44ConversationKey(key.priv, other.pub);
    expect(cryptoStats.signs, s0 + 1);
    expect(cryptoStats.verifies, v0 + 1);
    expect(cryptoStats.ecdhs, x0 + 1);
    expect(cryptoStats.summary()['laengsteMs'], isNotNull);
  });
}
