// SPDX-License-Identifier: MPL-2.0
// Fasan Split – browser: secp256k1 on the browser's native BigInt (web_extra/fasan-curve.js = @noble/curves 2.4.0, MIT, audited; built by
// tool/curve/build.sh). Measured 08.11. (cloud machine): signature check 129 ms in the Dart code compiled to WebAssembly, 2 ms here;
// signing 144 → 2.4 ms; ECDH 65 → 2.1 ms. The Dart code blocks the screen for that time on every message of a group.
// The script loads after the start; until it is there, and whenever its self-check fails, crypto.dart uses the Dart code. Results are
// the same: BIP-340 signatures are deterministic for a given aux value (tool/curve/check.js runs the official vectors against the bundle).
// dart:js_interop: api.dart.dev/dart-js_interop. MPL-2.0
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

extension type _Curve._(JSObject _) implements JSObject {
  external String get version;
  external bool verify(String msgHex, String sigHex, String pubHex);
  external String sign(String msgHex, String privHex, String auxHex);
  external String ecdh(String privHex, String pubHex);
  external String pubkey(String privHex);
}

@JS('fasanCurve')
external _Curve? get _curve;

bool _ok = false;
String _impl = 'pointycastle (nicht geladen)';

// Known answers made with the Dart code (crypto.dart; test/crypto_curve_test.dart checks the same values): secret key = sha256('k1'),
// other side = sha256('k2'), message = sha256('m'), aux = 32 zero bytes. The fast code is used only if it gives exactly these.
const _priv = '6ab9f1eb8f7d3388f4f9d586f66e99fd54080df2c446f0e58668b09c08a16dd0';
const _other = '015f7e6bc5aeaf483724089e9252cc13b50951a6b69412522765cff4d780306e';
const _msg = '62c66a7a5dd70c3146618063c344e531e6d4b59e379808443ce962b3abd63c5a';
const _pub = '669b8afcec803a0d323e9a17f3ea8e68e8abe5a278020a929adbec52421adbd0';
const _pubOther = '60b2003c386519fc9eadf2b5cf124dd8eea4c4e68d5e154050a9346ea98ce600';
const _sig = '2f7b0c41fd5c6b9a54024368550c485c3547fe2aaf62408d84c532bfe1ad2b400398a670a022be75077ee78fe6fce9573ceaf9d3e35694ccbcb4a807fdb92703';
const _ecdh = 'f41f4fa203ebb11543e9e44753529a01d9a06f11a4020b8d7421729d57cf5736';

/// Loads the script and runs the self-check. Without network or when the check fails, the Dart code stays in use.
Future<void> loadFastCurve() async {
  // ?curve=dart switches the fast code off (comparison measurements and a way out if it ever misbehaves on a device)
  if (Uri.base.queryParameters['curve'] == 'dart') {
    _impl = 'pointycastle (?curve=dart)';
    return;
  }
  if (_curve == null) {
    final done = Completer<void>();
    try {
      final s = web.document.createElement('script') as web.HTMLScriptElement;
      s.src = 'fasan-curve.js';
      s.onload = ((web.Event _) {
        if (!done.isCompleted) done.complete();
      }).toJS;
      s.onerror = ((web.Event _) {
        if (!done.isCompleted) done.complete();
      }).toJS;
      web.document.head!.append(s);
      await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    } catch (_) {
      return;
    }
  }
  _selfCheck();
}

void _selfCheck() {
  try {
    final c = _curve;
    if (c == null) return;
    final ok = c.pubkey(_priv) == _pub &&
        c.pubkey(_other) == _pubOther &&
        c.sign(_msg, _priv, '00' * 32) == _sig &&
        c.verify(_msg, _sig, _pub) &&
        !c.verify(_msg.replaceRange(0, 2, '00'), _sig, _pub) &&
        !c.verify(_msg, _sig.replaceRange(0, 2, '00'), _pub) &&
        c.ecdh(_priv, _pubOther) == _ecdh;
    _ok = ok;
    _impl = ok ? c.version : 'pointycastle (Selbsttest der schnellen Rechnung fehlgeschlagen)';
  } catch (_) {
    _ok = false;
  }
}

bool? fastVerify(String msgHex, String sigHex, String pubHex) {
  if (!_ok) return null;
  try {
    return _curve!.verify(msgHex, sigHex, pubHex);
  } catch (_) {
    return null;
  }
}

String? fastSign(String msgHex, String privHex, String auxHex) {
  if (!_ok) return null;
  try {
    return _curve!.sign(msgHex, privHex, auxHex);
  } catch (_) {
    return null;
  }
}

String? fastEcdh(String privHex, String pubHex) {
  if (!_ok) return null;
  try {
    return _curve!.ecdh(privHex, pubHex);
  } catch (_) {
    return null;
  }
}

String get curveImplementation => _impl;
