// Fasan Split – runs the in-app performance test (Einstellungen → Leistungstest) in a browser engine and saves the exported
// report. Engines: BROWSER=webkit (iPhone profile, Safari engine, not a real iPhone), chromium (Android-like phone profile), firefox.
// Playwright's engines are not the real devices: the numbers are comparison values; the real values come from the in-app export
// on the device itself. Local web server only, nothing goes to foreign services. MPL-2.0
const { webkit, chromium, firefox } = require('playwright');
const fs = require('fs');
const base = process.env.E2E_BASE || 'http://localhost:8765';
const dir = process.env.E2E_DIR || '/tmp/fasan-perf';
fs.mkdirSync(dir, { recursive: true });
const name = process.env.BROWSER || 'webkit';
const engine = { webkit, chromium, firefox }[name];
const profile = name === 'webkit'
  ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1' }
  : name === 'chromium'
    ? { viewport: { width: 360, height: 780 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true }
    : { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: true };
(async () => {
  const b = await engine.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
  const ctx = await b.newContext({ ...profile, locale: 'de-DE', acceptDownloads: true });
  await ctx.addInitScript(() => { localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ onboarded: true, me: 'Lena' }))); });
  await ctx.route(/^https?:\/\/(?!localhost|127\.0\.0\.1)/, (r) => r.abort()); // Beschluss 02.11.
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', (e) => errs.push(String(e).slice(0, 200)));
  const out = { engine: name };
  try {
    await p.goto(base + '/Fasan-Split/' + (process.env.QUERY || ''));
    await p.waitForTimeout(8000); // first visit: the service worker reloads once
    await p.waitForSelector('flt-glass-pane, flutter-view, canvas', { state: 'attached', timeout: 120000 });
    await p.waitForTimeout(3000);
    await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await p.waitForTimeout(1500);
    for (const n of [/^(Überspringen|Skip)$/, /^(Los geht|Loslegen|Weiter)/]) { const x = p.getByText(n).first(); if (await x.count()) { await x.click().catch(() => {}); await p.waitForTimeout(800); } }
    // Einstellungen live in the own profile since 11.11. (avatar top right, then the gear); the old top-level button is gone
    const gear = p.getByRole('button', { name: /^(Einstellungen|Settings)$/ });
    if (!(await gear.count())) { await p.getByRole('button', { name: /^(Profil|Profile)/ }).first().click({ timeout: 20000 }); await p.waitForTimeout(1200); }
    await gear.first().click({ timeout: 20000 });
    await p.waitForTimeout(1500);
    await p.screenshot({ path: `${dir}/${name}-1-settings.png` });
    // since the settings got sections (11.11.) the test sits under „Diagnose“
    const diag = p.getByText(/^(Diagnose|Diagnostics)$/).first();
    if (await diag.count()) { await diag.click({ timeout: 20000 }); await p.waitForTimeout(1200); }
    const t = p.getByText(/^(Leistungstest|Performance test)/).first();
    for (let i = 0; i < 30 && !(await t.count()); i++) { await p.evaluate(() => { for (const e of document.querySelectorAll('flt-semantics')) if (e.scrollHeight > e.clientHeight + 50 && getComputedStyle(e).overflowY !== 'visible') e.scrollTop += 600; }); await p.waitForTimeout(500); }
    await p.screenshot({ path: `${dir}/${name}-1b-settings-found.png` });
    await t.click({ timeout: 20000 });
    await p.waitForTimeout(1000);
    await p.getByText(/^(Test starten|Start test)$/).first().click({ timeout: 20000 });
    const t0 = Date.now();
    await p.waitForTimeout(35000);
    await p.screenshot({ path: `${dir}/${name}-2-running.png` });
    await p.getByText(/^(Noch einmal|Run again)$/).first().waitFor({ timeout: 400000 });
    out.testMs = Date.now() - t0;
    await p.screenshot({ path: `${dir}/${name}-3-done.png` });
    const [dl] = await Promise.all([p.waitForEvent('download', { timeout: 30000 }), p.getByText(/^(Speichern|Save)$/).first().click()]);
    await dl.saveAs(`${dir}/${name}-report.json`);
    out.report = JSON.parse(fs.readFileSync(`${dir}/${name}-report.json`, 'utf8'));
  } catch (e) { out.fail = String(e).slice(0, 400); }
  out.errors = errs.slice(0, 5);
  fs.writeFileSync(`${dir}/${name}-result.json`, JSON.stringify(out, null, 1));
  console.log(JSON.stringify(out.report ? { engine: name, testMs: out.testMs, geraet: out.report.geraet, phasen: out.report.phasen.map((x) => ({ p: x.phase, fps: x.fps, med: x.median, p95: x.p95, max: x.laengster, u33: x.ueber33, u100: x.ueber100 })) } : out));
  await b.close();
})();
