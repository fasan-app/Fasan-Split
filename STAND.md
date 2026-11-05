# Stand Fasan Split

**Version 0.2** (CI-Build `0.1.<Lauf>`; Stand der Beschreibung unten: 0.1.23), APK unter Releases → `neueste`, nur arm64, 82,5 MB, mit
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
- Gemessen (02.11. abends, hier in der Cloud-Sitzung, 2 CPU-Kerne): Mit dem ersten Kriterium („Name + USt-ID“) fielen bei Aldi und REWE Heide 2024
  die Postleitzahl weg (Abbruch zu früh). Darum verlangt `complete` jetzt Name + gültige NIF/USt-ID + saubere Straße + PLZ-Zeile.
  Danach: echte Bons 13/13 komplett richtig, Posten 98/98, Datum 12/13, PLZ 11/13 (identisch zum Lauf ohne Abbruch); 277 s gegen 560 s ohne
  Abbruch (der Lauf ohne Abbruch lief teils parallel zu Builds, die Zeiten sind nur grob vergleichbar). Synthetisch mit Abbruch: PNG 10/11,
  JPG 30/30, Posten 247/247 (wie vorher; `de-discount.png` bleibt der bekannte Fehlschlag).
- NICHT gemessen: SROIE 0–59 (Bons ohne vollständigen Kopf laufen unverändert zu Ende, aber nicht nachgemessen), Laufzeit auf dem S23, und die
  Begradigung als Animation auf dem Gerät (nur Widget-Test).

## Paket 2 (02.11. abends): Haptik und Klang

- APK 0.1.21 (Release `neueste`, gelesen mit androguard): Berechtigungen nur ACCESS_NETWORK_STATE, INTERNET, REQUEST_INSTALL_PACKAGES.
  Weder VIBRATE noch eine „Geräte in der Nähe“-Berechtigung sind deklariert; der Eintrag auf dem S23 ist aus dem Manifest nicht erklärbar.
- Doku: Flutter `HapticFeedback` ruft laut api.flutter.dev „default platform behavior“ auf (Android: `performHapticFeedback`; selectionClick →
  CLOCK_TICK, vibrate → LONG_PRESS, medium → KEYBOARD_TAP, heavy → CONTEXT_CLICK laut Flutter-Engine-Test). Seit Android 13 dürfen nur
  privilegierte Apps die Nutzer-Einstellung für Touch-Rückmeldung übergehen (`FLAG_IGNORE_GLOBAL_SETTING` veraltet, developer.android.com).
  AOSP schaltet Touch-Rückmeldung im Lautlos-Modus ab und wendet die Vibrationsstärke des Nutzers an (Commits Lais Andrade 2021/22).
  Folge: Ist auf dem S23 Lautlos aktiv oder Touch-Vibration/Berührungsrückmeldung aus, bleibt `HapticFeedback` stumm, und eine
  Vibrator-API mit VIBRATE würde die Einstellung nur mit einer anderen Nutzungsart (nicht Touch) umgehen. Nicht geprüft auf One UI.
- Nutzer 02.11. 21:24: Ton und Vibration sind am S23 eingeschaltet, trotzdem keine Veränderung → die Systemschalter sind nicht die Ursache.
- Umgesetzt (fasan_ui 38d0816, hier VIBRATE im Manifest): `FasanHaptics` vibriert standardmäßig direkt über den Vibrator-Dienst
  (Plugin `vibration`, BSD-2; Doku pub.dev: VIBRATE im Manifest nötig), mit Rückfall auf `HapticFeedback`; „Direkte Vibration“ ist
  abschaltbar. Klick-Ton über `SystemSound.play(click)` bei Tipp und Einrasten, abschaltbar. Auf Android gibt es laut Flutter-Doku nur
  `click` (`alert` nur Desktop); hörbar nur, wenn die Touch-Töne des Handys an sind (Drittquelle, nicht auf One UI geprüft).
  Einstellungen → Aussehen: Schalter „Direkte Vibration“, „Klick-Ton“ und drei Probe-Knöpfe (System-Haptik, Vibrator, Klick-Ton).
- Offen: Auf dem S23 die drei Probe-Knöpfe drücken und melden, welcher spürbar/hörbar ist. Bleibt auch der Vibrator stumm, ist die
  Ursache nicht Software der App (dann Samsung-Vibrationsintensität „Touch-Interaktion“ prüfen, nicht geprüft).

## Paket 3 (02.11. abends): Mehrfach-Upload und Übersicht

- „Foto wählen“ nimmt mehrere Fotos (`pickMultiImage`, Quelle: Paketcode image_picker 1.2): Bei einem Foto wie bisher, bei mehreren werden sie
  gespeichert, als „Wartet auf das Lesen“ gelistet und nacheinander gelesen (`state/scan_queue.dart`, Fortschritt in der Kachel). Fehler oder
  Abbruch (App geschlossen): Zustand „fehlgeschlagen“ mit „Nochmal lesen“ aus dem gespeicherten Original.
- Übersicht (`ui/home.dart`): Auswählen (Mehrfachauswahl) mit Gruppieren, Fertig/Offen setzen, Löschen; Gruppen mit Anzahl und Summe;
  Wischen nach rechts = Fertig/Offen, nach links = Löschen mit „Rückgängig“; langes Drücken und auf eine Gruppe ziehen (Drag and Drop).
  Meldungen schweben über der Glasleiste. Lehre aus dem Test: Flutter lässt eine Meldung mit Aktion standardmäßig stehen (`persist`), deshalb
  `persist: false`, sonst würden gelöschte Bons nie endgültig entfernt.
- Tests: `test/home_test.dart` (9: Auswahl/Gruppe, Wischen, Löschen mit/ohne Rückgängig, Warteschlange, Lesefehler, Löschen während des Lesens,
  Start nach Abbruch). Nicht auf dem Gerät geprüft: Ziehen auf Gruppen (nur Code, kein Test), Bedienbarkeit auf dem S23, Speicher bei vielen Fotos.
- Offen aus Paket 3: Mitbearbeiter (hängt an Nostr, braucht Freigabe zum Schreiben), Status „fertig“ als eigene Ansicht, Gruppe beim Hochladen
  wählen, mehrere Bons in einem Foto.

## Sitzung 02.11. nachts (0.1.23): Rückmeldungen vom S23 und Navigation

Recherche: `fasan_ui/docs/recherche/2026-11-02-navigation-layout-glas-ton.md` (Reiter-Konzept, Apple-Vorgaben für Layoutänderungen,
Papierkorb-Fristen, verschlüsselte Nostr-Relays, AV1-Korn, Glas, Ton).

Behoben (Ursache belegt):
- Korn und Hintergrund liefen nach „Weniger Bewegung“ nicht mehr: Beim Neustart des Tickers zählte die Zeit von null, der Takt-Vergleich blieb
  negativ (`film.dart`, `backdrop.dart`). Behoben, aber nur im Code geprüft, nicht auf dem Gerät.
- Menü sprang bei Stilwechsel (Häkchen machte Chips breiter) und beim Einschalten der Vignette: Häkchen weg (Farbe zeigt die Auswahl), weiches Ein-
  und Ausblenden mit `FasanReveal` (AnimatedSize + AnimatedSwitcher, ohne Bewegung ohne AnimatedSize, sonst Assertion).
- Dunkle Block-Overlays: SnackBar-, Dialog-, Menü-, Tooltip- und Chip-Theme im Stil (Fläche, Haarlinie, Radius des Stils).
- Schalter im Menü blieben still: `FasanSwitchTile` mit Haptik und Ton, in den Einstellungen von fasan_ui und Split.
- Auswahlmodus blieb hängen: bleibt bis zum X, zum gleichen Symbol oder „Zurück“.
- Scan nicht auf voller Breite (44 dp Rand für Avatare): Scan füllt die Breite, Avatare im rechten Papierrand.
- Scan verformt: Ein UVDoc-Bild gewann Gleichstände (guete 16851 gegen 16841) und streckt hohe Bons. `displayBonus` für „entfaltet“ ist 0, der
  Ausschnitt behält die Proportionen. Rand des Ausschnitts links 8 % → 12 % (Buchstaben am Rand wurden abgeschnitten). Nicht behoben: Der Scan
  verformt Bereiche ohne Text (QR-Code) leicht und hat unten links einen dunklen Keil (an Estrela do Bairro gesehen).
- „P Pizza Peperoni“: Ein Fleck vor „Uni“ blieb im Namen (`_n2`). Verdächtige Namen (einzelner Konsonant vorn, Sonderzeichen) sind sofort „unsicher“.
  Bearbeiten zeigt Lesesicherheit in % und andere Lesungen als Chips (`nameAlternatives`).
- Original: Posten sind wählbar (Ecken des Bons im Foto aus der Erkennung, bilinear auf die Zeilen; nur genähert). Wischen zwischen Scan, Original
  und Digital (Shared Axis); im Scan nur bei unverzoomtem Bon und einem Finger.

Neu:
- Navigation: unten drei Reiter (Rechnungen, Gruppen, Freunde), schwebendes Plus (Kamera, Galerie/Datei, ohne Bon), auf Rechnungen oben Offen, Archiv,
  Papierkorb. Ein Pager trägt fünf Seiten, Wischen geht der Reihe nach durch. „Fertig“ = Archiv; Löschen = Papierkorb (7 Tage, 30 Tage Standard, nur
  manuell; Einstellungen → Daten); Wischen rechts = Archiv, links = Papierkorb mit Rückgängig; Ziehen auf Gruppen.
