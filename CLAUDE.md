# Fasan Split – Arbeitsregeln

Fasan Split (`app.fasan.split`, Flutter) ist die Rechnungs-App der Fasan-Familie: Bon scannen, Summe, wer war dabei,
Posten zuordnen, wer hat bezahlt, Export. Der Code zieht später in Fasan Karte.

## Vor der Arbeit lesen (nur diese Dateien)

1. `STAND.md` in diesem Repo.
2. `../fasan/ENTSCHEIDUNGEN.md`, `GRUNDSAETZE.md`, `ZUSTAENDE-UND-PROFILE.md` (Repo fasan-app/Fasan).
3. `../fasan-karte/docs/PLAN-FLUTTER.md`, Abschnitte „Stile und Effekte“ und „Rechnung“.
4. `../fasan-diagnose/README.md` (Regression der Erkennung; Dart-Gegenstücke in `app/test/`).
5. `../fasan-karte/docs/ENTSCHEIDUNGEN.md`: alle Beschlüsse zu Bon und Kosten. Das ist der Soll-Umfang dieser App.
6. Vor Design- und Bedienarbeit die Kurzfassungen der Recherchen: `../fasan-karte/docs/recherche/` (gestaltung-psychologie,
   ui-design-2026, natives-gefuehl, rechnung-teilen-ux, gemeinsam-bearbeiten, bon-ansicht-und-farben, scan-und-bedienung,
   kosten-und-fuehrung), `../fasan-camera/docs/recherche/` (psychologie-bedienung, gestaltung-start-einstellungen, haptik),
   `../fasan_ui/docs/recherche/`. Details per grep.
7. Prüfen heißt: Emulator-Bildschirmfotos mit echtem Bon (aus `fasan-diagnose`) ansehen, nicht nur grep.

## Regeln

- Nie in fremde Dienste schreiben: keine Uploads, Nostr-Ereignisse, POST/PUT an Dritte, auch nicht zum Testen; Recherche nur lesend; Ausnahme nur mit ausdrücklicher Freigabe (Beschluss 02.11.). Jeder Agent-Auftrag nennt das wörtlich.

- Nichts raten: Vor System-APIs, Plugins und Shadern die offizielle Doku lesen (api.flutter.dev, pub.dev,
  developer.android.com, onnxruntime.ai). Annahmen mit Quelle oder als „nicht geprüft“.
- Englische Bezeichner, Kommentare für spätere Bearbeiter, modular. Lizenz MPL-2.0, keine GPL-Bausteine.
- Oberfläche Deutsch und Englisch, Du-Form, kurze Sätze. Keine Telemetrie; Diagnose nur nach Zustimmung.
- Echte Bonfotos nie ins Repo und nie in den Code; bekannte Test-Bons nicht in der App hinterlegen.
- Tippfläche ≥ 48 dp (Profil „Einfach“ 60 dp), Bewegung folgt „Animationen entfernen“ und der App-Einstellung.
- Token sparen: große Dateien nur per grep lesen; nach jedem Arbeitspaket `STAND.md` aktualisieren.
- Commits als `Fasan <fasan@christopherziehm.de>`.

## Arbeitsumgebung: alles läuft in der Cloud-Sitzung, der Nutzer arbeitet vom Handy (Beschluss 02.11.)

Der Nutzer hat keinen eigenen Rechner im Spiel. Nie „bei dir auf dem Rechner“ oder „lauf lokal“ antworten: Bauen, Testen,
E2E-Läufe und Commits macht die Sitzung selbst, Rückmeldung kommt vom Handy (S23). Ablauf, der funktioniert hat:

1. Repos anbinden mit `add_repo` (nicht vorher per curl prüfen): `fasan-app/Fasan-Split` (push), `fasan-app/Fasan` (Grundlagen),
   `fasan-app/fasan_ui` (Design, anonym lesbar, Klon nach `/home/claude/fasan-app/fasan_ui`), `fasan-app/fasan-diagnose` (privat,
   Test-Bons und Wahrheit). Dann je Repo EIN `git clone --depth 1 …` nach `/home/claude/<name>`, Timeout 10 min, nie parallel;
   danach `register_repo_root`. Bei „service unavailable“ oder „token is being refreshed“: kurz warten, einmal wiederholen.
2. Flutter 3.47.7 (wie CI): `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.7-stable.tar.xz`
   nach `/home/claude/tools` (Download im Hintergrund, Entpacken dauert ~2 min), `git config --global --add safe.directory
   /home/claude/tools/flutter`, `export PATH=…/flutter/bin FLUTTER_SUPPRESS_ANALYTICS=true`, `flutter config --no-analytics`.
   Danach `cd app && flutter pub get`, `flutter analyze`, `flutter test`.
3. Modelle: `bash app/tool/fetch_models.sh` (öffentliche Quelle, Prüfsummen). ONNX Runtime: `https://github.com/microsoft/onnxruntime/
   releases/download/v1.22.0/onnxruntime-linux-x64-1.22.0.tgz`, `LD_LIBRARY_PATH=…/onnxruntime-linux-x64-1.22.0/lib`.
4. E2E: `FASAN_DIAGNOSE=/home/claude/fasan-diagnose/tests [FASAN_BONORDNER=…/tests/echt] flutter test test/e2e_test.dart`
   (Vergleich Abbruch: `FASAN_EARLYSTOP=0`), SROIE: `git clone` des Datensatzes laut fasan-diagnose/README. Nur 2 CPU-Kerne:
   ~15 s je Bon, lange Läufe als Hintergrundskript mit Log in `/home/claude/tools`, nicht im Vordergrund.
5. APK der Testversion ist öffentlich lesbar (`releases/tags/neueste`); Berechtigungen und Version daraus lesen
   (`pip install androguard`, Logging mit `loguru` abschalten, sonst 100 KB Ausgabe).
6. Commits als `Fasan <fasan@christopherziehm.de>` mit den Anhängen der Sitzung. `app/pubspec.lock` nach `pub get` zurücksetzen
   (`git checkout`). Nicht mit `dart format` über bestehende Dateien gehen: das Repo ist nicht damit formatiert, der Diff explodiert.
7. Push und CI: Der Push stößt die CI an, bei grünen Tests wird die APK als `neueste` veröffentlicht und kommt per In-App-Update
   aufs Handy. Das ist Teil der Arbeit (eigenes Repo, keine fremden Dienste); vor dem Push `git fetch origin` und Tests grün.
