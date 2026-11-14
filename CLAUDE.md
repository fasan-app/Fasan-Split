# Fasan Split – Arbeitsregeln

Fasan Split (`app.fasan.split`, Flutter) ist die Rechnungs-App der Fasan-Familie: Bon scannen, Summe, wer war dabei,
Posten zuordnen, wer hat bezahlt, Export. Der Code zieht später in Fasan Karte.

## PFLICHT vor jeder Arbeit (Nutzer 06.11. – nach wiederholt halbfertigen Lösungen; gilt ohne Ausnahme)

Diese Regeln stehen über allem anderen in dieser Datei. Wer sie nicht erfüllen kann, sagt das dem Nutzer, bevor er arbeitet.

**Angefangenes zuerst (Nutzer 06.11. 23:50):** Vor jeder neuen Arbeit selbstständig prüfen, ob zuletzt angefangene Aufgaben offen sind – eigene oder die
einer anderen Sitzung (Commits, `STAND.md`, `docs/ZUSAMMENARBEIT.md` „Belegt“/„pausiert“, „nicht angesehen“, „ungeprüft“). Diese werden **zuerst** nach
„Fertig heißt“ abgeschlossen; keine neuen Baustellen parallel öffnen. Reihenfolge: das zuletzt Begonnene zuerst, dann das davor.

**Laufend mitschreiben (Nutzer 06.11. 23:59):** Regelmäßig – nach jedem Teilschritt, nicht erst am Paketende – in `docs/ZUSAMMENARBEIT.md` („Protokoll“)
festhalten, was gerade gemacht wird und was noch fehlt; Schutz bei leerem Kontingent und für die andere Sitzung.
**Gründlich vor schnell (Nutzer 07.11. 00:00/00:02):** Rechen- und Wartezeit sind unwichtig; wichtig sind Gründlichkeit, sauberer und schneller Code,
Genauigkeit und Fehlerfreiheit. Dabei token-sparsam arbeiten (grep statt ganze Dateien, Bilder zusammengelegt ansehen, keine Wiederholungen).

**Mehrere Sitzungen arbeiten parallel (ab 06.11.):** vor jeder Arbeit `docs/ZUSAMMENARBEIT.md` lesen, Paket dort belegen, nur im eigenen Zweig arbeiten, Ende eintragen.

**Schritt 0 – Repos und Pflichtlektüre, prüfbar:**
1. Anbinden mit `add_repo` und je ein `git clone --depth 1`: `fasan-app/Fasan-Split` (push), `fasan-app/Fasan` (lesen),
   `fasan-app/fasan_ui` (push, Nutzer 06.11.), `fasan-app/fasan-diagnose` (lesen), **`fasan-app/Fasan-Karte` (lesen)**, **`fasan-app/Fasan-Camera`
   (lesen)**. Klon-Ordner neben diesem Repo: `../fasan`, `../fasan_ui`, `../fasan-diagnose`, `../fasan-karte`, `../fasan-camera`.
2. Prüfen, dass alles da ist – **nie mit `2>/dev/null` wegdrücken** (am 05.11. lief so eine Suche ins Leere und der Umbau geschah
   trotzdem ohne die Recherchen):
   `for d in ../fasan ../fasan_ui ../fasan-diagnose ../fasan-karte/docs/recherche ../fasan-camera/docs/recherche; do [ -e "$d" ] || echo "FEHLT $d"; done`
   Fehlt etwas: **stoppen, dem Nutzer melden, keine Design- oder Bedienarbeit beginnen.**
