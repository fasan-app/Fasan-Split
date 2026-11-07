// Fasan Split – scan screens in the browser, to compare with test/screens_test.dart (steps sc01…sc03, Nutzer 06.11.: Web = App, Bildschirm
// für Bildschirm). Phone size; chooses the invented receipt FASAN_FILE (reads it for real in the Web Worker) and a blank picture
// FASAN_BAD (must end in the failure page). Screenshots screen-sc*.png in $E2E_DIR. Local web server only. MPL-2.0
const { chromium } = require('playwright');
const base = process.env.E2E_BASE || 'http://localhost:8765';
const dir = process.env.E2E_DIR || '/tmp/fasan-scan';
const good = process.env.FASAN_FILE, bad = process.env.FASAN_BAD;
const variant = { locale: process.env.LANG_TAG || 'de-DE', colorScheme: process.env.DARK ? 'dark' : 'light', viewport: process.env.LAND ? { width: 873, height: 393 } : { width: 393, height: 873 }, deviceScaleFactor: 2 };
(async () => {
  const b = await chromium.launch();
  const errs = [];
  const open = async () => {
    const ctx = await b.newContext(variant);
    await ctx.addInitScript(() => localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ me: 'Angi' }))));
    await ctx.route(/^https?:\/\/(?!localhost|127\.0\.0\.1)/, r => r.abort()); // nothing to foreign services (Beschluss 02.11.)
    const p = await ctx.newPage();
    p.on('pageerror', e => { errs.push(String(e).slice(0, 200)); console.log('PAGEERROR', String(e)); });
    await p.goto(base + '/Fasan-Split/');
    await p.waitForTimeout(15000); // first visit: coi-serviceworker reloads once
    await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await p.waitForTimeout(1500);
    for (const name of [/^(Überspringen|Skip)$/, /^(Los geht|Loslegen|Weiter)/]) { const x = p.getByText(name).first(); if (await x.count()) { await x.click().catch(() => {}); await p.waitForTimeout(800); } }
    return p;
  };
  const pick = async (p, file, shots) => {
    await p.getByRole('button', { name: /^(Neuer Bon|New receipt)$/ }).first().click({ timeout: 15000 });
    await p.waitForTimeout(1200);
    if (shots) await p.screenshot({ path: `${dir}/screen-sc01-neuer-bon.png` });
    const [fc] = await Promise.all([p.waitForEvent('filechooser', { timeout: 15000 }), p.getByText(/Galerie \/ Datei|Gallery \/ file/).first().click()]);
    await fc.setFiles(file);
  };
  const res = {};
  try {
    const p = await open();
    await pick(p, good, true);
    await p.waitForTimeout(3000);
    await p.screenshot({ path: `${dir}/screen-sc02-liest.png` });
    for (let i = 0; i < 300 && (await p.getByText(/Summe|Total/).count()) === 0; i++) await p.waitForTimeout(1000);
    await p.waitForTimeout(1500);
    await p.screenshot({ path: `${dir}/screen-sc04-ergebnis.png` });
    // the invented receipt must come out right: name, quantity and amount of every item, and the total (not only the sums)
    // Playwright 1.48 (CI) has no ariaSnapshot: read the labels of the semantics layer directly
    const snap = await p.evaluate(() => [...document.querySelectorAll('flt-semantics')].map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean).join('\n'));
    require('fs').writeFileSync(`${dir}/aria-sc04.txt`, snap);
    const want = ['Flammkuchen', '12,50', 'Apfelschorle', '4,20', 'Weizen', '5,40', 'Salat', '11,90', 'Espresso', '5,60', '39,60', 'Posten · 5', '2 ×'];
    res.missing = want.filter(w => !snap.includes(w));
    res.good = res.missing.length === 0;
    if (bad) {
      const q = await open();
      await pick(q, bad, false);
      for (let i = 0; i < 120 && (await q.getByText(/ließ sich nicht lesen|could not be read/).count()) === 0; i++) await q.waitForTimeout(1000);
      await q.waitForTimeout(800);
      await q.screenshot({ path: `${dir}/screen-sc03-fehler.png` });
      // a blank picture ends in the failure page or in an empty bill, never in invented items
      res.bad = (await q.getByText(/ließ sich nicht lesen|could not be read/).count()) > 0 || (await q.getByText(/Posten · 0|Items · 0/).count()) > 0;
    }
  } catch (e) { res.fail = String(e).slice(0, 300); }
  res.errors = errs.slice(0, 3);
  console.log('RESULT ' + JSON.stringify(res));
  await b.close();
  process.exit(res.good && res.bad && !res.fail ? 0 : 1);
})();
