# Reale und gefühlte Leistung – Studienlage für den Umbau (09.11.2026)

Auftrag Nutzer 09.11. 02:54: ausführliche Studien, Peer-Reviews, Statistiken und Fakten heranziehen, um reale und gefühlte Leistung zu maximieren.
Vorgehen: nur Lesen (Websuche), eigene Messungen aus `STAND.md`. Stufen: **[belegt]** Studie mit Methode gelesen (Zusammenfassung/Auszug),
**[Behauptung]** Industrie-Richtwert ohne Studie, **[übertragen]** Studie aus anderem Gebiet (Spiele), Übertragung auf Listen nicht geprüft.
Grenze: Volltexte der Studien nicht ganz gelesen, nur Zusammenfassungen und Auszüge der Suchtreffer. Zahlen daher mit Vorbehalt.

## 1. Wie schnell ist schnell genug?

- **Die 0,1 s / 1 s / 10 s-Grenzen (Miller 1968, Nielsen 1993) sind keine Messergebnisse.** Dubuc (Wikimedia, 2018, Literaturübersicht) fand dafür keine Versuche; Studien haben meist kleine, junge Studentengruppen. [Behauptung → nur als grobe Ordnung nutzen]
- **Maus:** Wahrnehmungsschwelle im Mittel etwa 65 ms (34–137 ms), 20 Studierende; Spielerfahrung senkt sie (Forch, Franke, Rauh, Krems 2017, Springer LNCS 10276). [belegt, kleine Stichprobe]
- **Direktes Ziehen mit dem Finger:** Schon 1 ms gegen ~6 ms Verzögerung unterscheiden Menschen (mittlere Schwelle 6,0 ms, Spanne 2,4–11,4 ms, 10 Personen; Ng et al., UIST 2012, Microsoft). Beim Tippen („Antippen → Rechteck erscheint“) liegt die Schwelle viel höher, 20–100 ms (Jota et al., CHI 2013). Leistung beim Ziehen sinkt mit der Verzögerung (Jota et al., CHI 2013, „How fast is fast enough?“; Deber et al., CHI 2015). [belegt]
- **Folge:** Wo der Finger Inhalt bewegt (Scrollen, Ziehen), zählt jede Bildzeit. Beim Antippen genügt eine sichtbare Rückmeldung im nächsten Bild; die Fachaktion darf kurz danach kommen.
- **INP (Interaction to Next Paint), Google:** gut ≤ 200 ms, verbesserungswürdig ≤ 500 ms, schlecht > 500 ms, gemessen am 75. Perzentil echter Seitenaufrufe (web.dev/articles/inp). [Industrie-Richtwert aus Felddaten, keine Wahrnehmungsstudie]

## 2. Gleichmäßigkeit schlägt Spitzenwert

- **Schwankende Bildzeiten verschlechtern die gefühlte Flüssigkeit** auch bei hoher mittlerer Rate: Schwankung von 12 ms spürbar schlechter, 4 ms kaum (Klein et al., NVIDIA/Uni, arXiv 2306.01691, 2024; Ego-Shooter-Spiel, 30–240 Hz). [belegt, übertragen]
- **Aussetzer-Größe zählt, nicht die Häufigkeit:** Modelle aus Standardabweichung der Bildzeit, mittlerer Rate und Aussetzer-Größe sagen die Zufriedenheit voraus; die Aussetzer-Größe ist ein starker Faktor, die Häufigkeit nicht (Xu & Claypool, ACM MMSys 2024; Spiele). [belegt, übertragen]
- **Folge für uns:** Ein einzelnes langes Bild (66, 100, 317 ms) schadet mehr als viele leicht späte. Messgröße deshalb **längstes Bild und Bilder > 33 ms**, nicht nur Bilder pro Sekunde. Ein **stabiles 60 Hz** ist besser als ein Springen zwischen 120 und 60: die Browser-Läufe vom 09.11. zeigen genau dieses Springen (Leerlauf 105 Bilder/s, Scrollen 59).
- **Höhere Bildrate:** In Spielen merkten Teilnehmer Unterschiede bis weit über 100 Bilder/s (Claypool-Gruppe, WPI, 2025, Spiele). Für **Scrollen von Listen auf dem Handy** habe ich keine begutachtete Studie gefunden, die 60 gegen 120 Hz vergleicht; Behauptungen von Blur Busters stehen nur in Forum/Webseite (nicht begutachtet). [Lücke]. Sicher ist: 120 Hz halbiert die Bildzeit und damit die Mindest-Verzögerung (Quelle: Tiefenstudie zu Touch-Jitter, CHI-Arbeit, core.ac.uk 362231493).

