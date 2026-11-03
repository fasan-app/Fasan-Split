// Fasan Split – cryptography for collaboration: BIP-340 Schnorr signatures, NIP-44 v2 encryption, group AEAD. MPL-2.0
//
// Built on pointycastle (secp256k1, ChaCha20, Poly1305, HMAC, SHA-256; MIT/BSD). Formats follow the published specifications:
// - BIP-340 (bips.xyz/340): x-only public keys, tagged hashes, Schnorr signatures.
// - NIP-44 v2 (nips/44.md): secp256k1 ECDH x-coordinate, HKDF-SHA256 (salt „nip44-v2“), padding, ChaCha20 (RFC 8439), HMAC-SHA256.
// - Group content: ChaCha20-Poly1305 (RFC 8439) with a random 256-bit group key and a random 96-bit nonce per message.
// Checked against the official test vectors (test/crypto_test.dart). NOT independently audited (Beschluss: dritte Prüfung vor „sicher“).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

final ECDomainParameters _secp = ECCurve_secp256k1();
final BigInt _n = _secp.n;
// field prime of secp256k1: 2^256 − 2^32 − 977
final BigInt _p = BigInt.parse('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F', radix: 16);

final math.Random _rng = math.Random.secure();

Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

// ---- small helpers ----

Uint8List sha256(List<int> data) => SHA256Digest().process(Uint8List.fromList(data));

Uint8List hmacSha256(List<int> key, List<int> data) {
  final h = HMac(SHA256Digest(), 64)..init(KeyParameter(Uint8List.fromList(key)));
  return h.process(Uint8List.fromList(data));
}

String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String s) {
  if (s.length.isOdd) throw const FormatException('hex length');
  return Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
}

BigInt _int(List<int> b) => b.fold(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));

Uint8List _bytes32(BigInt v) {
  final out = Uint8List(32);
  var x = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
  }
  return out;
}

Uint8List _concat(List<List<int>> parts) => Uint8List.fromList([for (final p in parts) ...p]);

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}

// ---- secp256k1 / BIP-340 ----

Uint8List _taggedHash(String tag, List<int> data) {
  final t = sha256(utf8.encode(tag));
  return sha256(_concat([t, t, data]));
}

ECPoint _mulG(BigInt k) => (_secp.G * k)!;

bool _hasEvenY(ECPoint p) => !p.y!.toBigInteger()!.isOdd;

/// Point with even y and the given x (BIP-340 lift_x), or null if x is not on the curve.
ECPoint? _liftX(BigInt x) {
  if (x >= _p) return null;
  final c = (x.modPow(BigInt.from(3), _p) + BigInt.from(7)) % _p;
  final y = c.modPow((_p + BigInt.one) >> 2, _p);
  if (y.modPow(BigInt.two, _p) != c) return null;
  final even = y.isEven ? y : _p - y;
  return _secp.curve.createPoint(x, even);
}

/// A secp256k1 key pair; [pub] is the 32-byte x-only public key (BIP-340), both as lower-case hex.
class KeyPair {
  KeyPair._(this.priv, this.pub);

  final String priv;
  final String pub;

  static KeyPair fromPrivate(String privHex) {
    final d = _int(fromHex(privHex));
    if (d <= BigInt.zero || d >= _n) throw const FormatException('private key out of range');
    return KeyPair._(privHex.toLowerCase(), toHex(_bytes32(_mulG(d).x!.toBigInteger()!)));
  }

  static KeyPair generate() {
    while (true) {
      final d = _int(randomBytes(32));
      if (d > BigInt.zero && d < _n) return fromPrivate(toHex(_bytes32(d)));
    }
  }
}

/// BIP-340 signature of a 32-byte [msg]. [aux] is 32 bytes of randomness (default random).
String schnorrSign(Uint8List msg, String privHex, {Uint8List? aux}) {
  var d = _int(fromHex(privHex));
  final pt = _mulG(d);
  if (!_hasEvenY(pt)) d = _n - d;
  final px = _bytes32(pt.x!.toBigInteger()!);
  final a = aux ?? randomBytes(32);
  final t = Uint8List.fromList(List<int>.generate(32, (i) => _bytes32(d)[i] ^ _taggedHash('BIP0340/aux', a)[i]));
  final rand = _taggedHash('BIP0340/nonce', _concat([t, px, msg]));
  var k = _int(rand) % _n;
  if (k == BigInt.zero) throw StateError('nonce zero');
  final r = _mulG(k);
  if (!_hasEvenY(r)) k = _n - k;
  final rx = _bytes32(r.x!.toBigInteger()!);
  final e = _int(_taggedHash('BIP0340/challenge', _concat([rx, px, msg]))) % _n;
  final s = (k + e * d) % _n;
  return toHex(_concat([rx, _bytes32(s)]));
}

bool schnorrVerify(Uint8List msg, String sigHex, String pubHex) {
  try {
    if (sigHex.length != 128 || pubHex.length != 64) return false;
    final pk = _liftX(_int(fromHex(pubHex)));
    if (pk == null) return false;
    final sig = fromHex(sigHex);
    final r = _int(sig.sublist(0, 32)), s = _int(sig.sublist(32));
    if (r >= _p || s >= _n) return false;
    final e = _int(_taggedHash('BIP0340/challenge', _concat([sig.sublist(0, 32), fromHex(pubHex), msg]))) % _n;
    final rr = (_mulG(s) + (pk * (_n - e))!)!;
    if (rr.isInfinity) return false;
    if (!_hasEvenY(rr)) return false;
    return rr.x!.toBigInteger() == r;
  } catch (_) {
    return false;
  }
}

