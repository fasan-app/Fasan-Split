# Stand Fasan Split

**Version 0.2** (CI-Build `0.1.<Lauf>`), APK unter Releases → `neueste`, nur arm64, 82,5 MB, mit
öffentlichem Test-Schlüssel signiert. Internet nur für die Update-Prüfung (GitHub) und auf Tipp OSM im Browser.
Stand 01.11.2026.

## Was da ist

- Erkennung in Dart (Port aus `Fasan-Karte/site/bon.js`, `scan.js`): PP-OCRv5 det/rec und UVDoc über ONNX Runtime
  (`onnxruntime_v2`), Leser, Begradigung, Spalten. Modelle holt `app/tool/fetch_models.sh` (Prüfsummen).
- Ablauf: Foto/Kamera → Summe und Zweck → wer war dabei → Zuordnen → wer hat bezahlt → Ergebnis.
- Zuordnen in vier Varianten: Fokus, Liste mit Zeilenbild, Bon gezoomt (jede Zeile ≥ 48 dp), Karten wischen.
  Mehrzeilige Posten als durchgehende Form, geteilte Posten mit Avataren.
- Teilen als Text, CSV (Semikolon, Dezimalkomma, BOM), Protokoll nur nach Rückfrage (ohne Namen).
- Design aus `fasan_ui` (Git, `main`).

## Testzahlen (ehrlich, 01.11.)

| Satz | Dart | Web 3.19 |
|---|---|---|
| Einheit (`test/reader_test.dart`) | 30/30 | 30/30 |
| Synthetisch (`test/e2e_test.dart`) | 40/41 komplett richtig (PNG 10/11, JPG 30/30) | 41/41 |
| SROIE 0–59 (`test/sroie_test.dart`) | 55/60 nach Web-Zählweise (02.11. mittags; vorher 54) | 55/60 |
| Echte Bons (`FASAN_BONORDNER=fasan-diagnose/tests/echt`), 02.11. mittags | 13/13 komplett richtig, Posten 98/98; Datum 13/13, PLZ 12/13 | – |
| Widget- und Modelltests (`flutter test`) | 37/37 | – |

Bekannter Fehlschlag: `de-discount.png` liest „Storno Chips Paprika“ als Unsinn, darum bleiben Chips und Storno als
zwei Posten stehen (Summe stimmt, „geprüft“ ja). Ursache der Lese-Abweichung zum Web nicht geprüft.

SROIE: echte Fehler 008, 020, 034, 041 (003 seit 02.11. mittags richtig), alle als „nicht geprüft“ gemeldet. 033 zählt formal als falsch und
„geprüft“, weil der Datensatz dort keine Summe hat; das Bild zeigt „Total Amount $8.20“, Dart liest 8,20 (richtig).
Welche Bons im Web scheitern, ist nicht dokumentiert; ein Einzelvergleich steht aus.

Aufrufe stehen jeweils im Kopf der Testdatei. E2E und SROIE brauchen `libonnxruntime.so.1.22.0` im
`LD_LIBRARY_PATH` und laufen ~20 s je Bon; in der CI werden sie übersprungen.

## Soll-Liste (Beschluss 02.11.: alles aus der Web-App + Punkte vom 02.11.)

Status: ✅ da · ◐ teilweise · ❌ fehlt. Quelle: `Fasan-Karte/docs/ENTSCHEIDUNGEN.md` (Bon 3.5–3.19, Kosten 2), Nutzer 02.11.

### Ablauf und Speichern
- ✅ Speichern nach jeder Änderung, Liste „Angefangen“, Schließen verwirft nie, großer Speichern-Knopf in jedem Schritt (0.2)
- ❌ Rückgängig/Wiederholen beliebig vieler Schritte
- ✅ Einführung beim ersten Start + Beispiel-Bon, beides überspringbar (0.2)
- ◐ Wer war dabei; ❌ gleich oder nach Posten, feste Beträge, Anteile
- ◐ Wer hat bezahlt; ❌ mehrere Zahler, Anzahlung, Trinkgeld/Rundung anteilig
- ✅ Cent nach größten Resten; ◐ Ausgleich mit wenigsten Überweisungen (prüfen: exakt, nicht gierig)
- ❌ Ausgaben ohne Kassenzettel (Formular)
- ✅ Gruppen-Knopf war „alles gleich teilen“ ohne Beschriftung: jetzt Menü „Mehr“ mit Rückgängig (0.2)

