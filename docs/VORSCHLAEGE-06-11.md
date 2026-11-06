# Vorschläge und Fragen vom 06.11. (vor Punkt 0)

Nutzer 06.11.: „Punkt 0 beginnt erst, wenn du mir alle notwendigen Fragen und selbstständigen Vorschläge gestellt hast … fundamentale
Probleme und Funktionen werden vor sich hin geschoben.“ Grundlage: `STAND.md` (Noch offen, Soll-Liste, Verlauf), `docs/ROADMAP.md`,
Nachrichten des Nutzers (`../fasan/nutzer/split-nachrichten.md`), Code-Prüfung am 06.11. **Antworten des Nutzers stehen unten (§ D).**
Design-Vorschläge sind vorläufig, bis die Pflicht-Recherchen gelesen sind (Punkt 0); was die Prüfliste dann ändert, wird hier ergänzt.

## A. Grundlegende Ursachen, am 06.11. im Code gefunden

1. **Fotos und Bon-Ausschnitte gehen nicht in die Gruppe.** Der Abgleich (`collab/bill_sync.dart`) überträgt nur ein Vorschaubild
   (`meta/thumb`, 120 px), weder Original noch Ausschnitte. Auf jedem zweiten Gerät (Browser **oder** Android) fehlen darum:
   Original/Digital-Knopf (`common.dart`: nur wenn das Foto lokal liegt), „Neu lesen“, „Auf dem Bon zuordnen“, Ausschnitte. Das ⋮-Menü
   im Bon blendet diese Einträge aus und zeigt dann nur „Gleichmäßig teilen“ oder ist leer. Das erklärt „⋮ geht nicht / nur 1 Funktion“
   und „Original-Knopf fehlt“ im Browser. Vorschlag: Ausschnitte und ein verkleinertes Original verschlüsselt mit dem Bon teilen (Frage 1).
2. **Menüs verstecken Einträge, statt sie zu erklären.** Vorschlag (entscheide ich): Jedes Menü zeigt immer dieselben Einträge in derselben
   Reihenfolge; was hier nicht geht, ist ausgegraut mit Grund („Foto liegt auf dem Gerät von Chris“).
3. **Browser-Start lädt alle Bonfotos in den Arbeitsspeicher** (`state/images_web.dart`, `initImages`: jedes Foto aus IndexedDB, mehrere MB
   je Bon, vor dem ersten Bild). Vermutlich ein Hauptgrund für den langsamen Browser (noch nicht gemessen). Vorschlag: Fotos erst laden,
   wenn sie gebraucht werden; Kacheln nur mit Vorschaubild.
4. **Der Erkennungstest prüft nur Beträge.** Mengen und Namen werden nie geprüft; `readLines` nimmt den allgemeinen Leser, sobald die Summe
   aufgeht. Vorschlag: Goldens je Posten (Name, Menge, Einzelpreis, Betrag), Plausibilität Menge × Einzelpreis = Betrag im Leser, Tor in der CI.
5. **Der „eine Bildschirm“ (05.11.) und die Gruppe entstanden ohne die Pflicht-Recherchen.** Vorschlag: Konzept bleibt (Beschluss 05.11.),
   wird aber in Punkt 0 gegen die Prüfliste geprüft; Abweichungen kommen als eigene Vorschläge zurück.
6. **„Geprüft“ fehlt bei richtig gelesenen Bons** (Protokoll Belém 06.11.: Summe = Posten, aber `geprueft: false`), weil seit 05.11. nur der
   Prüfen-Knopf prüft. Vorschlag: kleines Häkchen im Summenfeld, wenn Posten = Summe (keine Zeile, Beschluss 05.11. bleibt); Prüfen-Knopf für
   Posten einzeln.

## B. Grundfunktionen, die seit Wochen offen sind (Soll-Liste, Fasan-Karte-Beschlüsse Bon 3.x / Kosten 2)

