# Regelwerk Oberfläche – Fasan Split

Stand 02.11.2026. Verdichtung der Recherchen zu einem prüfbaren Regelwerk. Es ersetzt die Quellen nicht; bei Zweifel dort per grep nachlesen.
Zahlen in dp (Flutter: 1 dp = 1 logischer Pixel). Die Quellen schreiben teils „px“ (Web-App Fasan Karte); das gilt hier als dp. Ungeprüftes ist als „nicht geprüft“ oder „Ableitung“ markiert.
Wo sich Quellen widersprechen, steht „WIDERSPRUCH Wn“ in der Regel; die Auflösung steht am Ende (Abschnitt 12).

## Quellenkürzel

- GS = `fasan/GRUNDSAETZE.md`
- DG = `fasan_ui/docs/recherche/2026-11-01-design-grundlagen.md`
- EN = `fasan-karte/docs/ENTSCHEIDUNGEN.md` (Datum der Zeile)
- GP = `fasan-karte/.../2026-10-24-gestaltung-psychologie.md`
- NG = `.../2026-10-24-natives-gefuehl.md`
- KF = `.../2026-10-24-kosten-und-fuehrung.md`
- RT = `.../2026-10-25-rechnung-teilen-ux.md`
- GB = `.../2026-10-29-gemeinsam-bearbeiten.md`
- BF = `.../2026-10-29-bon-ansicht-und-farben.md`
- FR = `.../2026-10-30-fehleranalyse-rewe-und-bon-ansicht.md`
- UI = `.../2026-10-31-ui-design-2026.md`
- SB = `.../2026-11-01-scan-und-bedienung.md`
- PB = `fasan-camera/.../2026-10-12-psychologie-bedienung.md`
- GE = `fasan-camera/.../2026-10-12-gestaltung-start-einstellungen.md`
- HA = `fasan-camera/.../2026-10-11-haptik.md`
- CM = `fasan-split/CLAUDE.md`

Ein Kürzel in eckigen Klammern nennt die Datei; danach steht, falls vorhanden, die Originalquelle (Autor Jahr).

---

## 1. Grundsätze

1. Zeige nur, was funktioniert. Kommendes trägt die Beschriftung „Kommt später“. [GS; GE S6]
2. Frei (MPL-2.0), offline zuerst, keine Telemetrie, keine Konten. Diagnose nur nach Zustimmung. [GS; CM]
3. Oberfläche Deutsch und Englisch, Du-Form, kurze Sätze, Verb im Knopf. [CM; GP §7 Wortwahl]
4. Eine laute Sache je Ansicht: eine gefüllte Hauptaktion, eine Auswahl, der Rest ruhig. Der Wert „eine“ ist Vorschlag, nicht belegt. [GP R1 (Quelle G1: präattentive Merkmale)]
5. Mach wenig sichtbar und alles erreichbar. Höchstens 2 Ebenen; Häufiges zuerst, Seltenes unter „Mehr“ oder „Erweitert“. [GS (Carroll & Carrithers); PB R5 (NN/g)]
6. Wiedererkennen statt Erinnern: Zustand immer sichtbar, Symbol immer mit Wort. Fällt Platz weg, fällt zuerst das Symbol weg, nicht das Wort. [PB R7 (Nielsen H6); GP §7]
7. Jede Geste hat einen sichtbaren Zwilling (Knopf). Jede Funktion geht ohne Ziehen. [GS; PB R3 (WCAG 2.5.7)]
8. Nie Farbe allein: Zustand und Bedeutung stehen zusätzlich als Text oder Zeichen da. [GP R11 (WCAG 1.4.1); RT; BF]
9. Fehler verhindern statt melden: Speichern nur bei exakter Summe; „Weiter“ nie als toter grauer Knopf. [GP R8; SB §3 (Nielsen H5)]
10. Gestaltung ist Zugabe, nie Pflicht. Schönheit ändert die empfundene, nicht die tatsächliche Bedienbarkeit; sie ersetzt keine Zielgröße. [DG §3 (Tractinsky, Katz & Ikar 2000)]
11. Keine Dark Patterns: keine Bewertungsbitte, keine Dringlichkeit, keine beschämenden Ablehn-Texte, „Ja“ und „Nein“ gleich groß, nach einem „Nein“ nie wieder fragen. [PB R10 (Mathur u. a.; DSA Art. 25)]
12. Keine Punkte, Serien oder Abzeichen. [PB R19]
13. Kein Prüfwert ohne Beleg: jede Annahme im Code mit Quellenkommentar oder „nicht geprüft“. Prüfen heißt Emulator-Bildschirmfoto mit echtem Bon, nicht nur grep. [CM; fasan_ui/CLAUDE.md]
14. Echte Bonfotos nie ins Repo und nie in den Code; bekannte Test-Bons nicht in der App hinterlegen. [CM]
15. Zitiere nicht als alleinigen Grund: Hick-Gesetz, Doherty 400 ms, Miller 7±2, Jam-Studie. [PB Tabelle „schwach“, R13; GP R3]

## 2. Layout & Leisten

