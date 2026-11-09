# Lizenzen

Stand 08.11.2026. Siehe [README](README.md) für die Vertrauensmarken.

## Unser Code

- **MPL-2.0** für Fasan Split und die Pakete `fasan_core`, `fasan_reader`; **fasan_ui** und (seit 08.11.) Fasan Split haben eine `LICENSE`-Datei [sicher].
- Beschluss 07.10./08.10.: MPL-2.0, **keine GPL-Bausteine** (App-Store-Verträglichkeit), Bausteine einzeln veröffentlichbar.
- Was MPL-2.0 bedeutet [sicher, Mozilla-FAQ, https://www.mozilla.org/en-US/MPL/2.0/FAQ/]: Der Pflichtteil („Copyleft“) gilt **je Datei**. Wer eine MPL-Datei ändert und weitergibt,
  muss diese Datei wieder unter MPL offenlegen. Neue Dateien daneben dürfen unter anderer Lizenz oder auch proprietär sein. Es gibt eine Patentlizenz der Beitragenden.
- Folge für uns [wahrscheinlich]: Andere dürfen die App forken und auch verkaufen, müssen aber geänderte Dateien offen halten. Wer das **nicht** verhindern will, ist mit MPL richtig; wer Verkauf durch
  Dritte verhindern will, bräuchte eine andere Lizenz (siehe FINANZIERUNG.md, Modell D). Gegen unerwünschte Nutzung des **Namens** hilft nur eine Marke, nicht die Lizenz (SCHUTZ.md).
- Die MPL-FAQ sagt selbst, dass sich die Verträglichkeit mit App-Stores nach deren Bedingungen richtet und nicht allgemein beantwortbar ist [sicher]. Für Google Play ist MPL-Code in der Praxis üblich [geraten]; Apple-Store-Bedingungen für iOS nicht geprüft.
- Kopfzeilen: 177 von 210 Dart-Dateien (lib, packages, test) tragen einen MPL-Hinweis [sicher, gezählt 08.11.].

## Was wir benutzen

### Pub-Pakete (Sperrdatei `pubspec.lock`, 144 Einträge, Lizenzdatei je Paket im Pub-Cache gelesen, 08.11.2026)

| Lizenz | Pakete | Folge |
|---|---|---|
| BSD-3 / BSD | 109 | Copyright-Hinweis und Lizenztext beim Weitergeben (Flutter sammelt sie für die Lizenzseite) |
| MIT | 17 (inkl. `hex`) | wie BSD |
| Apache-2.0 | 10 | Lizenztext mitgeben, Änderungen kennzeichnen, NOTICE-Dateien beachten |
| MPL-2.0 | 1 (`dbus`, nur Linux-Desktop, indirekt) | Dateiebene; wir ändern es nicht |
| GPL / LGPL / AGPL | **0** [sicher: gesucht] | – |
| ohne Lizenzdatei im Cache | `fasan_ui` (Pfad/Git, hat selbst LICENSE), SDK-Pakete (Flutter, BSD-3 [wahrscheinlich]) | – |

Methode: Schlagworttest auf den ersten 4000 Zeichen der LICENSE-Datei. **Das ist eine grobe Einordnung** [wahrscheinlich]; Doppellizenzen und Sonderklauseln sieht sie nicht. Vor einem Store-Release mit einem
Lizenzwerkzeug (z. B. `dart pub deps` + Prüfliste) gegenprüfen [nicht geprüft].

### Modelle der Bon-Erkennung (`app/assets/models/DATEIEN.txt`)

| Datei | Quelle | Lizenz |
|---|---|---|
| `det.onnx`, `rec-latin.onnx`, `dict-latin.txt` | PaddleOCR PP-OCRv5, ONNX-Umwandlung aus ppu-paddle-ocr-models | Apache-2.0 laut Eintrag; PaddleOCR selbst Apache-2.0 [sicher, Projektseiten/Modellkarten] |
| `uvdoc.onnx` | UVDoc (Verhoeven, Magne, Sorkine-Hornung 2023), von uns nach ONNX umgewandelt | MIT [laut Eintrag; Upstream-Repo nicht neu geprüft] |

Apache-2.0 erlaubt kommerzielle Nutzung ohne Gebühr, verlangt Lizenztext und NOTICE beim Weitergeben [sicher]. **Lücke:** Der Text steht in keiner App-Ansicht. Die Umwandlung durch Dritte (ppu-paddle-ocr-models) wurde
nicht auf eigene Lizenzhinweise geprüft [nicht geprüft]. Trainingsdaten der Modelle: ihre Rechte sind für uns nicht prüfbar [nicht geprüft].

### Native Bibliotheken, Schrift, Daten, Standards

- **@noble/curves 2.4.0 und @noble/hashes** (nur Browser-Fassung, `web_extra/fasan-curve.js`, gebaut mit `tool/curve/build.sh`): MIT, Paul Miller [sicher, Lizenzdatei im Paket gelesen 08.11.]; Lizenztext in der App-Lizenzseite und unter `web_extra/fasan-curve.LICENSE.txt`.
- **ONNX Runtime** (Android-Bibliothek `onnxruntime-android`, Dart-Anbindung `onnxruntime_v2`): MIT laut CLAUDE.md [Eintrag, nicht neu geprüft]. Lizenztext fehlt in der App-Lizenzseite.
- **FasanEmoji.ttf**: Google, SIL Open Font License 1.1, Text liegt bei den Assets [sicher]. OFL erlaubt Einbetten und Weitergeben, verbietet den Verkauf der Schrift allein und verlangt den Lizenztext bei Weitergabe.
- **Wechselkurse (EZB)**: Der ECB erlaubt kostenlose Weiterverwendung, auch kommerziell, wenn die Quelle genannt und die Daten nicht verändert werden [sicher, https://www.ecb.europa.eu/home/disclaimer/html/index.en.html]. Die App nennt „EZB“; die Rechnung mit den Kursen ist unsere Berechnung, die Kurse selbst bleiben unverändert [wahrscheinlich]. Die Kurse sind „nur zur Information“ [sicher, ECB-Mitteilung].
- **Nostr** (Protokoll), **BIP-39** (12 Wörter), **EPC-QR/SEPA**, **PayPal.Me**-Links: offene Spezifikationen bzw. Fremddienste; Wortliste und Texte der BIP-39-Spezifikation nicht auf Lizenz geprüft [nicht geprüft]. Wir schreiben nur nach Beschluss 02.11. nirgends in fremde Dienste.
- **Test-Bons**: echte Kassenzettel Dritter und Datensätze; nie ins öffentliche Repo, nie in den Code (CLAUDE.md). Lizenz je Datei in `fasan-diagnose/tests/welt/quellen.json` (privat).
- **`web_extra/coi-serviceworker`**: eigene Lizenzdatei liegt bei [sicher].

## Pflichten beim Weitergeben der App (Zusammenfassung)

1. Lizenztexte und Urheberhinweise aller gebündelten Teile in der App erreichbar machen (Lizenzseite um Modelle, Schrift, ONNX Runtime ergänzen: `LicenseRegistry.addLicense`). **Teilweise erledigt 08.11.:** `lib/ui/bundled_licenses.dart` trägt Emoji-Schrift (OFL-Volltext aus dem Asset), PaddleOCR, UVDoc und ONNX Runtime in die Lizenzseite ein (Test `bundled_licenses_test.dart`). Noch offen: Volltexte Apache-2.0 und MIT (Urheberzeilen von UVDoc und ONNX Runtime nicht neu geprüft) mitliefern; Hinweistexte sind englisch, wie Lizenztexte üblich.
2. Eigene `LICENSE` (MPL-2.0) im Repo, SPDX-Zeile in jeder Datei. **Erledigt 08.11.:** SPDX-Zeile in allen Dart-Dateien unter app/lib, app/test, app/tool (197 Dateien).
3. Quelltext der MPL-Dateien auf Verlangen bzw. öffentlich bereithalten – bei uns erfüllt das Repo.
4. Apache-2.0-Teile, die wir ändern (z. B. eine eigene Umwandlung eines Modells), kennzeichnen wir als geändert.

## Quellen

- Mozilla: MPL 2.0 FAQ – https://www.mozilla.org/en-US/MPL/2.0/FAQ/
- ECB: Haftungsausschluss und Urheberrecht – https://www.ecb.europa.eu/home/disclaimer/html/index.en.html
- PaddleOCR (Apache-2.0): Projekt- und Modellseiten auf GitHub/Hugging Face (Suche 08.11.2026, u. a. https://huggingface.co/monkt/paddleocr-onnx)
- Eigene Prüfung: `pubspec.lock` gegen `~/.pub-cache/hosted/pub.dev/*/LICENSE`, 08.11.2026