- Gruppen (auch leere), Gruppenseite, Freunde (aus Bons und von Hand), Einladungsentwurf mit Link, frischem Schlüssel und QR (zxing2-Encoder). Es wird
  nichts gesendet (Beschluss 02.11.).
- Mehrfach-Upload: Miniatur sofort, Ort, Datum und Preis erscheinen nach dem ersten Durchlauf (`ScanPartial`), die Kachel spielt die Scan-Animation
  in klein (`ScanStage`, `ScanLive`).
- Korn nach AV1-Synthese (82×73-Vorlage per AR-Filter in Dart, 32×32-Blöcke mit zufälligem Versatz je Bild, Überlappung, Helligkeitsfunktion);
  Wärme standardmäßig aus, Glow/Halation/Überstrahlen stärker (Einstellungen Version 4: alte Werte werden zurückgesetzt).
- Eigene Töne (audioplayers, Sinus mit Hüllkurve, Nutzungsart „assistanceSonification“), Rückfall auf den Systemklick.
- Glas: Glanz und Kaustik am Rand, dünne Innenkante (überall sichtbar). Protokoll hat jetzt `darstellung` (Glas-Stufe, Grund, Korn-Vorlage).

Messungen (hier in der Cloud-Sitzung): echte Bons 13/13, Posten 98/98, Datum 12/13, PLZ 11/13; synthetisch PNG 10/11, JPG 30/30, Posten 247/247;
`flutter test`: 90 bestanden, 52 übersprungen (E2E/SROIE); fasan_ui 61 bestanden. Shader mit `impellerc` (GLES, Vulkan) übersetzt: grain.frag und
glass.frag ohne Fehler.

NICHT geprüft: alles auf dem S23 (Bedienung, Wischen zwischen Seiten und Konflikt mit dem Wischen auf Kacheln, Ziehen auf Gruppen, Ton, Korn, Glanz,
Begradigung); SROIE; Original-Zeilen bei stark gewölbten Bons (Näherung).

## Sitzung 03.11. (0.1.24): Rechenkern, Zuordnen, Ton, Glas-Probe, Schatten, Anleitung

Rückmeldung vom S23 (Protokoll 00:45): Glas-Stufe `blur`, Grund „Testbild falsch (gedreht oder schwarz)“; Ton still; 3 Cola auf 2 Personen
zeigten „1 + 1 Stück“; Zuordnen sprang nach „Alle“ sofort weiter; Anleitung fehlt.

Behoben / gebaut (Code und Tests, **nicht auf dem Gerät geprüft**):
- **Rechenkern** `model/split_math.dart`: ganze Cent, Anteile in Tausendsteln, keine Kommazahlen in Summen. Rest-Cent wandern reihum je Posten
  (Beschluss 03.11.). Jede Aufteilung läuft zweimal mit zwei verschiedenen Verfahren (größter Rest und kumulatives Runden); `Bill.audit()` prüft
  Summe der Posten, Summe der Personen gegen zugeordnet + Differenz, Überweisungen gegen Zahler. Ergebnis zeigt „Rechenprüfung“ mit aufklappbarem
  Rechenweg; bei Abweichung rote Warnung. Tests: 20 000 Zufallsfälle, 3 000 Zufallsrechnungen (auch Rabatte, Trinkgeld), `split_math_test.dart`.
  „Fertig“ ist gesperrt, solange die Prüfung eine Abweichung meldet (Meldung + Warn-Haptik).
- **Zuordnen**: kein Auto-Springen mehr (Standard „Nie“, einstellbar: nie, kurz warten mit Abbrechen, sofort; Einstellungen); Stück je Person als
  exakter Bruch in 0,5-Schritten (3 Stück auf 2 Personen = 1,5); Plus-Chip „Person hinzufügen“ direkt am Posten (die Person hat den Posten sofort);
  Langdruck auf eine Person: nur diese, bei diesem Posten entfernen, umbenennen, aus der Rechnung entfernen (`Bill.removePerson`).
  `FasanPersonChip.onLongPress` neu in fasan_ui. Tests `assign_test.dart` (5).
- **Ton**: Ursache belegt im Plugin-Quelltext: `BytesSource` geht nicht im Modus lowLatency („Bytes sources are not supported on LOW_LATENCY mode
  yet“, audioplayers_android 5.3.0). Der Fehler wurde verschluckt, der stumme Systemklick sprang ein. Jetzt MediaPlayer-Modus, ein vorbereiteter Player
  je Ton, Nutzungsart „media“ (Medienlautstärke), alle vier Töne spielen. Der Test-Knopf zeigt den echten Fehler, das Protokoll hat `darstellung.ton`.
- **Glas**: Probe erkennt „kopfüber“ und dreht im Shader (`uFlip`), statt aufzugeben; Protokoll `darstellung.glas.pixel` zeigt die gemessenen
  Farben. Optik stärker und überall sichtbar (Lichtrand 1,8 dp, Innenglühen, stärkerer Glanz). **Echte Brechung bei „schwarz“ ist nicht gelöst**:
  wenn das Protokoll wieder „Testbild falsch“ mit schwarzen Pixeln zeigt, braucht es den Weg ohne `ImageFilter.shader` (Hintergrundbild per
  `toImageSync` + Paint-Shader). Entwurf und Hürden: Glas-Leisten müssen außerhalb der erfassten Fläche liegen, sonst Rückkopplung.
- **Schatten**: `FasanShadows`/`FasanDepth` (fasan_ui): drei bis vier Schichten, Richtung folgt der Neigung (gleiche Winkelformel wie das Glas),
  getönt bei Primärknöpfen und Plus. Auf Zuordnungskarten, Kacheln, Knöpfen, Plus-Knopf und Glasleisten.
- **Anleitung**: Hinweiskarten am Ort (Zuordnen, Übersicht; „Verstanden“ schließt, Einstellungen „Hinweise wieder zeigen“), pulsierender Ring am Plus,
  leere Übersicht mit drei Aktionen, Archiv erklärt, wie Rechnungen dorthin kommen.
- **Zusammenarbeit**: Recherche `docs/recherche/2026-11-03-zusammenarbeit-verschluesselung.md` (Gift Wrap, Gruppenschlüssel, CRDT, Web-Link mit
  Schlüssel im Fragment, Wiederherstellung per 12 Wörtern, NIP-49, Sicherungsdatei, spätere Stufe MLS). **Noch kein Code**, nichts gesendet.

NICHT geprüft: alles auf dem S23; Wischen zwischen Seiten, Kollision Langdruck/Ziehen, Hinweis-Layouts im Querformat, Schatten bei „Akku maximal“,
Ton (Medienlautstärke), Glas-Probe nach der Änderung. E2E der Erkennung nicht neu gemessen (nichts an der Erkennung geändert; hier fehlt in dieser
Sitzung nur `LD_LIBRARY_PATH` für ONNX, daher laufen `e2e_test.dart` und `zz_view_test.dart` lokal nicht).

## Sitzung 03.11. nachts (Zusammenarbeit, Oberfläche): Stand nach der Übergabe

Erledigt (Commit d9d6637 auf main und wip-zusammenarbeit; fasan_ui main 2d0a4c3):
- `ui/collab_ui.dart`: Beitreten (JoinScreen, Link aus Zwischenablage oder Deep-Link), Einwilligung vor dem ersten Relay-Kontakt,
  Live teilen (neue oder bestehende Gruppe), Einladung mit QR, Link kopieren und teilen, Anfragen annehmen oder ablehnen,
  Widerruf, Mitglieder (Admin entfernt), Notizen mit Editor (entprellt, fremde Änderungen ohne Fokus), Chat, Konto
  (Name, Schlüssel, 12 Wörter auf Abruf, Wiederherstellen mit Bestätigung, Relays), Karten „Wartet auf Bestätigung“.
- `groups.dart` und `home.dart`: + auf der Gruppen-Seite fragt neu live, nur hier oder beitreten. Gruppen-Seite mit Live-Teil oder
  „Live teilen“. Alter Einladungsentwurf entfernt. Einstellungen: „Konto und Zusammenarbeit“.
- Tests: `test/collab_ui_test.dart` (Konto, Einladung, Notiz, Chat) mit MemoryRelay, keine öffentlichen Relays.
- fasan_ui: Schatten immer an (Effekt-Schalter und Akku steuern nur die Neigung). Brechung aus: ImageFilter.shader war auf dem
  S23 schwarz, Glas bleibt auf Stufe blur (`refractionEnabled = false`).
- `analyze` ohne Befund (zwei ungenutzte Imports in service_test entfernt).

Offen, mit Stand 03.11. nachts:
- Chat-Reihenfolge behoben (Kern, auf Entscheidung des Nutzers 03.11.): `collab/notes.dart` vergibt pro Telefon streng steigende
  Zeitstempel. Der Test „Zwei Telefone“ war in der CI rot, lokal mal grün, mal rot.
- CI auf main, Lauf 41703816840 (Commit 0a5ba6c): grün, 148 bestanden, 54 übersprungen. APK als Release „neueste“
  (Fasan Split 0.1.26, Test) veröffentlicht. Der Kotlin-Code für den nativen Ton ist damit in der CI gebaut.