### Bon-Ansicht
- ◐ Drei Ansichten: Scan, Original unverändert, Digital (0.2); ❌ PDF, Nebeneinander
- ✅ Immer der ganze Bon, Kopf/Fuß blasser; Zoom zwei Finger, Doppeltippen 1×↔2,5×, Knöpfe, „Ganze Breite“ (0.2)
- ✅ Modus „Person wählen, Zeilen antippen“; laufende Summen je Person oben fest; Personen als Leiste (0.2)
- ◐ Posten antippen: Korrekturleiste mit Zeilenbild, zuordnen, bearbeiten/löschen; Tipp neben Kasten rastet ein (0.2); ❌ ausblenden, andere Zeilen übernehmen
- ❌ Ladeanzeige ist der Bon selbst (Lichtband, aufleuchtende Zeilen)
- ✅ Zeilenkasten über die ganze Textbreite inkl. Mengenspalte (0.2)
- ✅ mehrzeilige Posten als eine Form; ✅ Avatare in eigener Spalte; ❌ Schraffur je Person; ❓ Farben: fasan_ui nutzt eine eigene kontraststarke Palette statt Okabe-Ito (Karte 3.8). Okabe-Gelb hat mit weißem Kürzel zu wenig Kontrast. später klären (Nutzer 02.11.)

### Erkennung und Daten
- ✅ Leser 3.19 nach Dart (Messwerte oben)
- ✅ Klarnamen mit Symbol, Bon-Name bereinigt klein darunter, abschaltbar (0.2)
- ❌ Lesesicherheit je Posten sichtbar, andere Lesungen wählbar, Korrektur lernt Lesefehler
- ❌ Bon-Art (Restaurant, Café, Einkauf …) füllt „Wofür?“
- ✅ Datum und Ort aus dem Bon (Adresse, NIF/USt-ID), änderbar, OSM-Suche auf Knopfdruck im Browser (0.2). Echte Bons: Datum 12/13, PLZ 11/13
- ❌ Fremdwährung, EZB-Kurs auf Knopfdruck
- ✅ Protokoll teilen in Einstellungen → Diagnose, Originalfoto nur auf Wunsch, ohne Namen (0.2)
- ✅ CSV; ❌ Volltext, PDF des digitalen Bons

### Gruppe (Web und App gemeinsam)
- ❌ Einladen per Link/QR, Mitmachen im Browser und in der App
- ❌ Nostr wie `site/funk.js` (NIP-01, AES-GCM), öffentliche Relays
- ❌ Gleiche Rechte, beschränkbar; Rechnung nur für Beteiligte (Schlüssel je Gerät und Rechnung)
- ❌ Original-Bonfoto für alle sichtbar (verschlüsselt auf Blossom-Server)

### Design und Einstellungen
- ◐ Gestaltungssystem (02.11.): Spezifikation `../fasan_ui/docs/GESTALTUNG.md`, Recherche Glas/Neigung/Übergänge
  `../fasan_ui/docs/recherche/2026-11-02-glas-neigung-bewegung.md` (WWDC25 Session 219). Umgesetzt in fasan_ui:
  Schichten (Grund → Inhalt → Glas → Rückmeldung), Grund mit animiertem Verlauf, Korn/Wackeln nur im Hintergrund
  (wählbar „ganzes Bild“), Lichteinfall, Überstrahlen; Glas mit Lichtkante nach Neigung (Game Rotation Vector, eigener
  Kanal), zwei Schatten, Berührungslicht, Materialisieren; Glow + Halation am Hauptknopf, Ring-Impuls wenn die Summe
  stimmt; Übergänge Shared Axis, Container Transform (Startkarte → Rechnung), Fade Through (Bon-Ansichten); Paletten
  A/B/C über den Akzent; Effekt-Testseite (Einstellungen → Aussehen → Effekte prüfen). Emulator-Bilder A/B/C liegen vor
  (fasan-diagnose, Zweig `bilder`): Korn nach erstem Lauf auf 1 px/0,22 gesenkt; Neigungssensor läuft im Emulator
  (game_rotation_vector, 30 Hz). Emulator rendert per Software (~1 Bild/s), daher Zeitlücken in den Fotos; Bildrate
  auf dem S23 offen. Verlaufsflecken kaum sichtbar. Größte Lücke: Aufbau der Seiten (Zuordnen-Kopf 4 Zeilen) – die
  Effekte allein machen es nicht ruhiger. ❌ Abnahme S23, Wahl A/B/C. Linse am Glasrand fehlt noch (braucht Bildlesen, erst nach Gerätetest)
