// SPDX-License-Identifier: MPL-2.0
// Fasan Split – fast secp256k1 (Schnorr, ECDH) in the browser, see curve_web.dart; elsewhere the pointycastle code in crypto.dart. MPL-2.0
export 'curve_stub.dart' if (dart.library.js_interop) 'curve_web.dart';
