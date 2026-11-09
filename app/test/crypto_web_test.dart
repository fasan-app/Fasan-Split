// SPDX-License-Identifier: MPL-2.0
// Checks the own ChaCha20-Poly1305 (used because pointycastle's Poly1305 fails in the browser) against RFC 8439 and
// against pointycastle on the VM, so data sealed by older app versions stays readable.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fasan_split/collab/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

Uint8List _hex(String s) {
  s = s.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  return Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
}

String _toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _pcSeal(Uint8List key, Uint8List nonce, Uint8List pt, Uint8List aad) {
  final c = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, aad));
  final out = Uint8List(c.getOutputSize(pt.length));
  var n = c.processBytes(pt, 0, pt.length, out, 0);
  n += c.doFinal(out, n);
  return out.sublist(0, n);
}

void main() {
  test('Poly1305 RFC 8439 2.5.2', () {
    final key = _hex('85:d6:be:78:57:55:6d:33:7f:44:52:fe:42:d5:06:a8:01:03:80:8a:fb:0d:b2:fd:4a:bf:f6:af:41:49:f5:1b');
    final tag = poly1305(key, Uint8List.fromList(utf8.encode('Cryptographic Forum Research Group')));
    expect(_toHex(tag), 'a8061dc1305136c6c22b8baf0c0127a9');
  });

  test('AEAD RFC 8439 2.8.2', () {
    final key = _hex('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
    final nonce = _hex('070000004041424344454647');
    final aad = _hex('50515253c0c1c2c3c4c5c6c7');
    final pt = Uint8List.fromList(utf8.encode("Ladies and Gentlemen of the class of '99: If I could offer you only one tip "
        'for the future, sunscreen would be it.'));
    final out = chacha20Poly1305Seal(key, nonce, pt, aad);
    expect(_toHex(out.sublist(out.length - 16)), '1ae10b594f09e26a7e902ecbd0600691');
    expect(_toHex(out.sublist(0, 16)), 'd31a8d34648e60db7b86afbc53ef7ec2');
    expect(chacha20Poly1305Open(key, nonce, out, aad), pt);
  });

  test('same output as pointycastle, tamper detected', () {
    final r = Random(7);
    Uint8List rnd(int n) => Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
    for (final n in [0, 1, 15, 16, 17, 63, 64, 65, 200, 1000]) {
      final key = rnd(32), nonce = rnd(12), pt = rnd(n), aad = rnd(n % 7 * 3);
      final mine = chacha20Poly1305Seal(key, nonce, pt, aad);
      expect(mine, _pcSeal(key, nonce, pt, aad), reason: 'n=$n');
      expect(chacha20Poly1305Open(key, nonce, mine, aad), pt);
      mine[0] ^= 1;
      expect(() => chacha20Poly1305Open(key, nonce, mine, aad), throwsFormatException);
    }
    final key = rnd(32);
    expect(aeadOpen(aeadSeal('Hallo Gruppe', key, 'x'), key, 'x'), 'Hallo Gruppe');
  });
}