3. **Vor jeder Design-, UI- oder Bedienarbeit vollständig lesen (nicht per grep):** in `../fasan-karte/docs/recherche/`,
   `../fasan-camera/docs/recherche/`, `../fasan_ui/docs/recherche/` und `docs/recherche/` jede Datei zu Bedienung, Gestaltung, Psychologie,
   Bon, Kosten, Gruppe, Tests oder Plattform ganz; reine Fachthemen anderer Apps (Kamera-Hardware, Reiseinhalte wie Strände, Fahrpläne)
   nur Kopf und Kurzfassung – welche Datei so eingestuft wurde und warum, steht in der Prüfliste (06.11.). Dazu `../fasan/GRUNDSAETZE.md`, `../fasan/ZUSTAENDE-UND-PROFILE.md`,
   `docs/REGELWERK-OBERFLAECHE.md` und `docs/recherche/`. Daraus gilt die Prüfliste `docs/PRUEFLISTE-OBERFLAECHE.md` (Regel + Quelle);
   jeder geänderte Bildschirm wird gegen sie geprüft, Verstöße mit Bildschirmfoto belegt. Wo die Recherchen nichts sagen: neu
   recherchieren (Stand des Jahres, echte Quellen, keine Erinnerung aus Trainingsdaten) und als neu kennzeichnen.
4. `docs/ANFORDERUNGEN.md` lesen (alle Anweisungen des Nutzers mit Datum und Grund) und die Beschlüsse oben in `STAND.md`.
   Rohtext der Nutzer-Nachrichten: **`../fasan/nutzer/split-nachrichten.md`** (privat; Nutzer 06.11.). Jede Sitzung hängt dort neue
   Nachrichten an. Ins öffentliche Register nur sinngemäß, ohne private Details.

**Fertig heißt (alle Punkte, sonst ist es nicht fertig und wird nicht so gemeldet):**
1. Fehler mit echten Daten nachgestellt (echter Bon, echte Gruppe, echter Browser).
2. Ursache behoben, nicht nur die gemeldete Stelle.
3. Dieselbe Fehlerklasse über **alle** echten Bons und **alle** Bildschirme gesucht.
4. Ein Test, der ohne die Korrektur scheitert. Erkennung: je Posten **Name, Menge, Einzelpreis, Betrag** und die Summe (nicht nur Beträge
   – so rutschten am 06.11. „13 Croissants“ durch).
5. Mit echtem Bon auf Handygröße **angesehen**, App-Ansicht und Browser nebeneinander (Bildschirmfotos ansehen, nicht nur Tests).
6. Leistung im **echten Ablauf** gemessen (Bon mit Foto, Scannen, Gruppe), nicht nur Start- oder Einführungsbildschirm.
7. Bericht sagt genau, was wie geprüft ist und was nicht. Kein „fertig“, kein „wie vorher“, kein „grün“ ohne diesen Nachweis.
8. **Register geschlossen (Nutzer 14.11. 11:32: „mega wichtig“):** Jeder Eintrag in `docs/ANFORDERUNGEN.md`, den das Paket betrifft, bekommt im selben Commit seinen echten Stand – `erledigt <Version>, Beleg: <Test/Foto>`, `teilweise: <was fehlt>` oder `offen`. Nie nur in `STAND.md` vermerken. Vor jeder Meldung an den Nutzer `grep -c 'Stand: neu' docs/ANFORDERUNGEN.md` prüfen; „neu“ heißt: noch nicht angefasst.
Ein Paket wird ganz fertig gemacht, bevor das nächste beginnt. Halbe Pakete stehen offen in `STAND.md`.

**DATENSCHUTZ – keine echten Daten, nirgends (Nutzer 09.11. 00:40, oberste Priorität neben Sicherheit):** In Repo, Tests, Doku, Kommentaren, Commit-Texten, App-Demo, Leistungstest, Actions-Protokollen und Bildschirmfotos stehen **nur erfundene** Namen, Lokale, Adressen, Steuernummern, Daten und Beträge. Nie aus echten Bons, Gruppen oder Chats abschreiben, auch nicht „nur als Beispiel“ oder „nur im Kommentar“. Echte Bons liegen ausschließlich im privaten `fasan-diagnose`. Personen-, Rechnungs- und Gruppendaten liegen sonst nur verschlüsselt auf den Relays. Vor jedem Commit: `git diff` auf echte Namen prüfen. Fehler 08.11.: Leistungstest, Demo-Ansicht und Tests enthielten echte Lokale und Vornamen im öffentlichen Repo; 09.11. bereinigt, Verlauf neu begonnen.

