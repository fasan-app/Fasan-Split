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
  const b = await chromium.launch({ args: process.env.CHROMIUM_ARGS ? process.env.CHROMIUM_ARGS.split(' ') : [] });
  // variants for the comparison with test/screens_test.dart: DARK=1, LAND=1 (sideways), LANG=en
  const ctx = await b.newContext({ locale: process.env.LANG_TAG || 'de-DE', colorScheme: process.env.DARK ? 'dark' : 'light', viewport: process.env.LAND ? { width: 873, height: 393 } : { width: 393, height: 873 }, deviceScaleFactor: 2 });
  await ctx.addInitScript(() => localStorage.setItem('flutter.split.settings', JSON.stringify(JSON.stringify({ me: 'Lena' }))));
  if (process.env.PERFMODE) await ctx.addInitScript(m => localStorage.setItem('flutter.perf.mode', JSON.stringify(m)), process.env.PERFMODE); // auto | full | light
  // never anything to foreign services (Beschluss 02.11.): only the local relay and the local server
  await ctx.route(/^https?:\/\/(?!localhost|127\.0\.0\.1)/, r => r.abort());
  if (ctx.routeWebSocket) await ctx.routeWebSocket(/^wss?:\/\/(?!127\.0\.0\.1|localhost)/, ws => ws.close());
  const p = await ctx.newPage();
  if (process.env.NOWASMGC) await p.addInitScript(() => { const v = WebAssembly.validate; WebAssembly.validate = (b) => (b && b.length < 64 ? false : v.call(WebAssembly, b)); }); // test of the JS fallback: the loader sees a browser without WasmGC
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
    await shot('j01-beitritt');
    await click(/^(Beitreten|Verbinden|Beitritt anfragen|Join|Connect|Ask to join)$/);
    await shot('j02-teilen-hinweis');
    await click(/^(Verstanden, teilen|Understood, share)$/);
    await p.getByRole('button', { name: /^(Nicht jetzt|Not now)$/ }).first().click({ timeout: 8000 }).catch(() => {}); // the one-time notification question
    await p.waitForTimeout(800);
    await shot('j03-beigetreten');
    await click(/^(Zur Gruppe|Go to the group)$/);
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
      const item = p.getByRole('menuitem', { name: /Am Original zuordnen|Assign on the original/ }).first();
      ready = (await item.count()) > 0 && !(await item.isDisabled().catch(() => true));
      if (!ready) { await p.keyboard.press('Escape'); await p.waitForTimeout(1500); }
    }
    result.ready = ready;
    if (process.env.LANG_TAG && process.env.LANG_TAG.startsWith('en')) {
      await shot('e01-menue'); await p.keyboard.press('Escape'); await p.waitForTimeout(800); await shot('e02-bon');
      await p.getByRole('button', { name: /^Receipt$/ }).first().click().catch(() => {}); await p.waitForTimeout(2000); await shot('e03-bon-ansicht');
      fs.writeFileSync(dir + '/photo-done.txt', JSON.stringify(result)); await b.close(); process.exit(0);
    }
    await p.keyboard.press('Escape').catch(() => {});
    await p.waitForTimeout(800);
    // every screen of the main flow, one screenshot each (compared with test/screens_test.dart, same bill); a step that fails is
    // noted and the walk goes on, so one missing control does not hide the rest
    const steps = [];
    // frame times of every step (action + 1.2 s settling, before the screenshot): worst frame and frames over 50 ms (Prüfliste G2/G6)
    result.perf = {};
    const rec = () => p.evaluate(() => { window.__r = []; let last = performance.now(); window.__rs = false; (function f(t) { window.__r.push(t - last); last = t; if (!window.__rs) requestAnimationFrame(f); })(last); });
    const recEnd = async name => { const d = await p.evaluate(() => { window.__rs = true; return window.__r; }), q = [...d].sort((a, c) => a - c); result.perf[name] = { n: d.length, p50: Math.round(q[Math.floor(q.length / 2)] || 0), max: Math.round(q[q.length - 1] || 0), slow: d.filter(x => x > 50).length }; };
    const step = async (name, fn) => { try { await rec(); await fn(); await p.waitForTimeout(1200); await recEnd(name); await shot(name); steps.push(name); } catch (e) { await recEnd(name).catch(() => {}); steps.push('FEHLT ' + name + ': ' + String(e).slice(0, 100)); await shot('fehlt-' + name); try { fs.writeFileSync(dir + '/aria-' + name + '.txt', await p.locator('body').ariaSnapshot({ timeout: 8000 })); } catch (_) {} } };
    // a real long press: pointer down, hold, up at the centre of the element (click({delay}) is taken as a tap by the semantics layer)
    const hold = async (loc, ms = 900, noSemantics = false) => { const bb = await loc.boundingBox(); if (noSemantics) await p.evaluate(() => document.querySelector('flt-semantics-host')?.remove()); const x = bb.x + bb.width / 2, y = bb.y + bb.height / 2; await p.mouse.move(x, y); await p.mouse.down(); await p.waitForTimeout(ms); await p.mouse.up(); };
    const back = async () => { await p.getByRole('button', { name: /Zurück|Back/ }).first().click({ timeout: 8000 }).catch(() => {}); await p.waitForTimeout(800); };
    await step('b01-bon', async () => {});
    await step('b02-menue', async () => { await p.getByRole('button', { name: /Mehr|More/ }).first().click(); });
    await step('b03-menue-zu', async () => { await p.keyboard.press('Escape'); });
    await step('b04-posten-blatt', async () => { await p.getByText('Pizza').first().click({ button: 'left', delay: 700 }); });
    await step('b05-posten-blatt-fest', async () => { await p.getByText(/Fester Betrag/).first().click(); });
    await step('b06-posten-zu', async () => { await p.keyboard.press('Escape'); });
    // pieces (07.11.): same steps as test/screens_test.dart b20 – quantity 2, Pia off, Lena on = one of two pieces. Own run (PIECES=1) that
    // ends here: the item stays changed and the rest of the walk needs it complete (undo and re-typing the quantity did not bring it back in the browser)
    if (process.env.PIECES) {
      await step('b20-stueck-posten', async () => {
        await p.getByText('Pizza').first().click({ button: 'left', delay: 700 });
        await p.waitForTimeout(800);
        await p.getByRole('button', { name: /^Pia/ }).last().click();
        await p.waitForTimeout(300);
        const q = p.getByRole('textbox', { name: /Menge|Quantity/ }).last();
        await q.click(); await q.fill('2');
        await p.waitForTimeout(300);
        await p.getByRole('button', { name: /^Lena/ }).last().click();
      });
      result.steps = steps; fs.writeFileSync(dir + '/photo-done.txt', JSON.stringify(result)); await b.close(); process.exit(0);
    }
    await step('b07-pruefen', async () => { await p.getByRole('button', { name: /Posten und Summe prüfen/ }).first().click(); });
    await p.keyboard.press('Escape'); await p.waitForTimeout(800);
    // the long press only works without the accessibility layer in the browser (see docs/WEB-GRENZEN.md): its own run with NOSEM=1,
    // which ends the walk after this picture because the role locators need that layer
    if (process.env.NOSEM) { await step('b08-person-lang', async () => { await hold(p.getByRole('checkbox', { name: /Pia/ }).first(), 900, true); }); result.steps = steps; fs.writeFileSync(dir + '/photo-done.txt', JSON.stringify(result)); await b.close(); process.exit(0); }
    await step('b09-person-zu', async () => { await p.keyboard.press('Escape'); });
    await step('b10-bon-ansicht', async () => { await p.getByRole('button', { name: 'Bon' }).first().click(); });
    await step('b11-bon-original', async () => { await p.getByRole('button', { name: 'Original' }).first().click(); });
    await step('b12-bon-digital', async () => { await p.getByRole('button', { name: 'Digital' }).first().click(); });
    await step('b13-zurueck', async () => { await back(); });
    await step('b14e-fertig', async () => { await p.getByRole('button', { name: /^Fertig/ }).first().click({ timeout: 8000 }); });
    await step('b15-eintragen', async () => { await p.getByRole('button', { name: /Eintragen/ }).first().click({ timeout: 8000 }); });
    await step('b15b-ergebnis', async () => { try { fs.writeFileSync(dir + '/aria-b15.txt', await p.locator('body').ariaSnapshot({ timeout: 8000 })); } catch (_) {} });
    await step('b16-zurueck', async () => { await back(); });
    await step('b17-gruppe', async () => { await back(); });
    await step('h01-home', async () => { await back(); });
    const tap = async (re, ms = 800) => { const l = p.getByRole('tab', { name: re }).or(p.getByRole('button', { name: re })).or(p.getByRole('checkbox', { name: re })).or(p.getByRole('menuitemcheckbox', { name: re })).or(p.getByText(re)).first(); await l.click({ timeout: 8000 }); await p.waitForTimeout(ms); };
    await step('h04-archiv', async () => { await tap(/^(Offen|Archiv|Papierkorb)$/); await tap(/^Archiv$/); });
    await step('h05-papierkorb', async () => { await tap(/^(Offen|Archiv|Papierkorb)$/); await tap(/^Papierkorb$/); });
    await step('h06-gruppen', async () => { await tap(/^Abrechnung/); });
    // the group card of „Alle Gruppen“ opens the same screen as the group picker (12.11.), then back to „Alle Gruppen“ for the picker step
    await step('h06b-karte-tippen', async () => { await p.getByRole('button', { name: /^Beispielstadt .*Bon/ }).first().click({ timeout: 8000 }); await p.waitForTimeout(1200); });
    await step('h06c-wieder-alle', async () => { await p.getByRole('button', { name: /^Beispielstadt$/ }).first().click({ timeout: 8000 }); await p.waitForTimeout(500); await p.getByText(/^Alle Gruppen$/).last().click({ timeout: 8000 }); await p.waitForTimeout(800); });
    // Option A (09.11.): the chip of the group picker picks the group, the tab Abrechnung then shows its people directly
    await step('h07-gruppe-offen', async () => { await tap(/^Alle Gruppen/); await p.waitForTimeout(500); await p.getByText(/^Beispielstadt$/).last().click({ timeout: 8000 }); await p.waitForTimeout(800); });
    await step('h08-personen', async () => { await p.waitForTimeout(300); });
    // profile of a person (12.11.): tap Lena in the people list, same name as the app walk (test/screens_test.dart h08g)
    await step('h08g-profil', async () => { await p.getByRole('button', { name: /^LE Lena/ }).first().click({ timeout: 8000 }); await p.waitForTimeout(800); });
    await step('h08g2-profil-zu', async () => { await back(); });
    // tap on a balance: the breakdown only for this person (12.11.), same name as the app walk (test/screens_test.dart h08h)
    await step('h08h-person-saldo', async () => { await p.getByRole('button', { name: /^[\u2212-]10,00 €$/ }).first().click({ timeout: 8000 }); await p.waitForTimeout(800); });
    await step('h08h2-saldo-zu', async () => { await back(); });
    await step('h08b-bezahlt-frage', async () => { await tap(/Als bezahlt eintragen/); });
    // a part first (06.11.: Teilbetrag), same names as the app walk (test/screens_test.dart h08d/h08e), then the rest
    await step('h08d-teilbetrag', async () => { const f = p.getByRole('textbox').last(); await f.click({ timeout: 8000 }); await p.waitForTimeout(400); await f.fill('4,00'); });
    await step('h08e-rest-offen', async () => { await p.getByRole('button', { name: /^Bezahlt$/ }).last().click({ timeout: 8000 }); await p.waitForTimeout(1500); });
    await step('h08f-rest-frage', async () => { await tap(/Als bezahlt eintragen/); });
    await step('h08c-bezahlt-eingetragen', async () => { await p.getByRole('button', { name: /^Bezahlt$/ }).last().click({ timeout: 8000 }); await p.waitForTimeout(1500); });
    // Notizen and Chat live on the Gruppe tab of the group (the walk was on Abrechnung)
    await step('h08i-gruppe-tab', async () => { await tap(/^Gruppe( Gruppe)?$/); await p.waitForTimeout(500); await tap(/^(Offen|Archiv|Papierkorb)$/); await tap(/^Offen$/); await p.waitForTimeout(500); });
    await step('h09-notizen', async () => { await tap(/^Notizen/); });
    await step('h10-notizen-zu', async () => { await back(); });
    await step('h11-chat', async () => { await tap(/^Chat/); });
    await step('h12-chat-zu', async () => { await back(); await back(); });
    await step('h13-freunde', async () => { await tap(/^Freunde/); });
    result.steps = steps;
  } catch (e) { console.log('FAIL', String(e).slice(0, 300)); await shot('fail'); }
  fs.writeFileSync(dir + '/photo-done.txt', JSON.stringify(result));
  console.log(`${errs.length ? 'FEHLER' : 'OK'} ${JSON.stringify(result)} · Fehler: ${errs.join(' | ') || 'keine'}`);
  await b.close();
  process.exit(0);
})();