- Nicht auf dem S23 geprüft: die Oberfläche der Zusammenarbeit (nur Widget-Tests mit MemoryRelay und die CI).
- `home_test` „Warteschlange Erste Angaben“: in der CI einmal rot (`ok` statt `reading`), in den späteren Läufen grün.
  Timing unter Last [Likely], nicht geprüft. 03.11. nachts lokal unter Last wieder rot: Test wartet jetzt auf das Ergebnis statt auf den Zähler (Ursache im Zähler von scan_queue nicht untersucht).
- Mitglied entfernen rotiert den Gruppenschlüssel nicht (`collab/group.dart`, Kommentar: nächste Stufe). Ein entferntes Mitglied
  kann mit dem alten Schlüssel weiter lesen, bis rotiert wird.
- Glas ohne ImageFilter.shader: Hintergrund per `RepaintBoundary.toImageSync` lesen, Leisten außerhalb der erfassten Fläche. Offen.
- Web-Build (Gruppen-Link), Scan-Begradigung, Rest der Liste unten. Offen.

## ÜBERGABE 03.11. abends (Branch `wip-zusammenarbeit`, NICHT auf main, Build dort absichtlich unvollständig)

Rückmeldung S23 (0.1.24, Protokoll 19:11): Klick-Ton geht, erster Druck dünn, später lauter, in der Führung teils doppelt/verzögert, Klang „ganz schlimm“.
Glas-Probe: Pixel oben/unten `rgb0,0,0` = **schwarz** (nicht kopfüber): `ImageFilter.shader` liefert auf dem S23 Schwarz, Glas bleibt `blur`.
Schatten „nicht da“: Verdacht [Likely]: Akku 19 % → Effekte aus → `FasanDepth` zeichnet dann nur Haarlinie (`!st.on`). Fix: statische Schatten immer, nur Neigung abhängig von `st.tilt`.
Bon-Ansicht: Langdruck auf Namen und Plus fehlten; im WIP-Stand ist `personMenu`/`addPersonDialog` (assign.dart) in `_PersonBar` (receipt_view.dart) eingebaut, **nicht getestet**.
**Nutzer: Zusammenarbeit hat jetzt höchste Priorität** (Teilnehmer, Kassenzettel abrechnen, Verschlüsselung, gleichzeitig bearbeiten, Notizen, Nachrichten).

FERTIG und getestet im WIP-Stand (39 Tests grün, `flutter test test/crypto_test.dart test/group_test.dart test/bill_sync_test.dart test/service_test.dart`):
- `app/lib/collab/`: `crypto.dart` (BIP-340, NIP-44 v2 mit offiziellen Vektoren, ChaCha20-Poly1305 RFC 8439), `keys.dart` (NIP-06, Identity, Vault), `nostr.dart` (Events, RelayPool/WsRelay, MemoryRelay für Tests), `lww.dart` (LWW-CRDT), `group.dart` (Gruppenschlüssel, GroupSession, Invite/Invitations/JoinFlow, Bestätigung durch Admin), `bill_sync.dart` (Bill ⇄ CRDT über `uid`), `notes.dart` (Notizen, Chat), `service.dart` (`CollabService`: Identität, Gruppen, Einladung, Brücke zu den Bons).
- `Bill`/`Person`/`BillItem` haben stabile `uid`.
- fasan_ui (Branch `wip-zusammenarbeit`): `FasanTone.kt` (nativer AudioTrack MODE_STATIC) + `sound.dart` neu (Ton ohne audioplayers, Entprellung, weichere Töne). **Kotlin nie kompiliert** (kein Android-SDK hier), erst die CI zeigt Fehler.
- `tool/patch_android.py`: Intent-Filter `fasansplit://join` (an frischem `flutter create` geprüft, XML gültig). `pubspec.yaml`: app_links, pointycastle, bip39, web_socket_channel, flutter_secure_storage.
- `l10n_collab.dart`: alle Texte der Zusammenarbeit (de/en).
- `main.dart`: `SplitApp` ist jetzt StatefulWidget mit `CollabScope`, `navigatorKey`, Deep-Link (öffnet `JoinScreen(prefill:)`). Importiert `ui/collab_ui.dart` → **diese Datei fehlt noch, bis sie da ist, baut nichts**.

NOCH ZU BAUEN (Reihenfolge):
1. `app/lib/ui/collab_ui.dart` mit: `JoinScreen({prefill})` (Link einfügen/Zwischenablage, Name, `service.join`), `GroupScreen`-Erweiterung für Live-Gruppen (Mitglieder, Einladen, Notizen, Nachrichten, Verlassen), `InviteScreen` neu (`g.invitations!.create()`, QR aus `invite.link`, Kopieren/Teilen, Anfragen mit `approve`/`decline`, widerrufen), `NotesScreen`/Editor (Speichern entprellt, Fremdänderungen einlesen), `ChatScreen`, `AccountScreen` (Name, 12 Wörter anzeigen, Wiederherstellen, Relays), Einwilligungsdialog vor dem ersten Relay-Kontakt, Karten „Wartet auf Bestätigung“ in der Gruppenliste, `home.dart` `_plus` auf Seite Gruppen: Neue Gruppe live/lokal oder Beitreten. Kein `groups.dart`-Entwurf mehr (`InviteScreen` ersetzen).
2. Einstellungen: Eintrag „Konto und Zusammenarbeit“ → `AccountScreen`.
3. Widget-Tests mit `CollabService(relayFactory: MemoryRelay…)`; CI muss grün sein, dann Merge nach main (Reihenfolge: fasan_ui nach main pushen, in Split `flutter pub upgrade fasan_ui`, Lock committen).
4. Danach: Schatten immer an, Glas ohne `ImageFilter.shader` (Hintergrund per `toImageSync`, Leisten außerhalb der erfassten Fläche), Web-Build (Flutter Web, Gruppen-Link), Scan-Begradigung, Rest unten.

Regeln: **Nie an öffentliche Relays senden, auch nicht zum Testen** (nur MemoryRelay); die App selbst nutzt sie nur nach Einwilligung des Nutzers. Lokal `app/pubspec_overrides.yaml` zeigt auf `../../fasan_ui` (gitignoriert, nicht committen; Vorlage `/tmp/po.yaml` kann fehlen: Inhalt `dependency_overrides:\n  fasan_ui:\n    path: ../../fasan_ui`).
Tests: `export PATH=/home/claude/tools/flutter/bin:$PATH; cd app; flutter test` (E2E nur mit `LD_LIBRARY_PATH=/home/claude/ort/onnxruntime-linux-x64-1.22.0/lib`, dauert ~13 min, im Hintergrund).

## Sicherung und Schlüsselwechsel (04.11.)

- Release-Schlüssel aktiv seit Lauf 453d4da (ci-logs/key.log: „Release-Schlüssel aktiv“, SHA256 7C:2B:13:B4:…:FE:A8, gleich
  dem Eintrag in fasan-app.github.io/.well-known/assetlinks.json). Eine Release-APK passt nicht über die Testversion.
- Neu: „Sichern“ in den Einstellungen (`state/backup.dart`, `ui/backup_ui.dart`): alle Bons mit Fotos und Protokollen,
  Einstellungen, auf Wunsch Konto (Schlüssel, 12 Wörter) und geteilte Gruppen in eine JSON-Datei; Einspielen fügt fehlende
  Bons hinzu, löscht nichts; Konto/Gruppen nur in eine Installation ohne anderes Konto, wirkt nach Neustart. Test:
  `test/backup_test.dart`. Nicht auf dem Gerät geprüft.
- Übergang: `FORCE_TEST_KEY: '1'` im Signaturschritt erzwingt einmal den Testschlüssel, damit die Sicherung per Update auf die
  installierte Testversion kommt. Ablauf: Update installieren → Sicherung speichern → Flag entfernen (Sitzung) → Release-APK:
  Testversion deinstallieren, neu installieren, Sicherung einspielen, App neu starten. ERLEDIGT 04.11. nachts: Flag entfernt (Nutzer hat mit Konto gesichert).

## Noch offen – Reihenfolge (aufgeräumt 04.11. abends; die einzige Liste, die gepflegt wird)

Alles Unerledigte aus dem Verlauf unten steht hier. Erledigtes wandert mit Datum in den Verlauf. Priorität: erst was
Einladen, Gruppen und Freunde blockiert (Nutzer 04.11.: „muss sofort funktionieren“), dann Bedienung, dann Neues.

Quellen nachlesen (Stand 04.11. spät, Gesamtliste mit Zeilen: Fasan `NACHPRUEFEN.md`): Netz-Freigabe wirkt in der laufenden
Sitzung, sobald die Umgebung geändert ist. Gelesen und in `docs/recherche/2026-11-04-anbindungen-zahlung-netz.md` (Nachtrag 2)
eingetragen: BIP 21/321, Monero-URI, Orbot-Ports, `HttpClient.findProxy`, Mastodon-Teilen-URL, GitHub-Release-`digest`,
EZB (kein CORS-Header → im Browser nicht lesbar), EPC-QR (nur Zweitquelle). **Offen:** EPC069-12-PDF (Cloudflare-Prüfung, nicht
umgangen; Version 002 und leeres BIC-Feld mit einer Banking-App prüfen), nostr.watch (nur JavaScript), Passkey-PRF (keine
offizielle Seite, Messprobe S23), Material-3-Seiten (nur JavaScript), Okabe-Ito-Hexwerte (nicht im Seitentext).