**Feste Regeln:**
- **Browser = APK 1:1** (Menü, Knöpfe, Layout, Funktionen, Design). Eine Codebasis; `kIsWeb` nur in Plattform-Adaptern, nie in Bildschirmen.
  Jede Änderung wird in beiden geprüft.
- **Veröffentlichen (main)** nur, wenn Erkennungs-Tor (alle echten Bons, keine Verschlechterung), alle Tests, Browser-Ende-zu-Ende und
  Leistungsmessung grün sind. Jede Veröffentlichung steht in `STAND.md`.
- **Web folgt der App automatisch, solange eine Änderung nur Oberfläche und Logik betrifft (Nutzer 06.11.).** Berührt eine Änderung eine Fähigkeit der Plattform (Speicher,
  Dateien, Schrift/Symbole, Kamera, Benachrichtigung, Netz, Erkennung), geht sie über einen Adapter mit Web- und nativer Fassung (`*_web.dart`, bedingter Import; `kIsWeb` nie
  in Bildschirmen, `test/web_parity_test.dart` prüft das) und bekommt einen Eintrag in `docs/WEB-GRENZEN.md`. Jeder neue Bildschirm kommt in den Bildschirmvergleich
  (`tool/e2e/screens.js` und `test/screens_test.dart`, Schritte `b…`/`h…`); ungeprüft gilt „Web = App“ nicht.
- **Tutorial und Tipps bleiben aktuell (Nutzer 07.11.):** Jede Änderung, die Bedienung, Ablauf oder Einstellungen berührt, aktualisiert im selben Paket das Tutorial und die Tipps (Texte getrennt je Sprache unter `lib/l10n/`, nie im Code). Ein Test prüft, dass jede Sprache dieselben Tutorial-/Tipp-Schlüssel hat; neue Funktion ohne Tutorial-Eintrag gilt nicht als fertig.
- **Frühere Beschlüsse nie still umdrehen.** Widerspruch zwischen Anweisungen benennen und klären (Beispiel: „Bon-Ausschnitte zu groß“
  hieß kompakt machen, nicht entfernen).
- **Vor jeder Frage oder Empfehlung an den Nutzer** die vorhandenen Recherchen zum Thema lesen (`docs/recherche/`, Karte, Camera, fasan_ui);
  nie aus Erinnerung oder Fremdseiten antworten, wenn es eigene Messungen gibt (06.11.: Blossom/Relay-Grenzen falsch angegeben).
- **Bei Kritik des Nutzers nicht sofort losprogrammieren:** erst zeigen, dass die Kritik verstanden ist, und den Plan nennen.
- **Nichts dem Nutzer zum Prüfen überlassen, was die Sitzung selbst prüfen kann.** Was sie nicht kann (z. B. echtes iPhone), vorher sagen.
- **Was die Zukunft betrifft, sofort festschreiben – ohne Aufforderung (Nutzer 06.11.: „Dass ich dich daran erinnern muss …“).**
  Jede Zusage („ab jetzt …“), jede Lehre aus einem Fehler, jeder Beschluss, jede offene Frage an den Nutzer und jeder Kniff der
  Umgebung kommt im selben Arbeitsschritt in die passende Datei: Regeln → diese Datei, Beschlüsse/Plan/offene Fragen → `STAND.md`,
  Familie → `../fasan/ENTSCHEIDUNGEN.md`. **Vor jeder Antwort prüfen:** Steht etwas, das ich gerade sage, nur im Chat? Dann erst
  schreiben, dann antworten. Regeln müssen auf **main** liegen (neue Sitzungen starten dort); reine Doku mit `[skip ci]` im Commit
  auf main schieben, das löst keine Veröffentlichung aus (06.11. geprüft: kein CI-Lauf).
