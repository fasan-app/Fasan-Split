# Zusammenarbeit mehrerer Sitzungen (ab 06.11. nachts)

Mehrere Claude-Sitzungen (verschiedene Konten) arbeiten **gleichzeitig** an Fasan Split. Diese Datei ist der einzige Ort, an dem sie sich
abstimmen. **Vor jeder Arbeit lesen, beim Beginn und Ende jedes Pakets aktualisieren, sofort auf `main` schieben** (`[skip ci]`, nur Doku).

## Regeln

1. **Ein Paket = ein Zweig** `mitarbeit/<kürzel>-<thema>` (Kürzel: `A` = erste Sitzung, `B` = zweite Sitzung). Nie zwei Sitzungen im selben Zweig.
2. **Paket belegen, bevor du anfängst:** Zeile in „Belegt“ eintragen (Kürzel, Paket, Zweig, Dateien/Bereiche, Beginn), auf `main` schieben,
   dann `git pull` und prüfen, dass niemand dasselbe belegt hat (wer zuerst auf `main` steht, hat es).
3. **Bereiche nicht überschneiden.** Wer `lib/ui/groups.dart` belegt hat, dem gehört die Datei bis zur Freigabe. Gemeinsame Dateien
   (`lib/l10n/strings_*.dart`, `STAND.md`, `docs/ANFORDERUNGEN.md`, `pubspec.*`) nur kurz anfassen, sofort committen und pushen, vorher `git pull --rebase`.
4. **Zusammenführen** in den gemeinsamen Arbeitszweig `mitarbeit/erkennung-und-ein-bildschirm` nur mit grünem schnellen Tor (Tests, Analyse,
   Wächter `architecture_test`, `web_parity_test`); vorher `git pull --rebase` des Arbeitszweigs. Veröffentlichung auf `main` (App-Update) nur nach
   dem **vollen Tor** und Absprache hier (Beschluss: eine Veröffentlichung am Ende).
5. **Fertig/frei:** Zeile von „Belegt“ nach „Erledigt“ mit Ergebnis und Nachweis (Tests, Bildschirmfotos, was nicht geprüft ist).
6. **Fragen an die andere Sitzung** unter „Nachrichten“ mit Datum und Kürzel; Antwort darunter. Nutzer-Nachrichten weiter in
   `../fasan/nutzer/split-nachrichten.md` (privat) und sinngemäß in `docs/ANFORDERUNGEN.md`.
7. Kontingent: Wer knapp wird, sichert sofort (Commit, Push, Eintrag hier „unterbrochen bei …“), damit die andere Sitzung übernehmen kann.

## Gerechte Aufteilung (Vorschlag, jede Sitzung darf hier umbelegen)

| Bereich | Wer | Inhalt |
|---|---|---|
| Erkennung (`packages/fasan_reader`, `lib/recognition`, Tor, Korpus) | **B** | 8 Welt-Bons „falsch als geprüft“, Hangul, Aldi, SROIE/CORD, Pfand/Rabatt-Hinweise strukturiert statt Text |
| Grundfunktionen + Gruppe (`lib/ui/groups.dart`, `flow.dart`, `lib/state`, `lib/collab`) | **A** | Lücken E3/E4 (`docs/VORSCHLAEGE-06-11.md`), Blossom-Kanal, Fotos von jedem Mitglied neu senden |
| Bon-Bildschirm + Gestaltung (`bill_screen`, `item_sheet`, `receipt_view`) | frei | E2/E5: Querformat-Leiste, „Nebeneinander“, PDF |
| Architektur-Rest | frei | `ui` weiter an Verträge, `fasan_core` eigene Tests, Texte nach Bereichen teilen |
| Leistung (echte Abläufe, große Fotos, alte Geräte) | frei | Messung im Browser gedrosselt + Budget in CI |

## Belegt

| Kürzel | Paket | Zweig | Dateien/Bereiche | seit |
|---|---|---|---|---|
| – | – | – | – | – |

## Erledigt (neueste oben)

- 06.11. nachts, A: Neuaufbau Schritte 2–6 (Pakete `fasan_core`, `fasan_reader`, Schichten + Wächter, 602 Texte in Tabellen), Bildschirmvergleich
  App/Browser (6 Funde behoben), Rückgängig/Wiederholen, Festbetrag, exakter Ausgleich, „bezahlt“ inkl. Teilbetrag. Volles Tor grün (341 Tests,
  Web-Build, Foto-Ende-zu-Ende, Erkennung 132 Bons/0 Fehler, Korpus gleich). Einzelheiten: `STAND.md`, `docs/ARCHITEKTUR.md`.

## Nachrichten

- 06.11. nachts, A → B: A ist am Kontingent-Ende und pausiert. Übernimm, wo du willst; belege vorher hier. Werkzeuge der Sitzung (nicht im Repo,
  neu anlegen): siehe `STAND.md` „Übergabe“.
