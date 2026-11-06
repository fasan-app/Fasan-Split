# Prüfliste Oberfläche (Regel + Quelle)

**IM AUFBAU (06.11., Punkt 0).** Gilt erst als fertig, wenn alle Quellen unten als „gelesen“ markiert sind und diese Zeile entfernt ist.

Grundlage ist `docs/REGELWERK-OBERFLAECHE.md` (13 Abschnitte, Stand 02.11., Kürzel dort). **Alle Regeln des Regelwerks gelten
weiter** und werden hier nicht wiederholt; hier stehen (a) neue Regeln aus den 06.11. vollständig gelesenen Quellen, (b) Widersprüche,
(c) schon gefundene Verstöße im heutigen Code. Jede Regel: Nr. · Regel · Quelle · gilt für · wie geprüft.

## Gelesen (vollständig, 06.11.)

- `../fasan/GRUNDSAETZE.md`, `../fasan/ZUSTAENDE-UND-PROFILE.md`, `docs/REGELWERK-OBERFLAECHE.md`
- `../fasan_ui/docs/recherche/`: design-grundlagen, navigation-layout-glas-ton, glas-neigung-bewegung, farbe-verlauf-aufmerksamkeit,
  lebendig-warten, echtes-glas-flutter, filmkorn-alter-film, stil-papier, stil-braun-technik (alle 9)

## Noch zu lesen (0b, vor jeder Gestaltungsarbeit; Plan in STAND.md „Kontingent“)
- Im Regelwerk schon verdichtet (Kürzel dort), nur Kurzfassung gegen das Regelwerk abgleichen: GP, NG, KF, RT, GB, BF, FR, UI, SB, PB, GE, HA.
- Ganz zu lesen: Karte kassenzettel, karten-ux, reisende-anforderungen, belegarten, dokument-restaurierung, protokoll, echte-bons,
  bon-erkennung, bon-erkennung-weltweit, fehleranalyse-da-se; Camera kamera-ux, zustaende-ein-ausgaben, tests-robustheit,
  wuensche-roadmap-updates, gesamtueberblick; Split einstellungen, konkurrenz-bedienung-saldo, einladen-benachrichtigen-messenger,
  einladung-situationen, konto-wiederherstellung, gruppe-nostr, updates-delta, anbindungen-zahlung-netz, zusammenarbeit-verschluesselung.
- Nicht relevant für Split (nur Kopf geprüft, Fachthema anderer App): Karte portugal-recht-gesundheit, laenderdaten-weltweit, hoehendaten,
  standort-und-live, fotospots, badestraende, besuchsdauer, supermaerkte, fahrplaene, kultur-sprache (Reise-Sätze), gruppenreisen
  (Abstimmen über Orte; Kosten-Teil steckt in KF); Camera camera2-fundament, aufnahmekette, camera2-belege, flutter-bruecke,
  foto-ausloeser, zeitbasierte-funktionen, video-faehigkeiten, horizont, hardware-eingaben, profi-kameras, kamerawechsel, zeitlupe,
  bessere-bilder, musik-erkennen, ki-werkzeuge, beta-ohne-github, video-haptik-belege (Haptik-Teil in HA). **Kopf noch nicht geprüft**
  – das geschieht in 0b, vorher gilt die Einstufung als vorläufig.

### Fortschritt 0b (06.11. vormittags)
Ganz gelesen: Split einstellungen, konkurrenz-bedienung-saldo, einladen-benachrichtigen-messenger, einladung-situationen,
konto-wiederherstellung, gruppe-nostr, updates-delta, anbindungen-zahlung-netz, zusammenarbeit-verschluesselung.
Daraus für Punkt 3 (Browser = APK): Fotos verschlüsselt auf Blossom (eigener Schlüssel je Foto, `{h,k,u,n}` in der Rechnung,
Upload an 2 Server, lokale Kopie bleibt, „Foto nicht mehr online“ als Zustand), Relay-Ereignis ≤ 48 KB, Snippets/kleines Original
in Chunks über Relays; Web-Speicher: Safari löscht nach 7 Tagen ohne Besuch (Home-Bildschirm ausgenommen) → Sicherung anbieten.
Offen in 0b: Karte (10 Dateien), Camera (5 Dateien).

## Neue Regeln

