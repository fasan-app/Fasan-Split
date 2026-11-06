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

(werden nach der Befragung am 06.11. hier eingetragen)