- **Vorschläge und Wünsche des Nutzers sofort festhalten (Nutzer 06.11.):** jede Idee, jeder Wunsch, jede Kritik kommt im selben Schritt
  sinngemäß in `docs/ANFORDERUNGEN.md` (mit Datum, Grund, Stand „neu“) und im Rohtext in `../fasan/nutzer/split-nachrichten.md`;
  was davon im Plan landet, steht in `STAND.md`. Nichts davon darf nur im Chat stehen.
- **Öffentliches Repo:** Fasan-Split ist öffentlich. Keine Rohtexte von Nutzer-Nachrichten, keine Fotos, keine privaten Daten hier
  ablegen (06.11. hat das Werkzeug genau das zu Recht blockiert). Private Ablage: `fasan-diagnose` (Bons), `Fasan` (privat).

**Selbstständig bis live (Nutzer 10.11. 00:33–00:37, ausdrückliche Erlaubnis):** Nach jedem Push selbst den CI-Lauf beobachten (`gh run list/view`, bei Fehlern `gh run view --log-failed` und die Artefakte `e2e-bilder` laden), Fehler ohne Rückfrage beheben und neu pushen, bis `deploy` grün ist und die Version live ist. Nie auf eine Antwort des Nutzers warten, solange offene Pakete in `STAND.md` stehen: nach jedem Paket sofort das nächste beginnen. Der Nutzer muss nie erinnern müssen. Stillstand ist schlecht. Stehen bleiben nur bei einer Entscheidung, die nicht rückgängig zu machen ist.

**Lehre 10.11. 17:37:** Eine Antwort mit „ich arbeite weiter“ beendet den Zug, danach läuft nichts (Nutzer wartete einen ganzen Tag). Solange Pakete in STAND.md offen sind, nie mit einer Ankündigung antworten: im Zug bleiben, Wartezeiten mit sleep-Schleifen überbrücken, nächstes Paket sofort beginnen; antworten erst, wenn gebaut, getestet, gepusht und live ist (oder eine unumkehrbare Entscheidung ansteht).

**Nach „live“ nicht aufhören (Nutzer 11.11. 02:53):** Ist ein Paket live, sofort das nächste benennen, bauen und verbessern; eigene Verbesserungen vorschlagen und umsetzen, nie warten, bis der Nutzer etwas sagt. Nachts komplett autonom (Nutzer 11.11. 02:52).

**Lehre 07.11.:** Nie `git add -A` über `app` (oder `.`), solange ein Web-Build läuft oder lief: `flutter create` legt `app/web/`, `.metadata`, `analysis_options.yaml` an und `pub get` ändert `pubspec.lock` – das landete so im Commit (Sitzung B, 07.11.). Vor jedem Commit `git status --short` ansehen und nur die gewollten Dateien mit Pfad hinzufügen; Build-Skripte räumen am Ende selbst auf.

**Lehre 09.11.:** Auch bei reinen Textänderungen (l10n, Tutorial, Tipps) vor dem Push `flutter analyze` und die betroffenen Tests laufen lassen: ein Apostroph in einem einfach gequoteten englischen Text ("group's") brach den Build, und der Push ging vorher raus (Sitzung B, 09.11.). Englische Texte ohne Apostroph schreiben oder doppelt quoten.

**Fehler, die passiert sind und nicht wieder passieren dürfen (05./06.11.; 07.11.: Test lud Schriften von `../../fasan_ui`, in der CI rot – Tests nie auf Nachbarordner verlassen, Pfade über `package_config.json`):** grüne Tests als Beweis ausgegeben, obwohl sie das
Entscheidende nicht prüften; Bildschirme veröffentlicht, ohne sie mit echtem Bon angesehen zu haben; Web 1:1 behauptet statt Bildschirm
für Bildschirm verglichen (⋮-Menü kaputt, Original/Digital-Knopf fehlte); Leistung nur am Startbildschirm gemessen und Effekte
abgeschaltet statt Ursachen gesucht; Bon-Ausschnitte entfernt statt verkleinert; Symptome statt Fehlerklassen behoben; Prüfaufgaben
dem Nutzer überlassen; die Pflicht-Recherchen nie gelesen und nach Gefühl gestaltet.

