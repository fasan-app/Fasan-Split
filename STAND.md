# Stand Fasan Split

**Version 0.1** (CI-Build `0.1.<Lauf>`, zuletzt 0.1.2), APK unter Releases → `neueste`, nur arm64, 82,5 MB, mit
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
| Widget- und Modelltests (`flutter test`) | 37/37 | – |

Bekannter Fehlschlag: `de-discount.png` liest „Storno Chips Paprika“ als Unsinn, darum bleiben Chips und Storno als
zwei Posten stehen (Summe stimmt, „geprüft“ ja). Ursache der Lese-Abweichung zum Web nicht geprüft.

SROIE: echte Fehler 003, 008, 020, 034, 041, alle als „nicht geprüft“ gemeldet. 033 zählt formal als falsch und
„geprüft“, weil der Datensatz dort keine Summe hat; das Bild zeigt „Total Amount $8.20“, Dart liest 8,20 (richtig).
Welche Bons im Web scheitern, ist nicht dokumentiert; ein Einzelvergleich steht aus.

Aufrufe stehen jeweils im Kopf der Testdatei. E2E und SROIE brauchen `libonnxruntime.so.1.22.0` im
`LD_LIBRARY_PATH` und laufen ~20 s je Bon; in der CI werden sie übersprungen.

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