## 3. Warten und Anzeigen

- **Skeleton-Bildschirme:** gemischte Lage. Viget 2017 (136 Personen, kein Peer-Review): gefühlte Wartezeit Skeleton 2,82 s, Spinner 2,41 s, leerer Bildschirm 2,29 s bei gleicher echter Zeit. Eine kleine Studie fand das Gegenteil (Nachrichtenseite, bessere gefühlte Geschwindigkeit); eine Masterarbeit (Drexel 2024, 134 Personen) sah „Schleifenanimation + Skeleton“ am kürzesten. [widersprüchlich]
- **Aktiv warten:** Etwas tun oder nichts tun wurde kürzer geschätzt als passiv lesen (Van Nimwegen & Van Rijn 2023, Behaviour & Information Technology 42(3)). [belegt, Online-Versuch]
- **Folge:** Kein Skeleton als Standard. Besser ist, **gar nicht zu warten**: Alles lokal zuerst anzeigen und schreiben, Netz und Relays im Hintergrund (das tut die App schon). Platzhalter nur mit festem Maß, damit nichts springt.

## 4. Regeln für den Umbau (abgeleitet, jede mit Quelle oben)

1. **Bildzeit-Budget im Scrollen:** Ziel ≤ 8,3 ms (120 Hz), hart: kein Bild > 33 ms, keines > 100 ms (Abschnitt 1–2).
2. **Spitzen vermeiden, nicht Mittelwerte schönen:** längste Bilder zählen (Abschnitt 2). Der Test beurteilt deshalb p95, längstes Bild und Zahl der Bilder > 33/100 ms.
3. **Keine Arbeit > ~50 ms im Hauptfaden** (Kryptografie in der APK, große Listen aufbauen, JSON): aufteilen oder auslagern (Abschnitt 1, INP).
4. **Listen:** nur sichtbare Zeilen bauen, feste Zeilenhöhe, keine Schatten/Unschärfe je Zeile, Vorschaubilder in Zielgröße vorab, keine Neuberechnung pro Bild. (Eigene Messung: nackte Zeilen 6 ms, mit Vorschau +1,5 ms, mit Schatten +1,5–3 ms.)
5. **Tippen:** sichtbare Rückmeldung im selben/nächsten Bild; Fachaktion danach (Abschnitt 1, 20–100 ms Tipp-Schwelle).
6. **Kein Warten auf das Netz:** immer zuerst lokal anzeigen (Abschnitt 3).
7. **Stabiler Takt:** Effekte aus, wenn sie Spitzen erzeugen; lieber konstantes 60 als wechselndes 120/60 (Abschnitt 2).

## 5. Was nicht belegt ist (offen)

- Ob Browser auf dem S23 bei Last wirklich von 120 auf 60 Hz zurückschalten (Compositor/Energiesparen) oder unsere Bilder zu spät fertig werden: **nicht belegt**, nur aus den Zahlen (Leerlauf 105, Scrollen 59) geschlossen. [Likely]
- Studien zu Scroll-Flüssigkeit auf Handys (60 vs. 120 Hz, begutachtet): nicht gefunden.
- Wirkung von „Optimistic UI“ auf gefühlte Geschwindigkeit: hier nicht gesucht, folgt aus Abschnitt 1 [Likely].

## Quellen