### A. Aufmerksamkeit und Bewegung
- **A1** Höchstens **ein** Bereich mit Aufmerksamkeitszustand je Bildschirm. Quelle: farbe-verlauf-aufmerksamkeit §2, §6. Alle Bildschirme.
  Prüfen: Bildschirmfoto, Zählung.
- **A2** **Kein Dauerpulsieren.** Hinweis = einmaliger Impuls (≤ 600 ms, Ring Deckkraft ≤ 0,35), danach stehendes Zeichen (2 dp Rand im
  Akzent ≥ 3:1, Fläche 8–12 %) plus Text. Höchstens 2 Impulse je Besuch (zweiter nach 8–10 s ohne Eingabe), Gesamtbewegung ≤ 5 s
  (WCAG 2.2.2). Quelle: farbe-verlauf §2/§6, lebendig-warten §3, Vorschlag B.3. Prüfen: Widget-Test misst laufende Ticker nach 6 s = 0.
- **A3** Bewegter Hintergrund nur auf Start-/Zusammenfassungsflächen, nie hinter Listen oder Eingaben; pausiert bei Tastatur, Scrollen,
  Hintergrund; > 5 s laufend braucht Aus-Schalter. Quelle: farbe-verlauf §1. Prüfen: Code + Test.
- **A4** Reduzierte Bewegung = `MediaQuery.disableAnimations` **oder** `PlatformDispatcher.accessibilityFeatures.reduceMotion` (iOS/Web)
  **oder** App-Schalter; Ersatz ist Überblenden (Deckkraft/Farbe), nie Verschieben/Skalieren. Quelle: farbe-verlauf §4, lebendig-warten §3
  (WCAG 2.3.3). Prüfen: Test mit beiden Flags.
- **A5** Layout springt nie: Ein-/Ausblenden über animierte Größe (ohne Bewegung: sofort, ohne `AnimatedSize` mit Dauer 0). Quelle:
  navigation-layout-glas-ton §2. Prüfen: Widget-Test „keine Verschiebung des Folgeelements ohne Animation“.
- **A6** Übergänge: Startkarte → Bon = Container Transform; Schritte = Shared Axis X; Ansichtswechsel (Scan/Original/Digital) = Fade
  Through; Bonfoto = Hero; reduziert = Überblenden ≤ 150 ms. Quelle: glas-neigung-bewegung §3.

### B. Warten und Scan
- **B1** Scan über 10 s: Schrittzähler mit benannten Stufen („Schritt 3 von 6: Spalten lesen“), keine Prozentzusage, keine Endlos-Animation
  über 10 s, „Abbrechen“ immer sichtbar, erste Rückmeldung < 100 ms. Quelle: lebendig-warten §1, A.1–A.3 (NN/g, Myers 1985).
- **B2** Balken ohne Pause vor dem Ende, ohne Pulsieren; steht er > 8 s: Text „Das dauert diesmal länger“. Quelle: lebendig-warten A.3
  (Harrison 2007).
- **B3** Arbeit sichtbar machen, nie künstlich bremsen (Labor Illusion nur für echte Arbeit). Quelle: lebendig-warten §1.
- **B4** Haptik im Scan höchstens 2-mal (Start, Ende); Summe stimmt = „Erfolg“, Abweichung = „Warnung“, je Muster eine Bedeutung. Quelle:
  lebendig-warten D (Apple HIG Haptics).
- **B5** Summe stimmt nicht: Differenz als Zeile direkt an der Summe, kein Rot-Alarm, stehender Marker an unsicheren Zeilen. Quelle:
  lebendig-warten C.3.
- **B6** Rückgängig-Snackbar ≥ 5 s (Regelwerk 6.10 verlangt ≥ 10 s – strengere Regel gilt). Quelle: lebendig-warten B.7.

### C. Farbe
- **C1** Neutrale Flächen + **ein** Akzent; gedämpft, nicht grau (Graustufen wirken stumpf, Entsättigung senkt Vertrauen). Quelle:
  farbe-verlauf §3 (Silvennoinen 2014; IADIS).
- **C2** Text liegt nie direkt auf Verlauf/Glas: Fläche ≥ 90 % deckend oder 4,5:1 im schlechtesten Punkt. Quelle: farbe-verlauf §6.
- **C3** Dunkel nicht reines Schwarz, Akzent im Dunkeln heller; Hell/Dunkel/System anbieten. Quelle: farbe-verlauf §3.

