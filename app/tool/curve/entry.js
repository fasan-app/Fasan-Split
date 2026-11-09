// Fasan Split – fast secp256k1 for the browser: BIP-340 Schnorr and ECDH on @noble/curves (MIT, Paul Miller; audited), made with
// the native JS BigInt. The Dart code (pointycastle) is 100+ ms per call in the browser and blocks the screen; the same call here
// takes milliseconds. Bundled with esbuild, see docs/WEB-GRENZEN.md. Hex strings in, hex strings out. MPL-2.0 for this wrapper.
import { schnorr, secp256k1 } from '@noble/curves/secp256k1.js';

const hex = (u) => Array.from(u, (b) => b.toString(16).padStart(2, '0')).join('');
const bytes = (h) => Uint8Array.from(h.match(/../g) || [], (x) => parseInt(x, 16));

globalThis.fasanCurve = {
  version: '@noble/curves 2.4.0',
  verify: (msgHex, sigHex, pubHex) => {
    try { return schnorr.verify(bytes(sigHex), bytes(msgHex), bytes(pubHex)); } catch (e) { return false; }
  },
  sign: (msgHex, privHex, auxHex) => hex(schnorr.sign(bytes(msgHex), bytes(privHex), bytes(auxHex))),
  ecdh: (privHex, pubHex) => hex(secp256k1.getSharedSecret(bytes(privHex), bytes('02' + pubHex)).slice(1, 33)),
  pubkey: (privHex) => hex(schnorr.getPublicKey(bytes(privHex))),
};
