# Erkennungs-Tor in der CI (Beschluss Nutzer 06.11.)

Vor jeder Veröffentlichung (APK und Web-App) läuft `app/test/gate_test.dart` über alle echten Bons im privaten `fasan-diagnose`
(`tests/echt`) und die synthetischen Bons (`tests/bons`). Scheitert ein Bon (Summe, Beträge, je Posten Name/Menge/Betrag, oder ein falsches
„geprüft“), wird **nichts** veröffentlicht. Workflow: `.github/workflows/erkennung.yml`, eingebunden in `android.yml` (APK baut erst nach
dem Tor) und `web.yml` (Deploy wartet auf das Tor).

## Einmal einrichten (Nutzer, ca. 3 Minuten, geht im Handy-Browser)

Quelle der Schritte: GitHub Docs „Managing your personal access tokens“ und „Using secrets in GitHub Actions“ (gelesen 06.11.).

1. Lese-Schlüssel anlegen – dieser Link füllt das Formular vor (Name, Besitzer `fasan-app`, 366 Tage, nur „Contents: Read“):
   `https://github.com/settings/personal-access-tokens/new?name=Fasan+Erkennungs-Tor&description=Liest+fasan-diagnose+fuer+die+CI+von+Fasan-Split&target_name=fasan-app&expires_in=366&contents=read`
   Im Formular unter **Repository access** „Only select repositories“ wählen und **nur `fasan-diagnose`** auswählen, dann
   **Generate token** und den Schlüssel kopieren. (Verlangt die Organisation eine Freigabe, steht der Schlüssel bis zur Freigabe auf
   „pending“ – laut GitHub Docs.)
2. In **Fasan-Split** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**: Name `FASAN_DIAGNOSE_TOKEN`,
   Wert = der Schlüssel → **Add secret**.
3. Nach 366 Tagen läuft der Schlüssel ab (GitHub löscht ungenutzte Schlüssel ohnehin nach einem Jahr); dann Schritt 1 und 2 wiederholen.
   Das Tor meldet dann „FASAN_DIAGNOSE_TOKEN fehlt“ bzw. scheitert beim Klonen.

## Pflege

- Jeder neue echte Bon kommt mit Wahrheit nach `fasan-diagnose/tests/echt/<land>-<ort>.json`: `posten` (Cent), `total`, und
  **`posten_detail`** `[{name, menge, betrag, einzel?}]` – nach dem Foto von Hand geprüft, nicht aus der Erkennung abgeschrieben.
- Ein Bon, den die Erkennung heute nachweislich nicht schafft, bekommt `"bekannt": "<Grund, Datum>"`. Er bleibt sichtbar im Bericht,
  hält das Tor aber nicht auf – außer er wird fälschlich als „geprüft“ gemeldet (das ist nie erlaubt).
- Lokal wie in der CI: `FASAN_BONORDNER=…/tests/echt:…/tests/bons LD_LIBRARY_PATH=…/onnxruntime-linux-x64-1.22.0/lib flutter test test/gate_test.dart`.
- Vergleich zweier Stände Posten für Posten: `test/snapshot_test.dart` (schreibt JSON) und `/home/user/tools/gate/compare.py` (nicht im Repo;
  Skript steht unten).

## Vergleichsskript (für Sitzungen)

```python
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
def fmt(i): return f"{i['qty']}× {i['name']} = {i['amount']}" + (f" (je {i['unit']})" if i.get('unit') else '') + ('' if i['sure'] else ' ?')
for k in sorted(set(a) | set(b)):
    x, y = a.get(k), b.get(k)
    if x is None or y is None: print(k, 'nur in', 'neu' if x is None else 'alt'); continue
    xi, yi = [fmt(i) for i in x['items']], [fmt(i) for i in y['items']]
    if xi == yi and x['total'] == y['total'] and x['checked'] == y['checked']: print(k, 'gleich'); continue
    print(k, 'VERSCHIEDEN', x['total'], '→', y['total'], x['checked'], '→', y['checked'])
    for i in range(max(len(xi), len(yi))): print('  ', xi[i] if i < len(xi) else '—', '|', yi[i] if i < len(yi) else '—')
```

## Stufe B: Korpus (06.11.)

`FASAN_KORPUS=<ordner>[:<ordner>…]` misst je Ordner, wie viele Bons ganz richtig sind; `FASAN_KORPUS_MIN=<json>` mit `{ordnername: bestwert}`
lässt das Tor scheitern, wenn ein Ordner schlechter wird. Quellen (nur zum Testen, nie in App oder öffentlichem Repo; Beschluss Nutzer 06.11.):
- CORD v2 (Clova AI, Indonesien, CC-BY-4.0): Hugging Face `naver-clova-ix/cord-v2`, Umwandlung `app/tool/korpus/cord_truth.py` (nur Bons,
  deren Posten zur Summe passen; Beträge in Rupiah ohne Nachkommastellen).
- SROIE 2019 (Malaysia, Forschungsdatensatz): `github.com/zzzDavid/ICDAR-2019-SROIE`, nur Summen (`test/sroie_test.dart`).
- Einzelfunde mit freier Lizenz (Openverse/Wikimedia/Flickr): Wahrheit je Posten von Hand nach Foto, privat in `fasan-diagnose/tests/welt/`.
