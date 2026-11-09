# Einstellungen für Fasan Split (Recherche 2026-11-02)

Stand: 02.11.2026. Eine Frage: Welche Einstellungen braucht Fasan Split, wie gruppiert, welche Standardwerte?
Quellen: Familienregeln (lokal), Fasan Karte (Web-App), vorhandener Code, 18 Web-Abrufe. Ungeprüftes ist als „nicht geprüft“ markiert.

## Kurzfassung

1. Wenige Einstellungen: Apple und Android sagen beide, Standardwerte sollen für die meisten passen und die Zahl klein bleiben [1][2]. Ziel: 8 Gruppen auf Ebene 1, höchstens 2 Ebenen, etwa 30 Einträge insgesamt.
2. Alles, was zu einer Rechnung gehört (gleich oder nach Posten, Trinkgeld, wer zahlt), ist keine Einstellung, sondern gehört in den Ablauf [1][2]. Die App merkt sich nur die letzte Wahl.
3. Systemeinstellungen nicht doppeln (Hell/Dunkel, Schriftgröße, „Animationen entfernen“, Berechtigungen) [1][2]. Standard „System“; eigene Schalter nur für Mehrwert (Stile, Filmeffekte, Weniger Bewegung als Zusatz).
4. Schon da (über `fasan_ui`): Stil, Akzent, Schrift, Hell/Dunkel, Filmeffekte samt 5 Reglern, Akku-Modus, Weniger Bewegung, Haptik, „Große Bedienung“, Stilvergleich, Lizenzen. Alles familienweit.
5. Fehlt und ist wichtig: Sprache (heute nur Systemsprache), Währung und Zahlenformat, „Ich bin“ und Personen, Foto-Aufbewahrung, Export/Sicherung/Löschen, Protokoll teilen sichtbar, Einführung erneut zeigen, Zurücksetzen.
6. Währung: Standard aus der Region des Geräts (Euro nur Rückfall). Fremdwährung mit Kurs von Hand; EZB-Kurs nur auf Knopfdruck, nie im Hintergrund (offline zuerst).
7. Datenschutz-Standard: Bonfoto bleibt auf dem Gerät, Protokoll nur nach Zustimmung und ohne Namen, keine Kontakte-Anfrage, kein Cloud-Backup ohne Entscheidung des Nutzers (offen: `allowBackup`).
8. Wenige Menschen ändern Standardwerte (Word-Studie: unter 5 %) [9]. Darum zählt der Standard mehr als jeder Schalter; ihn sichtbar machen und per „Zurücksetzen“ erreichbar halten.
9. Offene Entscheidungen für den Nutzer: Profil „Kinder“/„Gast“ in Split? Auto-Backup an oder aus? Bon-Foto nach dem Speichern behalten? App-Sperre ja/nein?

## 1. Was die Familie vorgibt

- Frei (MPL-2.0), offline zuerst, keine Telemetrie, keine Konten; Teilen entfernt Standort und Gerätedaten (GRUNDSAETZE.md).
- „Jede Einstellung erklärt sich“, „Doppeltipp auf Regler = Standard“, „Alles umkehrbar“ (GRUNDSAETZE.md).
- Profile gelten für alle Apps: Standard, Einfach, Kinder, Gast, Gut lesbar, Ruhige Hand (ZUSTAENDE-UND-PROFILE.md). Themes sind nur Aussehen.
- Akku (01.11.): Effekte bei wenig Akku und Energiesparmodus standardmäßig reduziert, „Akku maximal“ möglich, Nutzer behält die Wahl (ENTSCHEIDUNGEN.md).
- Split (02.11.): Speichern automatisch; Einführung und Beispiel-Bon überspringbar; Diagnose-Protokoll über „Teilen“, Briefkasten später (ENTSCHEIDUNGEN.md).
- Karte (01.11.): Tippfläche mindestens 48 dp, Profil „Einfach“ 60 dp. Diagnose-Hochladen nur nach Zustimmung (PLAN-FLUTTER.md).
- Einstellungen höchstens 2 Ebenen; „Erweitert“ als beschriftete Gruppe, nicht als dritte Ebene (fasan-camera, psychologie-bedienung, R-Regeln; Common Region: Gruppen mit Überschrift und Abstand).