1. Tippfläche mindestens 48 dp; Profil „Einfach“ 60 dp; Hauptknöpfe (Weiter, Speichern, Scan) 56 bis 60 dp; Abstand zwischen Zielen mindestens 8 dp. WIDERSPRUCH W1 (44 / 48 / 60). [CM; NG §3 Mindestgrößen; GS (Parhi, Karlson & Bederson 2006)]
2. Größen kommen nur aus Tokens (Ziel, Lücke, Schrift, Radius); kein fest eingetragenes `height: 64`. So skaliert ein Profil alles gleichmäßig. [UI §2 R1]
3. Profile: Standard / Groß / Gut lesbar. Quelle nennt 44 / 56 / 64 px. Für Split gilt 48 / 56 / 64 dp (Ableitung aus W1). [UI §1; CM]
4. Kopfleiste in einer Zeile: links Zurück (Symbol), Mitte Schrittpunkte, rechts Rückgängig, Wiederholen und „Speichern“ als kompakte Pille. [UI §2 R2]
5. Der Seitentitel steht unter der Kopfleiste, linksbündig, und wird nie abgeschnitten. Wichtige Texte brechen um, keine Auslassungspunkte. [UI §2 R2; PB R18]
6. Aktionen immer rechts oben; nur „Speichern“ ist farbig gefüllt. [UI §1 (Apple HIG)]
7. Häufiges liegt im unteren Drittel (Daumen). Seltenes und Info liegt oben. [GS (Bergstrom-Lehtovirta & Oulasvirta 2014); GE S8]
8. „Weiter“ steht fest am unteren Rand, volle Breite, 56 dp hoch, Abstand unten `max(16, Safe-Area)`. Er liegt nie im scrollenden Teil. [NG §5]
9. Kopf und Fuß werfen einen Schatten, solange darunter Inhalt weitergeht. Keine großen Leerflächen (Nutzer scrollen nicht, wenn die Seite fertig aussieht). [SB §3 (NN/g Illusion of Completeness, Scroll Fading)]
10. Schmale Breite (Kompakt, unter 600 dp): einspaltig. Ab 840 dp Breite oder Handy quer: zweispaltig, Bon links, Bedienung rechts. Inhalt höchstens 640 bis 760 dp breit. [UI §1 (Android Window Size Classes), §2 R5]
11. Gruppiere mit Abstand, nicht mit Rahmen: innen 8 dp, zwischen Gruppen 16 dp. Rahmen nur bei gemischtem Inhalt; keine vollbreiten Farbflächen in Listen. Die Zahlen sind Vorschläge. [GP R2 (Gestaltgesetze); GE §2 Punkt 11]
12. Höchstens etwa 4 gleichrangige Wahlpunkte, die man sich merken muss. Sortierte, gruppierte Auswahl darf länger sein. WIDERSPRUCH W4. [GP R3 (Cowan)]
13. Umschalter mit 2 bis 3 Möglichkeiten sind Segmentschalter, gleich breit, wischbar. [UI §2 R4; SB §4]
14. Symbole als Vektor mit gleicher Strichstärke und Semantik-Label (TalkBack); keine Textzeichen wie ↶ ↷. [UI §2 R3]
15. Schrift: Fließtext 18 sp, Nebentext 16 sp, nichts Lesenswertes unter 14 sp; „Gut lesbar“ 20 sp und mehr. Layout muss bei größter Systemschrift tragen (Test 200 %). WIDERSPRUCH W5 für die Versionsmarke. [GP R12 (Legge); PB R18]
16. Kontrast: Text 4,5:1 (groß 3:1), Symbole, Ränder und Zustände 3:1; Profil „Gut lesbar“ 7:1. Messe gegen die echten Hintergründe. WIDERSPRUCH W2. [PB R16 (WCAG 1.4.3, 1.4.11); GE §4]
17. Versionsmarke lesbar (volle Textfarbe, Rahmen), oben links oder in der Kopf- bzw. Hilfezeile; sie verdeckt nichts. [UI §2 R6]
18. Hell für Text, dunkel fürs Bild: Menüs folgen dem System; Bon-/Foto-Fläche darf dunkel sein. WIDERSPRUCH W6. [GS (Piepenbrock u. a. 2013)]
19. Zeitangaben als Uhrzeit („Stand 14:05“), nicht „vor 3 Min.“. Vorschlag ohne Beleg. [GP §4]

## 3. Bon-Ansicht

