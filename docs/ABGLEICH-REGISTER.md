# Abgleich des Anforderungs-Registers (14.11., nach Kritik des Nutzers 11:29/11:32)

Grundlage: jeder Eintrag in `docs/ANFORDERUNGEN.md`, geprüft am Code (grep, Stand main nach 0.1.128) und an angesehenen Bildschirmfotos dieser
Sitzung. **✅** gebaut und belegt · **◐** teilweise oder nicht am Bildschirm geprüft · **❌** fehlt. Was nicht am Bildschirm gesehen wurde, steht
als ◐, auch wenn der Code da ist. Bei jedem Paket hier und im Register nachtragen (CLAUDE.md „Fertig heißt“ Punkt 8).

## ❌ Fehlt (Reihenfolge = Plan)
| Eintrag | Was fehlt |
|---|---|
| 27d (12.11.), 26d (11.11.), 09.11. 18:44 Nr. 3, 08.11. 04:09 (2) | **Bon-Ansicht umbauen:** Personen/Vorschläge belegen bis zu 4 Zeilen vor den Posten; Kopf nicht wie die Gruppenübersicht. Am 14.11. fälschlich als erledigt gemeldet (Test-Bon mit 2 Personen). → Entwürfe zur Auswahl (Nutzer 14.11. 09:44). |
| 07.11. 21:56 | Suche: **Datumsbereich wählbar**, **gespeicherte Filter als Chips** – kein Code gefunden. |
| 08.11. 11:25 (Update) | Änderung antippen → **alter und neuer Stand nebeneinander vergleichen**, bestätigen, **Nachricht dazu** – nur Verlauf + Rückgängig vorhanden. |
| 09.11. 13:05 Nr. 1 | **Eigene Reihenfolge auch für Posten** – nur für Rechnungen (`moveBefore`). |
| 09.11. 19:04 Nr. 18 | Sichtbarkeit **„Posten geschwärzt“** (Zeilen ohne Namen, mit Betrag) – fehlt. |
| 07.11. 22:14 (1), 08.11. 00:13 | **Vorhängeschloss für ganze Gruppen** – nur Posten und Rechnung. |
| 08.11. 00:16 / 00:22 | Konto-Sicherung per SMS/E-Mail, **Passkey, 2FA** – nicht gebaut (Server nötig bzw. offen). |
| 08.11. 19:45 | Finanzbeschlüsse (Spendenbitte nach der Abrechnung) – nicht umgesetzt. |
| 09.11. 18:44 Nr. 7, 14.11. | **Push bei geschlossener App** – Freigabe da, Weg in Klärung (`docs/recherche/2026-11-14-push.md`). |
| 08.11. 12:33, 08.11. 21:15 | **Leistung iPhone/Safari** am echten Gerät – nie gemessen (nur WebKit unter Linux, 14.11.). |

## ◐ Teilweise oder am Bildschirm ungeprüft
| Eintrag | Stand |
|---|---|
| 08.11. 04:09 (1),(6) | Platz/Lücken, untere Leiste, Querverweise: vieles umgebaut (Menü A, Gruppenkopf), Gesamtbild nie gegen den Auftrag geprüft. |
| 09.11. 09:22 Nr. 1, 9, 12 | „Bauhaus/Rams/Apple“-Gestaltung von Start, Profil, Einstellungen: umgebaut, aber nie als Entwürfe zur Auswahl vorgelegt. |
| 09.11. 18:44 Nr. 2 | Suche: Sprung + Pulsieren (`focusItem`), letzte Suchen (`recentSearches`), „Meintest du“ (`search_suggest.dart`) da; Live-Aktualisierung und Posten-Ansicht nicht neu geprüft. |
| 09.11. 18:44 Nr. 4 | Einheitliche Abstände/Rundungen – nicht systematisch geprüft. |
| 09.11. 18:44 Nr. 5 | Weiße Seite nach App-Wechsel – `resume.dart` vorhanden, Ursache nicht am Handy belegt. |
| 09.11. 18:44 Nr. 13 | Glocke führt zum Ziel (`openBillAt`) – Pulsieren am Ziel nicht geprüft. |
| 08.11. 11:25 (Protokoll) | Jede Änderung überall nachlesbar – Verlauf je Gerät, begrenzt. |
| 08.11. 11:31, 12:08 | Veraltete Web-App: Erkennung (`outdated`, `staleApp`), Schreibschutz für Altstände ungeprüft auf echtem iPhone. |
| 11.11. 11:13 Nr. 25 | Verknüpfung über Konto (uid) statt Namen: lokal (`ownUids`), Chat/Mitgliederliste noch über Namen. |
| 09.11. 13:05 Nr. 10 | Kopf baut sich beim Blättern nicht nach – nicht neu geprüft. |
| 08.11. 22:00 | Leistungstest realistischer: Phasen mit 500 Posten da; Bewertung auf dem S23 nach den letzten Änderungen nicht neu gemessen. |
| 09.11. 00:40 | Datenschutz: Geschichte von Fasan-Split am 14.11. umgeschrieben; Wächter-Test gegen echte Namen im Repo fehlt; alte Commits bei GitHub (Support nur durch Nutzer). |
| 08.11. 00:32 / 00:33 | Recht/Finanzierung: `docs/recht/` angelegt, Entscheidungen 19:45 nicht umgesetzt. |

## ✅ Gebaut und belegt (Auswahl mit Beleg)
Vorhängeschloss Posten/Rechnung (lock_service_test) · Mengen-Posten + Rahmenfarbe (0.1.7x, Tests) · vorläufiger Saldo · Saldo-Aufstellung
„So kommt das zustande“ (balance_breakdown) · Saldo-Verlauf mit Rückgängig (0.1.112) · Rechnungsfarben, Sortierung nach Status/Datum (auch
Belegdatum, Hinweis 08.11. 12:09) · „Nur offene Posten“ ↔ „Alle Posten“ · Menü Gruppe | Abrechnung | Freunde (08.11. 21:06) · Rechnungen ohne
Zahler in der Gruppen-Übersicht (21:15) · Alle Posten der Gruppe (04:16) · Zahlung/Leihgabe (22:14 (5)) · Plus in der Gruppe · Tutorial und
Tipps je Sprache (Schlüssel-Test) · „Später weiter“ statt Speichern · Version/Datum/Neuigkeiten im Browser (0.1.85) · Neuigkeiten verständlich je
Sprache (news/) · Überhang „1 Stück zu viel“ (overUnits) · Schutz gegen Überschreiben durch Altstände (stale_store_test) · Stellvertreter-Stufen
und „vielleicht“ (Pakete 4, 0.1.117; maybe_test) · Sichtbarkeit „Beteiligte“, Beträge sichtbar lassen (0.1.99–0.1.105) · Posten schicken
(0.1.94/0.1.116) · Notizen an Bon und Posten (`it.note`, Bon-Notizen mit Anpinnen) · Konto/Abmelden/Wörter einfügen (0.1.106) · Pakete 1–8 vom
12.11. (0.1.114–0.1.121) · Schraffur je Person (0.1.122) · Bon als PDF (0.1.125) · Rechte der Gruppe (0.1.126) · Währung aus dem Bon (0.1.128).
