# Anforderungen des Nutzers (Register)

Stand 06.11. (erste Fassung, Punkt 0a). Quelle: Nachrichten ab 04.11. 23:36 (Rohtext privat in `../fasan/nutzer/split-nachrichten.md`),
Beschlüsse oben in `STAND.md`, `docs/VORSCHLAEGE-06-11.md`. Ältere Wünsche stehen in `STAND.md` (Soll-Liste, Verlauf) und
`../fasan-karte/docs/ENTSCHEIDUNGEN.md` (Soll-Umfang) und gelten weiter. **Stand je Zeile nach Doku/Erinnerung der Sitzung; bei jedem Paket
am Code nachprüfen und hier berichtigen.** Stand: ✅ umgesetzt und nachgewiesen · ◐ teilweise / ungeprüft · ❌ fehlt · ⚠ Widerspruch.

## Arbeitsweise (gilt für jede Sitzung)
| Datum | Anforderung (sinngemäß) | Grund | Stand | Ort |
|---|---|---|---|---|
| 05.11. | Alles, was die Sitzung prüfen kann, selbst prüfen und stresstesten; nichts dem Nutzer überlassen | „du überlässt mir ständig zu viel“ | ◐ | CLAUDE.md PFLICHT |
| 05.11. | Proaktiv recherchieren, welche Bedienung Nutzer erwarten, und einbauen | „baust mir das nicht proaktiv genug ein“ | ❌ (Recherchen nie angewendet) | Prüfliste, Punkt 0b |
| 06.11. | Alle Anweisungen prüfen, ob sie in den Projektdaten stecken; Iterationen vergleichen; Recherchen anwenden; selbstkritisch | wiederholt halbfertige Lösungen | ◐ (dieses Register) | hier |
| 06.11. | Fragen und Vorschläge vor der Arbeit klären | Kurs-Abweichungen | ✅ (3 Befragungen) | VORSCHLAEGE-06-11 |
| 06.11. | Zusagen, Lehren, Vorschläge sofort festschreiben, ohne Erinnerung | „dass ich dich daran erinnern muss“ | ✅ Regel | CLAUDE.md |
| 06.11. | Bis kurz vor Kontingent-Ende arbeiten, Rest für Notizen; Kontingent im Blick | Wochenlimit | ◐ | STAND „Kontingent“ |
| 06.11. | Stabile Bereiche einfrieren, Änderungen mit wenig Token-Aufwand; Industriestandard 2026 recherchieren | Zukunftssicherheit | ❌ | Plan Punkt 6 (Neuschreiben) |

## Erkennung
| Datum | Anforderung | Grund | Stand | Ort |
|---|---|---|---|---|
| 05.11. | Belém-Bon korrekt lesen, Algorithmus stresstesten, keine neue Version vorher | „völlige Katastrophe“ | ◐ (Korrektur da, Tor fehlt) | reader.dart, pipeline.dart |
| 05.11., 06.11. | Viel mehr echte, weltweite Bons/Rechnungen in die Tests (7-Eleven Japan, Miete Italien); alle auffindbaren, auch vereinzelte; ~100 selbst beschrieben | „13 Bons sind keine Grundlage“ | ❌ → in Arbeit (Korpus) | fasan-diagnose/tests/welt, CI |
| 06.11. | „13 Croissants“: zuvor gut laufender, kritischer Teil darf nie schlechter werden | Regression | ◐ (Ursache gefunden, ungeprüft im Zweig) | reader.dart (Steuersatz als Menge) |
| 06.11. | Tor in der CI über privates fasan-diagnose, stoppt Veröffentlichung | nie wieder unbemerkt | ❌ | Punkt 2 |
| 06.11. | Weltweite Schriften: erst Latein perfekt, dann Modelle in die APK | Beschluss 02.11. offline | ❌ | Punkt 7 |