1. Zeige immer den ganzen Bon. Kopf und Fuß sind nur blasser; es gibt kein Ein-/Ausblenden und keinen versteckten Zustand. [SB §3; EN 01.11.]
2. Der Bon ist von jedem Schritt aus einen Tipp entfernt: Knopf oben plus schwebender Knopf. [BF §2 (Nielsen H6); EN 29.10. Rechnung 3.8]
3. Die Bon-Ansicht ist das Arbeitsfeld, kein Anhang: Posten werden direkt im Bon angetippt, korrigiert, zugeordnet, ausgeblendet, gelöscht. [EN 29.10. Rechnung 3.8]
4. Scan (begradigt, Dokumentlook), Farbfoto und Kästen haben dieselbe Geometrie. „Foto“ ist das begradigte Farbbild. WIDERSPRUCH W7 (Modi „Bereinigt/Original/Nebeneinander“ gegen „Scan/Foto“). [SB §1; EN 01.11.]
5. Ein Tipp neben einen Kasten rastet auf die nächste Zeile ein. Tippflächen reichen bis zur Mitte zur Nachbarzeile: keine Lücken, keine Überlappung. [SB; FR §4]
6. Zeilen eines dichten Bons sind bei voller Breite etwa 14 dp hoch, unter dem WCAG-2.5.8-Minimum von 24. Darum nach jedem Tipp eine Korrekturleiste: Zeilenbild, Name, Person, ▲/▼ zum Verschieben auf den Posten darüber/darunter (Knöpfe 44 dp, besser 48), Rückgängig. [FR §4 (WCAG 2.5.8)]
7. Zoom: Zwei-Finger-Zoom (Stelle unter den Fingern bleibt stehen), Doppeltippen wechselt 1× und 2,5×, dazu Plus-/Minus-Knöpfe als Zwilling. „Ganze Breite“ erscheint nur, wenn vergrößert. Der Lupen-Knopf entfällt. [FR §3 (Apple „Zooming by Tapping“; WCAG 2.5.1)]
8. Doppeltippen nimmt den ersten Tipp zurück, wenn der schon zugeordnet hat. Bei Posten mit mehreren Stücken gilt schnelles Mehrfachtippen als „ein Stück je Tipp“. [FR §3]
9. Kästen: dünne Linie, nicht 3 dp gestrichelt (verdeckt die Schrift). Zugeordnet = Personenfarbe als Fläche plus Balken links (plus Schraffur, Abschnitt 5). [FR §4]
10. Menge × Preis bleibt ein Posten (Teilen auf Wunsch). Mengenzeile „2 Stk x 0,65“ gehört zum Posten und ist nicht antippbar. Zeige keine „(1/2)“, „(2/2)“-Zeilen. Jede Bonzeile gibt es nur einmal. [SB Einleitung, §3; EN 01.11.]
11. Pfand hängt am Artikel darüber („inkl. 0,25 € Pfand“), nie an Rabatt- oder Minuszeilen. [FR §1 Nr. 6]
12. Jeder Posten zeigt den deutschen Klarnamen mit Symbol; der Bon-Name steht klein darunter. Der Mensch sieht immer die Lesung neben dem Original. [EN 29.10. 3.8; BF §1]
13. Erkennung nie blind übernehmen: Rechenprobe immer; Summe, die nicht zu den Posten passt, stoppt auch bei hoher Sicherheit; mittlere Sicherheit vorbelegen, niedrige nicht als Tatsache zeigen. [RT (lilting.ch Human-in-the-loop)]
14. Gelesene Posten nur vorbelegen, wenn ihre Summe exakt zum Bon passt. Sonst: Foto zum Nachlesen, schnelles Eintragen, gelesene Posten nur auf ausdrücklichen Tipp. [EN 25.10.]
15. Unklare Zeilen erscheinen als Posten ohne Betrag mit Bildausschnitt; nie Platzhalter erfinden. [EN 29.10. 3.10]
16. Das Foto ist die Grundlage der Aufgabe: groß, nicht klein zwischen Bedienelementen. [RT Befund 9]
17. Beim Lesen: Das eigene Foto ist sofort sichtbar, die Felder darunter sind sofort bedienbar. Die Ladeanzeige ist der Bon selbst: Lichtband läuft darüber, gefundene Zeilen leuchten auf, dann erscheint der Scan. [SB §3 (Buell & Norton 2011; IHC 2025)]
18. Ladeanzeige klein: Balken mit Prozent und Stufe; Wichtiges nie unter der Falz. [SB Einleitung, §3 (Harrison u. a. 2007)]
19. Bon-Zeitverlauf der Anzeige: Lesen auf dem Gerät, Oberfläche bleibt flüssig (Hintergrund-Isolate); Anzeige zeigt Stufen. [EN 29.10. 3.11 – Web Worker; Übertragung auf Flutter: Ableitung]

## 4. Zuordnen

1. Eine Person wählen, dann Posten antippen: ein Ziel je Posten statt sechs. Die Leiste oben zeigt je Person die laufende Summe. Ob das für 4 bis 6 Personen schneller ist als Posten-zuerst, ist nicht gemessen. [RT Folgerungen; EN 25.10.]
2. „Alle teilen“ / „Gleich teilen“ ist der häufigste Fall und steht voran. Posten nur auf Wunsch. [RT (Hick, Chunking)]
3. Personenleiste: fest oben, wischbar, blendet am Rand aus; die gewählte Person ist als einzige gefüllt. [SB §3; EN 01.11.; GP R1]
4. Zuordnung sofort sichtbar: Fläche in Personenfarbe, Kürzel und Schraffur am Posten. [EN 29.10. 3.9]
5. Nach jedem Tipp gibt es Rückgängig (beliebig viele Schritte) und Wiederholen. [EN 31.10. 3.17; PB R11]
6. „Weiter“ springt bei fehlender Zuordnung zum ersten offenen Posten. Die Fehlermeldung steht an der Stelle des Problems, nicht am Ende. [SB §3; RT Befund 6]
7. Beträge sind ganze Cent (Integer), nie Fließkomma. [KF V4.1]
8. Teilen: Anteil = Abrundung von Betrag × Gewicht ÷ Summe der Gewichte. Reste verteilt das Größte-Reste-Verfahren, je 1 Cent. Gleichstand: kleinster Hash aus Eintrags-ID und Personen-ID. So zahlt nicht immer dieselbe Person, und jedes Handy rechnet gleich. [KF V4.2, V4.3]
9. Aufteilungsarten: gleich, nach Anteilen (Prozent = Anteile mit Summe 100), nach genauen Beträgen. Bei genauen Beträgen muss die Summe treffen; sonst „Rest verteilen“ oder Fehler. [KF V1.4, V4.4]
10. Trinkgeld wird anteilig zugerechnet. [EN 24.10. Kosten 2]
11. Test: Beträge 0,01 bis 1000,00 und 1 bis 6 Personen; die Summe der Anteile ergibt immer den Betrag. [KF V4.6]
12. Mehrere Zahler sind möglich (Liste aus Person und Betrag, Summe = Gesamtbetrag). Nichts ist vorausgewählt wie „Mehrere Personen“ neben einem Namen. [KF V1.3; RT Befund 8]
13. Währung: Originalbetrag, Währung, Kurs und Betrag in Gruppenwährung speichern; nie neu umrechnen; Quelle des Kurses nennen. [KF V1.8, V1.9]

