# Was die Web-App nicht kann (und warum) – Stand 05.11.

Frage des Nutzers: Was kann im Browser grundsätzlich nicht wie in der Android-App sein? Alles hier sind **Grenzen der
Plattform**, keine Auslassungen. Kennzeichen: **[Sekundär]** Suchergebnis / Wissen ohne gelesene Primärseite,
**[nicht geprüft]** nicht auf einem echten iPhone ausprobiert. Wir haben kein iPhone in der Cloud-Sitzung.

Was gleich ist (gleicher Dart-Code, gleiche Widgets): Kachel-Liste mit Bon-Kacheln, Bon-Bildschirm, Einladung, Chat,
Ergebnis, Export, Sprachen. Unterschiede gibt es nur dort, wo `kIsWeb` im Code steht: Beitritts-Hinweis, Anfrage für
dauerhaften Speicher, Update-Hinweis, Deep Links, Benachrichtigungen.

**Stand 06.11. (Parität geprüft):** `kIsWeb` steht nur noch in `main.dart` (Beitrittscode aus der Adresse, Deep Links), `recognition/service.dart`
(Erkennung im Web-Worker), `collab/notify.dart`, `ui/diagnose.dart` (Geräteblock), `ui/home.dart` mit Teil `ui/home_lists.dart` (Update-Prüfung, Home-Bildschirm-Hinweis),
`ui/join_screen.dart` (Web-App-Hinweis). `test/web_parity_test.dart` lässt neue Stellen scheitern. Bonfotos gehen seit 06.11. verschlüsselt über die
Relays an alle Mitglieder (`collab/photo_sync.dart`); im Browser liegen sie in IndexedDB und werden erst beim Anzeigen gelesen.
Sichtbar gleich in Browser und APK (Bildschirmfotos 06.11.): Gruppe, Bon mit Ausschnitten, ⋮-Menü, Scan/Original/Digital, Symbole (eigene Schrift).

## Echte Grenzen

| Thema | Android-App | Browser | Folge für uns |
|---|---|---|---|
| **Daten bleiben** | App-Speicher, bleibt bis Deinstallation | Safari/iOS löscht Website-Daten nach ca. 7 Tagen ohne Besuch (ITP) [Sekundär]; zusätzlich getrennter Speicher zwischen Safari-Tab und Home-Bildschirm-App [Sekundär] | Konto-Sicherung (12 Wörter, Sicherungsdatei) ist vorn: Beitrittsbildschirm und Home-Hinweis. Dauerhaften Speicher anfragen (`navigator.storage.persist`), Wirkung auf iOS [nicht geprüft] |
| **Home-Bildschirm-App (iPhone)** | – | Eigener Speicher: Konto aus dem Safari-Tab ist dort nicht da [Sekundär] | Hinweis „Zum Home-Bildschirm“ vor dem Anlegen; sonst Konto per 12 Wörtern übertragen |
| **Push im Hintergrund** | Benachrichtigung auch bei geschlossener App | Web-Push auf iPhone nur für Home-Bildschirm-Apps [Sekundär]; Relay-Verbindung bricht ab, sobald der Tab schläft | Nachrichten kommen beim Öffnen nach (`wake()`); kein Hintergrund-Sync |
| **Vibration/Haptik** | Haptik-API | Vibration API fehlt in iOS Safari [Sekundär] | Haptik entfällt auf iPhone-Browsern |
| **Ton** | Sofort | Audio braucht erst eine Nutzergeste (Autoplay-Regeln) [Sekundär] | Ton erst nach dem ersten Tippen; vorher stumm |
| **Kamera / Scan** | Direkt, volle Auflösung | Dateiauswahl oder `getUserMedia` mit Berechtigungsabfrage; keine Kamera-Steuerung (Fokus, Blitz) wie nativ [Sekundär] | Foto per Auswahl; Qualität hängt vom Browser ab |
| **Neigungssensor** (Effekte) | Frei | iOS fragt erst nach Erlaubnis (`DeviceOrientationEvent.requestPermission`) [Sekundär] | Effekt nur nach Zustimmung, sonst ruhig |
| **Rechenlast der Erkennung** | Nativ, mehrere Kerne | ONNX im Browser (WASM); Mehrfädigkeit braucht `SharedArrayBuffer`, also Cross-Origin-Isolation (auf GitHub Pages nur mit Service-Worker-Trick) [Sekundär]; Speichergrenze der Tabs [Sekundär] | Erkennung auf dem Handy-Browser langsamer, bei großen Bildern kann der Tab abbrechen [nicht geprüft] |
| **Dateien, Zwischenablage** | Frei | Teilen/Speichern über Browser-Dialoge, Zwischenablage nur nach Geste | Export als Download; „Link kopieren“ nur nach Tippen |
| **Langes Drücken mit Screenreader-Schicht** | Antippen/Halten wie erwartet (TalkBack: eigene Aktionen) | Ist die Zugänglichkeits-Schicht des Browsers an (Screenreader), wird ein Halten auf Chips als Antippen gelesen: Person-Blatt öffnet sich nicht, die Person wird aktiv geschaltet (Bildschirmvergleich 06.11., Playwright mit Semantik an: Antippen; ohne Semantik: Blatt öffnet sich wie in der App) | Jede Aktion des Blatts hat einen sichtbaren Zwilling („Wer hat bezahlt?“-Chip, Personen-Chip mit ×, „Alle offenen“ im Posten-Blatt); Bildschirmleser-Weg zum Blatt noch offen (benannte Aktion am Chip) |
| **Tippen direkt nach dem Antippen eines Feldes** | sofort | Flutter Web legt das eigentliche Eingabefeld erst beim Fokus an; tippt man im selben Augenblick, kann der erste Buchstabe fehlen (beobachtet in 6 von 20 CI-Läufen mit Playwright, 06.11.; bei Menschen **nicht geprüft**) | Test wartet auf den Fokus; beobachten, ob es im echten Browser auffällt |
| **Kurven-Rechnung (Signaturen, Schlüsseltausch)** | `pointycastle` in Dart (nativ ~12 ms je Signaturprüfung) | Dart-Code kompiliert zu WebAssembly braucht ~129 ms je Prüfung und blockiert den Bildschirm (gemessen 08.11., Cloud-CPU). Browser lädt `fasan-curve.js` (@noble/curves 2.4.0, MIT) mit der eingebauten BigInt-Rechnung: ~1–2 ms; Selbsttest beim Laden, sonst Rückfall auf Dart; `?curve=dart` schaltet ab | Bündel `web_extra/fasan-curve.js`, gebaut mit `tool/curve/build.sh`, geprüft mit `tool/curve/check.js` (BIP-340- und NIP-44-Vektoren) |
| **Updates** | In-App-Update der APK | Neuer Stand beim Laden; Knopf „Jetzt nach Updates suchen“ prüft `build.txt` und lädt neu (localStorage/IndexedDB bleiben, Login bleibt); Anzeige „Stand abc1234“ statt Dateiversion (08.11., Nutzer) | Update-Hinweis in der Web-App |
| **Links in die App** | App-Links | Link öffnet sich im Browser oder im In-App-Browser von Messengern (kein Speicher, oft abgeschnittene URLs) | Link v2 mit Prüfsumme, Einfügefeld, Landing-Seite erklärt Fehler |
| **Kein Konto, kein Server** | – | Browser-Daten löschen = Konto weg | Sicherung vorn; Wiederherstellung per 12 Wörtern |