## Bon-Bildschirm und Bedienung
| Datum | Anforderung | Grund | Stand | Ort |
|---|---|---|---|---|
| 05.11. | Mehrere Zahler mit unterschiedlichen Anteilen direkt im ersten Schritt | Alltag | ◐ (Blatt da, ungeprüft am Gerät) | ui/payers.dart |
| 05.11. | Negative Beträge (Gutschriften) ohne falsche Riesen-Meldung | 396 €/−198 € | ◐ | model alignSigns |
| 05.11. | Ein Bildschirm: Personen, Zahler, Zuordnen im ersten Schritt; Posten bearbeiten **und** zuweisen; Schritt 2 entfällt | Doppelarbeit | ◐ (gebaut ohne Recherchen) | ui/bill_screen.dart |
| 05.11. | Gruppenmitglieder vorschlagen; Person hinzufügen mit Live-Filter über Freunde und Gruppe | Sinn | ◐ | ui/person_picker.dart |
| 05.11. | Freund außerhalb der Gruppe einladen ohne Bestätigung, zurückziehbar | Bequemlichkeit | ◐ | collab/service.dart |
| 05.11. | Prüfen auf Wunsch per Knopf oben | Ruhe | ◐ | bill_screen |
| 05.11. | Lange Namen ausfaden und langsam federnd scrollen statt hart abschneiden | Lesbarkeit | ◐ (im Sparmodus aus, Beschluss 05.11. abends) | ui/marquee_text.dart |
| 05.11. | Wischmenüs auf Posten wie bei Rechnungen | Gewohnheit | ◐ | bill_screen |
| 06.11. | Bon-Ausschnitte unter den Posten **standardmäßig** sichtbar (kompakt) | einzig krisensicherer Beleg | ❌ (05.11. entfernt – ⚠ zu „zu groß/unruhig“ 05.11.: kompakt statt weg) | Punkt 5 |
| 06.11. | Gruppe „Bons zuerst“; ein Begriff „Personen“ | zu viel Platz, verwirrend | ❌ | Punkt 5 |

## Browser = App
| Datum | Anforderung | Grund | Stand | Ort |
|---|---|---|---|---|
| 05.11. | Browser und APK gleich in Funktion und Layout, soweit der Browser kann (Ton, Original-Bild, Menü oben rechts) | Freunde nutzen Browser | ❌ (⋮-Menü leer, Original fehlt: Fotos nicht im Abgleich, Startladen aller Fotos) | Punkt 3/4 |
| 05.11. | Kacheln mit Bons oben auch im Browser | fehlte | ◐ | home.dart |
| 06.11. | 1:1 in allem, künftige Änderungen gelten für beide; eine Codebasis | Beschluss | ◐ Regel | CLAUDE.md |
| 06.11. | Fotos/Ausschnitte für alle in der Gruppe: Relays + Blossom, Standard, ohne Verlust an Sicherheit/Leistung | 2. Gerät sieht nichts | ❌ | Punkt 4 |

## Leistung
| Datum | Anforderung | Grund | Stand | Ort |
|---|---|---|---|---|
| 05.11. | Leistungstest beim Sitzungsstart, Effekte danach reduzieren | Browser langsam | ✅ gebaut (Regler), ◐ gemessen nur teilweise | perf/perf_governor.dart |
| 05.11. | Grundeinstellung maximale Leistung, Effekte zuschaltbar | sofort | ✅ (Standard „Sparsam“) | perf_governor |
| 06.11. | Browser schnell selbst auf 10 Jahre alten Geräten; S23 „unterirdisch“ | Nutzung | ❌ (Ursachen gefunden, nicht behoben) | Punkt 5 (Leistung) |

## Einladung, Konto, Gruppe
| Datum | Anforderung | Grund | Stand | Ort |
|---|---|---|---|---|
| 05.11. | Einladungslink vollständig erkannt (iPhone/Samsung), ein Link genügt | Freunde landeten leer | ◐ (Link v2 + E2E grün; echtes iPhone nicht) | collab/group.dart, join/ |
| 05.11. | Beitrittsbildschirm selbsterklärend; Hinweis auf Konto, Sicherung, Wiederherstellung präsent | „was, wenn ich den Browser schließe?“ | ◐ | ui/join_screen.dart |
| 05.11. | Sagen, was der Browser grundsätzlich nicht kann | Klarheit | ✅ | docs/WEB-GRENZEN.md |

## Sprache
| Datum | Anforderung | Grund | Stand | Ort |
|---|---|---|---|---|
| 05.11. | Umschalter Deutsch/Englisch, App komplett englisch | weltweit | ◐ (alte Texte teils noch im Code) | lib/l10n |
| 05.11. | Alle Texte getrennt vom Code in Sprachdateien, ohne den ganzen Code zu lesen | viele Sprachen | ◐ | lib/l10n, docs/SPRACHEN.md |

## Umfang dieser einen Veröffentlichung (Befragung 2 und 3, 06.11.)
Rückgängig/Wiederholen; Ausgaben ohne Bon; Aufteilen gleich/fest/Anteile/Posten; exakter Ausgleich + „bezahlt“; dazu alle vier Bereiche
der Lückenliste (`docs/VORSCHLAEGE-06-11.md` § E2–E5). Stand: alle ❌ bzw. wie dort.
| 06.11. | Selbstständig weiterarbeiten, ohne dass der Nutzer jedes Mal bestätigen muss | Nutzer arbeitet vom Handy | ✔ gilt ab sofort (Zwischenberichte kurz, kein Warten auf „weiter“) | STAND.md |

- 06.11. abends (Nutzer): Als Nächstes Vergleich Bildschirm für Bildschirm zwischen App und Browser; nach Kontextverlust nichts übergehen oder vergessen. Grund: „Web 1:1“ war behauptet, nicht verglichen. Stand: in Arbeit.