## 5. Personen und Farben

1. Jede Person hat eine feste Farbe nach Okabe-Ito und ein Kürzel. Die Farbe bleibt für die Person gleich in allen Ansichten. [EN 29.10. 3.8; BF §2]
2. Okabe-Ito (Okabe & Ito 2008), bekannte Werte, in den Recherchen NICHT enthalten und nicht geprüft: Orange #E69F00, Himmelblau #56B4E9, Blaugrün #009E73, Gelb #F0E442, Blau #0072B2, Zinnober #D55E00, Rotviolett #CC79A7, Schwarz #000000. Vor dem Einbau am Original prüfen. [GP §6.5 sagt ausdrücklich: Seite war gesperrt, keine Werte genannt] Nachgelesen 04.11. (jfly.uni-koeln.de/color/, Okabe & Ito): Die Seite nennt dieselben acht Farben mit Namen (Schwarz, Orange, Himmelblau, Blaugrün, Gelb, Blau, Zinnober, Rotviolett) und Regeln: warme und kühle Farben abwechseln, bei zwei warmen/kühlen deutlich in Helligkeit oder Sättigung unterscheiden, niedrige Sättigung und Helligkeit vermeiden, für dünne Linien und kleine Schrift Dunkelblau und Orange statt Himmelblau und Gelb. Die Hex-Werte stehen im Seitentext **nicht** (vermutlich nur in Grafiken) → bleiben „bekannte Werte, am Original nicht geprüft“.
3. Es gibt 8 Farben. Ab der 9. Person wiederholen sie sich; Kürzel und Schraffur bleiben eindeutig. WIDERSPRUCH W3 (7 gegen 8 Farben). [BF „Nicht belegt“; EN 29.10.]
4. Wenige, deutlich verschiedene Farben; eine Farbe je Person. Suchzeit steigt, je mehr Elemente die Zielfarbe teilen und je ähnlicher andere Farben sind. [BF §2 (Human Factors 1979, 1975)]
5. Kürzel: kürzester eindeutiger Namensanfang ab 2 Zeichen (Pia/Piatina → „Pia“/„Piat“). Gleiche Namen bekommen eine Nummer. [BF §2]
6. Schraffur je Person als dritter Träger neben Farbe und Kürzel. Jede Person hat ein eigenes Muster. [EN 29.10. 3.9; WCAG 1.4.1]
7. Text auf Personenfarbe: Kontrast mindestens 4,5:1; sonst dunkle bzw. helle Textfläche. Messen, nicht schätzen. Ableitung aus PB R16. [PB R16]
8. Rot und Grün nie als einziges Paar. Zustandsfarben (ok, Warnung, Fehler) nur mit Symbol und Wort. Zwischen Blau und Gelb mehr Helligkeitsabstand (Ableitung). [GP §6.5 (Wuerger 2013)]
9. Personenfarben tragen keine Zustandsbedeutung; Zustände haben eigene Zeichen. [RT Befund 7]
10. Wirkung im Feld (große Gruppen, Farbsehschwäche) ist nicht gemessen; einmal mit Simulation für Protanopie und Deuteranopie prüfen. [BF „Nicht belegt“; GP §6.5 „Nicht geprüft“]

## 6. Ablauf und Speichern