## 2. Was es heute gibt

Split (`settings_screen.dart`): drei Zeilen: Aussehen (öffnet `FasanAppearancePage` aus `fasan_ui`), „Alle Stile vergleichen“, Über (Lizenzseite, Kurztext mit PaddleOCR, UVDoc, ONNX Runtime).
`FasanAppearancePage` / `FasanSettings`: Stil (6), Akzent (3), Schrift (3), Hell/Dunkel/System, Filmeffekte an/aus + Korn, Glühen, Halation, Überstrahlung, Bildstandwackeln (Standard leise), Akku (Automatisch/Akku maximal/Nie sparen) mit Link zum Energiesparmodus, Weniger Bewegung, Haptik, „Große Bedienung“ (60 dp).
Fasan Karte (Web, `site/app.js`, `zeichneMehr`): Profil, Bewegung (Wie das Gerät / Weniger Bewegung), Aussehen (Themes), „Über dich“ (Herkunftsland, Gehtempo, Essen), Navigation (Ansage), Stadtführer-Hinweise, Plan, Unterkunft, Daten und Verbindungen (Text), Quellen und Lizenzen, Zurücksetzen (Markierungen löschen), Einführung ansehen, Bon-Protokolle. Gut übertragbar: Profil, Bewegung, Daten-Text, Lizenzen, Einführung, Protokolle, Zurücksetzen.
Sprache: `l10n.dart` wählt Deutsch oder Englisch nach Gerätesprache, kein Schalter. Währung: im Code nur Euro (Fremdwährung laut STAND.md offen).

## 3. Gestaltungsregeln aus den Quellen

- Standardwerte für die größte Gruppe; Zahl der Einstellungen klein halten; Aufgaben-Optionen dort, wo sie wirken [1].
- Systemweite Einstellungen nicht nachbauen; nicht nach Dingen fragen, die sich erkennen lassen [1][2].
- Android: Standard „neutral, wenig Risiko, wenig Akku und Daten, nur unterbrechen wenn wichtig“ [2]. Ab 15 Einstellungen Untergruppen; bei tiefer Hierarchie Suche [2]. Schalter für Ein/Aus, Auswahl in Unterseite; Beschriftung ohne Verneinung, Status statt Erklärung als Zweittext [2].
- Android rät, App-Infos und Konto nicht auf die Übersicht zu legen [2]. Fasan legt „Über“ ans Ende (Abweichung bewusst klein).
- Berechtigungen erst, wenn die Funktion sie braucht; nur ein Knopf („Weiter“) vor dem Systemdialog [3].
- Studien: Defaults wirken stark, aber nicht überall gleich [5][6]; Wahlüberlast hat im Mittel Effekt nahe null, hängt von Bedingungen ab [7]. Folgerung: nicht Schalter zählen, sondern prüfen, ob Menschen sie im Moment verstehen (Test, nicht Telemetrie).
- Wettbewerb: Splitwise, Tricount, Settle Up und Spliit haben alle ein Gruppen- und Konto-Modell; reine Geräte-Einstellungen sind dort dünn. Siehe Abschnitt 5.

## 4. Vorschlag: Einstellungen in Gruppen

Legende: **F** = familienweit (in `fasan_ui` oder gemeinsamem Baustein), **S** = nur Split. Status: **da**, **teils**, **neu**.
Reihenfolge der Gruppen = Reihenfolge auf Ebene 1 (Häufiges zuerst). Jede Gruppenzeile zeigt den Zustand als Untertitel (z. B. „Euro · Deutsch“).

### 4.1 Rechnung und Erkennung (S)

