// SPDX-License-Identifier: MPL-2.0
// The browser's fast curve code (web_extra/fasan-curve.js) checks itself at load against known answers made with this Dart code
// (lib/collab/curve_web.dart). This test pins those answers to the Dart implementation: if the Dart code ever changes its results,
// the self-check constants would be wrong and the fast path would silently switch itself off. MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:fasan_split/collab/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _h(String s) => c.sha256.convert(utf8.encode(s)).toString();

void main() {
  test('bekannte Antworten der schnellen Rechnung stimmen mit der Dart-Rechnung überein', () {
    final priv = _h('k1'), other = _h('k2'), msg = _h('m');
    expect(priv, '6ab9f1eb8f7d3388f4f9d586f66e99fd54080df2c446f0e58668b09c08a16dd0');
    expect(other, '015f7e6bc5aeaf483724089e9252cc13b50951a6b69412522765cff4d780306e');
    expect(msg, '62c66a7a5dd70c3146618063c344e531e6d4b59e379808443ce962b3abd63c5a');
    expect(KeyPair.fromPrivate(priv).pub, '669b8afcec803a0d323e9a17f3ea8e68e8abe5a278020a929adbec52421adbd0');
    expect(KeyPair.fromPrivate(other).pub, '60b2003c386519fc9eadf2b5cf124dd8eea4c4e68d5e154050a9346ea98ce600');
    expect(schnorrSign(fromHex(msg), priv, aux: Uint8List(32)), '2f7b0c41fd5c6b9a54024368550c485c3547fe2aaf62408d84c532bfe1ad2b400398a670a022be75077ee78fe6fce9573ceaf9d3e35694ccbcb4a807fdb92703');
    expect(toHex(ecdhX(priv, KeyPair.fromPrivate(other).pub)), 'f41f4fa203ebb11543e9e44753529a01d9a06f11a4020b8d7421729d57cf5736');
  });
}