Gruppen, Einladen, Freunde
0. System-Benachrichtigungen – ERLEDIGT 04.11. (Gerät nicht geprüft); offen: Ablauf-Prüfung aller Bildschirme auf umständliches Verhalten.
1. Auf dem S23 prüfen: offener Einladungslink, Freundeslink + Chat, Bon-Status („Eintragen“, „ausgleichen“), Schritt 4 „Übersicht“.
2. Echte In-App-Browser (WhatsApp, Instagram) und iPhone/Safari: nicht geprüft (nachgestellt nur ohne Service Worker / ohne Speicher).
3. Browser-E2E: Bon im Browser bearbeiten (heute nur Android↔Android-Test); „schon Mitglied“ → direkt in die Gruppe; Relay nicht erreichbar; abgelaufener Link mit klarer Meldung.
4. Online / zuletzt online – ERLEDIGT 04.11. (presence_test).
5. Messenger: gelesen ERLEDIGT 04.11.; offen: schreibt gerade, Profilbild/Status, @Bon im Chat, anpinnen, stumm, Privatnachricht in der Gruppe (eigene Verschlüsselung je Empfänger – Entwurf mit dem Nutzer).
6. Gruppe verlassen auf allen eigenen Geräten; Mitglieder von Hand auch im Live-Teil abgleichen; verknüpfte Person umbenennen.
7. Konto: Passkey-Messprobe auf dem S23, danach bauen; soziale Wiederherstellung (2 von 3) als Entwurf.

Anbindungen (Recherche `docs/recherche/2026-11-04-anbindungen-zahlung-netz.md`)
6b. ERLEDIGT 04.11. (SEPA-QR ungeprüft gegen EPC-PDF). Bezahlen-Knopf beim Ausgleichen: SEPA-QR (EPC/GiroCode) und PayPal.Me zuerst, Bitcoin/Lightning/Monero als Option; Angaben verschlüsselt im Profil der Gruppe, nur auf Tipp, kein Geld durch Fasan.
6c. ERLEDIGT 04.11. (Gerät nicht geprüft; .onion offen). „Über Tor verbinden“ (Orbot-Proxy) + .onion-Relays als Option; I2P vorerst nicht (kein Weg für Nostr gefunden).
6d. Messenger: ERLEDIGT 04./05.11. (Modell `collab/notes.dart`, Tests `chat_test.dart` mit 200-Läufe-Konvergenztest, `chat_collab_test.dart` zwei Geräte, `collab_ui_test.dart`; NICHT auf dem Gerät geprüft): Antworten/Zitat, Reaktionen, bearbeiten, „für alle löschen“ (Marker bleibt), @ im Chat (Erwähnung zählt nur, solange @Name im Text steht und nur für Mitglieder; kommt als „Neuigkeit“, auch bei stumm), Suche im Chat, Anpinnen (für die ganze Gruppe, Leiste oben), Stumm je Chat (keine Meldungen außer Erwähnungen, Zähler bleiben). Alles über langes Drücken auf eine Nachricht. Bearbeiten/Löschen prüft den Absender nur im Code, nicht kryptografisch. Offen: Umfragen, schreibt gerade, Profil-/Gruppenbild, Blockieren, Freund per QR, Fotos im Chat, Reaktions-Chips antippbar machen (heute nur Anzeige).

Bedienung, Saldo, Bons
7b. Visualisierung (Nutzer 04.11. abends): Stand/Kategorien als Diagramm mit Animation, Vorschläge; Leerräume je Bildschirm prüfen; „?“-Hilfen überall; Ziehen-Regel systemweit.
8. Saldo-Plakette auch auf Unterseiten, Visualisierung; Filter nach Gruppe/Person/„ich schulde“, Suche.
9. Avatar und Gruppenbild, Namen ändern, Währung aus dem Bon erkennen ($, £, USD); EZB-Abruf im Browser (CORS) prüfen.
10. Kontakte löschen: nur aus Vorschlägen, nicht aus Bons mit Kosten/Zahler.
11. Mehrere Zahler ERLEDIGT 04.11.; offen: Rückgängig/Wiederholen, PDF, Rechenprüfung auch beim Teilen/Export und bei Entwürfen.
12. Erkennung: Betrag im Geschäftsnamen trennen („Uber -12,98 €“), Scan-Begradigung (QR-Bereich, Keil unten links, Papierkante), Lesesicherheit aus Wortkonfidenzen, Korrekturen lernen, `de-discount.png` und SROIE gegen Web.

Gestaltung, Technik, Roadmap
13. Glas echt (vom Nutzer zurückgestellt), Indikatoren/Farben/Animation nach Regelwerk, Übergänge ohne Ruckeln, Menüs und Einstellungen neu ordnen, Gestaltung §9 (Lebendig, Papier, Braun, Kino).
14. Am Gerät beurteilen: Bon-Ansicht (Zoom breiter als Bildschirm, Querformat), Akku mit laufendem Korn, Leistung auf alten Geräten.
15. APK-Größe (`uvdoc.onnx` 31,6 MB, fp16 prüfen); Safari mit 1 Thread.
16. Fasan Karte: Fundament (model, collab, recognition, state ohne App-Abhängigkeit) halten.
17. Roadmap: Widgets, große/kleine Bildschirme, MCP-Schnittstelle, Import Splitwise/Tricount, Konkurrenz-Apps einzeln.
18. Nutzer: GitHub-Konto für fasan@christopherziehm.de (dann „Verified“-Commits möglich).

## Verlauf der offenen Liste (bis 04.11.; nicht mehr pflegen, offene Punkte stehen oben)