| Einstellung | Standard | Warum | F/S | Status |
|---|---|---|---|---|
| Standardwährung | Währung der Geräteregion, sonst Euro | Erkennen statt fragen [1]; Splitwise rechnet je Teilnehmer in dessen Standardwährung um [11] | S (Währungsliste familienweit nutzbar) | neu |
| Fremdwährung: Kurs | von Hand; „EZB-Kurs holen“ nur auf Knopfdruck | offline zuerst, kein Hintergrundabruf; Settle Up lädt täglich und erlaubt feste Kurse je Gruppe [12] | S | neu (STAND: offen) |
| Bonland / Zahlenformat am Bon | automatisch erkennen | Leser erkennt Format am Bon (ENTSCHEIDUNGEN 29.10.); manuell nur als Rückfall unter „Erweitert“ | S | neu (nur Rückfall) |
| Trinkgeld-Art | % | Trinkgeld ist oft freiwillig (Karte, DECO) | S | neu |
| Trinkgeld-Vorgabe | 0 | nichts annehmen, was nicht auf dem Bon steht | S | neu |
| Bon-Foto behalten | ja, nur auf dem Gerät | Original muss erreichbar bleiben (ENTSCHEIDUNGEN 29.10.); „nach dem Speichern löschen“ als Option | S | neu |
| Foto im Verlauf verkleinern | an (nicht geprüft: Größe/Qualität) | spart Speicher; Wert noch zu messen | S | neu, nicht geprüft |
| Bon zeigen als | Scan (entzerrt) | neuer Dokumentlook (Karte 3.19); Foto bleibt wählbar | S | neu |
| Posten-Klarnamen mit Symbol | an | Wörterbuch (ENTSCHEIDUNGEN 29.10.), Bon-Name klein darunter | S | neu |
| Export-Format | Text und CSV (Semikolon, Dezimalkomma, BOM) | so bereits beschlossen (STAND.md) | S | teils (Teilen da) |

Keine Einstellung (feste Regeln): Cent nach Größte-Reste-Verfahren, Summen müssen exakt stimmen (ENTSCHEIDUNGEN 24.10.), Speichern automatisch (02.11.), Posten nur vorbelegt, wenn Summe passt. Bargeldrundung auf 5 Cent (z. B. CH, NL): Regeln und Geltung **nicht geprüft**; erst bei Bedarf recherchieren.
Gleich oder nach Posten, wer hat bezahlt, Anteile: im Ablauf, letzte Wahl merken; keine Einstellung [1][2].

### 4.2 Personen und Gruppe (S, später F mit Karte)

| Einstellung | Standard | Warum | F/S | Status |
|---|---|---|---|---|
| Ich bin … (Name, Farbe) | beim ersten Start gefragt, überspringbar | Spliit fragt beim Öffnen einer Gruppe, wer man ist [10]; Name nur lokal | F (Karte „Über dich“) | neu |
| Zuletzt genutzte Personen merken | an, nur auf dem Gerät | spart Tippen bei Stammrunden | S | neu |
| Gemerkte Personen verwalten / vergessen | Liste, Wisch zum Entfernen | Alles umkehrbar | S | neu |
| Kontakte vorschlagen | aus; keine Anfrage | Berechtigung erst bei Bedarf [3]; Daten minimal | F | neu |
| Standardgruppe | keine | Gruppen kommen erst mit dem Relay (Karte) | F | später, beschriftet „kommt“ |

### 4.3 Sprache und Region (F, Währung S)

| Einstellung | Standard | Warum | F/S | Status |
|---|---|---|---|---|
| Sprache | System (Deutsch/Englisch) | Android 13+ hat Pro-App-Sprache im System; eigener Schalter ist optional, und wer die öffentliche API nutzt, hält das System synchron [4] | F | neu (heute nur System) |
| Zahlen- und Datumsformat | folgt der Sprache/Region | `NumberFormat` nutzt Locale und ISO-4217-Währung [8] | F | neu (kein Schalter nötig) |
| Währung | siehe 4.1 | | S | |

Hinweis: iOS hat vergleichbar Pro-App-Sprache im System (nicht geprüft). Darum Sprachzeile mit Link „In Systemeinstellungen öffnen“ statt eigener Liste prüfen.

### 4.4 Darstellung (F, da)

| Einstellung | Standard | Warum | Status |
|---|---|---|---|
| Hell/Dunkel | System | Systemwahl respektieren [1][2] | da |
| Stil | Ruhe + Glas | Beschluss 01.11. | da |
| Akzent | Kobalt | Beschluss 01.11. | da |
| Schrift | Inter | Beschluss 01.11. | da |
| Stile vergleichen | Seite | hilft bei Wahl, kein Wert | da |