1. Vollbild-Ablauf in 3 bis 4 Schritten: Summe → Wer war dabei, gleich oder nach Posten → Posten zuordnen → Wer hat bezahlt, Speichern. Kein langes Formular auf einer Seite. [EN 25.10.; RT (Hull 1934; Atticus Li 2026: 2 bis 4 Schritte, erster unter 30 s)]
2. Zeige „Schritt n von m“ und Schrittpunkte. Zugehörige Beschriftung für Screenreader. [RT; NG §5]
3. Summe zuerst und groß. Sie ist der Prüfwert für alles andere. Der Nutzer kann sie tippen, bevor die Erkennung fertig ist. [RT Folgerungen]
4. Scan ist der Haupteinstieg: großer Knopf, ein Tipp öffnet die Kamera; Galerie als Alternative. Der Zweck („Wofür?“) wird aus Bon-Art und Geschäft vorbelegt. [EN 25.10., 29.10. 3.9]
5. Ein Bildschirm, eine Aufgabe. Zwischenstand sofort sichtbar: wer wie viel zahlt, nicht erst unten. [RT Befund 5]
6. Angefangene Rechnungen werden nach jeder Änderung auf dem Gerät gespeichert und unter „Angefangen“ fortgesetzt. Schließen verwirft nicht. [EN 29.10. 3.9]
7. Speichern nur, wenn Posten und Summe exakt stimmen. Eine Abweichung Posten/Bon wird erklärt und per Knopf gelöst. [EN 24.10. Kosten 2, 25.10.; GP §5]
8. Status der Rechnung: offen → vollständig (alles zugeordnet, Summe stimmt) → gebucht. [GB §1]
9. Nie überschreiben: jede Änderung ist ein Ereignis mit Autor, Zeit, alter Fassung. Löschen setzt nur `deleted_at`/`deleted_by`; „Gelöschte Einträge“ mit „Wiederherstellen“. [KF V5.1, V5.2]
10. Direkt nach Löschen: „Rückgängig“ mindestens 10 s sichtbar und erreichbar. Zusätzlich Liste „Zuletzt“ ohne Frist. [KF V5.7; PB R11; GP §5]
11. Verlauf je Eintrag: wer, wann, Feld alt → neu. Suche über Zweck, Zahler, Betrag von Anfang an. [KF V5.3, V5.5]
12. Salden: Gruppensumme und eigener Saldo sofort sichtbar; Liste aller Salden mit Vorzeichen und Text „bekommt“ / „schuldet“. [KF V2.1, V2.2, V7.1]
13. Überweisungsvorschlag als Satz („Anna zahlt Ben 23,40 €“) mit Knopf „Als bezahlt buchen“. Bar bezahlt: Ausgleich in höchstens 2 Tipps. [KF V2.3, V7.3]
14. Schalter „Vereinfacht / Direkt“ in der Ansicht, nicht in den Einstellungen. Vereinfacht rechnet exakt mit den wenigsten Überweisungen (bei 6 Personen alle 64 Teilmengen; ab 12 Personen Greedy). Der Vorschlag ist nur Anzeige; der Saldo wird aus dem Protokoll berechnet, nie gespeichert. [KF V2.4, V3.2 bis V3.5; EN 24.10.]
15. Export: CSV mit Semikolon und UTF-8-BOM (öffnet in Excel/LibreOffice) und als Volltext. [EN 31.10. 3.15]
16. Foto des Bons bleibt auf dem Gerät. Teilen entfernt Standort und Gerätedaten. [EN 24.10.; GS]

## 7. Einführung

1. Höchstens 3 Karten, immer überspringbar. Karten: wofür die App da ist; Zuordnen zum Ausprobieren; Loslegen. [NG §5 (Apple HIG Onboarding; NN/g 2020)]
2. „Überspringen“ oben rechts, 48 dp Trefferfläche, auf jeder Karte außer der letzten. Wischen und Knöpfe sind gleichwertig. [NG §5]
3. Fortschritt als Punkte plus Text „2 von 3“. [NG §5]
4. Nach Überspringen oder Ende nicht wieder zeigen; unter „Hilfe“ erneut aufrufbar. [NG §5 (HIG)]
5. Kontext-Tipps statt Rundgang: ein Hinweis am Element beim ersten Besuch („Person wählen, dann Posten antippen“). Er verschwindet bei Tipp oder Zeitablauf. [GS (Grossman & Fitzmaurice 2010); NG §5]
6. Kamera-Berechtigung erst beim ersten Tipp auf „Bon scannen“. Ein Satz erklärt den Grund; ein Knopf öffnet die Systemabfrage. Die App bleibt ohne Zusatzrechte nutzbar. [NG §5 (HIG Privacy); PB R10]
7. Tutorials ändern die Erfolgsquote nicht (91 % mit, 94 % ohne; n = 70, 4 iOS-Apps) und machen die Aufgabe schwerer wirken. Darum kurz halten und die Oberfläche selbst einfach bauen. [NG §5 (NN/g 08.03.2020)]
8. Leerer Zustand erklärt in einem Satz und führt zur ersten Aufgabe (Bon scannen). [GE §3.1 S1a]
9. Testgröße für Layouts: 320 × 568 dp als kleinster Fall (Vorschlag). [NG §5]
10. Im Moment der Aufnahme keine Dialoge und keine Hinweise (Ausnahme: Gefahr für Datei). [PB R14 – Ableitung]

## 8. Bewegung und Haptik