- Rückgängig/Wiederholen beliebig weit (Bon 3.17) – fehlt.
- Ausgaben ohne Kassenzettel (schnelles Formular) – fehlt.
- Aufteilen gleich, feste Beträge, Anteile, nach Posten (Kosten 2) – nur „nach Posten“ und „gleichmäßig“.
- Ausgleich **exakt** mit den wenigsten Überweisungen (heute gierig) und „bezahlt“ für Ausgleichszahlungen eintragen – fehlt.
- Rechnungen nur für Beteiligte sichtbar – fehlt.
- Lesesicherheit je Posten sichtbar, andere Lesungen wählbar, Korrekturen lernen – fehlt.
- Bon digital als PDF – fehlt. Währung aus dem Bon erkennen ($, £) – fehlt. Betrag im Geschäftsnamen trennen („Uber −12,98 €“) – fehlt.
- Scan-Begradigung (QR-Bereich, Keil unten links, Papierkante) – offen seit 03.11.
- Kontakte löschen (nur Vorschläge), Gruppe verlassen auf allen eigenen Geräten, verknüpfte Person umbenennen, Avatar/Gruppenbild – offen.
- Alte Texte noch im Code (`lib/l10n.dart`, `de ? … : …`) statt in Sprachdateien – offen (Nutzer 05.11.: alle Texte getrennt vom Code).
- Weltweit lesen: CJK, Kyrillisch, Arabisch usw. kann das lateinische Lesemodell nicht (Frage 3).
- Profile der Familie (Einfach 60 dp, Kinder, Gut lesbar …) – in Split nicht vorhanden.

## C. Prüfen, was die Sitzung bisher nicht konnte (entscheide ich, Nutzer bekommt keine Prüfaufgaben)

- APK-Bildschirmfotos mit echtem Bon über den vorhandenen Workflow „Emulator-Bilder“ im privaten `fasan-diagnose` – vor jeder
  Veröffentlichung, neben Browser-Bildschirmfotos aus Playwright (gleiche Daten, gleiche Größe).
- Safari: Playwright-WebKit als nächster Ersatz (Safari-Engine, nicht iPhone); echtes iPhone bleibt ungeprüft und wird so benannt.
- Leistung: Playwright auf echten Abläufen (Start mit 20 Bons und Fotos, Bon mit 30 Posten, Scannen, Gruppe), ungedrosselt und
  gedrosselt; Budget in der CI.

## Vorgeschlagene Reihenfolge

0. Pflicht (Recherchen, Register, Prüfliste). 1. Erkennung + Tor. 2. Paritäts-Tor: Emulator- und Browserbilder, Datenparität (A1–A3).
3. Architektur: Kerne als Pakete mit Tor-Tests, Plattform-Adapter (Frage 5). 4. Leistung in echten Abläufen. 5. Gestaltung nach Prüfliste:
Gruppe, Personen, Ausschnitte, Bon-Bildschirm. 6. Grundfunktionen aus B (Frage 6). 7. Weltweit lesen. 8. Rest (Visualisierung, Chat,
Glas, Profile).

## D. Antworten des Nutzers

Befragung 1 (06.11.):
1. Fotos/Ausschnitte teilen: **offen** – Nutzer fragt zuerst: „Was ist ein Blossom-Server, Pro und Kontra?“ (Antwort und neue Frage unten).
2. Personen: **ein Begriff „Personen“** mit Status „in der App“ / „ohne App“; Verwaltung/Rechte im Blatt der Person; eigener
   Mitglieder-Knopf fällt weg.
3. Weltweit lesen: **erst Latein perfekt (mit Tor), dann weitere Schriftmodelle direkt in die APK** (Beschluss 02.11. „offline ab
   Installation“ bleibt).
4. Zwischenstand: **keine Zwischenveröffentlichungen** – alles zusammen, wenn Umbau und Korrekturen fertig sind und das Tor besteht.

### Was ist ein Blossom-Server? (recherchiert 06.11., Quellen unten)

- **Was:** ein HTTP-Dateiserver für Nostr. Eine Datei liegt unter ihrem SHA-256-Fingerabdruck (`GET /<sha256>`, BUD-01). Hochladen mit
  einem signierten Nostr-Ereignis (kind 24242) im `Authorization`-Header (BUD-02, BUD-11). Abruf ohne Anmeldung, Server müssen
  `Access-Control-Allow-Origin: *` setzen (im Browser lesbar). Spiegeln auf mehrere Server (BUD-04), Serverliste je Nutzer (BUD-03).
