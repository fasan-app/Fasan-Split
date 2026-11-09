// SPDX-License-Identifier: MPL-2.0
// Fasan Split – phone and tests: no fast path, crypto.dart does the curve work with pointycastle (12 ms per signature check in native
// Dart, measured 08.11.). MPL-2.0

/// Loads nothing here.
Future<void> loadFastCurve() async {}

/// Null: not available, the caller computes it itself.
bool? fastVerify(String msgHex, String sigHex, String pubHex) => null;
String? fastSign(String msgHex, String privHex, String auxHex) => null;
String? fastEcdh(String privHex, String pubHex) => null;

/// For the performance report: which curve code runs.
String get curveImplementation => 'pointycastle';