1. Dauern: kurz 150 ms easeOutCubic (Rückmeldung auf Tippen); mittel 220 ms easeInOutCubic (Zustandswechsel, Blätter); lang 320 ms easeInOutCubic (Bildschirmwechsel). [GS (Chang & Ungar 1993; Heer & Robertson 2007)]
2. Druckzustand sofort beim Aufsetzen des Fingers (nicht beim Loslassen). Gefüllte Knöpfe: Skalierung 0,97 und 10 % Überlage, Eingang höchstens 100 ms, Ausgang 150 bis 200 ms. Listenzeilen: nur 10 % Überlage. Maße sind Autorenmeinung. [NG §3 (Apple WWDC18; M3 State Layer)]
3. Gesten folgen dem Finger 1:1 ohne Verzögerung. Beim Loslassen: Feder mit response 0,35 s, Dämpfung 0,9; bei langsamem Loslassen Dämpfung 1,0. Die Fingergeschwindigkeit fließt in die Feder. [NG §0 (Apple WWDC18, WWDC23)]
4. Bewegung bleibt auf einer Achse, kein Nachfedern an Seitenwechseln. [UI §1 (PWABuilder)]
5. Bewegung erklärt Veränderung (Gleiten statt Auftauchen). Nächster Bildschirm erscheint sofort, Feinarbeit lädt nach. [GS (Huhtala u. a. 2010)]
6. „Animationen entfernen“ (System) oder App-Einstellung „Weniger Bewegung“: alle Zustandswechsel auf 0 ms, kein Skalieren, keine Dauerschleifen, keine Unschärfe-Animation. Federn für direkte Gesten bleiben ohne Überschwingen. WIDERSPRUCH W3b (0 ms gegen Überblendung 150 bis 200 ms). [GS; NG §6 (Apple HIG; MDN); UI §2 R7]
7. Flutter: `MediaQuery.disableAnimationsOf` lesen. Federn mit `SpringSimulation`. [DG §1, §3 (Flutter API)]
8. Rückmeldezeiten: bis 0,1 s Druckzustand; bis etwa 1 s keine Anzeige; 1 bis 10 s ein Wort am betroffenen Teil; über 10 s Fortschritt mit Schätzung und „Abbrechen“; nach 10 s ohne Ergebnis einen Ausweg anbieten. Hinweis frühestens nach etwa 0,4 s, damit nichts flackert (nicht belegt). [GP R4 (Miller 1968, Card 1991, NN/g)]
9. Skeleton nur für ganze Ansichten. Spinner nur mit Wort. Keine künstliche Verzögerung, kein Spielzeug im Warten. [GP R5; PB R13] Spannung zu 3.17: siehe W8.
10. Haptik ist nur Zusatz: kurz, abschaltbar, eine Bedeutung je Muster, Stärke nach Häufigkeit (häufig leise, selten laut). Sie folgt dem Systemschalter „Berührungsfeedback“. [HA §6.1, §6.4; NG §4 (Apple HIG)]
11. Muster trennen über Pulszahl und Rhythmus, dann Charakter, nur drittens Stärke (höchstens 3 Stufen, Verhältnis mindestens 1,4). Längstes Muster höchstens 400 ms. Gleiche Rast höchstens alle 150 ms. [HA §6.1 (Brewster & Brown u. a.; Android Haptics)]
12. Vorschlag für Split (Ableitung, Fühltest steht aus): Posten zugeordnet = Rast (leiser Tick); Rechnung gespeichert = Klick; Summe stimmt nicht / Fehler = Dreifach (3 kurze Klicks, 70 ms Lücke); Bon-Scan fertig = Rast. [HA §6.2; NG §4 Tabelle]
13. Eine Einstellung „Haptik“ mit Test-Knopf („Fühlen“, 60 dp), Stärke in 3 Stufen. Ob Flutter-`HapticFeedback` die Muster liefert, ist nicht geprüft; erst offizielle Doku lesen. [HA §6.4; CM]
14. Wichtiges (Fehler) stark genug: Beim Gehen sinkt die Erkennung schwacher Vibration von 73,9 % auf 54,4 %. Untergrenze der Skalierung 0,3. [HA Kurzfassung 8 (Studie [16]), §6.4]

## 9. Effekte

1. Standardstil ist „Ruhe“: wenig Elemente, klare Ordnung, ehrliche Zustände. Effekte sind Zugabe. [DG §1 (Rams, Vitsœ)]
2. Glas nur für die Bedienebene (Leisten, Blätter), nie für Inhalt. Name „Glas“, nicht „Liquid Glass“ (Markenname von Apple). [DG §2; UI §1]
3. `FasanGlass` = `BackdropFilter` mit `ImageFilter.blur`, leichte Tönung, helle feine Kante, kurzer Lichtpunkt beim Tippen. Immer mit `ClipRect`, sonst gilt der Filter für den ganzen Bildschirm. [DG §2, §4 (Flutter-Doku)]
4. Keine Schrift und keine Schalter direkt auf Unschärfe. Fläche mit Deckkraft als Rückfall. In „Gut lesbar“, bei „Transparenz reduzieren“ und im Sparmodus ist Glas eine deckende Fläche. [GE §4 (Apple iOS 26.1 „Getönt“); DG §2]
5. Filmeffekte (Grain, Glow, Halation, Vignette) sind optional und standardmäßig aus. Grain: eigener Fragment-Shader; Bildstandwackeln: Verschiebung unter 1 dp; Vignette: `CustomPainter`; Glow/Halation: `ImageFilter.shader` nur unter Impeller (`ImageFilter.isShaderFilterSupported`). [DG §4 (Flutter „Writing and using fragment shaders“)]
6. Shader nie über Bonfläche oder Zahlen legen, die der Nutzer prüft (Lesbarkeit der Beträge geht vor). Ableitung aus Regel 3.13 und GP R9. [Ableitung]
7. Akku-Stufen: Voll (Standard); Sparen bei Akku ≤ 20 %, Energiesparmodus oder Wärme ≥ `MODERATE`: keine laufenden Effekte, Glas ohne Weichzeichner; Akku maximal (vom Nutzer gewählt): zusätzlich dunkles Theme, keine Shader, kürzeste Animationen. Jede Automatik abschaltbar. [DG §5 (Android PowerManager; Beschluss 01.11.)]
8. Dunkles Theme spart auf OLED Strom (Apple: bis zu 70 %; Android nicht gemessen). [DG §5 (WWDC22)]
9. Kontrast ist wichtiger als Effekt: Glas-Rückfall und „Gut lesbar“ müssen sauber aussehen und werden mit Emulator-Bildschirmfoto geprüft. [DG §1; CM]

