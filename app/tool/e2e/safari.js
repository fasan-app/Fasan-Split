// Fasan Split – the browser app in WebKit (the engine of every iPhone browser) with an iPhone profile (Nutzer 08.11.: Safari and
// iPhone are a large part of the users and were never tested; operation there is slow). Measures start time, which build is used
// (wasm or JavaScript), cross-origin isolation, and the frame times (requestAnimationFrame) while idle and during taps.
// Playwright's WebKit is not iOS: it shows engine problems, not the speed of a real iPhone (the numbers are comparison values,
// not iPhone values). Local web server only, nothing goes to foreign services. MPL-2.0
const { webkit, chromium, firefox, devices } = require('playwright');
const base = process.env.E2E_BASE || 'http://localhost:8765';
const dir = process.env.E2E_DIR || '/tmp/fasan-safari';
const engine = process.env.BROWSER === 'chromium' ? chromium : process.env.BROWSER === 'firefox' ? firefox : webkit;
const profile = process.env.BROWSER === 'firefox' ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: true } : process.env.BROWSER === 'chromium' ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true } : devices[process.env.DEVICE || 'iPhone 13'];
const fs = require('fs');
fs.mkdirSync(dir, { recursive: true });
const stats = (a) => {
  if (!a.length) return { n: 0 };
  const s = [...a].sort((x, y) => x - y), q = (p) => +s[Math.min(s.length - 1, Math.floor(p * s.length))].toFixed(1);
  return { n: a.length, p50: q(0.5), p95: q(0.95), max: +s[s.length - 1].toFixed(1), over50: a.filter((x) => x > 50).length, over100: a.filter((x) => x > 100).length };
};
(async () => {
  const b = await engine.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
  const ctx = await b.newContext({ ...profile, locale: 'de-DE' });
  await ctx.addInitScript(() => {
    localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ me: 'Lena' })));
    window.__fr = { cur: 'start', data: {} };
    let last = 0;
    const tick = (t) => { if (last) (window.__fr.data[window.__fr.cur] ||= []).push(t - last); last = t; requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
  });
  await ctx.route(/^https?:\/\/(?!localhost|127\.0\.0\.1)/, (r) => r.abort()); // Beschluss 02.11.: nothing to foreign services
  if (process.env.SEED) { // measure with a filled phone: 15 bills with line pictures (the empty app hides storage and list costs)
    const seed = fs.readFileSync(process.env.SEED, 'utf8');
    await ctx.addInitScript(([bills]) => {
      try {
        if (!localStorage.getItem('flutter.bills.v1')) {
          localStorage.setItem('flutter.bills.v1', JSON.stringify(bills));
          localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ onboarded: true, me: 'Pia', hints: ['group.how', 'group.anyone'] })));
        }
      } catch (e) {}
    }, [seed]);
  }
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', (e) => errs.push(String(e).slice(0, 200)));
  const fs_ = {}; let phase = 'start';
  p.on('console', (m) => { if (m.text().startsWith('FRAMESTAT ')) { try { (fs_[phase] ||= []).push(JSON.parse(m.text().slice(10))); } catch (e) {} } if (m.type() === 'error') errs.push('console: ' + m.text().slice(0, 200)); });
  const res = { engine: process.env.BROWSER || 'webkit', device: process.env.BROWSER === 'firefox' ? 'firefox-phone' : process.env.BROWSER === 'chromium' ? 'chromium-phone' : process.env.DEVICE || 'iPhone 13' };
  const mark = (name) => { phase = name; return p.evaluate((n) => { window.__fr.cur = n; }, name); };
  const t0 = Date.now();
  try {
    await p.goto(base + '/Fasan-Split/?perf=1');
    // first visit: the service worker (cross-origin isolation) reloads the page once
    await p.waitForTimeout(8000);
    await p.waitForSelector('flt-glass-pane, flutter-view, canvas', { state: 'attached', timeout: 120000 });
    res.startMs = Date.now() - t0;
    errs.length = 0; // what failed while the first load was replaced by the service worker's reload does not count
    if (!process.env.NOSEM) await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); // NOSEM=1: like a real visitor (no screen reader), the accessibility tree costs extra
    await p.waitForTimeout(1500);
    for (const name of [/^(Überspringen|Skip)$/, /^(Los geht|Loslegen|Weiter)/]) { const x = p.getByText(name).first(); if (await x.count()) { await x.click().catch(() => {}); await p.waitForTimeout(800); } }
    res.env = await p.evaluate(() => ({
      crossOriginIsolated: self.crossOriginIsolated, sharedArrayBuffer: typeof SharedArrayBuffer !== 'undefined',
      resources: performance.getEntriesByType('resource').map((e) => e.name.split('/').pop()).filter((n) => /main\.dart\.(wasm|js|mjs)|skwasm|canvaskit\.wasm/.test(n)),
    }));
    await p.screenshot({ path: `${dir}/safari-01-start.png` });
    await mark('settling'); await p.waitForTimeout(8000); // start-up work (fonts, probes, storage) is measured apart from the steady state
    await mark('idle'); await p.waitForTimeout(3000);
    if (process.env.SEED) {
      await p.screenshot({ path: `${dir}/safari-00-seed.png` });
      await mark('scroll-liste');
      for (let i = 0; i < 6; i++) { await p.mouse.move(195, 600); await p.mouse.wheel(0, i % 2 ? -500 : 500); await p.waitForTimeout(500); }
      await mark('open-gruppe');
      const g = process.env.NOSEM ? { count: async () => 1, click: async () => { await p.mouse.click(195, 790); await p.waitForTimeout(1200); await p.mouse.click(195, 330); } } : p.getByText(/Stadt 26/).first();
      if (await g.count()) { const t = Date.now(); await g.click({ timeout: 20000 }).catch(() => {}); await p.waitForTimeout(2500); res.openGroupMs = Date.now() - t; await p.screenshot({ path: `${dir}/safari-00b-gruppe.png` }); }
      await mark('scroll-gruppe');
      for (let i = 0; i < 6; i++) { await p.mouse.move(195, 600); await p.mouse.wheel(0, i % 2 ? -500 : 500); await p.waitForTimeout(500); }
      await mark('open-bon');
      const bon = process.env.NOSEM ? { count: async () => 1, click: async () => { await p.mouse.click(195, 450); } } : p.getByText(/Restaurante Nr\. \d+/).or(p.getByLabel(/Restaurante Nr\. \d+/)).first();
      if (await bon.count()) { const t = Date.now(); await bon.click({ timeout: 20000 }).catch(() => {}); await p.waitForTimeout(3000); res.openBillMs = Date.now() - t; await p.screenshot({ path: `${dir}/safari-00c-bon.png` }); }
      await mark('im-bon'); await p.waitForTimeout(3000);
    }
    if (!process.env.SEED) {
    await mark('tap-neuer-bon');
    const tap = Date.now();
    await p.getByRole('button', { name: /^(Neuer Bon|New receipt)$/ }).first().click({ timeout: 20000 });
    await p.waitForTimeout(1500);
    res.tapToIdleMs = Date.now() - tap;
    await p.screenshot({ path: `${dir}/safari-02-neuer-bon.png` });
    }
    await mark('after');
    await p.waitForTimeout(2000);
    res.frames = Object.fromEntries(Object.entries(await p.evaluate(() => window.__fr.data)).map(([k, v]) => [k, stats(v)]));
  } catch (e) { res.fail = String(e).slice(0, 300); }
  // build and raster time per phase (worst second of the phase): where the slow frames come from
  res.frameTimes = Object.fromEntries(Object.entries(fs_).map(([k, v]) => [k, { buildP95: Math.max(...v.map((x) => x.build.p95 ?? 0)), rasterP95: Math.max(...v.map((x) => x.raster.p95 ?? 0)), buildMax: Math.max(...v.map((x) => x.build.max ?? 0)), rasterMax: Math.max(...v.map((x) => x.raster.max ?? 0)) }]));
  res.errors = errs.slice(0, 4);
  fs.writeFileSync(`${dir}/safari.json`, JSON.stringify(res, null, 1));
  console.log('RESULT ' + JSON.stringify(res));
  await b.close();
  process.exit(res.fail || res.startMs === undefined ? 1 : 0);
})();