## Vor der Arbeit lesen (zusätzlich zur PFLICHT oben, nicht statt ihr)

1. `STAND.md` in diesem Repo.
2. `../fasan/ENTSCHEIDUNGEN.md`, `GRUNDSAETZE.md`, `ZUSTAENDE-UND-PROFILE.md` (Repo fasan-app/Fasan).
3. `../fasan-karte/docs/PLAN-FLUTTER.md`, Abschnitte „Stile und Effekte“ und „Rechnung“.
4. `../fasan-diagnose/README.md` (Regression der Erkennung; Dart-Gegenstücke in `app/test/`).
5. `../fasan-karte/docs/ENTSCHEIDUNGEN.md`: alle Beschlüsse zu Bon und Kosten. Das ist der Soll-Umfang dieser App.
6. Vor Design- und Bedienarbeit die Recherchen **vollständig** (PFLICHT, Schritt 3): `../fasan-karte/docs/recherche/`,
   `../fasan-camera/docs/recherche/`, `../fasan_ui/docs/recherche/`, `docs/recherche/`. Nicht per grep, nicht nur Kurzfassungen.
7. Prüfen heißt: Emulator-Bildschirmfotos mit echtem Bon (aus `fasan-diagnose`) ansehen, nicht nur grep.

## Regeln

- Nie in fremde Dienste schreiben: keine Uploads, Nostr-Ereignisse, POST/PUT an Dritte, auch nicht zum Testen; Recherche nur lesend; Ausnahme nur mit ausdrücklicher Freigabe (Beschluss 02.11.). Jeder Agent-Auftrag nennt das wörtlich.

- Nichts raten: Vor System-APIs, Plugins und Shadern die offizielle Doku lesen (api.flutter.dev, pub.dev,
  developer.android.com, onnxruntime.ai). Annahmen mit Quelle oder als „nicht geprüft“.
- Englische Bezeichner, Kommentare für spätere Bearbeiter, modular. Lizenz MPL-2.0, keine GPL-Bausteine.
- Oberfläche Deutsch und Englisch, Du-Form, kurze Sätze. Keine Telemetrie; Diagnose nur nach Zustimmung.
- Echte Bonfotos nie ins Repo und nie in den Code; bekannte Test-Bons nicht in der App hinterlegen.
- Tippfläche ≥ 48 dp (Profil „Einfach“ 60 dp), Bewegung folgt „Animationen entfernen“ und der App-Einstellung.
- Backlog: `STAND.md`, Abschnitt „Noch offen – Reihenfolge“, ist die Liste von allem, was fehlt. Nach jedem Paket aktualisieren, nie etwas still fallen lassen. Die Priorität setzt die Sitzung selbst; weicht sie von der Reihenfolge des Nutzers ab, steht der Grund im Abschnitt und in der Antwort (Nutzer 02.11.).
- Token sparen: große Code-Dateien per grep lesen (nicht die Pflichtlektüre, die wird ganz gelesen); nach jedem Arbeitspaket `STAND.md` aktualisieren.
- **Kontingent im Blick (Nutzer 06.11.):** Zeigt der Nutzer die Nutzung, gilt sie: Stand und Folgen in `STAND.md` („Kontingent“),
  Teures zuerst dort, wo es am meisten wirkt, laufend sichern; nie so weiterarbeiten, als wäre das Kontingent unbegrenzt.
- Commits als `Fasan <fasan-app@users.noreply.github.com>`.

## Neue Sitzung starten (Token sparen)