- **Pro:** große Dateien (nostr.build/blossom.band laut Anbieter: bis 20 MiB je Datei kostenlos, Zahl der Uploads unbegrenzt), volle
  Auflösung möglich, Relays bleiben schlank (der Bon trägt nur Fingerabdruck und Schlüssel), mehrfach spiegelbar, später eigener Server
  (Open Source) möglich.
- **Contra:** zusätzlicher fremder Dienst. Verschlüsselung ist **nicht** Teil des Standards – Fasan müsste selbst verschlüsseln (geht:
  Schlüssel liegt im verschlüsselten Bon). Der Server sieht IP-Adresse, Zeit, Dateigröße und den öffentlichen Schlüssel des Hochladenden
  (steht im Token). Aufbewahrung nicht garantiert („Sunset“ ist nur ein Hinweis), Löschen hängt vom Server ab, Bedingungen und Kosten je
  Server; wer den Fingerabdruck kennt, kann die (verschlüsselte, ohne Schlüssel nutzlose) Datei laden. Welche weiteren öffentlichen Server
  es gibt und was sie kosten: nicht geprüft.
- **Zum Vergleich die Relays der App** (NIP-11 abgerufen 06.11.): nos.lol nimmt höchstens 128 KB je Nachricht, relay.damus.io und
  relay.primal.net 1 MB; Aufbewahrung ebenfalls ohne Zusage. Ein verkleinertes Original (200–400 KB) geht also nur in Stücken über alle drei.
- **Tests:** nur gegen einen lokalen Blossom-Nachbau (Regel „nie in fremde Dienste schreiben“).

Quellen: github.com/hzrd149/blossom (README, `buds/01.md`, `02.md`, `11.md`), b.nostr.build (Anbieterangaben), NIP-11-Antworten der drei Relays.

Befragung 2 (06.11.):
1. **Fotos teilen: Relays UND Blossom, beides als Standard** – doppelte Sicherung in niedriger (Relays: Ausschnitte + verkleinertes
   Original, verschlüsselt, in Stücken) und hoher Qualität (Blossom: volle Auflösung, verschlüsselt). **Bedingung des Nutzers:** darf
   Sicherheit und Leistung nicht beeinträchtigen. Umsetzung dafür (Vorschlag der Sitzung): eigener Schlüssel je Datei, Hochladen mit einem
   **Einmal-Schlüssel** (nicht dem Konto-Schlüssel), damit der Server kein Konto zuordnen kann; Server sieht dann nur IP-Adresse (wie die
   Relays auch), Zeit und Größe einer verschlüsselten Datei; Hochladen und Verkleinern im Hintergrund, nie im Bild-Takt; ohne Netz oder
   bei Fehler bleibt alles lokal und wird später wiederholt. Tests nur gegen lokalen Blossom-Nachbau. Welche Server: offen (Recherche).
2. **Architektur: komplett neu schreiben** (statt Kerne umziehen). Alte Teile nur als Vorlage; Schutz durch die Tore aus Schritt 1–2.
3. **Grundfunktionen in diese Runde:** Rückgängig/Wiederholen, Ausgaben ohne Bon, Aufteilen-Arten (gleich, fest, Anteile, nach Posten),
   exakter Ausgleich + „bezahlt“ eintragen. **Dazu:** „Prüfe, was zusätzlich noch offen ist – mir fallen sehr viele Dinge ein, die immer
   noch fehlen“ → vollständige Lückenliste in § E (aus Fasan-Karte-Beschlüssen = Soll-Umfang, Soll-Liste, Roadmap, Nachrichten).
4. **Reihenfolge: erst Tore, dann Umbau** – 0 Pflicht → 1 Erkennung + Tor → 2 Paritäts-Tor → 3 Neuschreiben → 4 Fotos teilen, Menüs →
   5 Leistung → 6 Gestaltung nach Prüfliste → 7 Grundfunktionen; alles in **einer** Veröffentlichung.

## E. Was noch fehlt – vollständige Lückenliste (06.11.)

Quellen: Soll-Umfang `../fasan-karte/docs/ENTSCHEIDUNGEN.md` (Bon 3.5–3.19, Kosten 2, 24.10.), `../fasan-karte/docs/PLAN-FLUTTER.md`,
`STAND.md` (Soll-Liste, Noch offen), `docs/ROADMAP.md`, Nachrichten des Nutzers. **Stand nach Doku, im Code noch nicht einzeln geprüft**
(das macht das Register in Punkt 0). ✅ = schon in dieser Runde (Befragung 2), sonst Vorschlag.

