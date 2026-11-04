// Fasan Split – joiner side of the browser end-to-end test (Nutzer 04.11.: invitations must work out of the box).
// A fresh browser opens the invitation link from $E2E_DIR/link.txt, joins with the prefilled name and must land in the
// group with the bill visible, without anyone tapping „Annehmen“. Local relay and local web server only (no foreign
// services). MODE: normal | nosw (in-app browsers without service workers) | nostorage (localStorage throws).
// Exit code 0 = passed. MPL-2.0
const { chromium } = require('playwright');
const fs = require('fs');
const dir = process.env.E2E_DIR || '/tmp/fasan-e2e';
const base = process.env.E2E_BASE || 'http://localhost:8765';
const mode = process.env.MODE || 'normal';
(async () => {
  let link = null;
  for (let i = 0; i < 240 && !link; i++) { try { link = fs.readFileSync(dir + '/link.txt', 'utf8').trim(); } catch (_) { await new Promise(r => setTimeout(r, 1000)); } }
  if (!link) { console.log('FAIL kein Link'); process.exit(1); }
  const url = link.replace('https://fasan-app.github.io', base);
  const b = await chromium.launch();
  const ctx = await b.newContext({ locale: 'de-DE', viewport: { width: 412, height: 900 }, serviceWorkers: mode === 'nosw' ? 'block' : 'allow' });
  await ctx.addInitScript((m) => {
    localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ me: 'Angi' })));
    if (m === 'nostorage') for (const k of ['localStorage', 'sessionStorage']) Object.defineProperty(window, k, { get() { throw new DOMException('blocked', 'SecurityError'); } });
  }, mode);
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', e => { errs.push(String(e).slice(0, 200)); console.log('PAGEERROR', String(e), (e.stack || '').slice(0, 400)); });
  await p.goto(url);
  // first visit: coi-serviceworker reloads once, then Flutter starts
  await p.waitForTimeout(15000);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); // accessibility tree on
  await p.waitForTimeout(1500);
  const shot = (n) => p.screenshot({ path: `${dir}/${mode}-${n}.png` });
  await shot('1-join');
  const click = async (name) => { await p.getByRole('button', { name }).first().click({ timeout: 20000 }); await p.waitForTimeout(1500); };
  try {
    await click('Beitritt anfragen');
    await click('Verstanden, teilen');
  } catch (e) { console.log('FAIL Knopf fehlt', String(e).slice(0, 200)); await shot('fail'); await b.close(); process.exit(1); }
  let inGroup = false;
  for (let i = 0; i < 60 && !inGroup; i++) { await p.waitForTimeout(1000); inGroup = (await p.getByText('Pizza Napoli').count()) > 0; }
  await shot('2-group');
  console.log(`${inGroup ? 'OK' : 'FAIL'} mode=${mode} in der Gruppe mit Bon: ${inGroup} · Fehler: ${errs.join(' | ') || 'keine'}`);
  if (inGroup) fs.appendFileSync(dir + '/joined.txt', mode + '\n');
  await b.close();
  process.exit(inGroup && errs.length === 0 ? 0 : 1);
})();