/// ECDH x-coordinate (32 bytes) between our private key and the other side's x-only public key (NIP-44: no hashing).
Uint8List ecdhX(String privHex, String pubHex) {
  final pt = _liftX(_int(fromHex(pubHex)));
  if (pt == null) throw const FormatException('public key not on curve');
  final d = _int(fromHex(privHex));
  if (d <= BigInt.zero || d >= _n) throw const FormatException('private key out of range');
  final s = (pt * d)!;
  return _bytes32(s.x!.toBigInteger()!);
}

// ---- NIP-44 v2 ----

Uint8List nip44ConversationKey(String privHex, String pubHex) {
  final shared = ecdhX(privHex, pubHex);
  return hmacSha256(utf8.encode('nip44-v2'), shared); // HKDF-extract
}

Uint8List hkdfExpand(Uint8List prk, Uint8List info, int length) {
  final out = <int>[];
  var prev = Uint8List(0);
  for (var i = 1; out.length < length; i++) {
    prev = hmacSha256(prk, _concat([prev, info, [i]]));
    out.addAll(prev);
  }
  return Uint8List.fromList(out.sublist(0, length));
}

int nip44PaddedLen(int len) {
  if (len <= 32) return 32;
  final nextPower = 1 << ((len - 1).bitLength);
  final chunk = nextPower <= 256 ? 32 : nextPower ~/ 8;
  return chunk * (((len - 1) ~/ chunk) + 1);
}

Uint8List _chacha20(Uint8List key, Uint8List nonce12, Uint8List data) {
  final c = ChaCha7539Engine()..init(true, ParametersWithIV(KeyParameter(key), nonce12));
  return c.process(data);
}

Uint8List _nip44Pad(String plaintext) {
  final u = utf8.encode(plaintext);
  if (u.isEmpty || u.length > 65535) throw ArgumentError('plaintext length must be 1..65535 bytes');
  final out = Uint8List(2 + nip44PaddedLen(u.length));
  out[0] = u.length >> 8;
  out[1] = u.length & 0xff;
  out.setRange(2, 2 + u.length, u);
  return out;
}

/// Encrypts with a conversation key. [nonce] is for tests only (32 random bytes otherwise).
String nip44Encrypt(String plaintext, Uint8List conversationKey, {Uint8List? nonce}) {
  final n = nonce ?? randomBytes(32);
  final keys = hkdfExpand(conversationKey, n, 76);
  final padded = _nip44Pad(plaintext);
  final ct = _chacha20(keys.sublist(0, 32), keys.sublist(32, 44), padded);
  final mac = hmacSha256(keys.sublist(44, 76), _concat([n, ct]));
  return base64.encode(_concat([[2], n, ct, mac]));
}

/// Decrypts a NIP-44 v2 payload; throws [FormatException] on any defect (version, length, MAC, padding).
String nip44Decrypt(String payload, Uint8List conversationKey) {
  if (payload.isEmpty || payload[0] == '#') throw const FormatException('unsupported version');
  final data = base64.decode(payload);
  if (data.length < 99 || data.length > 65603) throw const FormatException('invalid payload length');
  if (data[0] != 2) throw const FormatException('unsupported version');
  final n = Uint8List.fromList(data.sublist(1, 33));
  final ct = Uint8List.fromList(data.sublist(33, data.length - 32));
  final mac = data.sublist(data.length - 32);
  final keys = hkdfExpand(conversationKey, n, 76);
  if (!constantTimeEquals(hmacSha256(keys.sublist(44, 76), _concat([n, ct])), mac)) throw const FormatException('invalid MAC');
  final padded = _chacha20(keys.sublist(0, 32), keys.sublist(32, 44), ct);
  final len = (padded[0] << 8) | padded[1];
  if (len == 0 || padded.length != 2 + nip44PaddedLen(len) || 2 + len > padded.length) throw const FormatException('invalid padding');
  return utf8.decode(padded.sublist(2, 2 + len));
}

// ---- group content: ChaCha20-Poly1305 ----

/// Encrypts [plaintext] with a 32-byte group key; [aad] is authenticated but not encrypted (binds the message to its slot).
/// Output: base64(0x01 || nonce(12) || ciphertext || tag(16)).
String aeadSeal(String plaintext, Uint8List key, String aad) {
  final nonce = randomBytes(12);
  final c = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List.fromList(utf8.encode(aad))));
  final input = Uint8List.fromList(utf8.encode(plaintext));
  final out = Uint8List(c.getOutputSize(input.length));
  var n = c.processBytes(input, 0, input.length, out, 0);
  n += c.doFinal(out, n); // appends the Poly1305 tag
  return base64.encode(_concat([[1], nonce, out.sublist(0, n)]));
}

String aeadOpen(String payload, Uint8List key, String aad) {
  final data = base64.decode(payload);
  if (data.length < 1 + 12 + 16 || data[0] != 1) throw const FormatException('invalid payload');
  final nonce = Uint8List.fromList(data.sublist(1, 13));
  final c = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List.fromList(utf8.encode(aad))));
  final input = Uint8List.fromList(data.sublist(13));
  final out = Uint8List(c.getOutputSize(input.length));
  try {
    var n = c.processBytes(input, 0, input.length, out, 0);
    n += c.doFinal(out, n); // checks the tag
    return utf8.decode(out.sublist(0, n));
  } on InvalidCipherTextException {
    throw const FormatException('authentication failed');
  } on ArgumentError {
    throw const FormatException('authentication failed'); // pointycastle reports a wrong tag as ArgumentError
  }
}