### E1 Rechnen und Aufteilen (Kosten 2, Karte 24.10.)
- ✅ Aufteilen gleich, feste Beträge, Anteile, nach Posten; ✅ exakter Ausgleich (wenigste Überweisungen); ✅ „bezahlt“ trägt Ausgleichsbuchung ein.
- ✅ Ausgaben ohne Kassenzettel (Formular). ✅ Rückgängig/Wiederholen (Bon 3.17).
- Summen müssen genau stimmen, sonst kein Eintragen – auch beim Teilen/Export und bei Entwürfen prüfen (offen seit 03.11.).
- Löschen überall mit Rückgängig (Karte 24.10.) – je Bildschirm prüfen.

### E2 Bon und Erkennung (Bon 3.8–3.19)
- Lesesicherheit je Posten sichtbar, andere Lesungen mit Prozent wählbar, Korrektur lernt den Lesefehler (3.11) – fehlt.
- Bon-Art erkennen (Restaurant, Café, Einkauf, Tanken …), füllt „Wofür?“ (3.9) – fehlt (Kategorie gibt es).
- Zusatzzeilen (Pfand, Rabatt, Extras) in der App umhängen oder als eigenen Posten (3.13); Posten ausblenden, andere Zeilen als Posten
  übernehmen (3.8) – fehlt.
- Bon-Ansicht „Nebeneinander“ (Original | Digital, 3.14), digital als PDF und Volltext (3.15) – fehlt.
- Ladeanzeige ist der Bon selbst (Lichtband, aufleuchtende Zeilen, 3.19) – teilweise (`scan_stage`), prüfen.
- Eigene Kamera-Ansicht mit Live-Begradigung (Plan Flutter, Rechnung 1) – fehlt.
- Leere Stelle im Bon antippen liest dort neu (3.10) – prüfen.
- Schraffur je Person zusätzlich zur Farbe (3.9); Farben Okabe-Ito oder eigene Palette (3.8) – offen.
- Währung aus dem Bon erkennen ($, £, USD); Betrag im Geschäftsnamen trennen („Uber −12,98 €“); Scan-Begradigung (QR-Bereich, Keil,
  Papierkante); Wörterbücher je Sprache; `de-discount.png`; SROIE 008/020/034/041 – offen.
- Weltweite Schriften – nach Latein (Beschluss 06.11.).

### E3 Gruppe, Personen, Chat
- Ein Begriff „Personen“ (Beschluss 06.11.); Gruppe „Bons zuerst“; Fotos/Ausschnitte teilen (Beschluss 06.11.).
- Rechnungen nur für Beteiligte sichtbar (Karte/Soll) – fehlt.
- Gruppe verlassen auf allen eigenen Geräten; verknüpfte Person umbenennen; Kontakte löschen (nur aus Vorschlägen); Avatar/Gruppenbild.
- Chat: Umfragen, „schreibt gerade“, Fotos im Chat, Reaktionen antippbar, Privatnachricht in der Gruppe (Entwurf mit dir), Blockieren,
  Freund per QR.
- Konto: Passkey (Messprobe S23), soziale Wiederherstellung (2 von 3) als Entwurf.

### E4 Übersicht und Saldo
- Saldo-Plakette auch auf Unterseiten; Filter nach Gruppe/Person/„ich schulde“, Suche; Visualisierung (Stand/Kategorien als Diagramm).
- „?“-Hilfen überall; Ziehen-Regel systemweit (Gruppen-, Freunde-Seite); Leerräume je Bildschirm.

### E5 Plattform und Gestaltung
- Browser = APK (Beschluss), Ton im Browser (Nutzer 05.11.), Haptik auf dem S23 nicht spürbar (Ursache offen).
- Profile der Familie (Einfach 60 dp, Gut lesbar/Groß, Kinder, Gast) – in Split nicht vorhanden.
- Tablet/Querformat zweispaltig (3.18), sehr große und kleine Bildschirme, Widgets (Saldo, schneller Scan).
- Meldungen, Dialoge, Blätter im Stil (SnackBar noch schwarzer Kasten); Menüs und Einstellungen neu ordnen; Übergänge ohne Ruckeln;
  Gestaltung §9 (Lebendig/Warten, Papier, Braun, Kino), echtes Glas (zurückgestellt).