### D. Glas und Leistung
- **D1** Glas nur in der Bedienebene (Leisten, Blätter, Knöpfe), nie auf Inhaltskarten. Quelle: navigation-layout-glas-ton §6,
  farbe-verlauf §1 (Apple HIG Materials).
- **D2** **Eine** Hintergrundkopie je Bildschirm (`BackdropGroup`/`BackdropFilter.grouped`); Lesekosten sind vollbild, egal wie klein
  die Form. Kein `ImageFilter.compose(shader, blur)` (Flutter-Fehler #194832). Quelle: echtes-glas-flutter §5. Prüfen: Code + Messung.
- **D3** Impeller auf alten GPUs ist teils deutlich langsamer (Adreno 506: 28 statt 54 Bilder/s, Issue #187009). Leistung auf
  Mittelklasse/alt messen, nicht nur S23. Quelle: echtes-glas-flutter §5. Prüfen: Leistungs-Tor.
- **D4** Shader `precision highp`, kein Ternary in Kantenberechnung, Testbild asymmetrisch, Test auf GLES und Vulkan. Quelle: echtes-glas §2.

### E. Navigation
- **E1** Unten drei Reiter (Rechnungen, Gruppen, Freunde) + schwebendes Plus; Plus fragt Kamera / Galerie / ohne Bon. Quelle:
  navigation-layout-glas-ton §1 (Beschluss).
- **E2** Papierkorb: Frist 7 / 30 (Standard) / manuell; Archiv ≠ Papierkorb. Quelle: navigation-layout-glas-ton §3.

### F. Stile und Effekte (nur, wenn der Nutzer sie zuschaltet; Standard „Sparsam“ seit 05.11.)
- **F1** Korn: je Bild neu und je Ort unabhängig (nie wandernde Textur), höchstens 24 Hz neu zeichnen, Flackern ±2–4 %, nie 40 %;
  WCAG 2.3.1 (≤ 3 Blitze/s). Quelle: filmkorn-alter-film Kurzfassung, §3, Nachtrag WCAG.
- **F2** Papier: Textur ≤ 4 % Helligkeit, einmal gebacken, statisch; Papier nur mit Funktion (Bon, Zettel), nie Dekor; Bon bleibt im
  Dunkeln helles, gedimmtes Papier; Dunkel nicht invertieren. Quelle: stil-papier Kurzfassung 2/5/10/11/15, §5.
- **F3** Braun: höchstens ein Signal je Bildschirm, Farbe ist Information, kein Leder/Schrauben/Textur; Bedienflächen brauchen sichtbaren
  Rand oder Hub (NN/g flat design). Quelle: stil-braun-technik Kurzfassung, §4, §5.
- **F4** Beträge immer mit gleich breiten Ziffern (`tabularFigures`), Summen nie nur als Zeiger/Grafik. Quelle: stil-braun §5, Baustein 1.

## Widersprüche (neu)
- **W10** navigation-layout-glas-ton §2: „Auswahl nur durch Farbe, kein Häkchen“ (gegen Springen) ↔ Regelwerk 1.8 „Nie Farbe allein“.
  Auflösung (Vorschlag): Auswahl durch Füllung **und** Kontrast/Rand (Form), kein Häkchen, das die Breite ändert.
- **W11** Rückgängig-Dauer: ≥ 5 s (lebendig-warten) ↔ ≥ 10 s + Liste ohne Frist (Regelwerk 6.10, W9). Auflösung: ≥ 10 s + Liste.

## Schon gefundene Verstöße im Code (06.11.)
- **V1** `ui/hints.dart` `PulseRing`: `_c.repeat()` pulsiert endlos → verstößt gegen A2 (WCAG 2.2.2).
- **V2** `ui/bill_screen.dart` ⋮-Menü und `ui/common.dart` Bon-Knopf **verstecken** Einträge, wenn das Foto nicht lokal liegt → Regelwerk
  1.6 (Zustand sichtbar), 1.1 (nur Funktionierendes zeigen – richtig wäre: ausgegraut mit Grund) und Beschluss Browser = APK.
- **V3** Vollglas mit Weichzeichner je Element ohne gemeinsame Hintergrundkopie (bisheriger Standardstil) → D2; inzwischen per „Sparsam“
  aus, Ursache aber nicht behoben.