Nacht 04.11. (Einladung im Browser, Bon-Status, Freunde):
- Behoben: Web-App konnte keine Beitrittsanfrage senden und keine Gruppe lesen (pointycastle-Poly1305 wirft im Browser „full width integer not supported“). Eigenes ChaCha20-Poly1305 nach RFC 8439, gleiche Bytes wie vorher (Test `crypto_web_test.dart`). Einladungen gespeichert und standardmäßig automatisch bestätigt (`invite_robust_test.dart`), Beitrittsseite öffnet die Gruppe, sobald sie da ist. Browser-Ende-zu-Ende lokal geprüft (lokales Relay `app/tool/e2e/relay.py`, `tool/e2e/joiner.js`, Admin `test/e2e_web_admin_test.dart`): Angi tritt im Browser bei, sieht Gruppe und Bon, ist verknüpft.
- Freunde antippbar: zu Gruppe hinzufügen, einladen, Nachricht im Gruppen-Chat, gemeinsame Bons.
- Als Nächstes (in dieser Reihenfolge, Grund: Nutzer „muss sofort funktionieren“): (1) Freigabe im Link – Beitritt ohne dass ein Verwalter online ist (Plan in `docs/recherche/2026-11-04-einladung-situationen.md`); (2) Browser-Test als CI-Schranke vor Pages (normal, ohne Service Worker, ohne Speicher); (3) Bon-Status „Eingetragen“ (Offen, zählt im Saldo) vs. „Ausgeglichen“ (Archiv, zählt nicht mehr), letzter Schritt als Übersicht mit „Eintragen“ statt doppelter Zahler-Frage (Nutzer 04.11.).
- Gebaut (später in der Nacht): (1) offener Link – Beitritt sofort, auch wenn kein Verwalter online ist (Kern `group.dart` 4b, `invite_open_test.dart`); (2) Browser-E2E als CI-Schranke vor Pages (`web.yml` Job e2e, `tool/e2e/run.sh`: Admin offline, 3 Browser normal/ohne Service Worker/ohne Speicher). Stresstest fand und behob: Absturz ohne Browser-Speicher, Fehler in coi-serviceworker ohne Service Worker. Offen: (3) Bon-Status; Bearbeiten aus dem Browser im E2E (heute nur Android-Test).
- Bon-Status gebaut (Nutzer 04.11., Test `settled_test.dart`, NICHT auf dem Gerät geprüft): „eingetragen“ (Schritt 4 „Eintragen“) bleibt unter Offen und zählt im Saldo; „ausgeglichen“ (Bon: „Alles bezahlt – ausgleichen“, Gruppe: „Alle haben bezahlt – ausgleichen“, Wischen nach rechts) geht ins Archiv und zählt nicht mehr. Angefangene Bons können nicht ins Archiv (Hinweis). Bons, bei denen niemand etwas schuldet, sind beim Eintragen gleich ausgeglichen. Geteilt über `meta/settled`. Schritt 4 heißt jetzt „Übersicht“: kleine Zeile „Bezahlt hat“, Ergebnis, Erklärung, Knopf „Eintragen“. Listentitel ohne Gruppe: „Ohne Gruppe“ / Archiv „Ausgeglichen“.
- Freunde ohne Gruppe gebaut (Nutzer 04.11., Tests `friend_direct_test.dart` + Browser-E2E Modus friend, nicht auf dem Gerät): „Freund einladen“ auf der Freunde-Seite → Link (offen, Zweier-Verbindung `GroupSecret.direct`), wer ihn öffnet, landet im Chat; Verbindung erscheint nur unter Freunde (Chat-Symbol, „verbunden“), nie unter Gruppen oder Bons. Menü je Person vereinfacht: „Nachricht schreiben“ / „Mit … verbinden“, ein „In Gruppe aufnehmen“ (geteilte Gruppe: Einladungslink öffnet sich gleich). Browser im Test sperrt jetzt alle nicht-lokalen Verbindungen (ein Testaufbau trug kurz öffentliche Relays im Link; der Sitzungs-Proxy lehnte alle Verbindungen ab, nichts ging raus).
- Abend 04.11. (Rückmeldung S23, Tests + Browser-Bilder, nicht auf dem Gerät): EIN Name überall – Kontoname und „Ich bin“ waren getrennt, der Kontoname blieb leer („Verknüpft mit —“) und wurde nur mit Enter gespeichert; jetzt übernimmt das Konto „Ich bin“, Umbenennen geht an alle Gruppen über ein eigenes Profil-Dokument `profile:<pub>` (nur der Besitzer schreibt, Test `name_test.dart`), Speichern beim Tippen. Profil hinter dem Avatar oben links (Name, Mein Stand, Freund einladen, Gerät hinzufügen/anmelden, Sicherung, Wörter, Einstellungen). Auswahl ohne Springen (Häkchen auf dem Vorschaubild, Rahmen gleich breit). Ziehen: kleine Bon-Vorschau über dem Finger, unten Ablageziele (Gruppe, Ausgleichen, Papierkorb, ggf. Offen), das Ziel unter dem Finger wird größer, farbig und sagt „Loslassen: …“, oben keine Knöpfe mehr während des Ziehens. Glas ohne Rauschen als Standard (einmal auch für bestehende Installationen). Erklärtexte in den Einstellungen hinter „?“ (`TitleHelp`).
- Offen aus dieser Rückmeldung: Visualisierung mit Animationen und Vorschlägen (Diagramme Stand/Kategorien, Übergänge), unpassende Leerräume Bildschirm für Bildschirm, Glas auf dem S23 sichtbar prüfen, „?“ auch in den übrigen Bildschirmen, Ziehen-Regel systemweit (Gruppen-, Freunde-Seite).
- Nacht 04.11. (Rückmeldung „Einladen ist eine Katastrophe“, Recherche `docs/recherche/2026-11-04-einladen-benachrichtigen-messenger.md`; Tests, Browser-Bilder, nicht auf dem Gerät):
  - Ein Einladen: Link sofort da, Gültigkeit 1/7/30 Tage, „Link teilen“ mit fertigem Text, offene Einladungen als Liste (für wen, bis wann), einzeln zurückziehen; Einladen-Knopf in jeder Gruppe (eine Gruppe nur auf dem Handy wird dabei geteilt). Wer beitritt, steht sofort als Person in der Gruppe; gleiche Namen in Bons gehören automatisch zum Mitglied; über offene Links Beigetretene dürfen selbst einladen (`invite_simple_test.dart`).
  - Freunde = alle aus meinen Gruppen + Zweier-Verbindungen; Tipp schreibt (Zweier-Verbindung entsteht auf Zuruf, NIP-44 an den anderen, nur von Leuten mit gemeinsamer Gruppe), letzte Nachricht mit Zeit, Ungelesen fett mit Zahl; Zahlen an den Reitern Gruppen/Freunde und am Chat der Gruppe; Gruppenkachel zeigt ungelesene Nachricht.
  - Glocke „Neuigkeiten“: beigetreten, neuer/geänderter Bon, Nachricht, Erwähnung; geänderte Bons mit Punkt bis zum Öffnen; Einstellungen → Benachrichtigungen (vier Schalter, eine Stelle).
  - Gleicher Stand: fehlgeschlagenes Senden wird von selbst wiederholt (3 s … 2 min), Pause zwischen Dokumenten gegen Relay-Bremsen, beim Start alles einmal neu senden, Papierkorb wird geteilt, Vorschaubild (120 px) wird geteilt (`sync_robust_test.dart`).
  - Bons im Chat anhängen (Karte öffnet den Bon); Notizen im Bon mit Anpinnen (Hinweis oben in allen Schritten) und @-Erwähnung (`bill_notes_test.dart`).
  - Bon schließen führt zurück, wo er geöffnet wurde (Gruppe, Chat), nicht mehr zur Startseite. Gruppenzeile Mitglieder/Notizen/Chat kompakt. Breite Bildschirme: Spalte 600 px in der Mitte.
  - Offen: System-Benachrichtigungen auf dem Handy (flutter_local_notifications, BSD-3; Android-Erlaubnis erst beim Einschalten; ganz beendete App: erst beim Öffnen – ohne Google-Push), gelesen-Häkchen, schreibt gerade, online/zuletzt online, Antworten/Reaktionen; weitere Bedien-Prüfung aller Abläufe auf „komisches Verhalten“.
- Mehrere Zahler (Nutzer 04.11., Test `payers_test.dart`, nicht auf dem Gerät): Schritt 4 „Mehrere haben bezahlt“, Beträge je Person (gleiche Teile vorgeschlagen), Eintragen erst, wenn die Summe passt; Überweisungen aus Saldo je Person (größter Schuldner an größten Gläubiger, exakte Cent); `meta/paid` im Gruppenabgleich. Ferreiras 7,90: wurde rechnerisch schon anteilig verteilt, stand aber nur als rote Differenz da; jetzt beim Scannen immer eigene Zeile (5/10/12/15 % der Posten → „Bedienung x %“, sonst „Ohne Postenzeile“), für alte Bons Knopf in Schritt 1.
- Benachrichtigungen auf dem Gerät (Punkt 0, nicht auf dem Gerät geprüft): `flutter_local_notifications` 22.3.3 (BSD-3), `state/notify.dart`; Einstellungen → Benachrichtigungen → „Auf dem Gerät anzeigen“ fragt erst dann die Erlaubnis (Android 13+, Browser); zeigt Neuigkeiten, solange die App läuft oder im Hintergrund ist und nicht vorne; ganz geschlossen: nichts (kein Google-Push), dann in der Glocke. CI-Bau mit AGP 9.1.0/compileSdk 36, Desugaring war schon an.
- Online / zuletzt online und „gelesen“ (Test `presence_test.dart`): Profil-Dokument je Gruppe `seen` (alle 3 min, nur wenn die App vorne ist) und `read`; grüner Punkt in der Freundesliste, „zuletzt …“, im Chat „online“/„zuletzt online“, ✓/✓✓ und in Gruppen „gelesen von n“. Einstellungen → „Online-Status und gelesen teilen“: aus = nichts geht hinaus und man sieht es bei anderen nicht.
- Konto löschen (Nutzer 04.11., Test `account_delete_test.dart`, nicht auf dem Gerät): Profil → „Konto löschen“ (wahlweise mit Bons); meldet in jeder Gruppe/jedem Chat „gelöscht“ (Profil `deleted`), trägt sich aus der Mitgliederliste aus, schickt eine leere Kontoliste und eine NIP-09-Lösch-Bitte (kind 5, `a`-Tags; Befolgen durch Relays nicht garantiert), löscht Schlüssel, Wörter, Gruppenliste und `collab.*`. Bei den anderen: „Konto gelöscht“ in der Freundesliste, Tipp → „Aus der Liste entfernen“ (blendet aus, verlässt den Zweier-Chat). „gelesen“ wurde bei jedem Neuzeichnen neu gesendet – behoben (Zeit der letzten Nachricht statt jetzt).
- Bezahlen-Knopf (6b, Tests `pay_test.dart`, nicht auf dem Gerät): Profil → „So kann man dich bezahlen“ (IBAN mit Prüfziffer, Kontoinhaber, PayPal.Me-Name, Bitcoin/Monero optional), nur im Profil-Dokument der Gruppen (verschlüsselt). „Bezahlen“ neben jedem „Du gibst …“ im Bon und im Gruppen-Ausgleich: SEPA-QR (GiroCode, EUR) + IBAN kopieren, PayPal.Me mit Betrag, Wallet öffnen (ohne Betrag, kein Kurs). Fasan bewegt kein Geld. SEPA-QR-Aufbau NICHT gegen das EPC-PDF geprüft (Host in dieser Sitzung trotz Freigabe gesperrt, 403) → mit Banking-App prüfen oder in neuer Sitzung PDF lesen.
- „Über Tor verbinden (Orbot)“ (6c, nicht geprüft – kein Orbot hier): Einstellungen; prüft, ob Orbot läuft (127.0.0.1:8118), gilt nach Neustart; alle wss-Relays über Orbots HTTP-Tunnel (CONNECT, belegt im Dart-SDK-Quelltext). ws://-.onion-Relays gehen so nicht (bräuchte SOCKS). Im Browser nicht (Tor Browser selbst nutzen).
- To-do Nutzer 04.11.: GitHub-Konto für fasan@christopherziehm.de anlegen (dann signierte „Verified“-Commits möglich).
- Wunsch Nutzer 04.11., später: Freunde „online“ / „zuletzt online“ (verschlüsselter Zeitstempel je Gruppe, in Einstellungen abschaltbar; aus = auch keine fremden Zeiten), weitere Messenger-Funktionen (gelesen, schreibt gerade, Profilbild/Status, Erwähnungen, stumm, anpinnen).