- APK-Größe (`uvdoc.onnx` 31,6 MB, fp16 prüfen), Safari mit 1 Thread, Versionsmarke auf jeder Seite (3.17).
- Import aus Splitwise/Tricount, MCP-Schnittstelle (Roadmap).

### E6 Ungeprüft Gebliebenes (muss in die Tore, nicht zum Nutzer)
- SEPA-QR gegen das EPC-PDF; Wallet-Links (Nutzer 05.11.: „ob Wallets richtig lesen, musst du recherchieren“); EZB-Kurs im Browser (CORS);
  Benachrichtigungen, Tor/Orbot, Koppeln per QR, Bon-Status – alle „nicht auf dem Gerät geprüft“.
- Foto-Warteschlange „lief rot“ (Nutzer 05.11.) – Stand prüfen.

Befragung 3 (06.11.): **Alle vier Bereiche (E2 Bon & Erkennung, E3 Gruppe & Chat, E4 Übersicht & Saldo, E5 Plattform & Gestaltung)
kommen zusätzlich in diese eine Veröffentlichung.** Liste nach Nutzer vorerst vollständig. Neue Regel des Nutzers: „Wenn ich Vorschläge
für die App mache, müssen diese direkt aufgeschrieben und festgehalten werden.“
Folge (von der Sitzung benannt): Mit diesem Umfang und „keine Zwischenveröffentlichung“ kommt lange kein Update aufs Handy – auch die
Korrektur der 13 Croissants nicht. Der Nutzer kann das jederzeit ändern; bis dahin gilt sein Beschluss.

### Korrektur der Sitzung (06.11. nachts) zu Befragung 2, Frage 1 – Fehler: vorhandene Recherche nicht gelesen

`docs/recherche/2026-11-02-gruppe-nostr.md` (§ 2, § 3) hat Relays und Blossom am 02.11. **gemessen**. Die Angaben in der Befragung waren
dadurch teils falsch:
- Relays: nos.lol lehnt Ereignisse **ab 64 KB** ab (NIP-11 nennt 131072, stimmt also nicht); relay.primal.net bis 200 KB ok, 500 KB nicht.
  Faustregel dort: **≤ 48 KB je Ereignis**. Ein verkleinertes Original (200–400 KB) braucht also 5–10 Stücke je Bon.
- Blossom: **nostr.build/blossom.band und blossom.primal.net nehmen keine verschlüsselten Dateien** (415, nur echte Bilder). Angenommen haben
  verschlüsselte Blobs nur **cdn.hzrd149.com** und **nostr.download**. Aufbewahrung nirgends zugesagt.
- Die damalige Empfehlung lautete „Fotos gehören nie in Relays“ (wegen der Größe). Der Beschluss des Nutzers vom 06.11. (beides als Standard)
  bleibt umsetzbar: Relays in Stücken ≤ 40 KB, Blossom über die zwei Server, die verschlüsselte Dateien annehmen.
- **Dem Nutzer vorzulegen:** ob er den Beschluss mit diesen Fakten bestätigt.

Befragung 4 (06.11. nachts):
1. Fotos: **bestätigt mit den richtigen Fakten** – Relays (Stücke ≤ 40 KB) + Blossom (cdn.hzrd149.com, nostr.download, gespiegelt), beides Standard.
2. Testdaten: **„Alle echten Rechnungen und Kassenzettel, die du findest, auch vereinzelte“** – alle frei zugänglichen Datensätze (auch
   Forschungslizenz) und Einzelfunde, nur zum Testen, nie in App oder öffentlichem Repo; Quelle/Lizenz je Satz dokumentiert.
3. **Etwa 100 selbst beschriebene Bons** (Wahrheit je Posten nach dem Foto) zusätzlich zu den Datensätzen mit Wahrheit.
Kritik dazu: „Du arbeitest wieder nur mit 13 Bons, das ist keine Grundlage“ – schon am 05.11. gefordert, nicht erledigt.