## Nicht übertragbar

- Hintergrundbetrieb und echte Push-Nachrichten bei geschlossenem Browser.
- Haptik auf iPhone-Browsern.
- Garantierte Dauer der Daten auf iPhone-Safari ohne Sicherung.
- Gleiche Erkennungsgeschwindigkeit wie nativ.

## Wasm-Build (skwasm), seit 07.11.

- Veröffentlicht wird `flutter build web --wasm`: Browser mit WasmGC laden `main.dart.wasm` (skwasm), alle anderen automatisch `main.dart.js` mit CanvasKit (Flutter-Lader, erkannt über `WebAssembly.validate`).
  Gemessen (Chromium ohne GPU, Walk): langsame Bilder 165 → 28 (1×), 129 → 74 (4× gedrosselt) gegenüber CanvasKit.
- Mehrfädig nur mit Cross-Origin-Isolation; GitHub Pages setzt die Köpfe nicht, `coi-serviceworker.js` holt sie nach dem ersten Laden nach (ein Neuladen). Davor läuft skwasm einfädig (Konsolenhinweis der Engine).
- Geprüft: Scan-Lauf im Browser mit Wasm und im simulierten Rückfall (WasmGC-Erkennung abgeschaltet → CanvasKit/JS), beide lesen den erfundenen Bon richtig. **Nicht geprüft:** echtes Safari/Firefox/ältere Browser, echtes Handy (Chromium-Messungen sind ohne GPU eher pessimistisch).
- **Gemessen 07.11. (A/B, Chromium headless, CPU 4× gedrosselt, `tool/e2e/scan.js`, echter Bon de-aldi, je 2 Läufe):** Scan-Dauer CanvasKit 75/73 s, wasm 73/71 s (≈ 2–3 %, innerhalb der Messstreuung: die Erkennung läuft im Worker, nicht in der Oberfläche). Bildzeiten während des Scans: gleiche p50/p90 (17 ms, Bildwiederholrate), aber **längster Ruckler 750 ms (CanvasKit) gegen 267/283 ms (wasm)**, und wasm schafft im selben Zeitraum ~35 % mehr Bilder (4250/4167 gegen 3201/3090). Fazit: wasm hilft gegen Ruckler der Oberfläche, nicht gegen die Rechenzeit der Erkennung. Offen: echtes Handy, Safari, Firefox; Messung für Blättern/Leerlauf.
- skwasm-Fehler, die dabei behoben wurden: `Image.toByteData(png)` liefert Fenstergröße (jetzt `rawStraightRgba` + `package:image`, Test `snippets_size_test`); dart2wasm trennt `int`/`double` strikt (`photoQuad` je Element `toDouble()`).

## Noch zu prüfen (ehrlich offen)

- Echtes iPhone (Safari und Home-Bildschirm-App): kein Gerät verfügbar; Chromium-Läufe mit Playwright ersetzen das nicht.
- Messenger-In-App-Browser (WhatsApp, Telegram, Instagram): Verhalten beim Beitrittslink nur aus Berichten bekannt [Sekundär].