- ◐ Korn jetzt merkbar (0.2). Dunkler Kasten: Ursache ist der Glow/Halation-Filter (`ImageFilter.shader`); im Emulator (Impeller OpenGLES) stand damit die ganze App kopfüber. Filter aus, Regler ausgeblendet, bis er auf GLES und Vulkan nachweislich stimmt (fasan_ui `FasanFilm.bloomVerified`). Emulator danach: richtig herum. Der Kasten auf dem S23 kam aber vom Korn-Shader: mediump (16 Bit) lief im Hash ab ~250 dp über, Korn nur oben links. Jetzt highp + kleine Hash-Eingaben. S23 noch zu prüfen
- ◐ Einstellungen nach Recherche (`docs/recherche/2026-11-02-einstellungen.md`): Rechnung, Personen, Aussehen, Einführung, Daten (Export, Fotos/alles löschen), Diagnose, Über (0.2); ❌ Währung, Profile, Wiederherstellen
- ✅ Karten: Knopfreihe über der Leiste; Meldungen über der Leiste statt über „Weiter“ (0.2)
- ❌ Eigene Kamera-Ansicht mit Live-Begradigung

### Prüfen
- ✅ Echte Bons: 13 Fotos in `fasan-diagnose/tests/echt`, 13/13. McDonald's war ein Auswahlfehler (leerer Durchlauf gewann; Kopfzeilen zählten als unklar), kein Lesefehler. Ferreiras richtig „nicht geprüft“ (7,90 € ohne Postenzeile)
- ✅ Emulator-Bildschirmfotos mit echtem Bon: Workflow „Emulator-Bilder“ im privaten fasan-diagnose (Bilder im Zweig `bilder`), Vorführmodus `--dart-define=FASAN_DEMO`; Modus `entwuerfe`: A/B/C × hell/dunkel × Start/Summe/Bon/Ergebnis + Effekt-Testseite (`FASAN_DEMO=tour|lab`, `FASAN_ACCENT`)

## Updates in der App (0.2.1)

Prüft `releases/tags/neueste` über die GitHub-API (einmal am Tag, abschaltbar, oder auf Tipp in Einstellungen → Updates),
lädt die APK, prüft SHA-256 (`digest` der API) und startet den Android-Installer (ota_update, MIT). Berechtigungen:
INTERNET, ACCESS_NETWORK_STATE, REQUEST_INSTALL_PACKAGES; Plugin-Berechtigungen WRITE_EXTERNAL_STORAGE,
INSTALL_PACKAGES, ACCESS_WIFI_STATE entfernt. Funktioniert nur, solange alle Versionen mit demselben Schlüssel signiert sind.

## Bildschirmfotos

`FASAN_SCREENS=<ordner> flutter test test/screens_test.dart`: 9 Ansichten × hoch/quer × hell/dunkel, erfundener Bon.

## Nutzer-Rückmeldung 02.11. abends (S23, 0.1.15) und Stand danach

Erledigt (Ursache belegt):
- Name/Adresse/NIF „Unfug“: Kopf kam aus dem Posten-Gewinner (Da Sé: Gewinner begann bei „CONSUMIDOR FINAL“;
  Estrela: Gewinner las „Vara fiario de Noticias“). Jetzt `bestHeader` über alle Durchläufe, NIF-Prüfziffer Modulo 11,
  Zeilen-Sauberkeit (place.dart). Tests mit den Zeilen aus den Protokollen.
