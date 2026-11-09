// Fasan Split – browser: the Settings button „Jetzt nach Updates suchen“ (needs a web build made with FASAN_BUILD=<id> and a build.txt next to
// it, see /home/claude/tools/webbuild-perf.sh). Same id → „neuester Stand“ note; different id → the page reloads and what the page stored
// (localStorage stands for the login) is still there. Local server only. MPL-2.0
const { webkit } = require('playwright');
const fs = require('fs');
const base = process.env.E2E_BASE || 'http://localhost:8765';
const dir = process.env.E2E_DIR || '/tmp/fasan-upd';
const buildTxt = process.env.BUILD_TXT; // path of build.txt in the served folder
const id = process.env.BUILD_ID;
fs.mkdirSync(dir, { recursive: true });
(async () => {
  const b = await webkit.launch();
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'de-DE' });
  await ctx.addInitScript(() => { try { if (!localStorage.getItem('flutter.split.settings')) localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ onboarded: true, me: 'Lena' }))); } catch (e) {} });
  await ctx.route(/^https?:\/\/(?!localhost|127\.0\.0\.1)/, (r) => r.abort());
  const p = await ctx.newPage();
  const res = {};
  try {
    fs.writeFileSync(buildTxt, id + '\n');
    await p.goto(base + '/Fasan-Split/');
    await p.waitForTimeout(8000);
    await p.waitForSelector('flt-glass-pane, flutter-view, canvas', { state: 'attached', timeout: 120000 });
    await p.waitForTimeout(3000);
    await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await p.waitForTimeout(1500);
    await p.getByRole('button', { name: /^(Einstellungen|Settings)$/ }).first().click({ timeout: 20000 });
    await p.waitForTimeout(1500);
    const t = p.getByText(/^Jetzt nach Updates suchen/).first();
    for (let i = 0; i < 30 && !(await t.count()); i++) { await p.evaluate(() => { for (const e of document.querySelectorAll('flt-semantics')) if (e.scrollHeight > e.clientHeight + 50 && getComputedStyle(e).overflowY !== 'visible') e.scrollTop += 600; }); await p.waitForTimeout(500); }
    res.label = (await t.innerText().catch(() => '')).replace(/\n/g, ' | ');
    await p.screenshot({ path: `${dir}/upd-1-label.png` });
    await p.evaluate(() => { window.__marker = 1; localStorage.setItem('fasan-test-login', 'bleibt'); });
    await t.click();
    await p.waitForTimeout(1500);
    await p.screenshot({ path: `${dir}/upd-2-aktuell.png` });
    res.noteSame = await p.getByText(/neuesten Stand/).count();
    res.markerAfterSame = await p.evaluate(() => window.__marker);
    fs.writeFileSync(buildTxt, 'bbbbbbb2222222\n'); // the server now holds a newer build
    await t.click();
    await p.waitForTimeout(500);
    await p.screenshot({ path: `${dir}/upd-3-lade-neu.png` });
    await p.waitForTimeout(4000);
    res.markerAfterNewer = await p.evaluate(() => window.__marker); // undefined = page was loaded again
    res.loginKept = await p.evaluate(() => localStorage.getItem('fasan-test-login'));
    res.settingsKept = await p.evaluate(() => localStorage.getItem('flutter.split.settings'));
  } catch (e) { res.fail = String(e).slice(0, 300); }
  console.log(JSON.stringify(res));
  await b.close();
})();
