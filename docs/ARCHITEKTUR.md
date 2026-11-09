# Architektur – Ist-Zustand und Plan zum Neuaufbau (Beschluss Nutzer 06.11.: „komplett neu schreiben“)

Stand 06.11. nachts. **Der Neuaufbau ist noch nicht begonnen.** Dies ist Schritt 1: Bestandsaufnahme mit Zahlen (aus den Imports gemessen), danach der Plan.

## Ist (99 Dateien, rund 24 600 Zeilen in `app/lib`)

| Baustein | Dateien | Zeilen | hängt ab von |
|---|---|---|---|
| `ui/` | 32 | 10 419 | model, state, collab, recognition, l10n, **main.dart (22 Dateien!)**, web_platform |
| `recognition/` | 18 | 6 279 | model (1) |
| `collab/` | 14 | 3 853 | model, state |
| `state/` | 10 | 1 324 | model, **collab (3)**, recognition_service |
| `model/` | 6 | 1 098 | **recognition (2), recognition_service, state (1)** |
| `l10n*` | 8 | ≈ 800 | – |
| Adapter Web | `*_web.dart` ×6 + Stubs | ≈ 300 | – |

## Befunde (jeder ist ein Konstruktionsfehler, kein Geschmack)

1. **Das Modell kennt höhere Schichten** (`model` → `recognition`, `state`, `recognition_service`). Das Modell (Posten, Summen, Teilen) muss unten stehen und nichts kennen.
2. **Zyklus `state` ↔ `collab`.** Speicher und Zusammenarbeit kennen sich gegenseitig.
3. **Bildschirme hängen an `main.dart`** (22 von 32): `StoreScope`/`CollabScope` liegen im Einstiegspunkt. Bildschirme dürfen den Einstieg nicht importieren.
4. **Texte liegen in Wurzeldateien** (`l10n_bill/collab/groups/web.dart`) neben dem Code statt in einem eigenen Paket.
5. **Plattform-Adapter verstreut** (`web_platform*`, `recognition_browser*`, `l10n_web`, `images_web`, `ws_connect_web`, `onnx_web`) ohne gemeinsame Schnittstellenordnung.
6. **Die Erkennung (6 279 Zeilen) ist stabil und gut getestet**, hängt aber an einem Modelltyp; sie gehört in ein eigenes Paket mit eigener, kleiner Schnittstelle.

## Zielbild (Dart-Pakete im selben Repo, Abhängigkeit nur nach unten)

```
app (Einstieg, Verdrahtung)            ← kennt alles, nichts kennt ihn
 ├─ ui            Bildschirme, Widgets  (kennt: core, sync, store, recognition_api, l10n, platform_api)
 ├─ sync          Gruppen, Relays, Foto-Stücke, Verschlüsselung (kennt: core, platform_api)
 ├─ store         Speicher, Verlauf (Rückgängig), Sicherung (kennt: core)
 ├─ recognition   Leser, OCR-Pipeline (kennt: core; Modelle über platform_api)
 ├─ l10n          Texte de/en
 ├─ platform_api  Schnittstellen: Bildspeicher, Netz, Schrift, Erkennungs-Ausführung (reine Verträge)
 │    ├─ platform_native   Android/iOS/Desktop-Fassung
 │    └─ platform_web      Browser-Fassung (IndexedDB, Worker, WebSocket)
 └─ core          Posten, Personen, Beträge, Teilen (SplitMath), Prüfung – **keine** Abhängigkeiten
```

Regeln, die der Test erzwingt (Paketgrenzen = `pubspec`, dazu ein Import-Wächter-Test wie `web_parity_test`):
- `core` importiert nichts außer `dart:`-Bibliotheken.
- `kIsWeb` und `dart:html/js_interop` nur in `platform_web`.
- Kein Bildschirm importiert `main.dart`/`app`.
- Jeder neue Bildschirm kommt in den Bildschirmdurchlauf (`tool/e2e/screens.js`, `test/screens_test.dart`).

## Vorgehen (gesichert durch die Tore, nie auf Verdacht)

Tore, die vor und nach jedem Schritt grün sein müssen: Erkennungs-Tor (alle echten Bons + Korpus, keine Verschlechterung), schnelle Suite (322 Tests), Foto-Ende-zu-Ende im Browser, Bildschirmdurchlauf (Bild für Bild App ↔ Browser).

