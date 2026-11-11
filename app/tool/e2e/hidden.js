// Fasan Split – browser side of the hidden-bill end-to-end test (test/e2e_web_hidden_test.dart is the phone). A fresh browser
// in phone size joins as „Lena“, must read bill A (she is on it, item name visible), must not see bill B (item name absent),
// and must get B after the phone put her on it. Local relay and local web server only. Screenshots in $E2E_DIR. MPL-2.0
const { chromium } = require('playwright');
const fs = require('fs');
const dir = process.env.E2E_DIR || '/tmp/fasan-e2e';
const base = process.env.E2E_BASE || 'http://localhost:8765';
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  let link = null;
  for (let i = 0; i < 420 && !link; i++) { try { link = fs.readFileSync(dir + '/link.txt', 'utf8').trim(); } catch (_) { await sleep(1000); } }
  if (!link) { console.log('FAIL kein Link'); process.exit(1); }
  const url = link.replace('https://fasan-app.github.io', base);
  const b = await chromium.launch();
  const ctx = await b.newContext({ locale: 'de-DE', viewport: { width: 393, height: 873 }, deviceScaleFactor: 2 });
  await ctx.addInitScript(() => localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ me: 'Lena' }))));
  // never anything to foreign services (Beschluss 02.11.)
  await ctx.route(/^https?:\/\/(?!localhost|127\.0\.0\.1)/, r => r.abort());
  if (ctx.routeWebSocket) await ctx.routeWebSocket(/^wss?:\/\/(?!127\.0\.0\.1|localhost)/, ws => ws.close());
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', e => { errs.push(String(e).slice(0, 200)); console.log('PAGEERROR', String(e)); });
  const shot = n => { console.log('SHOT', n, 'errors so far', errs.length); return p.screenshot({ path: `${dir}/hidden-${n}.png` }); };
  const click = async name => { await p.getByRole('button', { name }).first().click({ timeout: 20000 }); await p.waitForTimeout(1500); };
  const later = async () => { await p.getByRole('button', { name: /^(Nicht jetzt|Not now)$/ }).first().click({ timeout: 8000 }).catch(() => {}); await p.waitForTimeout(800); };
  const has = t => p.getByText(t).or(p.getByLabel(t)).count();
  const waitFor = async (t, s) => { for (let i = 0; i < s && (await has(t)) === 0; i++) await p.waitForTimeout(1000); return (await has(t)) > 0; };
  const result = {};
  try {
    await p.goto(url);
    await p.waitForTimeout(15000);
    await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await p.waitForTimeout(1500);
    await click(/^(Beitreten|Verbinden|Beitritt anfragen)$/);
    await click('Verstanden, teilen');
    await later();
    await click('Zur Gruppe');
    fs.writeFileSync(dir + '/joined.txt', 'ok');
    result.seesA = await waitFor('Versteckt-A', 90);
    await shot('1-gruppe');
    result.bAbsent = (await has('Versteckt-B')) === 0 && (await has('Geheimposten')) === 0;
    // bill C is „nur Beträge“: sums arrive as a nameless bill („•••“), the purpose and the item name never do
    for (let i = 0; i < 60 && (await has('•••')) === 0; i++) await p.waitForTimeout(1000);
    result.sumsOnly = (await has('•••')) > 0 && (await has('Versteckt-C')) === 0 && (await has('Sparposten')) === 0;
    await shot('1b-nur-betraege');
    if (result.seesA) {
      await p.getByText('Versteckt-A').or(p.getByLabel('Versteckt-A')).first().click({ timeout: 20000 });
      await p.waitForTimeout(2500);
      result.itemA = await waitFor('Cocktail Aqua', 20);
      await shot('2-bon-a');
      await p.keyboard.press('Escape');
      await p.getByRole('button', { name: /Zurück|Back/ }).first().click({ timeout: 5000 }).catch(() => {});
      await p.waitForTimeout(1500);
    }
    fs.writeFileSync(dir + '/a-seen.txt', 'ok');
    // the phone puts Lena on B now: key and bill must arrive in the browser
    result.seesB = await waitFor('Versteckt-B', 90);
    await shot('3-gruppe-mit-b');
    if (result.seesB) {
      await p.getByText('Versteckt-B').or(p.getByLabel('Versteckt-B')).first().click({ timeout: 20000 });
      await p.waitForTimeout(2500);
      result.itemB = await waitFor('Geheimposten', 20);
      await shot('4-bon-b');
    }
    // web = app: the same hide dialog as on the phone. Bill D is visible for all; Lena hides it, amounts stay visible.
    await p.keyboard.press('Escape');
    await p.getByRole('button', { name: /Zurück|Back/ }).first().click({ timeout: 5000 }).catch(() => {});
    await p.waitForTimeout(1500);
    result.seesD = await waitFor('Sichtbar-D', 60);
    if (result.seesD) {
      await p.getByText('Sichtbar-D').or(p.getByLabel('Sichtbar-D')).first().click({ timeout: 20000 });
      await p.waitForTimeout(2500);
      await p.getByRole('button', { name: /Mehr|More/ }).first().click({ timeout: 10000 });
      await p.waitForTimeout(1000);
      const entry = p.getByRole('menuitem', { name: /Sichtbar für alle in der Gruppe/ }).first();
      result.entryEnabled = (await entry.count()) > 0 && !(await entry.isDisabled().catch(() => true));
      await shot('5-menue-sichtbarkeit');
      await entry.click({ timeout: 10000 });
      await p.waitForTimeout(1500);
      result.dialog = (await has('Nur für Beteiligte?')) > 0 && (await has('Beträge für alle sichtbar lassen')) > 0;
      await shot('6-dialog');
      await p.getByRole('checkbox', { name: /Beträge für alle sichtbar lassen/ }).first().click({ timeout: 10000 });
      await p.waitForTimeout(500);
      await shot('7-dialog-haken');
      await p.getByRole('button', { name: /^Nur Beteiligte$/ }).first().click({ timeout: 10000 });
      await p.waitForTimeout(1500);
      result.done = await waitFor('Jetzt sehen nur die Beteiligten', 10);
      await shot('8-verborgen');
    }
    fs.writeFileSync(dir + '/d-done.txt', 'ok');
  } catch (e) { console.log('FAIL', String(e).slice(0, 300)); await shot('fail'); }
  fs.writeFileSync(dir + '/hidden-done.txt', JSON.stringify(result));
  const ok = result.seesA && result.bAbsent && result.itemA && result.sumsOnly && result.seesB && result.itemB && result.seesD && result.entryEnabled && result.dialog && result.done && errs.length === 0;
  console.log(`${ok ? 'OK' : 'FAIL'} ${JSON.stringify(result)} · Fehler: ${errs.join(' | ') || 'keine'}`);
  await b.close();
  process.exit(ok ? 0 : 1);
})();