- „Unf/Uní …“ blieben im Namen: Lesarten von „Uni“ (reader.dart `_n2`, bill.dart).
- Angefangene Bons: Zurück ging nicht zum vorigen Schritt (nur letzter Schritt geöffnet). Jetzt `ResumeFlow` mit allen
  früheren Schritten.
- Korn wanderte diagonal (Hash-Feld verschoben). Jetzt je Bild/Ort unabhängiges Gauß-Korn, fein einstellbar; alter Film
  (Flackern, Staub, Kratzer, Vignette, warm) nur in Kino-Stilen an (Nutzer). Recherche fasan_ui `2026-11-02-filmkorn-alter-film.md`.
- Springen beim Stilwechsel: gleiche Textmaße in allen Stilen, Knopf-Radius/Glow im Look, Theme überblendet 380 ms.
- Echtes Glas S0 (Brechung am Rand, Glanz, Fresnel, Neigung) mit Selbsttest beim Start, sonst S2. Ergebnis auf der
  Effekt-Testseite („Glas: refract/blur“). Recherche `2026-11-02-echtes-glas-flutter.md`. Nicht auf Gerät geprüft.
- Update: erst Größe + Änderungen, Laden nur auf Tipp. Teil-Updates: Recherche `docs/recherche/2026-11-02-updates-delta.md`
  empfiehlt Modelle als eigene Dateien (Nutzer entscheidet nach Recherche; widerspricht „alles offline ab Installation“).

Nächste Sitzung (Token sparen: 80 % der Woche verbraucht am 02.11.): Reihenfolge und Aufträge in
`../fasan_ui/docs/GESTALTUNG.md` §9. Updates bleiben ganze APK (Beschluss). Für die Erkennung neu (Nutzer 02.11.):
- Mehrdeutige Lesungen direkt im Posten zur Auswahl anbieten, mit Wahrscheinlichkeit in Prozent.
- Korrekturen lernen: Wählt der Nutzer eine Lesart, gilt sie künftig bei ähnlich verlesenen Wörtern (lokal, ohne Netz).
- Größere Wörterbücher sinnvoller Texte und Wörter je erkannter oder angegebener Sprache (PT, DE, EN …), Lizenz prüfen.

Übersicht und Ablauf (Nutzer 02.11., Soll):
- Mehrere Bons auf einmal hochladen und nacheinander erkennen (Warteschlange mit Fortschritt).
- Startseite: Bons auswählen (Mehrfachauswahl), gruppieren, löschen, Status sehen und setzen.
- Mitbearbeiter sehen und auffordern (hängt an der Gruppe über Nostr, siehe Soll-Liste „Gruppe“).
- 0.1.20 scheiterte am 02.11. nur am NDK-Download der CI (Tests grün); Lauf neu gestartet.

Offen (Recherche liegt vor, Umsetzung nächste Sitzung):
- Stil Papier (`fasan_ui/docs/recherche/2026-11-02-stil-papier.md`), Stil Braun-Technik (`…-stil-braun-technik.md`).
- Lebendig/Warten (`…-lebendig-warten.md`): Scan zeigt echte Arbeit (Zeilen erscheinen, Schrittzähler), Hinweis-Impulse.
- Kino-Stile (Maschine, Sci-Fi, Spionage): eigene Recherche fehlt noch. Nutzer: alle Stile bleiben, die Familie bekommt mehr.
- „Pão“ als „PAD“ gelesen, „Pica-Pau“ ohne Klarnamen.

## Paket 1 (02.11. abends, Code geprüft, nicht nur STAND): Erkennungsabbruch und Scan-Animation

- Abbruch (`pipeline.dart`, `Recognizer.earlyStop`, Test-Schalter `FASAN_EARLYSTOP=0`): Sobald die Summe stimmt (ohne Widerspruch)
  und der Kopf vollständig ist (`ReceiptHeader.complete`: Name plus gültige NIF/USt-ID oder sauber gelesene Straße und PLZ-Zeile),
  laufen kein Ganzfoto-Durchlauf, kein UVDoc, keine Begradigungsläufe und kein Betrags-Nachlesen mehr. Das Protokoll hat dazu
  den Eintrag `abbruch`. Bons ohne vollständigen Kopf (z. B. SROIE) laufen wie bisher bis zum Ende.