Spätabend 04.11. (Tests, nicht auf dem Gerät):
- Gerät koppeln per QR ohne Abtippen (Test `pairing_test.dart`): neues Gerät zeigt Code + Prüfcode, altes Gerät überträgt Konto verschlüsselt (NIP-44 an Einmal-Schlüssel) über ein Relay; Konto → „Mit anderem Gerät anmelden“ / „Gerät hinzufügen“; Link öffnet über die System-Kamera direkt die App. Einführung: „Schon ein Konto?“.
- Sicherung mit Passwort und „Senden …“ (z. B. Mail an mich), Einspielen fragt das Passwort (Test).
- Passkey: nicht gebaut, offizielle Doku zu PRF auf Android fehlt; zuerst Messprobe auf dem S23 (Recherche-Nachtrag).

Abend 04.11. (Tests, nicht auf dem Gerät):
- Gruppe nach Neuinstallation weg – Ursachen: (1) Gruppen lagen nur auf dem Gerät, 12 Wörter brachten sie nicht zurück; (2) eine Sicherung mit Konto wurde still verworfen, wenn auf dem neuen Gerät schon ein frisches Konto angelegt war (z. B. „Konto“ geöffnet), und wirkte erst nach Neustart.
- Behoben: Konto-Abgleich (Kern `service.dart`): Gruppenliste als verschlüsseltes Ereignis an mich selbst (NIP-44, d `fs:account:v1`) auf den Relays, nach jeder Änderung veröffentlicht; „Konto aus 12 Wörtern“ holt die Gruppen zurück und meldet die Anzahl; laufende Geräte mit denselben Wörtern bekommen neue Gruppen live. Sicherung mit Konto ersetzt ein leeres Konto und wirkt sofort. Test `account_sync_test.dart` (Neuinstallation, zweites Gerät, Sicherung) grün. Entscheidung in Fasan/ENTSCHEIDUNGEN.md.
- Offen dazu: Gerät per QR koppeln (12 Wörter nicht abtippen), Verlassen einer Gruppe auf allen Geräten, Hinweis beim ersten Start „Schon ein Konto? 12 Wörter eingeben“.
- Kacheln dichter: weniger Innenabstand, kleineres Vorschaubild/Avatare, Zeile mit Datum · Schritt/Personen · wer zahlte · Ort.

Nachmittag 04.11. (Tests, nicht auf dem Gerät):
- „Bon neu lesen“: Symbol in Schritt 1, Menü im Ergebnis; neueste Erkennung, Personen/Zahler/Gruppe/Kategorie/Währung/Name bleiben, Zuordnung der Posten wird neu (`ScanQueue.reread`).
- Posten „anteilig“ (`BillItem.proportional`): Zeile ohne Posten (0 % MwSt.) wird nach den übrigen Posten verteilt (Nutzer: wer weniger hatte, zahlt weniger), exakte Cents, im Abgleich (`prop`), Test `proportional_test.dart`.
- Glas (fasan_ui): Lupen-Brechung ohne Shader (ImageFilter.matrix + Blur wie Flutters RawMagnifier), verschiebt mit der Neigung; im Browser ohne Fehler, auf dem S23 nicht geprüft.
- Chips in Schritt 1 kompakt (VisualDensity.compact, Tippfläche bleibt 48 dp); Vorschaubilder ohne Lücke (gaplessPlayback).
- Gesamtablauf mit drei Telefonen (`full_flow_test.dart`): Gruppe teilen, Person aus dem Bon per https-Link einladen, Freigabe, Verknüpfung, gleiche Bons und Salden, Änderungen in beide Richtungen, zweites Mitglied von Hand verknüpft, Entfernen mit neuem Schlüssel – grün.
- App Links: `fasan-app.github.io` jetzt öffentlich, aber `has_pages` = false → Pages ist dort nicht eingeschaltet (Nutzer: Settings → Pages → Deploy from a branch → main, / (root)).

Gesamt-Roadmap aller Fasan-Repos: `docs/ROADMAP.md` (gelesen 04.11.). Hinweis: `fasan-app/fasan-app.github.io` ist privat – Pages aus privaten Repos braucht einen bezahlten Plan, sonst findet Android assetlinks.json nicht (Nutzer prüfen). Ausgleich ist noch gierig, Karte-Beschluss verlangt exakt wenigste Überweisungen.

Rückmeldung 04.11. vormittags (S23, 0.1.46) – ERLEDIGT 04.11. (Tests/E2E, nicht auf dem Gerät):
- Einladung im Browser (Angi landete in leerer App): coi-serviceworker lädt beim ersten Besuch einmal neu, der Code war vorher schon gelesen und gelöscht. Jetzt bleibt er im Tab, bis die Anfrage gesendet ist; auch auf Android verdeckt die Einführung den Beitreten-Schirm nicht mehr. Geprüft in Chromium mit frischem Profil. Vertrauens-Schalter stand fälschlich im Beitreten-Schirm, jetzt im Konto.
- Kategorie wird sofort angezeigt und gespeichert (Chip hört auf den Speicher); vorhandene Bons bekommen die Kategorie einmal nachgetragen (`migrateCategories`).
- Wischfläche so groß wie die Karte (Ablagelinie als foregroundDecoration statt 3 px Rand); weniger Platz über „Angefangen“; letzte Karte rollt ganz über Plus-Knopf und Leiste (Abstand 200); Plus-Knopf schlicht: Akzent, Kartenradius, Kartenschatten, kein Leuchten.
- Erkennung Ferreiras LX: Steuerspalte + „e“ (€) aus den Namen, „z“ vorn = Menge 2, verlesener Name per Mehrheit der Durchläufe (`recognition/name_repair.dart`, Test mit den Lesarten aus dem S23-Protokoll); Betrag ohne Postenzeile aus der 0-%-Zeile der Steuertabelle wird eigener Posten „Ohne Postenzeile (0 % MwSt.)“. E2E echte Bons weiter 13/13, Posten 98/98. Wirkt bei neuem Lesen („Erneut lesen“).
- Namen: „Zuletzt dabei“ ohne Bons im Papierkorb; Langdruck entfernt einen Namen aus den Vorschlägen mit Meldung, wo er noch steht.
- Schritt 1: „Wer war dabei“ und „Wer hat bezahlt“ als Chips direkt unter der Summe; mit ≥ 2 Personen weiter direkt zum Zuordnen.
- Zuordnen: Bon und Liste; Fokus und Karten nur per Einstellung.
- Bon-Ansicht: weicher Schleier statt harter Kante, der Bereich in der Bildschirmmitte bleibt klar; zurück zum Scan → wieder bei den Posten; beide Fotos vorab geladen, Bilder ohne Lücke (gaplessPlayback) gegen Flackern/schwarze Bilder (nicht auf dem Gerät geprüft).