Schriftgröße: nicht nachbauen, Systemgröße gilt [1][2]; Profil „Gut lesbar“ erhöht Kontrast (7:1) zusätzlich.

### 4.5 Bewegung und Effekte (F, da)

| Einstellung | Standard | Warum | Status |
|---|---|---|---|
| Weniger Bewegung | aus; Systemoption „Animationen entfernen“ gilt immer | Familienregel; Zusatz, kein Ersatz | da |
| Filmeffekte an | an, leise | Beschluss 01.11. | da |
| Korn, Glühen, Halation, Überstrahlung, Bildstandwackeln | 0,25 / 0,2 / 0,15 / 0,1 / 0,15 | Beschluss 01.11.; unter „Erweitert“ einklappen | da |
| Haptik | an | Rückmeldung; Haptik-Quelle: fasan-camera/docs/recherche | da |

Spannung: Der Schalter „Weniger Bewegung“ doppelt eine Systemoption [1][2]. Er bleibt, weil er auch App-eigene Effekte (Shader, Gleiten) steuert. In der Zeile steht der Systemstatus als Zusatztext.

### 4.6 Akku (F, da)

| Einstellung | Standard | Warum | Status |
|---|---|---|---|
| Akku-Modus | Automatisch (spart bei ≤ 20 %, Energiesparmodus, Wärme ≥ moderat) | Android: Standard soll wenig Akku brauchen [2]; Beschluss 01.11. | da |
| Akku maximal / Nie sparen | Auswahl | Nutzer behält die Wahl | da |
| Energiesparmodus öffnen | Knopf | Systemeinstellung verlinken statt nachbauen [1] | da |

### 4.7 Bedienung und Profil (F)

| Einstellung | Standard | Warum | Status |
|---|---|---|---|
| Profil | Standard | Nutzergruppen sind Profile (07.10.) | teils (nur Schalter „Große Bedienung“ = Einfach) |
| Profile in Split | Standard, Einfach, Gut lesbar, Ruhige Hand | passen zu Rechnung; wirken auf Größe, Kontrast, Tippverhalten | neu |
| Kinder und Gast | offen | Sperre per PIN/Anheften sinnvoll bei Geld und Fotos? Entscheidung nötig | offen |
| Tippfläche | 48 dp; „Einfach“ 60 dp | Karte-Beschluss 01.11. | da |
| Haptik | siehe 4.5 | | da |
| Einführung erneut zeigen | Knopf | Einführung überspringbar (02.11.), also wieder aufrufbar | neu |
| Hinweise am Element | an, einmalig | „Hilfe im Moment“ (GRUNDSAETZE) | neu |

Profilwechsel mit Vorschau und Häkchen, nicht nur Farbe (Gestaltung-Recherche E6). „Große Bedienung“ wird zur Profilauswahl; Schalter bleibt als Kurzweg.

### 4.8 Datenschutz und Daten (F-Muster, Inhalte S)

| Einstellung | Standard | Warum | F/S | Status |
|---|---|---|---|---|
| Daten bleiben auf dem Gerät | Text mit Beleg, kein Schalter | Grundsatz | F | teils (Kurztext da) |
| Alles exportieren (Datei) | Knopf, Dateiformat offen (JSON mit Fotos als ZIP: nicht geprüft) | Mitnahme ohne Konto | S | neu |
| Aus Datei wiederherstellen | Knopf | Gegenstück zum Export | S | neu |
| Android-Sicherung (Auto Backup) | offen | Standard in Android ist an für Apps ab API 23, 25 MB Grenze, Einstellungen/Datenbank/Dateien eingeschlossen; Ausschluss per Regeldatei, Abschalten per `allowBackup=false` [13]. Cloud-Backup bei Google passt nicht ohne Weiteres zur FOSS-Haltung; Entscheidung nötig | F | neu, offen |
| Bon-Fotos von der Sicherung ausnehmen | ja | 25-MB-Grenze [13] | S | neu |
| App-Sperre (Fingerabdruck/PIN) | aus | Geld und Namen; Umsetzung nicht geprüft | F | neu, offen |
| Bon-Fotos löschen | Knopf mit Bestätigung | Alles umkehrbar nur vor dem Löschen; danach Hinweis | S | neu |
| Rechnungen löschen | je Rechnung, auch „Alle“ mit Bestätigung | Karte hat „Markierungen löschen“ als Vorbild | S | neu |
| Berechtigungen | Zeile mit Link zu den Systemeinstellungen (Kamera) | nicht nachbauen [1][2][3] | F | neu |
| Kamera-Berechtigung | erst beim ersten Scan anfragen, mit einem Satz Zweck | [3] | F | prüfen |