- Scan-Animation: ein gedrehter Kasten je Zeile entlang der Zeile (`scan_preview.dart`, `lineQuad`), nur für Zeilen, die die
  Summe bestätigt hat (`verifiedLines`); am Ende begradigt sich der geknickte Bon entlang des Entzerrungsgitters (`ScanWarp`,
  `drawVertices`), die Kästen drehen mit. Ohne Bewegung (Animationen entfernt) erscheint sofort der gerade Bon.
- Tests: `place_test.dart` (Abbruchkriterium), `scan_preview_test.dart` (Kästen, Gitter, ScanScreen mit/ohne Bewegung).
  `flutter test`: 69 bestanden, 54 übersprungen (E2E/SROIE brauchen Modelle, `libonnxruntime` und das private fasan-diagnose).
- NICHT gemessen: Wirkung des Abbruchs auf die Trefferquote (E2E 40/41, SROIE 55/60, echte Bons 13/13) und die Laufzeit auf dem
  S23. Vergleich mit `FASAN_EARLYSTOP=0` steht aus. Das Zeichnen der Begradigung ist nur im Widget-Test gelaufen, nicht auf dem Gerät.

## Paket 2 (02.11. abends): Haptik und Klang – Befund, noch keine Umsetzung

- APK 0.1.21 (Release `neueste`, gelesen mit androguard): Berechtigungen nur ACCESS_NETWORK_STATE, INTERNET, REQUEST_INSTALL_PACKAGES.
  Weder VIBRATE noch eine „Geräte in der Nähe“-Berechtigung sind deklariert; der Eintrag auf dem S23 ist aus dem Manifest nicht erklärbar.
- Doku: Flutter `HapticFeedback` ruft laut api.flutter.dev „default platform behavior“ auf (Android: `performHapticFeedback`; selectionClick →
  CLOCK_TICK, vibrate → LONG_PRESS, medium → KEYBOARD_TAP, heavy → CONTEXT_CLICK laut Flutter-Engine-Test). Seit Android 13 dürfen nur
  privilegierte Apps die Nutzer-Einstellung für Touch-Rückmeldung übergehen (`FLAG_IGNORE_GLOBAL_SETTING` veraltet, developer.android.com).
  AOSP schaltet Touch-Rückmeldung im Lautlos-Modus ab und wendet die Vibrationsstärke des Nutzers an (Commits Lais Andrade 2021/22).
  Folge: Ist auf dem S23 Lautlos aktiv oder Touch-Vibration/Berührungsrückmeldung aus, bleibt `HapticFeedback` stumm, und eine
  Vibrator-API mit VIBRATE würde die Einstellung nur mit einer anderen Nutzungsart (nicht Touch) umgehen. Nicht geprüft auf One UI.
- Nächster Schritt: Auf dem S23 Lautlos aus und Touch-Vibration an, dann Effekt-Testseite. Erst wenn es danach noch still bleibt, Vibrator-Kanal.

## Offen

- Auf dem Handy testen (S23): Kamera, Galerie, Erkennungszeit, Akku mit laufendem Korn (siehe unten).
- Bon-Variante: Der Zoom macht den Bon breiter als den Bildschirm; Beträge und Avatare liegen rechts, man muss
  seitlich schieben. Im Querformat verdecken Hinweisfeld und Leiste viel. Am Gerät beurteilen.
- Grund (Verlauf, Korn, Wackeln, Licht) läuft in Akku-Stufe „Voll“ dauerhaft mit 24 Hz, auch im Leerlauf; Neigung
  30 Hz nur bei sichtbarem Glas. Verbrauch nicht gemessen (Effekt-Testseite zeigt Bildrate und Sensortakt).
- `de-discount.png` und SROIE einzeln gegen Web vergleichen.
- APK-Größe: `uvdoc.onnx` allein 31,6 MB; kleinere Variante (z. B. fp16) prüfen.
- Release-Schlüssel als Secret hinterlegen (`FASAN_KEYSTORE_B64`, `FASAN_KEYSTORE_PASSWORD`).
- Code zieht später in Fasan Karte.