- Dubuc, G. (2018): Magic numbers, Web Performance Calendar, calendar.perfplanet.com/2018/magic-numbers/ (Literaturübersicht)
- Forch, Franke, Rauh, Krems (2017): Are 100 ms Fast Enough? Characterizing Latency Perception Thresholds in Mouse-Based Interaction. LNCS 10276, doi:10.1007/978-3-319-58475-1_4
- Ng et al. (2012): Designing for Low-Latency Direct-Touch Input, UIST 2012 (Zahlen aus der zugehörigen Patentbeschreibung gelesen, nicht aus dem Aufsatz)
- Jota, Ng, Dietz, Wigdor (2013): How fast is fast enough? CHI 2013, doi:10.1145/2470654.2481317
- Deber, Jota, Forlines, Wigdor (2015): How Much Faster is Fast Enough? CHI 2015
- Klein et al. (2024): Variable Frame Timing Affects Perception of Smoothness in First-Person Gaming, arXiv:2306.01691
- Xu & Claypool (2024): User Study-based Models of Game Player QoE with Frame Display Time Variation, MMSys 2024
- Van Nimwegen & Van Rijn (2023): Time swipes when you're having fun, Behaviour & Information Technology 42(3), doi:10.1080/0144929X.2022.2155576
- Faulkner & Olvera (2017): A Bone to Pick with Skeleton Screens, viget.com (kein Peer-Review)
- Khuc (2024): Feedback combinations on perceived online wait time, Drexel (Masterarbeit)
- Google: Interaction to Next Paint, web.dev/articles/inp

## Nachtrag 09.11. 03:50 – Tab-Leiste (Originaltexte gelesen)
- Apple HIG „Tab bars“ (developer.apple.com/design/human-interface-guidelines/tab-bars): Tab-Leiste bleibt überall sichtbar; so wenige Tabs wie nötig (üblich 3–5); Tabs nie ausblenden oder abschalten; nur zum Navigieren, nicht für Aktionen. Dazu Abzeichen sparsam.
- Material 3 (m3.material.io/components/navigation-bar): Seite braucht JavaScript, mit WebFetch **nicht lesbar**; Flutter-API-Seite `NavigationBar` nennt keine Zahl. Material-Angabe „3–5 Ziele“ daher **nicht geprüft** (nur aus Zweitquellen).
- Folge für Option A: drei Tabs Gruppe | Abrechnung | Freunde, Tab-Leiste bleibt; Auswahl innerhalb eines Ortes (Alle / Ohne Gruppe / Gruppe) liegt im Inhalt als Gruppenwähler, nicht in der Leiste.

## Nachtrag 09.11. 04:05 – warum der Browser beim Scrollen bei ~60 Bildern/s hängt (Quellen, kein Beweis)
- Mozilla Support (Firefox Android): „nur die Browser-Oberfläche läuft mit 120 Hz, die Webseite mit 60 Hz; erst bei offenem Menü springt es hoch“ (support.mozilla.org/kn/questions/1571960). Brave-Forum: Samsung/OnePlus halten eine eigene Liste von Apps, die hohe Bildraten bekommen; andere bleiben bei 60 Hz (community.brave.com, „Compatibility with 120 HZ Refresh Rate“). TestUFO-Forum: Browser bleiben oft bei 60 fps hängen, Ursache oft Hersteller oder Software-Rendering (forums.blurbusters.com, „TestUFO stuck at 60Hz“). Cromite hat sogar eine Option „Throttle frame rate to 60hz“ (github.com/uazo/cromite/issues/2572).
- Unser Befund passt dazu: Leerlauf bis 105 Bilder/s (die Seite KANN schneller), beim Scrollen 59. **[Likely]** Das ist eine Entscheidung von Android/Browser („Bewegungsflüssigkeit adaptiv“, Bildraten-Stimme), nicht der App. **[Nicht belegt]** auf dem S23 (kein Test mit ausgeschalteter adaptiver Rate).
- Folge für die Ziele: im Browser ist **stabile 60** das Ziel (Budget 16,7 ms je Bild, kein Hänger > 50 ms), nicht 120. Das Urteil des Leistungstests muss das Hz-Maß des Browsers (gemessene Obergrenze beim Scrollen) nehmen, nicht die Bildschirm-Hz. Offene Prüfung durch den Nutzer: Einstellungen → Display → Bewegungsflüssigkeit auf „Hoch“ und denselben Test erneut laufen lassen; ändert sich nichts, ist es der Browser.