### 4.9 Diagnose (F-Muster, S-Inhalt)

| Einstellung | Standard | Warum | Status |
|---|---|---|---|
| Protokoll der letzten Erkennung teilen | Knopf in den Einstellungen (nicht nur nach Fehler) | STAND.md: „in Einstellungen gut sichtbar“ fehlt | teils |
| Foto ins Protokoll | aus, nur nach Rückfrage | Echte Bonfotos nicht ohne Zustimmung; Namen nie | teils |
| Protokolle automatisch sammeln | aus | keine Telemetrie | neu |
| Protokolle löschen | Knopf | umkehrbar; Speicher | neu |
| An Briefkasten senden | später; immer nach Zustimmung | Beschluss 01.11./02.11. | später |

### 4.10 Über (F)

Version (Marke), Lizenzen (da), Quellcode-Link, Datenquellen/Modelle (da im Kurztext), „Einführung ansehen“, Datenschutz-Kurztext. Ans Ende, nicht auf die Übersicht oben [2].

### 4.11 Zurücksetzen (F)

„Alle Einstellungen auf Standard“ (löscht keine Rechnungen). Getrennt von „Daten löschen“ (4.8). Je Regler Doppeltipp = Standard (GRUNDSAETZE).

## 5. Vergleich mit anderen Apps (was geprüft wurde)

- **Splitwise:** rechnet Ausgaben je Teilnehmer in dessen Standardwährung um [11]. Weitere Einstellungen (Vereinfachen, Benachrichtigungen, Export): im Abruf nicht belegt, **nicht geprüft**.
- **Tricount:** Mehrwährung (Kosten in verschiedenen Währungen, Gesamtsumme in einer) und Offline-Eintragen mit späterer Synchronisation [14]. Rundung, Export, Erinnerungen auf der Funktionsseite **nicht geprüft**.
- **Settle Up:** Kurse täglich von Yahoo, je Buchung änderbar, alle Kurse im Gruppen-Bildschirm änderbar; manueller Kurs gilt für künftige Buchungen; wiederkehrende Buchungen; Archivieren nur nach Ausgleich [12]. Rundung, Export, Backup, Offline **nicht geprüft**.
- **Spliit (FOSS):** Gruppen teilen, ungleich aufteilen, Rückzahlungen, Kategorien, Favoriten, „Wer bist du“ beim Öffnen, PWA, Bon-Scan mit KI-Anbieter; Standardwährung nur als Server-Variable `DEFAULT_CURRENCY_CODE` [10].
- Lehre: Gruppen-Einstellungen (Währung, Kurse, Rechte) sind in diesen Apps Gruppen-Daten. In Split gehören Währung und Kurs deshalb zur einzelnen Rechnung/Gruppe, die App-Einstellung liefert nur den Standard.

## 6. Reihenfolge und Aufbau

Ebene 1 (Liste, Untertitel zeigt Zustand): Rechnung und Erkennung · Personen · Sprache und Region · Aussehen (Stil, Hell/Dunkel, Akzent, Schrift) · Bewegung, Effekte und Akku · Bedienung und Profil · Daten und Datenschutz · Diagnose · Über.
Ebene 2: Einträge; Seltenes unter „Erweitert“ in der Gruppe (Effekt-Regler, Bonland von Hand, Fotoqualität).
Oben „Oft genutzt“ mit Währung, Profil, Hell/Dunkel (nur wenn Platz; Suche erst ab >15 Einträgen sinnvoll [2]).
Zusammenlegen der heutigen Seite `FasanAppearancePage` in zwei Seiten (Aussehen / Bewegung und Akku) ist ein Vorschlag, im Paket `fasan_ui` zu klären (nicht geprüft, ob die Seite sich teilen lässt).