## 10. Fehler und Meldungen

1. Fehlertext in drei Teilen: Was ist passiert? Was ist erhalten? Was tun? Beispiel: „Kein Netz. Deine Posten sind gespeichert. Du kannst weiterarbeiten.“ [GP §7 Wortwahl (COGA 2020)]
2. Die Meldung steht an der Stelle, an der man sie braucht, nicht am Ende der Seite. Meldungen sind kompakt. [RT Befund 6; EN 01.11.]
3. Wörtlich schreiben, ohne Bilder und Abkürzungen: „Ort schließt in 20 Minuten“ statt „Zeit wird knapp“. [GP §7]
4. Rückgängig statt Bestätigungsdialog. Dialog nur bei Unumkehrbarem, mit dem Verb im Knopf („Rechnung löschen“, nicht „OK“). [GP R8; PB R11]
5. Ausgeblendete oder gelöschte Dinge bleiben auffindbar („Ausgeblendete zeigen“), sonst glaubt man an Verlust. [GP §5]
6. Jeder Zustand hat Zeichen und Wort: aktuell, veraltet, offline; „Alle 6 auf Stand“ oder „2 fehlen“ mit Zeit des letzten Abgleichs. Die Statuszeile bleibt an fester Stelle und verschiebt nichts. [GP R6; KF V6.7]
7. Keine Pflicht zu raten: Wenn die Erkennung scheitert, sag es und biete Foto plus Eintragen an. Zeige keine Zahl, die nicht gelesen wurde („keine aktuelle Info“ statt einer Zahl). [RT; EN 25.10.; GP §4]
8. Summe stimmt nicht: zeige die Abweichung in Zahlen und biete eine Lösung per Knopf („Rest verteilen“, „Zum ersten offenen Posten“). Keine Schuldzuweisung. [KF V4.4; SB §3; EN 25.10.]
9. Bei Unklarheit sag es: Das gilt auch in Meldungen („nicht sicher gelesen“). [CM; fasan/CLAUDE.md Nicht-raten-Regel]

## 11. Gemeinsam bearbeiten (Konzept; noch nicht gebaut, Stand EN 29.10.)

1. Jede Person schreibt nur ihre eigenen Ansprüche: Paar (Posten, Person) mit Zeitstempel. So ändern zwei Handys nie denselben Wert; „neuester Stand je Schlüssel gewinnt“. [GB §1]
2. Nur Posten-Name/-Betrag, „wer ist dabei“ und „abgeschlossen“ ändern mehrere. Dort: neuester Stand gewinnt plus sichtbarer Verlauf („Mara hat 2,50 → 3,50 geändert“). [GB §1]
3. Protokoll nur anhängen; Reihenfolge: Lamport-Zähler, dann Geräte-ID (nicht die Handyuhr). Konflikt zeigt „2 Fassungen“ mit Knopf „Andere übernehmen“. Bearbeiten gegen Löschen: Löschen gilt, Eintrag bleibt wiederherstellbar. [KF V6.2 bis V6.5]
4. Entfernt der Ersteller eine Person, werden deren Posten wieder frei, mit Hinweis an alle. [GB §1]
5. Jedes Handy hält eine eigene Kopie und arbeitet offline weiter („local-first“); Abgleich beim Öffnen und bei Netz. Sichtbarer Stand: „Alle 6 auf Stand“ oder „2 fehlen“. [GB §1 (Ink & Switch 2019); KF V6.6, V6.7]
6. Benachrichtigung ohne Server: Hinweis in der App und ein „Einladen“-Knopf, der einen Link per Teilen-Funktion an WhatsApp/Signal/SMS gibt. Push an eine geschlossene App braucht immer einen sendenden Server. [GB §2, §1]
7. Foto nicht ganz senden (Relay-Grenzen); gelesene Zeilen plus kleine Zeilenbilder je Posten (2 bis 4 kB) plus stark komprimiertes Graustufenfoto in Stücken. Ende-zu-Ende verschlüsselt. [GB §1]
8. Ehrlich sagen: „Löschen“ erreicht bei Peer-to-Peer nicht alle Kopien; es ist eine Bitte. [GB §1 Datenschutz]
9. Eine App, nicht zwei: Einstellung „Server: keiner / eigener (Adresse)“. [GB §4]
10. Rechte: ohne Konto keine echte Identität; jede Änderung trägt die Personen-ID; Verlauf und Rückgängig sind der Schutz für Freundesgruppen. [GB §1]
11. Personen ohne App sind möglich (Name nur in der Rechnung). [EN 24.10. Kosten 2]
12. Offen: Flutter-Weg für Nostr/Relay und Push in Split ist hier nicht festgelegt; Fasan Karte plant, den Split-Code später aufzunehmen. [CM; GB §5 – nicht geprüft]

