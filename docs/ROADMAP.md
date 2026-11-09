# Roadmap Fasan Split und Fasan-Familie (Stand 04.11.2026)

Zusammengetragen aus allen Repos der Familie (gelesen 04.11.): `fasan-app/Fasan` (ENTSCHEIDUNGEN, GRUNDSAETZE,
ZUSTAENDE-UND-PROFILE), `Fasan-Karte` (docs/PLAN-FLUTTER, docs/ENTSCHEIDUNGEN, Recherchen), `fasan_ui`
(docs/GESTALTUNG §4 und §9), `Fasan-Camera` (FUNDAMENT, Recherchen), `CUK999/Fasan-Kiosk` (README, BAUPLAN),
`Fasan-Releases` (leer), dieses Repo (STAND.md A1–A14, docs/recherche). Was hier steht, ist Plan, nicht Stand; der Stand
steht in STAND.md. Reihenfolge innerhalb eines Abschnitts = Vorschlag der Sitzung, Begründung in Klammern.

## 1. Fasan Split – jetzt (Fehler und Bedienung, die stören)

1. Rückmeldungen vom S23 prüfen (0.1.47+): Bon-Ansicht ohne Flackern, Wischfläche, Plus-Knopf, Namen aus der Erkennung.
2. Fasan-Glas (fasan_ui §4/§9.3): echte Brechung ohne ImageFilter.shader (Hintergrund per `toImageSync`, auf dem S23
   schwarz), Spiegelung beim Scrollen, z-Ebenen, Neigungsschatten; Leistungstest (§9.6) vorher, „spektakulär smooth“.
3. Meldungen, Dialoge, Blätter im Stil (§9.7; SnackBar noch schwarzer Kasten).
4. Übergänge ohne Ruckeln messen (FrameTiming, alte Geräte), Bildschirmfotos aller Seiten hell/dunkel/quer.
5. Menü und Einstellungen neu ordnen (Recherche fasan-camera gestaltung-start-einstellungen).
6. Avatar/Profil auf allen Seiten, Avatar- und Gruppenbild, Namen ändern.

## 2. Fasan Split – Umfang aus Fasan Karte (Beschlüsse Bon 3.5–3.19, Kosten 2)

- Kosten 2: mehrere Zahler und Anzahlung; Aufteilen gleich, feste Beträge, Anteile oder nach Posten; Trinkgeld
  anteilig; Cent nach Größte-Reste; Ausgleich EXAKT mit den wenigsten Überweisungen (Teilmengen mit Summe 0, nicht
  gierig – heute ist `settle.dart` gierig); „Bezahlt“ trägt Ausgleichszahlungen ein; Personen ohne App.
- Ausgaben ohne Bon (schnell), Fremdwährung (gebaut), Währung aus dem Bon erkennen.
- Rückgängig/Wiederholen beliebig weit (Bon 3.17).
- Schraffur je Person zusätzlich zu Farbe (Bon 3.9).
- Bon digital als PDF teilen (Familienbeschluss 02.11.: drei Ansichten, digital auch als PDF).
- Rechte: Standard alle gleich; Rechnungen auf Beteiligte begrenzen (nur wer dabei war, sieht sie) – noch nicht gebaut;
  Sperren von Änderungen über mich (gebaut).
- Erkennung: Original-Zeilen genauer, Lesesicherheit aus Wortkonfidenzen, echte Alternativen, Korrekturen lernen,
  Wörterbücher; Scan-Begradigung (QR-Bereich, Keil unten links, Papierkante), Kopf/Geschäftsname aus abgeschnittenem Kopf.
- Bons per Langdruck (gebaut), Kontakte löschen (teils), Chat: Bon-Verweis mit @, Anpinnen, Privatnachricht
  (NIP-44 je Empfänger, Entwurf mit dem Nutzer).
- Ort per OpenStreetMap nur auf Knopfdruck; Zuordnung zu Reise und Tag später in Karte.

## 3. Fasan Split – Plattform und Verteilung

- Web-App = volle App (gebaut, Erkennung im Worker, 4 Threads); Safari/iPhone prüfen (Speicher, credentialless).
- Pages: `fasan-app/fasan-app.github.io` ist PRIVAT – GitHub Pages aus privaten Repos braucht einen bezahlten Plan; ohne
  Veröffentlichung findet Android `assetlinks.json` nicht (App Links). Prüfen (Nutzer): Repo öffentlich machen.
- Verteilung: GitHub Releases (läuft), Obtainium, später F-Droid (ohne Google-Bibliotheken) und Google Play; iOS über
  Web, später nativ. Release-Schlüssel aktiv seit 04.11., Offline-Kopie beim Nutzer.
- Widgets (Saldo, schneller Scan), sehr große (Tablet, Foldable, Desktop) und kleine Bildschirme, Querformat
  (Familienbeschluss 08.10.: alle Geräteklassen mit Größenklassen).
- MCP-Schnittstelle für KI (Entwurf: lokal aus Sicherung/Export oder als Gruppenmitglied mit eigenem Schlüssel, Schreiben
  nur nach Freigabe); Import aus Splitwise/Tricount.
- Profile der Familie (Standard, Einfach 60 dp, Kinder, Gast, Gut lesbar, Ruhige Hand) – in Split noch nicht.
- APK-Größe (uvdoc 31,6 MB), Akku mit Korn, SROIE nachmessen.

## 4. Fasan Karte (Ziel: Split zieht hinein)

Reihenfolge laut PLAN-FLUTTER: Grundgerüst, Designpaket, Rechnung (= Split) → Karte, Plan, Gruppe, Mehr.
- Karte offline (PMTiles je Reiseziel), Orte, Fotospots, Besuchsdauer, Badestrände, Supermärkte, Fahrpläne, Höhen
  (Copernicus DEM), Länderdaten, Kultur/Sprache, Recht/Gesundheit (Recherchen liegen vor).
- Plan und Abstimmungen (verdeckte Stimmen), Live-Standort nur während Freigabe (Foreground Service), Treffpunkt,
  Notfallseite offline, Gruppe mit Chat.
- Push zuerst FOSS (ntfy/UnifiedPush), FCM später. App-Kennung `app.fasan.karte`, Android ≥ 10.
- Vorkehrung in Split dafür: Module ohne App-Abhängigkeiten (model, collab, recognition, state), App-Kennungen getrennt,
  Gruppenformat versioniert und abwärtskompatibel.

## 5. Familie und Server

- fasan_ui §9: Lebendig/Warten, Haptik und Klang (auf dem S23 nicht spürbar, Ursache offen), Glas 3D, Papier,
  Braun-Technik, Kino mit Film-Voreinstellungen, Leistungstest, Overlays im Stil.
- VPS (erst nach gemeinsamer Prüfung): Gruppen-Relay E2E, ntfy, Diagnose-Briefkasten (Token nur auf dem Server),
  Traccar; Server nur einseitig nach GitHub; Beta-Wünsche ohne GitHub-Konto.
- Netz je Funktion freigeben, Protokoll jeder Verbindung, Offline-Ausgabe ohne Internetrecht (Familienbeschluss 08.10.).
- Fasan Kamera ruht (Stufe 2a; Stufen 3–10: Freistellung, Mehrgeräte, Editor, Video/Ton, Galerie, Training, Tresor,
  Dokumente), Fasan Player und RSS geplant, Fasan Kiosk (Bilderrahmen, K0–K9), Sammel-App „Fasan Live“ als Fernziel.
- Marke „Fasan“ vor Veröffentlichung schützen, Beiträge Dritter nur mit CLA.