## 7. Zu tun (Vorschlag, in dieser Reihenfolge)

1. Sprache (System/Deutsch/English) + Währungsliste + Zahlenformat über `intl` [8].
2. Daten: Foto-Aufbewahrung, Export, Löschen, Zurücksetzen.
3. Diagnose-Seite (Protokoll teilen sichtbar).
4. Personen („Ich bin“, gemerkte Personen).
5. Profile über `fasan_ui` ausbauen (Einfach, Gut lesbar, Ruhige Hand).
6. Offene Entscheidungen vom Nutzer holen (Kinder/Gast, Auto-Backup, App-Sperre).

## 8. Grenzen

- Splitwise-, Tricount- und Settle-Up-Hilfeseiten wurden nur über Suchergebnisse und Funktionsseiten erreicht; vollständige Einstellungsmenüs sind **nicht geprüft**.
- Rundungsregeln bar (CH, NL u. a.): Quelle nicht abrufbar, **nicht geprüft**.
- iOS-Pro-App-Sprache, Backup-Verhalten unter iOS, App-Sperre: **nicht geprüft**.
- Johnson & Goldstein (Organspende): Prozentwerte im Abruf nicht enthalten; nur die Aussage, dass Voreinstellungen stark wirken [5].
- Die „unter 5 %“-Zahl stammt aus einem Blogbeitrag zu einer Word-Befragung [9], nicht aus dem Primärpapier; Mackay 1991 nennt im Volltext keine Gesamtquote, aber „viele nutzen Anpassung gar nicht“ und Auslöser wie Beobachtung eigener Muster (43 %) [15].

## Quellen

1. Apple, Human Interface Guidelines: Settings. https://developer.apple.com/design/human-interface-guidelines/settings
2. Android Developers, Settings (Design-Muster). https://developer.android.com/design/ui/mobile/guides/patterns/settings
3. Apple, Human Interface Guidelines: Privacy. https://developer.apple.com/design/human-interface-guidelines/privacy
4. Android Developers, Per-app language preferences. https://developer.android.com/guide/topics/resources/app-languages
5. Johnson & Goldstein 2003, Do Defaults Save Lives? Science 302. Zusammenfassung: https://deceptive.design/articles/do-defaults-save-lives- ; Original: https://science.sciencemag.org/content/302/5649/1338.abstract (nicht abgerufen)
6. fasan-camera/docs/recherche/2026-10-12-psychologie-bedienung.md (R9, Voreinstellungen), lokal.
7. Scheibehenne, Greifeneder, Todd 2010, Can There Ever Be Too Many Options? https://ideas.repec.org/a/oup/jconrs/v37y2010i3p409-425.html
8. Flutter intl, NumberFormat.simpleCurrency. https://api.flutter.dev/flutter/intl/NumberFormat/NumberFormat.simpleCurrency.html
9. UIE, Do users change their settings? https://archive.uie.com/brainsparks/2011/09/14/do-users-change-their-settings/
10. Spliit. https://github.com/spliit-app/spliit
11. Splitwise-Überblick (Währung): https://robots.net/fintech/how-to-change-currency-in-splitwise/ (Sekundärquelle)
12. Settle Up Tipps. https://settleup.io/tips
13. Android Developers, Auto Backup. https://developer.android.com/identity/data/autobackup
14. Tricount Funktionen. https://www.tricount.com/en/features
15. Mackay 1991, Triggers and Barriers to Customizing Software. https://www.lri.fr/~mackay/pdffiles/CHI91.Triggers.pdf
16. Lokal: fasan/ENTSCHEIDUNGEN.md, GRUNDSAETZE.md, ZUSTAENDE-UND-PROFILE.md; fasan-camera/docs/recherche/2026-10-12-gestaltung-start-einstellungen.md; fasan-karte/site/app.js (`zeichneMehr`); fasan-split/app/lib/ui/settings_screen.dart; fasan_ui/lib/src/settings.dart, gallery.dart.