---

## 12. Widersprüche zwischen den Dateien und Auflösung

- **W1 Zielgröße.** GS, PB, GE: 60 dp (9,6 mm), Auslöser 96 dp. UI: 44 px Standard, 56 „Groß“, 64 „Gut lesbar“. NG: 48 dp, wichtige 56 bis 60. CM (Split): 48 dp, „Einfach“ 60. GP rechnet vor: 44 CSS-px sind etwa 7 mm, unter den 9,6 mm; die Umrechnung px nach mm ist nicht am Gerät gemessen.
  Auflösung für Split: CM gilt (48 dp, Einfach 60 dp), Hauptknöpfe 56 bis 60 dp. Messen am Gerät steht aus.
- **W2 Kontrast.** GP R9: mindestens 7:1 draußen, Ränder 3:1. PB R16 und GE §4: 4,5:1, nur Profil „Gut lesbar“ 7:1 (Projektvorgabe aus `ZUSTAENDE-UND-PROFILE.md`).
  Auflösung: 4,5:1 als Standard, 7:1 in „Gut lesbar“. Für Bon-Zahlen und Summe (kritische Prüfwerte) 7:1 anstreben (Ableitung).
- **W3 Zahl der Farben.** GP R11: höchstens 7 Kategorienfarben. BF und EN 29.10.: 8 Okabe-Ito-Farben, danach Wiederholung.
  Auflösung: 8 Personenfarben bleiben (EN 29.10. ist Beschluss); Kürzel und Schraffur tragen die Eindeutigkeit.
- **W3b Reduzierte Bewegung.** GS: 0 ms. NG §6: Überblendung 150 bis 200 ms, Federn ζ 1,0. UI: „schaltet alle Animationen ab“.
  Auflösung: 0 ms für Zustandswechsel (GS und UI sind Beschlüsse); direkt am Finger geführte Bewegung bleibt, ohne Überschwingen.
- **W4 Wahl und Hick.** GP R3 nennt „höchstens etwa 4“ und sagt zugleich, Hick sei nicht zu zitieren. RT stützt sich auf das Hick-Gesetz. PB R4 und Tabelle: Hick und Choice Overload sind schwache Belege.
  Auflösung: Zahl nicht als Gesetz behandeln; Entscheidungen aus dem Moment nehmen (Stufen, Häufiges voran). RT bleibt als Ableitung aus Splitwise, nicht aus Hick.
- **W5 Mindestschrift.** GP R12: nichts unter 14. UI §2 R6: Versionsmarke 11 px. Auflösung: Versionsmarke ist Debug-Hinweis und darf 11 sp haben; sie steht nie in Nutzertexten.
- **W6 Hell/Dunkel.** GP R10: hell mit dunkler Schrift als Tag-Standard, Dunkel wählbar. GS: Menüs folgen dem System. Auflösung: System-Modus als Standard, beide Paletten fertig; Bonfläche immer hell (Papier).
- **W7 Bon-Ansicht Modi.** UI (31.10.) und EN 31.10.: Bereinigt | Original | Nebeneinander. SB und EN 01.11.: Scan und „Foto“ (begradigtes Farbbild) mit gleicher Geometrie; UI §3 nennt „nur Posten“ als Lücke.
  Auflösung: SB und EN 01.11. sind neuer; Modi in Split neu festlegen (Vorschlag: Scan | Foto), alte Namen nicht übernehmen.
- **W8 Warten.** GP R5 und PB R13: kein Spielzeug im Warten, keine künstliche Verzögerung. SB §3: sichtbar gemachte Arbeit wirkt besser (Buell & Norton 2011), darum die Bon-Ladeanimation.
  Auflösung: Animation nur, wenn sie echten Fortschritt zeigt (gefundene Zeilen, Stufe, Prozent); nichts zum Zeitvertreib.
- **W9 Rückgängig.** PB R11 und KF V5.7: Hinweis mindestens 10 s. GP §5: Frist ist problematisch, besser Liste „Zuletzt“ ohne Frist. Beides umsetzen.

## 13. Offen und nicht geprüft

- Reichweite (Daumen) und Umrechnung dp nach mm an echten Geräten. [PB R2; GP §6.3]
- Okabe-Ito-Werte am Original; Simulation für Farbsehschwächen. [GP §6.5]
- Person-zuerst gegen Posten-zuerst bei 4 bis 6 Personen. [RT]
- Flutter-Haptik-API, `InteractiveViewer`/Zoom-Verhalten, Impeller-Verfügbarkeit auf den Testgeräten: vor Einbau offizielle Doku lesen. [CM; DG §4]
- TalkBack-Reihenfolge. [PB Prüfliste 16]
- Fühltest der Haptik-Muster. [HA §7]
