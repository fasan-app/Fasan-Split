// Fasan Split – scanning in the browser, timed (Punkt 4, Nutzer 06.11.: Leistung auch auf 10 Jahre alten Geräten). A fresh
// browser opens the app, chooses a photo (FASAN_FILE) and waits for the result; reports start, time to the result and the
// frame times while it runs. THROTTLE = CPU slowdown (4 ≈ an old phone). Local web server only. MPL-2.0
const { chromium } = require('playwright');
const base = process.env.E2E_BASE || 'http://localhost:8765';
const file = process.env.FASAN_FILE, th = Number(process.env.THROTTLE || 1), dir = process.env.E2E_DIR || '/tmp';
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ locale: 'de-DE', viewport: { width: 393, height: 873 }, deviceScaleFactor: 2 });
  await ctx.addInitScript(() => localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ me: 'Chris' }))));
  await ctx.route(/^https?:\/\/(?!localhost|127\.0\.0\.1)/, r => r.abort());
  const p = await ctx.newPage();
  if (th > 1) await (await ctx.newCDPSession(p)).send('Emulation.setCPUThrottlingRate', { rate: th });
  const errs = []; p.on('pageerror', e => errs.push(String(e).slice(0, 160)));
  p.on('console', m => { if (/recogni|worker|ort/i.test(m.text()) && m.type() === 'error') errs.push(m.text().slice(0, 160)); });
  const t0 = Date.now();
  await p.goto(base + '/Fasan-Split/');
  await p.waitForTimeout(12000);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(1500);
  const shot = n => p.screenshot({ path: `${dir}/scan-${n}.png` });
  await shot('1-start');
  const r = { throttle: th, startSeconds: Math.round((Date.now() - t0) / 1000) };
  try {
    // skip the intro if it shows
    for (const name of [/^(Überspringen|Skip)$/, /^(Los geht|Loslegen|Weiter)/]) { const x = p.getByText(name).first(); if (await x.count()) { await x.click().catch(() => {}); await p.waitForTimeout(800); } }
    await p.getByRole('button', { name: /^(Neuer Bon|Hinzufügen)$/ }).first().click({ timeout: 15000 }).catch(async () => { await p.mouse.click(340, 800); });
    await p.waitForTimeout(1200);
    const [fc] = await Promise.all([p.waitForEvent('filechooser', { timeout: 15000 }), p.getByText(/Galerie \/ Datei/).first().click()]);
    const t1 = Date.now();
    await fc.setFiles(file);
    await p.evaluate(() => { window.__d = []; let last = performance.now(); (function f(t) { window.__d.push(t - last); last = t; if (!window.__stop) requestAnimationFrame(f); })(last); });
    let done = false;
    for (let i = 0; i < 400 && !done; i++) {
      await p.waitForTimeout(1000);
      if (i === 5) await shot('2-lauft');
      done = (await p.getByText(/Summe|Total/).count()) > 0 && (await p.getByText(/Posten|Items/).count()) > 0 && (await p.getByRole('button', { name: /Weiter|Fertig|Speichern|Save|Done/ }).count()) > 0;
    }
    r.scanSeconds = Math.round((Date.now() - t1) / 1000); r.done = done;
    await p.evaluate(() => { window.__stop = true; });
    const d = await p.evaluate(() => window.__d), q = [...d].sort((a, c) => a - c);
    r.frames = { n: d.length, p50: Math.round(q[Math.floor(q.length * 0.5)]), p90: Math.round(q[Math.floor(q.length * 0.9)]), max: Math.round(q[q.length - 1]) };
    await shot('3-ergebnis');
  } catch (e) { r.fail = String(e).slice(0, 200); await shot('fail'); }
  r.errors = errs.slice(0, 3);
  console.log('RESULT ' + JSON.stringify(r));
  await b.close();
})();
