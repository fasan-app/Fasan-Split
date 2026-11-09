// Runs the official vectors against web_extra/fasan-curve.js: BIP-340 (test/data/bip340.csv: keys, signatures with aux, verification
// incl. the invalid cases) and NIP-44 v2 conversation keys (test/data/nip44.json). Exit code 1 on any difference. MPL-2.0
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
require(path.join(__dirname, '../../web_extra/fasan-curve.js'));
const c = globalThis.fasanCurve;
let bad = 0, n = 0;
const eq = (name, got, want) => { n++; if (got !== want) { bad++; console.log('FAIL', name, '\n  got ', got, '\n  want', want); } };

const rows = fs.readFileSync(path.join(__dirname, '../../test/data/bip340.csv'), 'utf8').split('\n').slice(1).filter(Boolean).map((l) => l.split(','));
for (const r of rows) {
  const [idx, sk, pk, aux, msg, sig, ok] = [r[0], r[1].toLowerCase(), r[2].toLowerCase(), r[3].toLowerCase(), r[4].toLowerCase(), r[5].toLowerCase(), r[6] === 'TRUE'];
  if (sk) {
    eq(`bip340 #${idx} pubkey`, c.pubkey(sk), pk);
    eq(`bip340 #${idx} sign`, c.sign(msg, sk, aux), sig);
  }
  let got;
  try { got = c.verify(msg, sig, pk); } catch (e) { got = false; }
  eq(`bip340 #${idx} verify`, got, ok);
}
const v2 = JSON.parse(fs.readFileSync(path.join(__dirname, '../../test/data/nip44.json'), 'utf8')).v2.valid;
for (const x of v2.get_conversation_key) {
  const shared = c.ecdh(x.sec1, x.pub2);
  const key = crypto.createHmac('sha256', 'nip44-v2').update(Buffer.from(shared, 'hex')).digest('hex');
  eq(`nip44 conversation key ${x.sec1.slice(0, 8)}`, key, x.conversation_key);
}
// the known answers curve_web.dart uses for its self-check
const priv = crypto.createHash('sha256').update('k1').digest('hex'), other = crypto.createHash('sha256').update('k2').digest('hex'), msg = crypto.createHash('sha256').update('m').digest('hex');
eq('known sig', c.sign(msg, priv, '00'.repeat(32)), '2f7b0c41fd5c6b9a54024368550c485c3547fe2aaf62408d84c532bfe1ad2b400398a670a022be75077ee78fe6fce9573ceaf9d3e35694ccbcb4a807fdb92703');
eq('known ecdh', c.ecdh(priv, c.pubkey(other)), 'f41f4fa203ebb11543e9e44753529a01d9a06f11a4020b8d7421729d57cf5736');
console.log(`${n} Prüfungen, ${bad} Abweichungen (${c.version})`);
process.exit(bad ? 1 : 0);
