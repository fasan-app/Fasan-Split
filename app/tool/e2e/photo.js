// Fasan Split – browser side of the shared-photo end-to-end test (test/e2e_web_photo_test.dart is the phone). A fresh
// browser in phone size joins with the link from $E2E_DIR/link.txt, opens the bill „Foto-Test“ and must get the scan, the
// original and the line pictures from the group: line pictures under the items, the ⋮ menu with all entries enabled, the
// receipt with Scan / Original / Digital. Screenshots in $E2E_DIR. Local relay and local web server only. MPL-2.0
const { chromium } = require('playwright');
const fs = require('fs');
const dir = process.env.E2E_DIR || '/tmp/fasan-e2e';
const base = process.env.E2E_BASE || 'http://localhost:8765';
(async () => {
  let link = null;
  for (let i = 0; i < 420 && !link; i++) { try { link = fs.readFileSync(dir + '/link.txt', 'utf8').trim(); } catch (_) { await new Promise(r => setTimeout(r, 1000)); } }
  if (!link) { console.log('FAIL kein Link'); process.exit(1); }
  const url = link.replace('https://fasan-app.github.io', base);
  const b = await chromium.launch();
  const ctx = await b.newContext({ locale: 'de-DE', viewport: { width: 393, height: 873 }, deviceScaleFactor: 2 });
  await ctx.addInitScript(() => localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ me: 'Lena' }))));
  // never anything to foreign services (Beschluss 02.11.): only the local relay and the local server
  await ctx.route(/^https?:\/\/(?!localhost|127\.0\.0\.1)/, r => r.abort());
  if (ctx.routeWebSocket) await ctx.routeWebSocket(/^wss?:\/\/(?!127\.0\.0\.1|localhost)/, ws => ws.close());
  const p = await ctx.newPage();
  const throttle = Number(process.env.THROTTLE || 1);
  if (throttle > 1) await (await ctx.newCDPSession(p)).send('Emulation.setCPUThrottlingRate', { rate: throttle });
  // frame times over a period (Prüfliste G2/G6): fps, median, 90th percentile, worst
  const frames = async (ms, act) => {
    await p.evaluate(ms => { window.__d = []; let last = performance.now(); const end = last + ms; (function f(t) { window.__d.push(t - last); last = t; if (t < end) requestAnimationFrame(f); else window.__done = true; })(last); window.__done = false; }, ms);
    if (act) await act();
    await p.waitForFunction(() => window.__done, null, { timeout: 60000 });
    const d = await p.evaluate(() => window.__d), q = [...d].sort((a, b) => a - b);
    const at = r => Math.round(q[Math.floor((q.length - 1) * r)]);
    return { fps: Math.round(d.length / (ms / 1000)), p50: at(0.5), p90: at(0.9), max: at(1) };
  };
  const errs = [];
  p.on('pageerror', e => { errs.push(String(e).slice(0, 200)); console.log('PAGEERROR', String(e)); });
  const t0 = Date.now();
  await p.goto(url);
  await p.waitForTimeout(15000); // first visit: coi-serviceworker reloads once, then Flutter starts
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(1500);
  const shot = (n) => p.screenshot({ path: `${dir}/photo-${n}.png` });
  const click = async (name) => { await p.getByRole('button', { name }).first().click({ timeout: 20000 }); await p.waitForTimeout(1500); };
  const later = async () => { await p.getByRole('button', { name: /^(Nicht jetzt|Not now)$/ }).first().click({ timeout: 8000 }).catch(() => {}); await p.waitForTimeout(800); };
  const result = {};
  try {
    await click(/^(Beitreten|Verbinden|Beitritt anfragen)$/);
    await click('Verstanden, teilen');
    await later(); // the one-time notification question
    await click('Zur Gruppe');
    for (let i = 0; i < 60 && (await p.getByText('Foto-Test').or(p.getByLabel('Foto-Test')).count()) === 0; i++) await p.waitForTimeout(1000);
    await shot('1-gruppe');
    await p.getByText('Foto-Test').or(p.getByLabel('Foto-Test')).first().click({ timeout: 20000 });
    await p.waitForTimeout(2500);
    await shot('2-bon-frisch');
    // the photo comes in pieces: wait until the menu entries are enabled (line pictures and receipt need the scan)
    let ready = false;
    for (let i = 0; i < 90 && !ready; i++) {
      await p.getByRole('button', { name: /Mehr|More/ }).first().click({ timeout: 10000 }).catch(() => {});
      await p.waitForTimeout(800);
      const item = p.getByRole('menuitem', { name: /Am Original zuordnen/ }).first();
      ready = (await item.count()) > 0 && !(await item.isDisabled().catch(() => true));
      if (!ready) { await p.keyboard.press('Escape'); await p.waitForTimeout(1500); }
    }
    result.secondsToPhoto = Math.round((Date.now() - t0) / 1000);
    await shot('3-menue');
    result.menuEntries = await p.getByRole('menuitem').count();
    // switch the line pictures on, if they are off
    const snip = p.getByRole('menuitemcheckbox', { name: /Bon-Ausschnitte/ }).first();
    if ((await snip.count()) > 0 && (await snip.getAttribute('aria-checked')) !== 'true') { await snip.click(); await p.waitForTimeout(1500); }
    else await p.keyboard.press('Escape');
    await p.waitForTimeout(1000);
    await shot('4-ausschnitte');
    result.throttle = throttle;
    result.billIdle = await frames(3000);
    result.billScroll = await frames(2500, async () => { await p.mouse.move(200, 600); await p.mouse.wheel(0, 700); });
    await click('Bon');
    await p.waitForTimeout(2000);
    result.layers = { scan: await p.getByRole('button', { name: 'Scan' }).count(), original: await p.getByRole('button', { name: 'Original' }).count(), digital: await p.getByRole('button', { name: 'Digital' }).count() };
    await shot('5-scan');
    if (result.layers.original) { await click('Original'); await p.waitForTimeout(1500); await shot('6-original'); }
    if (result.layers.digital) { await click('Digital'); await p.waitForTimeout(1000); await shot('7-digital'); }
    result.ready = ready;
    // reload: the photos now come from IndexedDB, loaded only when shown (images_web.dart, 06.11.)
    const t1 = Date.now();
    await p.reload();
    await p.waitForTimeout(12000);
    await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await p.waitForTimeout(1500);
    for (let i = 0; i < 30 && (await p.getByText('Foto-Test').or(p.getByLabel('Foto-Test')).count()) === 0; i++) await p.waitForTimeout(1000);
    await p.getByText('Foto-Test').or(p.getByLabel('Foto-Test')).first().click({ timeout: 20000 });
    await p.waitForTimeout(2500);
    await shot('8-nach-neustart');
    await click('Bon');
    await p.waitForTimeout(2500);
    result.afterReload = { scan: await p.getByRole('button', { name: 'Scan' }).count(), seconds: Math.round((Date.now() - t1) / 1000) };
    await shot('9-scan-nach-neustart');
  } catch (e) { console.log('FAIL', String(e).slice(0, 300)); await shot('fail'); }
  fs.writeFileSync(dir + '/photo-done.txt', JSON.stringify(result));
  const ok = result.ready && result.layers && result.layers.scan && result.layers.original && result.layers.digital && result.afterReload && result.afterReload.scan && errs.length === 0
    // frame budget (Prüfliste G6, coarse because CI runners vary): idle at least 20 fps, median frame ≤ 50 ms while scrolling
    && result.billIdle.fps >= 20 && result.billScroll.p50 <= 50;
  console.log(`${ok ? 'OK' : 'FAIL'} ${JSON.stringify(result)} · Fehler: ${errs.join(' | ') || 'keine'}`);
  await b.close();
  process.exit(ok ? 0 : 1);
})();
