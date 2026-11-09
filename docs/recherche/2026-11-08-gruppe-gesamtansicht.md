# Recherche 08.11.: Alle Posten einer Gruppe, offene Posten, fehlende Zahlungen

Anlass: Nutzer 04:16 (alle Posten aller Rechnungen sehen/bearbeiten; offene Posten und nicht eingetragene Zahlungen ohne Durchklicken). Nur lesend recherchiert.

## Befunde
- Splitwise trennt laut ionos.com/digitalguide (Vergleich, nicht geprüft in der App) „Ausgaben“ (Liste aller Kosten mit Zahler) und „Salden“ („Wer schuldet wem wie viel“, Zahlung oder „bezahlt“ markieren). Tricount: Reiter „Expenses“ und „Balance“ (tricount.com, Glossar). Gemeinsamer Aufbau: Liste und Abrechnung getrennt, beide in der Gruppe.
- Kein Vergleichs-App-Text nennt eine Ansicht „alle Posten aller Belege“ – das ist ein Unterscheidungsmerkmal von Fasan Split (nicht geprüft, nur aus den gefundenen Beschreibungen geschlossen).
- Apple HIG (Auszug über Sekundärquellen skills.sh/skills.cat, nicht die Originalseite): Segmentierte Steuerung für sich ausschließende Ansichten, 2–5 Einträge, kurze Beschriftungen; aktueller Zustand immer sichtbar; Suchumfang/Filter „Tokens“ statt komplizierter Abfragen; breiter Standard, Nutzer verfeinern; Sheets mit Detents (medium/groß); lange Listen: Wichtigstes zuerst plus „Alle zeigen“. Originaltext developer.apple.com/design/human-interface-guidelines noch zu lesen, bevor gebaut wird.
- Eigene frühere Recherche (`2026-11-04-konkurrenz-bedienung-saldo.md`): Saldo je Person und vereinfachter Ausgleich sind Standard.

## Vorschlag (noch nicht gebaut, wartet auf Zustimmung)
1. Gruppenbildschirm: zweiteiliger Umschalter „Rechnungen | Posten“ (segmentiert, ein Tipp, Zustand sichtbar).
2. „Posten“: eine flache Liste aller Posten, gruppiert nach Rechnung (feste Zwischenüberschrift mit Name), dieselben Bedienelemente wie im Bon (Zuordnen, Schloss), Filter als Tokens (Offen, Person, Rechnung). Schloss-Regeln gelten unverändert.
3. Eine einzige Hinweiszeile unter dem Gruppenkopf, nur sichtbar wenn etwas offen ist: „4 offene Posten · 2 Zahlungen fehlen“; Tipp springt in „Posten“ mit Filter bzw. in die Abrechnung. Ist alles erledigt, verschwindet sie.
4. Kopfpreis öffnet die Abrechnung (Sheet): Saldo je Person, Ausgleichsvorschlag, offene Beträge, Abschnitte „Offene Posten“ und „Fehlende Zahlungen“ als Sprungziele.

## Offene Fragen an den Nutzer
- „Nicht eingetragene Bezahlungen“: gemeint ist (a) Rechnung ohne eingetragenen Zahler, (b) Ausgleichsüberweisungen, die noch nicht als bezahlt markiert sind, oder beides? (Annahme: beides.)
- Stand: Annahmen nicht geprüft; Leistung bei vielen Posten (Hunderte) vor dem Bau messen.