Neu 04.11. (Nutzer; Recherche: docs/recherche/2026-11-04-konkurrenz-bedienung-saldo.md). Reihenfolge: erst Fehler und
Bedienung, die stören, dann Saldo-Sicht, dann neue Funktionen:
A1. Sicherung mit Konto/Gruppen ging nicht (Liste im Speicher) – ERLEDIGT 04.11. (fe5b884, Test); danach echten Schlüssel einschalten (FORCE_TEST_KEY entfernen, sobald gesichert).
A2. ERLEDIGT 04.11. (Widget-Tests, nicht auf dem Gerät): Langdruck: hebt sofort an (ohne Loslassen), Ablegen auf Gruppe, Bon, Reiter unten (Archiv, Papierkorb, Gruppen → Gruppe wählen/neu, Duplikat prüfen); Auswahlleiste ohne Rutschen/Ausblenden.
A3. TEIL ERLEDIGT 04.11.: Einladen nur oben, Mitglieder/Notizen/Chat als kleine Chips, „Gruppe verlassen“ im Menü mit Abfrage (Verwaltung wird gewarnt), Löschen mit Abfrage. OFFEN: Gründer verlässt Gruppe → heute bleibt die Gruppe lesbar und beschreibbar, aber niemand kann einladen oder Mitglieder ändern (adminPub steckt im Gruppengeheimnis); ERLEDIGT 04.11. nachts (Kern, Test): mehrere Verwalter (`m/<pub>.admin`, Mitglieder → „Zur Verwaltung machen“); Gruppe bleibt verwaltbar, wenn der Gründer geht, und er kann wieder eingeladen werden. Warnung beim Verlassen nur, wenn ich die einzige Verwaltung bin.
A4. TEIL ERLEDIGT 04.11. (+ nachts: eigener Stand je Bon und je Gruppe grün/rot an den Kacheln): Saldo-Plakette oben auf den Hauptseiten (Ring grün/rot, Betrag), „Mein Stand“ (gesamt, je Gruppe, je Person), `model/settle.dart` myDebts. „Wer zahlt als Nächstes“ bewusst NICHT (Nutzer 04.11.: Gruppe kann unvollständig sein, Zahlungsaufforderung durch ein Programm stößt übel auf). OFFEN: Plakette auch auf Unterseiten, Visualisierung. Ursprünglich: Profil-Avatar auf allen Seiten mit Stand; „Mein Stand“ gesamt, je Gruppe, über Gruppen, je Person; „Wer zahlt als Nächstes?“.
A5. TEIL ERLEDIGT 04.11. nachts: Sortieren (eigene Reihenfolge, Datum, Betrag, Ort/Geschäft, Kategorie, Status) und Filter nach Kategorie im Knopf oben (`ui/category_ui.dart`), Punkt am Knopf bei aktivem Filter. OFFEN: Filter nach Gruppe/Person/„ich schulde“, Suche.
A6. ERLEDIGT 04.11. nachts (Tests, nicht auf dem Gerät): 12 Grundkategorien mit Symbol/Farbe, Vorschlag aus Geschäft/Posten/Speisen beim Scannen (`model/category.dart`), Chip im Ergebnis, eigene Kategorien, Symbol an der Kachel, im Gruppenabgleich (`meta/category`).
A7. ERLEDIGT 04.11. nachts (Chromium geprüft, Safari/iPhone nicht): `navigator.storage.persist()` beim Start; Hinweis „Zum Home-Bildschirm“ nur auf iPhone/iPad im Browser; coi-serviceworker 0.1.7 (MIT, `web_extra/`) macht die Seite cross-origin isolated → ONNX mit bis zu 4 Threads (Chromium: isoliert, 4 Kerne; pt-esplanada 27,9 s inkl. Modell-Laden, de-aldi 48,3 s); Modelle im Cache API (`fasan-models-v1`, danach offline). Flutters eigener Service Worker ist aus (`web_template/flutter_bootstrap.js`): beide kämpften um denselben Bereich → Endlos-Neuladen (35× in 20 s) – behoben, jetzt einmal beim ersten Besuch. Safari: coi nutzt dort `credentialless`, das Safari nicht kann → 1 Thread (nicht geprüft).
A8. ERLEDIGT 04.11. nachts (Tests): Hinweis auf der Startseite ab 3 Bons: nie gesichert und 10 Änderungen, 7 Tage seit der letzten Sicherung mit Änderungen, oder 40 Änderungen; „Später“ = 3 Tage Ruhe; Zähler setzt „Sicherung speichern“ zurück.
A9. ERLEDIGT 04.11. nachts (Kern, Test mit drei Telefonen `test/core_admin_test.dart`, nicht auf dem Gerät): Entfernen gibt allen anderen einen neuen Gruppenschlüssel (`CollabService.rotateKey`, „rekey“-Ereignis NIP-44 je Mitglied, gebunden an die alte Gruppe; alle Dokumente ziehen um). Offene Einladungen der alten Gruppe gelten danach nicht mehr.
A10. ERLEDIGT 04.11. nachts (Kern, Test): Standard allen vertrauen; je Mitglied („Darf meine Anteile ändern“) oder für alle (Konto) abschaltbar. Dann werden Änderungen anderer an meinen Anteilen, meiner Person oder dem Zahler nicht übernommen, sondern als „Vorschläge“ an der Gruppe angezeigt (Annehmen/Ablehnen). Nur auf meinem Gerät: die anderen sehen die Änderung schon. Vorschläge leben bis zum Neustart (nicht gespeichert; beim nächsten Abgleich kommen sie wieder).
A11. Avatar und Gruppenbild, Namen ändern, Standardwährung, Fremdwährung mit EZB-Kurs (Datum, manuell aktualisieren). TEIL ERLEDIGT 04.11. nachts (Tests, nicht auf dem Gerät, EZB-Abruf hier nicht erreichbar → Abruf nicht geprüft): Standardwährung (Einstellungen → Währung), Bon-Währung mit Chip in Schritt 1 und Ergebnis, Kurs von der EZB (eurofxref-daily/-hist-90d, Datum des Bons, Cache 6 h, abschaltbar, `state/rates.dart`) oder von Hand, Kursdatum sichtbar, Salden rechnen in die Standardwährung um (`Bill.toHome`), Anzeige überall mit der Bon-Währung (`CurrencyScope`). Im Browser blockt die EZB evtl. (CORS, nicht geprüft) → von Hand. OFFEN: Währung aus dem Bon erkennen ($, £, USD), Avatar/Gruppenbild, Namen ändern.
A12a. TEIL ERLEDIGT 04.11. nachts: Wischen mit runder Fläche unter der Karte, Symbol und Text blenden mit dem Wischweg ein (`ui/swipe.dart`, auch Freunde); Leiste unten so breit wie die Karten; Schatten eigener Schalter in Erscheinungsbild (fasan_ui 1202b7f); „Schritt 1/4“ statt Umbruch. Hinweis: In Test-Bildschirmfotos sind Schatten ohne Unschärfe gezeichnet (Test-Renderer), auf dem Gerät weich.
A12. Indikatoren, Farben, Visualisierung, Animation nach Regelwerk und Recherchen; Übergänge ohne Ruckeln; Menüs und Einstellungen neu ordnen; Leistung auf alten Geräten messen.
A13. Integration in Fasan Karte/Reise: Fundament (Module ohne App-Abhängigkeiten: model, collab, recognition, state) halten.
A14. Roadmap: Widgets; sehr große und kleine Bildschirme; MCP-Schnittstelle für KI; Import aus Splitwise/Tricount; weitere Konkurrenz-Apps einzeln ansehen (Splidu, Splidit, Splital, Wexpense, Cashinator, Splitser, Finanzguru Split, iOS, Open Source).

Neu 03.11. abends (Nutzer, Priorität nach Abhängigkeit gesetzt):
1. ERLEDIGT 03.11. (Tests, nicht auf dem Gerät): Bon-Modell: Betrag immer positiv + Richtung `Bill.refund` (Ausgabe/Erstattung, Zahler bei Erstattung hält den Anteil der anderen). Negative Bon-Summe: Abfrage „Bezahlt oder Geld zurück?“ in Schritt 1, „Weiter“ gesperrt bis zur Antwort. Negative Zeilen bleiben Zeilen. `meta/refund` im Gruppenabgleich ergänzt (bill_sync.dart, kleine Ergänzung im Kern). Nachtrag 03.11. (Branch `mitarbeit/erstattung-anzeigen`, Tests, nicht auf dem Gerät): Richtung sichtbar in Bon-Liste (Untertitel „Erstattung ·“), Ergebnis (Hinweis unter der Summe), Teilen-Text, CSV („Erstattung erhalten von“); Personen-Summe zieht Erstattungen ab statt sie zu addieren
2. Gruppen ohne Bon anlegen (Name, Mitglieder), Gruppenseite mit Personen und Saldo. ERLEDIGT 03.11. (Branch `mitarbeit/gruppen-ohne-bon`, Tests, nicht auf dem Gerät): Mitglieder von Hand je Gruppe (`groupMembers` in den App-Einstellungen), dazu alle aus den Bons der Gruppe; Saldo je Person über fertige Bons mit Zahler (`model/settle.dart`, Erstattung beachtet), Ausgleich mit wenigen Überweisungen; neue Gruppe „nur hier“ öffnet gleich die Gruppenseite; in „Wer war dabei?“ Knopf „Alle aus <Gruppe>“. Offen dazu: Mitglieder von Hand werden im Live-Teil noch nicht abgeglichen (nur lokal); „Als bezahlt markieren“ für Ausgleichszahlungen fehlt.
   Reihenfolge danach (Nutzer 03.11.: Gruppen und Web-App sollen bald gehen): 5 (Web-App, https-Einladung) vor 3 und 4.
