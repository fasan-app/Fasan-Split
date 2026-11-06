// Fasan Split – screen walk in the browser (Nutzer 06.11.: Vergleich Bildschirm für Bildschirm, App und Browser). Based on photo.js: browser side of the shared-photo end-to-end test (test/e2e_web_photo_test.dart is the phone). A fresh
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
  await ctx.addInitScript(() => localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ me: 'Angi' }))));
  if (process.env.PERFMODE) await ctx.addInitScript(m => localStorage.setItem('flutter.perf.mode', JSON.stringify(m)), process.env.PERFMODE); // auto | full | light
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
  const shot = (n) => p.screenshot({ path: `${dir}/screen-${n}.png` });
  const click = async (name) => { await p.getByRole('button', { name }).first().click({ timeout: 20000 }); await p.waitForTimeout(1500); };
  const result = {};
  try {
    await click(/^(Beitreten|Verbinden|Beitritt anfragen)$/);
    await click('Verstanden, teilen');
    await click('Zur Gruppe');
    for (let i = 0; i < 60 && (await p.getByText('Foto-Test').count()) === 0; i++) await p.waitForTimeout(1000);
    await shot('1-gruppe');
    await p.getByText('Foto-Test').first().click({ timeout: 20000 });
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
    result.ready = ready;
    await p.keyboard.press('Escape').catch(() => {});
    await p.waitForTimeout(800);
    // every screen of the main flow, one screenshot each (compared with test/screens_test.dart, same bill); a step that fails is
    // noted and the walk goes on, so one missing control does not hide the rest
    const steps = [];
    const step = async (name, fn) => { try { await fn(); await p.waitForTimeout(1200); await shot(name); steps.push(name); } catch (e) { steps.push('FEHLT ' + name + ': ' + String(e).slice(0, 100)); await shot('fehlt-' + name); try { fs.writeFileSync(dir + '/aria-' + name + '.txt', await p.locator('body').ariaSnapshot({ timeout: 8000 })); } catch (_) {} } };
    const back = async () => { await p.getByRole('button', { name: /Zurück|Back/ }).first().click({ timeout: 8000 }).catch(() => {}); await p.waitForTimeout(800); };
    await step('b01-bon', async () => {});
    await step('b02-menue', async () => { await p.getByRole('button', { name: /Mehr|More/ }).first().click(); });
    await step('b03-menue-zu', async () => { await p.keyboard.press('Escape'); });
    await step('b04-posten-blatt', async () => { await p.getByText('Pizza').first().click({ button: 'left', delay: 700 }); });
    await step('b05-posten-blatt-fest', async () => { await p.getByText('Chris').last().click(); await p.waitForTimeout(500); await p.getByText(/Fester Betrag/).first().click(); });
    await step('b06-posten-zu', async () => { await p.keyboard.press('Escape'); });
    await step('b07-pruefen', async () => { await p.getByRole('button', { name: /Posten und Summe prüfen/ }).first().click(); });
    await p.keyboard.press('Escape'); await p.waitForTimeout(800);
    await step('b08-person-lang', async () => { await p.getByRole('checkbox', { name: /Chris/ }).first().click({ delay: 700 }); });
    await step('b09-person-zu', async () => { await p.keyboard.press('Escape'); });
    await step('b10-bon-ansicht', async () => { await p.getByRole('button', { name: 'Bon' }).first().click(); });
    await step('b11-bon-original', async () => { await p.getByRole('button', { name: 'Original' }).first().click(); });
    await step('b12-bon-digital', async () => { await p.getByRole('button', { name: 'Digital' }).first().click(); });
    await step('b13-zurueck', async () => { await back(); });
    await step('b14-angi', async () => { await p.getByRole('checkbox', { name: /Angi/ }).first().click(); });
    await step('b14b-zuordnen', async () => {
      // via the item sheets (a tap on a row opens the sheet when no person is active)
      await p.getByText('Pizza').first().click(); await p.waitForTimeout(800);
      await p.getByRole('button', { name: /Chris/ }).first().click(); await p.waitForTimeout(400);
      await p.keyboard.press('Escape'); await p.waitForTimeout(800);
      await p.getByText('Wein').first().click(); await p.waitForTimeout(800);
      await p.getByRole('button', { name: /Angi/ }).first().click(); await p.waitForTimeout(400);
      await p.keyboard.press('Escape');
    });
    await step('b14c-weiter', async () => { await p.getByRole('button', { name: /offen|Weiter|Fertig|Eintragen|Speichern/ }).last().click(); });
    await step('b15-danach', async () => {});
    await step('b16-zurueck', async () => { await back(); });
    await step('b17-gruppe', async () => { await back(); });
    await step('h01-home', async () => { await back(); });
    await step('h02-einstellungen', async () => { await p.getByRole('button', { name: /Einstellungen|Settings/ }).first().click(); });
    await step('h03-zurueck', async () => { await back(); });
    result.steps = steps;
  } catch (e) { console.log('FAIL', String(e).slice(0, 300)); await shot('fail'); }
  fs.writeFileSync(dir + '/photo-done.txt', JSON.stringify(result));
  console.log(`${errs.length ? 'FEHLER' : 'OK'} ${JSON.stringify(result)} · Fehler: ${errs.join(' | ') || 'keine'}`);
  await b.close();
  process.exit(0);
})();