1. **Bestandsaufnahme** (dieses Dokument) – fertig.
   **Fortschritt 06.11. nachts:** Schritt 2 **erledigt** (`app/packages/fasan_core`: bill, split_math, settle, pay, speisen, text_util, accents, category_guess; reines Dart;
   alte Pfade leiten nur weiter; 327 Tests grün; Wächter `test/architecture_test.dart`). Schritt 3a **erledigt**: Zyklus state↔collab aufgelöst – Sicherung, Benachrichtigung,
   Scan-Ablauf und Scan-Warteschlange nach `lib/flows/` (Schicht über state/collab), Kategorie-Darstellung nach `lib/ui/category.dart`, Kategorie-Raten in den Kern.
   Schritt 3b **erledigt**: `StoreScope`, `CollabScope` und die app-weiten Griffe (navigatorKey, deviceNotifier, perfGovernor, startedWithInvite) in `lib/ui/scope.dart`;
   **kein Bildschirm importiert mehr `main.dart`** (vorher 22 von 32). `main.dart` exportiert `scope.dart` nur noch für die Tests.
   Wächter erzwingt jetzt: model → nichts, recognition → model, state → model/recognition, collab → model/state, flows → model/recognition/state/collab,
   ui → alles außer Einstieg, perf → nichts; niemand außer dem Einstieg importiert `main.dart`.
   Schritt 4 **erledigt**: Erkennungs-Ausführung nach `lib/recognition/service.dart` (+ `browser*.dart`, Web-Worker-Adapter), Browser-Plattform nach
   `lib/platform/web_platform*.dart`, Update-Prüfung nach `lib/flows/update.dart`. In der Wurzel von `lib/` liegen nur noch `main.dart` und die Texte (Schritt 6).
   Adapter-Regel: ein Adapter liegt in der Schicht, die ihn nutzt (`state/images_*`, `collab/ws_connect_*`, `recognition/onnx_*`, `recognition/browser_*`);
   nur Fähigkeiten ohne eigene Schicht stehen in `lib/platform/`.
   Schritt 5 **erledigt**: Paket `app/packages/fasan_reader` (reader, model, name_repair, place – das Lesen aus Textzeilen, reines Dart, nur `fasan_core`); Bild- und OCR-Motor
   (ONNX, Bildverarbeitung, QR, Pipeline) bleibt als Adapter in `lib/recognition/`. Volles Tor danach grün (338 Tests, Web, Foto-Ende-zu-Ende, Erkennung 132 Bons/0 Fehler, Korpus gleich).
   Schritt 6 **großteils erledigt**: 602 Texte, die im Code standen (`de ? '…' : '…'`), stehen jetzt in `lib/l10n/strings_de.dart`/`strings_en.dart` (342 aus `l10n*.dart` mit
   `tool/l10n_migrate.py`, 260 aus den Bildschirmen mit `tool/l10n_inline.py`; beide Werkzeuge ändern nur eindeutige Fälle und listen den Rest). Nachweis: alle 699 Texte von `S`
   in beiden Sprachen vorher = nachher (`test/l10n_dump_test.dart`, L10N_DUMP), 336 Tests grün, Bildschirme Pixel-Vergleich vorher/nachher. **Offen:** 7 verschachtelte Stellen
   (Datum, Plural im Satz, Mehrfach-Zahler) von Hand; danach Wächter „kein `de ? '` mehr im Code“; Texte nach Bereichen in eigene Dateien teilen.
2. **`core` herauslösen**: `model/` + `split_math` ohne Fremdabhängigkeit; die zwei Verweise auf `recognition` umdrehen (Erkennung liefert Daten *an* das Modell, nicht umgekehrt).
3. **`platform_api`** mit den vier Verträgen anlegen, bestehende `*_web.dart`/Stubs dahinter verschieben.
4. **`store` und `sync` trennen** (Zyklus auflösen: `sync` kennt `store` nur über eine Schnittstelle).
5. **`recognition` als eigenes Paket** mit schmaler Schnittstelle.
6. **`l10n` als Paket**, Texte nach Bereich geordnet, Test auf fehlende/überzählige Schlüssel.
7. **`ui` an die Verträge hängen**, `StoreScope`/`CollabScope` aus `main.dart` in ein eigenes Scope-Modul.
8. **Wächter-Tests** für alle Regeln; Veröffentlichung erst, wenn alle Tore grün sind (eine Veröffentlichung, Beschluss 06.11.).

Jeder Schritt: eigener Commit auf dem Arbeitszweig, Tore laufen, STAND.md aktualisiert. Verhalten ändert sich nicht (Neuaufbau = gleiche Funktion, gesichert durch die Tests); Fehler, die dabei sichtbar werden, werden getrennt behoben.

## Geprüft (06.11. nachts, eigener Versuch – dart.dev ist aus der Sitzung nicht erreichbar, Netzregel)

- **Pub-Workspaces funktionieren mit Flutter 3.47.7 / Dart 3.13.5**: Wurzel-`pubspec.yaml` mit `workspace: [packages/core]`, Mitglied mit `resolution: workspace`;
  **die App selbst kann die Wurzel bleiben** (`app/pubspec.yaml`), dadurch ändern sich CI-Pfade nicht. Eine gemeinsame `pubspec.lock` in der Wurzel.
- `flutter test` in der App findet `package:core`; im reinen Dart-Paket läuft `dart test` (braucht `test` als dev-Abhängigkeit, pub.dev ist erreichbar).
- Folgerung: Schritt 2 als Paket `app/packages/fasan_core` (reines Dart, kein Flutter). Übergang ohne Bruch: an den alten Stellen (`lib/model/bill.dart` …) bleiben
  kurze `export`-Dateien, bis alle Imports umgestellt sind; dann fallen sie weg.

## Offen / zu recherchieren (Regel: echte Quellen, Stand des Jahres, als neu kennzeichnen)
- Dart-Pub-Workspaces (Dart ≥ 3.6) gegenüber Pfad-Abhängigkeiten für die Paketstruktur; Auswirkung auf die CI.
- Bedingte Importe vs. Schnittstelle + Einbindung per Verdrahtung (Dokumentation dart.dev, flutter.dev „Packages“/„Federated plugins“ als Vorbild für `platform_api`/`_native`/`_web`).
- Aufwand/Risiko: Schritt 2–4 betreffen fast alle 99 Dateien; jede Verschiebung bricht Imports → in kleinen Schritten mit grünen Toren dazwischen.