3. Bons per Langdruck auswählen, bei Mehrfachauswahl per Drag and Drop verschieben und sortieren. ERLEDIGT 03.11. nachts (Widget-Test, nicht auf dem Gerät): Langdruck startet die Auswahl; in der Auswahl hebt Langdruck alle gewählten Bons an (Zähler am Bon), auf eine Gruppe abgelegt → in die Gruppe, auf einen Bon abgelegt → direkt davor (eigene Reihenfolge `Bill.order`, nur auf diesem Gerät, `store.moveBefore`). Vorher: Langdruck zog einen einzelnen Bon auf eine Gruppe.
4. Kontakte komplett löschen (Tippfehler, ehemalige Personen), auch aus Vorschlägen und Bons-Namenslisten.
5. Einladungslink als https-Adresse (Web-App auf GitHub Pages, Install-Hinweis ohne App, Android App Links mit assetlinks.json). Doku zu App Links vorher lesen, nicht geprüft. TEIL ERLEDIGT 03.11. (Branch `mitarbeit/web-app`, Doku `docs/WEB.md`): Einladungen sind `https://fasan-app.github.io/Fasan-Split/join/#<code>` (alter Link geht weiter), Web-Build der ganzen App (ONNX im Web durch Platzhalter ersetzt, Kamera/Galerie/Einführung/Update im Web aus), Hinweis „In der App öffnen“ und „App laden“ beim Beitreten, Workflow `web.yml` für Pages, App-Link-Filter mit autoVerify in `patch_android.py`. fasan_ui: Energie- und Neige-Kanal im Web aus (sonst MissingPluginException). Geprüft: Web-Build und Einladung in Chromium (keine Fehler, keine fremden Hosts), Tests. Nachtrag 03.11. spät: Pages läuft (Web-App-Workflow grün), `fasan-app.github.io` mit assetlinks.json (Release- und Testschlüssel) gepusht, Web-Hinweis „Neu laden“ bei neuer Version (build.txt), CI schreibt den Fingerabdruck in ci-logs/key.log. Release-Schlüssel erzeugt (SHA256 7C:2B:13:B4:…:FE:A8), wartet auf die Secrets FASAN_KEYSTORE_B64/FASAN_KEYSTORE_PASSWORD (Nutzer); Wechsel verlangt einmal Deinstallieren der Testversion. Nutzer 03.11. spät: alle Funktionen auch im Web, auch Bon-Erkennung (ERLEDIGT 03.11. nachts, Branch `mitarbeit/erkennung-web`: Erkennung async (`OnnxModel.run` → Future), Nachrichten in `recognition/scan_events.dart`, Browser liest Bons im Web Worker `recognition/web_worker.dart` mit onnxruntime-web 1.22.0 (wasm, 1 Thread), Fotos im Browser in IndexedDB (`state/images*.dart`), Kamera/Galerie/Einführung im Web wieder an. Geprüft: E2E echte Bons vorher/nachher gleich (13/13, Posten 98/98), Chromium-Worker: de-aldi 3 Posten 4,23 € geprüft, pt-esplanada 7 Posten 39,60 € geprüft, keine fremden Hosts. Nicht geprüft: Safari/iOS (Speicher: Modelle ~45 MB), Bedienung im Browser per Hand, Dauer auf dem Handy-Browser; im Test ~30–150 s je Bon bei 1 Thread und belegter CPU), Personen im Bon einladen und mit Mitgliedern verknüpfen (ERLEDIGT 03.11. nachts, Tests mit MemoryRelay, nicht auf dem Gerät: Einladung trägt optional die Person (`Invite.person`, Feld `p`), bei Freigabe wird das neue Mitglied mit ihr verknüpft (`m/<pub>.person`, Admin selbst `l/admin`, Kern group.dart/service.dart); Gruppenseite zeigt je Person „Verknüpft mit …“ oder „Noch nicht in der App“, Verwaltung kann einladen, verknüpfen, lösen; Mitgliederliste: Person zuordnen; „Wer war dabei?“: Tippen auf eine Person lädt sie ein (Live-Gruppe, Verwaltung). Eine Person = ein Mitglied. Nachtrag: Saldo je Mitglied (ERLEDIGT, Nutzer einverstanden 03.11.): ein Mitglied kann mehrere Namen haben (`m/<pub>.persons`), alle zählen zusammen, Anzeige „zählt bei …“. Offen: Umbenennen einer verknüpften Person). Release-Schlüssel: Secrets gesetzt, CI-Schritt scheiterte beim Entpacken (Lauf dd8e140); Schritt entfernt jetzt Leerzeichen/Umbrüche und meldet Fehler klar in ci-logs/key.log. Offen: echter Beitritt aus dem Browser und auf dem S23 nicht geprüft.
6. Chat (Nutzer 03.11. abends): Bons im Chat mit @ nennen (Bon-Verweis), Nachrichten und Bons anpinnen, Nachricht nur an einzelne Mitglieder (Privatnachricht in der Gruppe). Nachrichten im Kern sind für alle Mitglieder lesbar: Privatnachrichten brauchen eine eigene Verschlüsselung je Empfänger (NIP-44 an dessen Schlüssel), Entwurf mit dem Nutzer abstimmen.
7. Bons umbenennen: Verdacht, geprüft im Code, nicht auf dem Gerät: ScanDone ersetzte den Bon und überschrieb den Namen, den der Nutzer während des Lesens getippt hatte; der Name wurde nur mit „Weiter“ gespeichert. Behoben (Commit siehe Log). Dazu: Kopf „Uber Uber -12,98 €“ enthält den Betrag im Geschäftsnamen (Protokoll 03.11. 21:18), Erkennung muss Betrag aus dem Namen trennen. Offen.
8. Kontakte löschen: Name nur aus Vorschlägen entfernen, nicht aus Bons, in denen die Person Kosten hatte oder bezahlt hat (Nutzer 03.11.).

1. Rückmeldung vom S23 zu 0.1.24: Ton (Test-Knopf zeigt jetzt den Grund), Glas-Probe (`pixel`, `kopfueber`), Schatten, Anleitung, Zuordnen.
2. Glas echt (Paket 5, Rest): wenn die Probe auf dem S23 „schwarz“ meldet: Hintergrund per `toImageSync` erfassen und mit Paint-Shader brechen
   (Schaltmöglichkeit Auto/Echt/Einfach). Wenn die Probe „kopfüber“ meldet: nur Feinschliff.
3. Scan-Begradigung weiter: QR-Bereich, dunkler Keil unten links, Papierkante; Verformungsmaß mit Rückfall auf den Ausschnitt; mit echten Bons messen.
   (Nutzer 03.11.: „muss absolut gut sein“.)
4. Rechenprüfung auch beim Teilen/Export und beim Speichern von Entwürfen anzeigen (Fertig ist schon gesperrt).
5. Zusammenarbeit (Recherche liegt vor), in dieser Reihenfolge: Schlüssel + Wiederherstellung (12 Wörter, NIP-49, Sicherungsdatei) ohne Netz; Krypto-Paket
   mit Testvektoren; Relay-Client gegen lokalen Relay; CRDT für Rechnung, Notizen, Chat; Web-Build mit Einladungslink; Bestätigung neuer Mitglieder.
   Öffentliche Relays nur nach ausdrücklicher Freigabe je Test.
6. Original-Zeilen genauer, Lesesicherheit aus Wortkonfidenzen, echte Alternativen, Korrekturen lernen, Wörterbücher.
7. Soll-Liste (❌ oben): Rückgängig/Wiederholen, mehrere Zahler und Anzahlung, Ausgaben ohne Bon, Fremdwährung, PDF.
8. Gestaltung §9: Lebendig/Warten, Papier, Braun-Technik, Kino-Stile, Leistungstest; Erststart-Tour auf Hinweise am Ort abgleichen.
9. Technik: APK-Größe (`uvdoc.onnx` 31,6 MB), Release-Schlüssel, Akku mit laufendem Korn, SROIE nachmessen, `de-discount.png`.

## Offen (alt, in „Noch offen“ oben übernommen)

- Auf dem Handy testen (S23): Kamera, Galerie, Erkennungszeit, Akku mit laufendem Korn (siehe unten).
- Bon-Variante: Der Zoom macht den Bon breiter als den Bildschirm; Beträge und Avatare liegen rechts, man muss
  seitlich schieben. Im Querformat verdecken Hinweisfeld und Leiste viel. Am Gerät beurteilen.
- Grund (Verlauf, Korn, Wackeln, Licht) läuft in Akku-Stufe „Voll“ dauerhaft mit 24 Hz, auch im Leerlauf; Neigung
  30 Hz nur bei sichtbarem Glas. Verbrauch nicht gemessen (Effekt-Testseite zeigt Bildrate und Sensortakt).
- `de-discount.png` und SROIE einzeln gegen Web vergleichen.
- APK-Größe: `uvdoc.onnx` allein 31,6 MB; kleinere Variante (z. B. fp16) prüfen.
- Release-Schlüssel als Secret hinterlegen – ERLEDIGT 04.11. (Release-Schlüssel aktiv).
- Code zieht später in Fasan Karte.

## Sitzung 05.11. (Cloud, vom Handy): Fehler gefunden und behoben (Nutzer: „es dürfen niemals Fehler in der App auftreten“)

- **Scan-Warteschlange (echter Fehler, im Volllauf als roter `home_test` sichtbar):** Der async `ScanDone`-Handler lief noch, als `onDone` schon „fertig“ meldete → `open == 0`, während ein Bon noch „liest“, und der nächste Bon startete zu früh. Außerdem blieb ein Bon bei einem Strom ohne Ergebnis für immer auf „liest“. Behoben in `state/scan_queue.dart` (Ereignisse nacheinander, „fertig“ erst nach dem letzten Handler, Strom ohne Ergebnis = fehlgeschlagen). Stresstest `scan_queue_test.dart`: Schranke bei jeder Meldung (bei `open == 0` ist jeder Bon fertig oder fehlgeschlagen), 5 Seeds mit 60 Fotos, Fehler, Strom ohne Ergebnis, Löschen, Hinzufügen während des Lesens, 150 weitere Seeds; vor dem Fix rot, danach grün; `home_test` 25× unter CPU-Last ohne Fehler.
- **Bitcoin-/Monero-Link:** Leerzeichen wurden als `+` geschrieben. BIP 21 (RFC 3986, Beispiel `%20`) und der Monero-Parser (`convert_from_url_format` dekodiert nur `%xx`; `docs/URI_SCHEME.md`: „Spaces must be … `%20`“) lesen `+` nicht als Leerzeichen → Wallet hätte „Angi+Muster“ gezeigt. Jetzt `Uri.encodeComponent`, getestet mit 2000 Zufallsnamen gegen einen Parser, der nur Prozent-Kodierung dekodiert. Konkrete Wallet-Apps nicht geprüft (nur die Parser-Quellen).
- **SEPA-QR:** Zeilenumbruch oder Steuerzeichen in Name/Text verschob alle folgenden Felder → jetzt zu Leerzeichen, Kürzen nach Zeichen statt UTF-16-Einheiten.
- **Meldung der ersten Nachricht:** Die erste Nachricht in einer neuen Gruppe löste nie eine Meldung aus (beim ersten Chat-Ereignis galt alles als „Anfangsabgleich“). Jetzt zählen nur Nachrichten, die älter als 30 s sind, als Verlauf.
- **Erkennung (fasan-diagnose):** Der Volllauf nimmt `../fasan-diagnose` als Nachbarordner und läuft die Erkennung auf den Test-Bons mit: png 10/11, jpg 30/30, Posten 247/247. Der eine Fehler ist `de-discount.png` („9/9 +2 falsch“), schon als offen vermerkt (Punkt 12).