- 06.11. nachts (Nutzer, Frage): Warum Code nicht direkt als Browser-Version, machen andere alles doppelt? Antwort gegeben (eine Codebasis, dünne Adapter, Grenzen des Browsers); Aussage zu anderen Diensten nicht geprüft. Stand: beantwortet.

- 06.11. nachts (Nutzer, Frage): Wenn Flutter denselben Code nutzt, warum waren Web und App so verschieden und die Anpassung so kompliziert? Antwort gegeben (Daten nicht geteilt, Schrift, Speicher, Erkennung, kein früherer Vergleich); Stand: beantwortet.

- 06.11. nachts (Nutzer, Frage): Muss die Web-Anpassung jedes Mal gemacht werden, greift der modulare Aufbau auch im Web (App-Änderung → Web)? Antwort + Regel in CLAUDE.md; Stand: beantwortet, modularer Neubau offen.

- 06.11. nachts (Nutzer, Kritik/Frage): Warum gab es Unterschiede Web/App; arbeitest du am Neuaufbau vom Fundament (letzte Nacht beauftragt), was ist der Plan? Stand: Neuaufbau NICHT begonnen (ehrlich gemeldet); Schritt 1 Bestandsaufnahme + Plan in docs/ARCHITEKTUR.md; Umsetzung als Nächstes.

- 06.11. 23:35 (Nutzer an Sitzung B): B übernimmt parallel zu A; selbstständig arbeiten ohne Rückfragen je Schritt; Repos wie CLAUDE.md Schritt 0 (Fasan nur lesend);
  Vorschlag für B: Bereich „Erkennung“, vorher in `docs/ZUSAMMENARBEIT.md` belegen; eine Veröffentlichung auf main am Ende nach vollem Tor; jede Zusage/Nachricht/
  jeden Beschluss sofort in Dateien. Stand: angenommen, belegt 06.11. 23:50 (Zweig `mitarbeit/B-erkennung`). Rohtext: nicht in `../fasan/nutzer/` (B nur lesend).

- 06.11. 23:48 (Nutzer an B): Was Sitzung A zuletzt begonnen und wegen Kontingent nicht abgeschlossen hat, ist wichtiger als die Erkennung zu verbessern. Stand: angenommen; Erkennung pausiert (817d52f), B übernimmt A's Rest (ZUSAMMENARBEIT). Rohtext: nicht in `../fasan/nutzer/` (B nur lesend).
- 06.11. 23:50 (Nutzer): Selbstständig erkennen, ob zuletzt angefangene Aufgaben (eigene oder von Sitzung A) offen sind; die zuerst abschließen, statt parallel neue Baustellen zu öffnen. Stand: Regel in CLAUDE.md und ZUSAMMENARBEIT; Reihenfolge B: Teilzahlung (A) → übriger A-Rest → eigene Erkennung 817d52f → erst dann Neues.
- 06.11. 23:54 (Nutzer, Wunsch + Frage): **Vorläufiger Saldo**, sobald Posten vergeben sind – beim Profil und in Gruppen sichtbar, auch wenn noch unklar ist, wer bezahlt hat, und der Bon nicht fertig ist. Grund: Bons werden oft erst spät von allen ausgefüllt; man weiß nur, ob man selbst bezahlt hat, will aber Ausgaben und Schulden früh sehen. Stand: **neu**, Vorschlag gemacht (STAND „Offene Fragen“), Umsetzung nach dem angefangenen Rest (Regel „Angefangenes zuerst“). Heute zählt `fasan_core/settle.dart` nur fertige Bons mit Zahler.
- 06.11. 23:57/23:58 (Nutzer): Roadmap nicht aus dem Auge verlieren; direkt nach dem Angefangenen Priorität 1: Web und App komplett gleich, 2: maximale Leistung (Browser ruckelt extrem, wenig reaktiv); erst dann andere Aufgaben. Stand: Rangfolge in STAND.md.
- 06.11. 23:59 / 07.11. 00:00 / 00:02 (Nutzer): regelmäßig aufschreiben, was getan wird und was fehlt (Kontingent, Zusammenarbeit); effektiv und token-sparsam; Rechen-/Wartezeit egal, Gründlichkeit, sauberer schneller Code, Genauigkeit, Fehlerfreiheit zählen. Stand: Regeln in CLAUDE.md, Protokoll in ZUSAMMENARBEIT.

- 07.11. 09:58 (Nutzer): Vorläufiger Saldo – Hauptzahl zählt fest und vorläufig zusammen (Vorschlag Sitzung B übernommen). Außerdem Wunsch, dass B Schreibrecht auf die privaten Repos `Fasan` und `fasan-diagnose` bekommt (Rohtexte, Bestwerte im Tor). Stand: neu; Umsetzung nach „Web = App“ und Leistung.
