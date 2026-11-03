// Fasan Split – identity: key pair on the device, 12-word recovery phrase (NIP-06), secure storage. MPL-2.0
//
// NIP-06: BIP-39 mnemonic → seed → BIP-32 path m/44'/1237'/0'/0/0 → secp256k1 private key. Test vector from nips/06.md.
// The key never leaves the device. Without the 12 words (or a backup) a lost phone means a lost account; the groups stay with the others.
import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import 'crypto.dart';

final ECDomainParameters _secp = ECCurve_secp256k1();

Uint8List _hmac512(List<int> key, List<int> data) {
  final h = HMac(SHA512Digest(), 128)..init(KeyParameter(Uint8List.fromList(key)));
  return h.process(Uint8List.fromList(data));
}

BigInt _big(List<int> b) => b.fold(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));

Uint8List _b32(BigInt v) {
  final out = Uint8List(32);
  var x = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (x & BigInt.from(255)).toInt();
    x >>= 8;
  }
  return out;
}

/// Private key at BIP-32 [path] (indices; add 0x80000000 for hardened) from [seed].
Uint8List bip32Derive(Uint8List seed, List<int> path) {
  var i = _hmac512(utf8.encode('Bitcoin seed'), seed);
  var key = _big(i.sublist(0, 32));
  var chain = i.sublist(32);
  for (final idx in path) {
    final data = <int>[];
    if (idx >= 0x80000000) {
      data..add(0)..addAll(_b32(key));
    } else {
      final pt = (_secp.G * key)!;
      data
        ..add(pt.y!.toBigInteger()!.isOdd ? 3 : 2)
        ..addAll(_b32(pt.x!.toBigInteger()!));
    }
    data.addAll([(idx >> 24) & 255, (idx >> 16) & 255, (idx >> 8) & 255, idx & 255]);
    i = _hmac512(chain, data);
    final il = _big(i.sublist(0, 32));
    if (il >= _secp.n) throw StateError('invalid child key');
    key = (il + key) % _secp.n;
    if (key == BigInt.zero) throw StateError('invalid child key');
    chain = i.sublist(32);
  }
  return _b32(key);
}

const int _h = 0x80000000;

/// NIP-06 key for [account] from a BIP-39 [mnemonic] (no passphrase).
KeyPair keyFromMnemonic(String mnemonic, {int account = 0}) {
  final words = mnemonic.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
  if (!bip39.validateMnemonic(words)) throw const FormatException('invalid recovery phrase');
  final seed = bip39.mnemonicToSeed(words);
  return KeyPair.fromPrivate(toHex(bip32Derive(seed, [44 + _h, 1237 + _h, account + _h, 0, 0])));
}

String newMnemonic() => bip39.generateMnemonic(); // 128 bit = 12 words

/// Where the secrets live. Android Keystore-backed on the phone; memory in tests.
abstract class Vault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryVault implements Vault {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

class SecureVault implements Vault {
  const SecureVault();
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Our identity: key pair, display name and (if made here) the recovery phrase.
class Identity {
  Identity(this.key, this.name, {this.mnemonic});

  final KeyPair key;
  String name;
  final String? mnemonic;

  String get pub => key.pub;

  static const _kKey = 'fasan.identity.priv', _kName = 'fasan.identity.name', _kWords = 'fasan.identity.words';

  /// Loads the stored identity; creates one (with a new 12-word phrase) on first use.
  static Future<Identity> loadOrCreate(Vault v, {String defaultName = ''}) async {
    final priv = await v.read(_kKey);
    if (priv != null) {
      return Identity(KeyPair.fromPrivate(priv), await v.read(_kName) ?? defaultName, mnemonic: await v.read(_kWords));
    }
    final words = newMnemonic();
    final id = Identity(keyFromMnemonic(words), defaultName, mnemonic: words);
    await id.save(v);
    return id;
  }

  /// Restores from 12 words (throws [FormatException] for a wrong phrase) and stores it.
  static Future<Identity> restore(Vault v, String words, {String name = ''}) async {
    final id = Identity(keyFromMnemonic(words), name, mnemonic: words.trim().toLowerCase().split(RegExp(r'\s+')).join(' '));
    await id.save(v);
    return id;
  }

  Future<void> save(Vault v) async {
    await v.write(_kKey, key.priv);
    await v.write(_kName, name);
    if (mnemonic != null) {
      await v.write(_kWords, mnemonic!);
    } else {
      await v.delete(_kWords);
    }
  }
}
