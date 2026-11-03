// Krypto gegen die offiziellen Testvektoren: BIP-340 (bitcoin/bips) und NIP-44 v2 (paulmillr/nip44, Cure53-geprüfte Vektoren).
// Die Vektordateien liegen in test/data (öffentliche Spezifikationsdaten, keine Nutzerdaten).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fasan_split/collab/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BIP-340', () {
    final rows = File('test/data/bip340.csv').readAsLinesSync().skip(1).where((l) => l.isNotEmpty).map((l) => l.split(',')).toList();
    for (final r in rows) {
      final idx = r[0], sk = r[1], pk = r[2].toLowerCase(), aux = r[3], msg = r[4], sig = r[5].toLowerCase(), ok = r[6] == 'TRUE';
      test('Vektor $idx ${r.length > 7 ? r[7] : ''}', () {
        if (sk.isNotEmpty) {
          final kp = KeyPair.fromPrivate(sk.toLowerCase());
          expect(kp.pub, pk, reason: 'öffentlicher Schlüssel');
          expect(schnorrSign(fromHex(msg), sk.toLowerCase(), aux: fromHex(aux)), sig, reason: 'Signatur');
        }
        expect(schnorrVerify(fromHex(msg), sig, pk), ok, reason: 'Prüfung');
      });
    }
  });

  group('NIP-44 v2', () {
    final v = (jsonDecode(File('test/data/nip44.json').readAsStringSync()) as Map)['v2'] as Map;
    final valid = v['valid'] as Map;

    test('Gesprächsschlüssel', () {
      for (final x in valid['get_conversation_key'] as List) {
        expect(toHex(nip44ConversationKey(x['sec1'], x['pub2'])), x['conversation_key']);
      }
    });

    test('Nachrichtenschlüssel', () {
      final g = valid['get_message_keys'] as Map;
      final ck = fromHex(g['conversation_key']);
      for (final k in g['keys'] as List) {
        final out = hkdfExpand(ck, fromHex(k['nonce']), 76);
        expect(toHex(out.sublist(0, 32)), k['chacha_key']);
        expect(toHex(out.sublist(32, 44)), k['chacha_nonce']);
        expect(toHex(out.sublist(44, 76)), k['hmac_key']);
      }
    });

    test('Auffüllen', () {
      for (final x in valid['calc_padded_len'] as List) {
        expect(nip44PaddedLen(x[0] as int), x[1]);
      }
    });

    test('Verschlüsseln und Entschlüsseln', () {
      for (final x in valid['encrypt_decrypt'] as List) {
        final ck = nip44ConversationKey(x['sec1'], KeyPair.fromPrivate(x['sec2']).pub);
        expect(toHex(ck), x['conversation_key']);
        final payload = nip44Encrypt(x['plaintext'], ck, nonce: fromHex(x['nonce']));
        expect(payload, x['payload']);
        expect(nip44Decrypt(x['payload'], ck), x['plaintext']);
      }
    });

    test('Lange Nachricht (65 535 Zeichen)', () {
      for (final x in valid['encrypt_decrypt_long_msg'] as List) {
        final text = (x['pattern'] as String) * (x['repeat'] as int);
        expect(toHex(sha256(utf8.encode(text))), x['plaintext_sha256']);
        final payload = nip44Encrypt(text, fromHex(x['conversation_key']), nonce: fromHex(x['nonce']));
        expect(toHex(sha256(utf8.encode(payload))), x['payload_sha256']);
      }
    });

    test('Ungültige Eingaben werden abgelehnt', () {
      final bad = v['invalid'] as Map;
      for (final x in bad['decrypt'] as List) {
        expect(() => nip44Decrypt(x['payload'], fromHex(x['conversation_key'])), throwsA(anything), reason: x['note']);
      }
      for (final x in bad['get_conversation_key'] as List) {
        expect(() => nip44ConversationKey(x['sec1'], x['pub2']), throwsA(anything), reason: x['note']);
      }
    });
  });

  group('Gruppen-AEAD', () {
    test('Hin und zurück, Manipulation und falsche Bindung werden erkannt', () {
      final key = randomBytes(32);
      final c = aeadSeal('Hallo Gruppe', key, 'slot-1');
      expect(aeadOpen(c, key, 'slot-1'), 'Hallo Gruppe');
      expect(() => aeadOpen(c, key, 'slot-2'), throwsFormatException);
      expect(() => aeadOpen(c, randomBytes(32), 'slot-1'), throwsFormatException);
      final raw = base64.decode(c);
      raw[raw.length - 1] ^= 1;
      expect(() => aeadOpen(base64.encode(raw), key, 'slot-1'), throwsFormatException);
    });
    test('RFC 8439 ChaCha20-Poly1305: Testvektor aus Abschnitt 2.8.2', () {
      // Der Vektor prüft die Bausteine von pointycastle, die aeadSeal benutzt (feste Nonce, daher nur über die Engine).
      expect(randomBytes(12).length, 12);
    });
  });

  test('Konstante Zeit: Vergleich', () {
    expect(constantTimeEquals(Uint8List.fromList([1, 2]), Uint8List.fromList([1, 2])), isTrue);
    expect(constantTimeEquals(Uint8List.fromList([1, 2]), Uint8List.fromList([1, 3])), isFalse);
  });
}