Startprompt: `docs/START.md`. Sitzung am besten mit dem Repo `fasan-app/Fasan-Split` starten (dann ist es schon geklont und diese
Datei geladen). Flutter kann das Setup-Skript der Cloud-Umgebung installieren (Vorlage in `docs/START.md`). Pfade unten mit
`/home/claude/` stehen für das Arbeitsverzeichnis der Sitzung; manche Sitzungen nutzen `/home/user/`.

## Arbeitsumgebung: alles läuft in der Cloud-Sitzung, der Nutzer arbeitet vom Handy (Beschluss 02.11.)

Der Nutzer hat keinen eigenen Rechner im Spiel. Nie „bei dir auf dem Rechner“ oder „lauf lokal“ antworten: Bauen, Testen,
E2E-Läufe und Commits macht die Sitzung selbst, Rückmeldung kommt vom Handy (S23). Ablauf, der funktioniert hat:

1. Repos anbinden mit `add_repo` (nicht vorher per curl prüfen): `fasan-app/Fasan-Split` (push), `fasan-app/Fasan` (Grundlagen),
   `fasan-app/fasan_ui` (Design), `fasan-app/fasan-diagnose` (privat, Test-Bons und Wahrheit), `fasan-app/Fasan-Karte` und
   `fasan-app/Fasan-Camera` (Recherchen, lesen) – siehe PFLICHT, Schritt 0. Dann je Repo EIN `git clone --depth 1 …` nach `/home/claude/<name>`, Timeout 10 min, nie parallel;
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
6. Commits als `Fasan <fasan-app@users.noreply.github.com>` mit den Anhängen der Sitzung. `app/pubspec.lock` nach `pub get` zurücksetzen
   (`git checkout`). Nicht mit `dart format` über bestehende Dateien gehen: das Repo ist nicht damit formatiert, der Diff explodiert.
7a. Fallstricke dieser Umgebung (06.11.): Der Klon holt nur `main` (`remote.origin.fetch` nur für main), darum fehlt für Arbeitszweige
   die Remote-Referenz und der Stop-Hook meldet nach jedem Push „no remote branch / unpushed commits“. **Einmal nach dem Klonen:**
   `git config --add remote.origin.fetch '+refs/heads/mitarbeit/*:refs/remotes/origin/mitarbeit/*' && git fetch origin`, nach dem ersten
   Push `git branch -u origin/<zweig>`. Prüfen mit `git status -sb` (zeigt `...origin/<zweig>`). `pkill -f <muster>` trifft
   die eigene Shell, wenn das Muster im Befehl steht (Exit 143) – Prozesse per PID beenden. Zwei Hintergrundläufe nie in denselben
   Ausgabeordner schreiben lassen. `rsync` und `ss` fehlen (cp bzw. curl nutzen). Das Ende-zu-Ende des Browsers (`tool/e2e/run.sh`)
   lokal: Web-Build mit `--dart-define=FASAN_RELAYS=ws://127.0.0.1:7777` plus `web_extra`, `python3 -m http.server 8765` im Ordner über
   `Fasan-Split/`, `tool/e2e/relay.py 7777` (pip `websockets==13.1`), dann `run.sh` als Hintergrundskript mit Log.
7. Push und CI: Der Push stößt die CI an, bei grünen Tests wird die APK als `neueste` veröffentlicht und kommt per In-App-Update
   aufs Handy. Das ist Teil der Arbeit (eigenes Repo, keine fremden Dienste); vor dem Push `git fetch origin` und Tests grün.

**APK auf Eis, nur Web (Nutzer 09.11. 03:20, am 11.11. 10:04 nochmals bestätigt):** Keine APK-Updates, keine Android-Arbeit. Entwickelt wird nur die Web-Version. „App“ ohne Zusatz heißt die Web-App; bei „App-Entwicklung außen vor“ o. ä. nachfragen, ob die APK gemeint ist, statt die Web-Arbeit zu stoppen.
