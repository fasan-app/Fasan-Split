# Stand Fasan Split

**Version 0.2** (CI-Build `0.1.<Lauf>`), APK unter Releases → `neueste`, nur arm64, 82,5 MB, mit
öffentlichem Test-Schlüssel signiert, ohne Internet-Berechtigung.
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
| SROIE 0–59 (`test/sroie_test.dart`) | 54/60 nach Web-Zählweise | 55/60 |
| Echte Bons (`FASAN_BONORDNER=fasan-diagnose/tests/echt`), 02.11. | 12/13 komplett richtig, Posten 95/98; Datum 12/13, PLZ 11/13 | – |
| Widget- und Modelltests (`flutter test`) | 37/37 | – |

Bekannter Fehlschlag: `de-discount.png` liest „Storno Chips Paprika“ als Unsinn, darum bleiben Chips und Storno als
zwei Posten stehen (Summe stimmt, „geprüft“ ja). Ursache der Lese-Abweichung zum Web nicht geprüft.

SROIE: echte Fehler 003, 008, 020, 034, 041, alle als „nicht geprüft“ gemeldet. 033 zählt formal als falsch und
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
- ✅ mehrzeilige Posten als eine Form; ✅ Avatare in eigener Spalte; ❌ Schraffur je Person; ❓ Farben: fasan_ui nutzt eine eigene kontraststarke Palette statt Okabe-Ito (Karte 3.8). Okabe-Gelb hat mit weißem Kürzel zu wenig Kontrast. Entscheidung offen

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
- ❌ Stile deutlich unterscheidbar (Rams/Ive/Bauhaus, Recherchen in Fasan-Karte und Kamera)
- ◐ Korn jetzt merkbar (0.2). Dunkler Kasten: Ursache ist der Glow/Halation-Filter (`ImageFilter.shader`); im Emulator (Impeller OpenGLES) stand damit die ganze App kopfüber. Filter aus, Regler ausgeblendet, bis er auf GLES und Vulkan nachweislich stimmt (fasan_ui `FasanFilm.bloomVerified`). Emulator danach: richtig herum, kein Kasten. S23 (Vulkan) noch zu prüfen
- ◐ Einstellungen nach Recherche (`docs/recherche/2026-11-02-einstellungen.md`): Rechnung, Personen, Aussehen, Einführung, Daten (Export, Fotos/alles löschen), Diagnose, Über (0.2); ❌ Währung, Profile, Wiederherstellen
- ✅ Karten: Knopfreihe über der Leiste; Meldungen über der Leiste statt über „Weiter“ (0.2)
- ❌ Eigene Kamera-Ansicht mit Live-Begradigung

### Prüfen
- ✅ Echte Bons: 13 Fotos in `fasan-diagnose/tests/echt`, 12/13. Fehlschlag: McDonald's (keine Summe, keine Posten). Ferreiras richtig „nicht geprüft“ (7,90 € ohne Postenzeile)
- ✅ Emulator-Bildschirmfotos mit echtem Bon: Workflow „Emulator-Bilder“ im privaten fasan-diagnose (Bilder im Zweig `bilder`), Vorführmodus `--dart-define=FASAN_DEMO`

## Bildschirmfotos

`FASAN_SCREENS=<ordner> flutter test test/screens_test.dart`: 9 Ansichten × hoch/quer × hell/dunkel, erfundener Bon.

## Offen

- Auf dem Handy testen (S23): Kamera, Galerie, Erkennungszeit, Akku mit laufendem Korn (siehe unten).
- Bon-Variante: Der Zoom macht den Bon breiter als den Bildschirm; Beträge und Avatare liegen rechts, man muss
  seitlich schieben. Im Querformat verdecken Hinweisfeld und Leiste viel. Am Gerät beurteilen.
- Korn und Bildstandwackeln laufen in Akku-Stufe „Voll“ dauerhaft mit 24 Hz über den ganzen Bildschirm, auch im
  Leerlauf. Verbrauch nicht gemessen.
- `de-discount.png` und SROIE einzeln gegen Web vergleichen.
- APK-Größe: `uvdoc.onnx` allein 31,6 MB; kleinere Variante (z. B. fp16) prüfen.
- Release-Schlüssel als Secret hinterlegen (`FASAN_KEYSTORE_B64`, `FASAN_KEYSTORE_PASSWORD`).
- Code zieht später in Fasan Karte.
