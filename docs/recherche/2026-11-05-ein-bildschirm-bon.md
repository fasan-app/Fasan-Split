# Ein Bildschirm statt vier Schritte (Nutzer 05.11.)

Anlass: Der Nutzer sieht im ersten Schritt nur ein Namensfeld, obwohl die Gruppe Mitglieder hat; Personen, Zuordnen und Bezahlen
liegen auf drei weiteren Bildschirmen; Posten lassen sich in Schritt 1 nur bearbeiten, in Schritt 3 nur zuordnen; manche Angaben
(Bon-Ausschnitt unter jedem Posten, Prüfzeile, „Wer war dabei?“) sind unverhältnismäßig groß oder unruhig.

## Was recherchiert ist (und was nicht)

Kennzeichen: **[Quelle]** gelesen, **[Sekundär]** Suchergebnis ohne Primärseite, **[nicht geprüft]**.

- **Zuordnen in Rechnungs-Apps** [Sekundär: App-Store-Texte und Bewertungen von Tab, Billy, SplitBill, TabSplit, Piecemeal,
  Checkify; keine Nutzerforschung]: Es gibt beide Wege – Person antippen, dann Posten; Posten antippen, dann Personen wählen – und
  Ziehen auf Personen. Wiederkehrende Beschwerde: Mengen teilen (2 Stück, 1 davon für eine Person), Teil-Anteile, Prozent. Ein
  Bewerter wollte „Posten antippen, Liste aller Personen, auswählen“. Folge: **beide Wege anbieten**, Mengenanteile behalten
  (gibt es schon: `SplitMath.pieces`), jede Zuordnung leicht korrigierbar.
- **Auswahlliste beim Tippen** [Sekundär: Baymard, Lucidworks, Voyado über Suchfeld-Autovervollständigung, nicht Personenauswahl]:
  wenige Vorschläge (4–8 auf dem Handy, sonst Auswahlmüdigkeit), nach Art gruppiert mit Überschriften, die Liste liegt zwischen
  Feld und Tastatur, manche tippen so schnell, dass sie Vorschläge nie sehen. Folge: **Liste kurz, gruppiert (Gruppe, Freunde,
  zuletzt), Treffer ab dem ersten Buchstaben, „Neu: <Text>“ als letzte Zeile**, Enter nimmt den ersten Treffer. Nielsen Norman
  Group wurde gesucht, aber nicht gefunden (nicht geprüft).
- **Assistent oder eine Seite** [Sekundär: Designsystem-Seiten Visa, Trimble, CFPB, Blogs]: Unter etwa zehn Feldern sind
  Einzelseiten nicht schlechter als Assistenten; auf kleinen Bildschirmen brauchen Assistenten viel Platz, einklappbare Bereiche
  passen besser; Verlust von Eingaben beim Zurückgehen schadet dem Vertrauen. Folge: **eine Seite, Bereiche, die sich
  verdichten**, alles sofort gespeichert (wie heute).
- **Chips** [Sekundär: Material-2-Text und Flutter-Doku; Material-3-Seite nicht lesbar]: Eingabe-Chips sind der Weg für
  Personen in einem Feld (entfernbar, auch aus Vorschlägen), Auswahl-Chips für genau eine Option (Zahler), Filter-Chips für
  mehrere. Folge: Personen als Eingabe-Chips, „Bezahlt von“ als eigene Zeile.

Quellen: apps.apple.com (Billy id6740248870, TabSplit id6748755549, Tab, Checkify), baymard.com/blog/autocomplete-design,
lucidworks.com/blog/best-practices-to-convert-autocomplete, cfpb.github.io/design-system/patterns/designing-forms,
styles.trimble.com/components/web/wizard, m2.material.io/components/chips, api.flutter.dev (InputChip, ActionChip).

## Beschlüsse des Nutzers (05.11.)

1. Schritt 2 entfällt. Personen, Zahler und Zuordnen sind in Schritt 1. Es gibt nur noch diesen Bildschirm und danach die fertige
   Anzeige (Übersicht/Ergebnis); „Fertig“ markiert den Bon nur als fertig, alle Funktionen von vorher bleiben (schließen,
   zurückgehen, ausgleichen, teilen, bezahlen).
2. Die Posten stehen in Schritt 1 wie die Liste in Schritt 3. **Bearbeiten und Zuordnen gleichzeitig** (ein Blatt je Posten).
3. In einer Gruppe werden die anderen Mitglieder **vorgeschlagen**. „Person hinzufügen“ öffnet eine Auswahl aus allen Freunden
   und Gruppenmitgliedern, **beim Tippen live gefiltert**.
4. Ist ein Freund nicht in der Gruppe: **fragen, ob er eingeladen werden soll**; die Einladung geht direkt an ihn und braucht keine
   Bestätigung durch uns; sie lässt sich **zurückziehen** (Rückgängig).
5. Prüfen der Posten: **auf Wunsch per Knopf oben**, nicht als Dauerzeile. Eine Zeile erscheint nur, wenn etwas nicht stimmt.
6. Anzeige verdichten: keine Dauer-Bildchen unter jedem Posten, kleinere Köpfe, ruhige Statuszeile.
7. Browser und App sind gleich (Funktionen, Layout, Menü oben rechts, Original-Bild, Ton), soweit der Browser es kann.
8. Alle Texte liegen **getrennt vom Code** in Sprachdateien, damit weitere Sprachen ohne Code-Lesen dazukommen.

## Aufbau des neuen Bildschirms (von oben)

1. Kopf (eine Zeile): Zurück · Titel „Bon“ · Knöpfe **Prüfen**, **Original** (Bon-Ausschnitte an/aus), Menü ⋮ (neu lesen,
   gleichmäßig teilen, Kategorie/Währung, Bon schließen). Kein „1 / 4“.
2. „Wofür?“ und „Summe“ (eine Zeile, Summe rechts, groß nur hier). Darunter **eine** Zeile kleiner Chips: Währung, Kategorie,
   Datum, Ort.
3. **Personen**: Eingabe-Chips der Beteiligten (in einer Gruppe: alle Mitglieder schon vorgeschlagen, mit einem Tipp übernommen;
   „Alle aus der Gruppe“), `+` öffnet die Auswahl. Eine Person antippen macht sie „aktiv“: danach schaltet Antippen eines Postens
   sie dort an/aus (schnell für viele Posten). Danach **„Bezahlt von“** als eigene Zeile (Pia ▾; Mehrere mit Beträgen im Blatt).
4. **Posten** (wie Liste in Schritt 3): Name, Menge, Preis, Avatare der Zugeordneten. Antippen der Zeile öffnet das **Blatt**
   mit Name, Menge, Preis (sofort gespeichert) und darunter den Personen-Chips samt Mengenanteilen; Wischen löscht (mit
   Rückgängig). Fehlende Zuordnung ist ruhig markiert (Rand), nicht rot.
5. Unten feste Leiste: **Fertig** (zeigt „3 offen“, bis alles zugeordnet, ein Zahler gewählt und die Summe geprüft ist, sonst
   sagt ein Tipp, was fehlt) und **Speichern**.

Fertige Anzeige (bisher Schritt 4/Ergebnis): Ergebnis, Überweisungen, Bezahlen-Knopf, Ausgleichen, Teilen, Export; „Fertig“ setzt
nur das Kennzeichen; Zurück führt in den Bildschirm, Schließen zur Liste.

## Prüfung der Bedienung (Stresstest)

Widget-Tests für: Gruppe mit 5 Mitgliedern (alle vorgeschlagen), Live-Filter, Freund außerhalb der Gruppe → Einladung → Rückgängig,
Posten bearbeiten und zuordnen im selben Blatt, aktive Person, mehrere Zahler, Fertig-Bedingungen; Größen: Handy hoch/quer,
Tablet, Desktop-Spalte; Sprachen de/en. Dazu Zufallsbedienung (Monkey: 500 zufällige Tipps/Eingaben, keine Ausnahme, kein
Überlauf) und Browser-Läufe mit Playwright (Handy- und Desktop-Fenster) mit Bildschirmfotos. Was davon nicht automatisch geht,
steht in `STAND.md` als „nicht geprüft“.

## Lange Namen und Wischmenüs (Nutzer 05.11., Nachtrag)

**Recherche** (alles Zweitquellen; die HIG-Seite zu Swipe Actions und Material 3 ließen sich nicht abrufen, nicht geprüft):
- iOS (SwiftUI-Doku `swipeActions`): Aktionen hängen am führenden oder nachlaufenden Rand, die erste Aktion liegt am nächsten am
  Rand, ganzes Durchwischen führt die erste Aktion aus, „destruktiv“ ist eigens gekennzeichnet; Warnung vor versehentlichem Löschen
  durch volles Durchwischen → bei uns Löschen immer mit „Rückgängig“.
- Android/Chrome-Hinweise: die Geste enthüllt schrittweise einen Hintergrund, der das Ergebnis zeigt (Mülleimer); kurzes Wischen
  federt ohne Aktion zurück; Trennlinien zeigen, dass etwas wischbar ist.
- Rechnungs-Apps (App-Store-Texte): Tab Team „wischen = für sich/alle teilen“, SplitApp „Posten per Wischen bearbeiten“, Tippen zum
  Zuordnen, Ziehen auf Personen. Folge: rechts wischen = für alle (nochmal = niemand), links = löschen, Tippen = Blatt (bearbeiten
  und zuordnen), langes Drücken auf eine Person = Menü (hat bezahlt, alle offenen Posten, entfernen).
- Laufschrift (WCAG-Hinweise zu `<marquee>`): bewegter Text braucht Kontrolle, darf mit „Animationen reduzieren“ nicht von selbst
  laufen, WCAG 2.2.2: länger als 5 s braucht eine Pause. Folge: **ein** kurzer Durchgang (höchstens 3,4 s + 0,65 s Halt + Feder)
  nach 1,4 s, dann alle 10 s nur solange sichtbar; nie bei reduzierter Bewegung; Volltext in der Semantik; ausgeblendeter Rand
  statt hartem Schnitt.

**Beschluss:** `MarqueeText` (`ui/marquee_text.dart`): überlanger einzeiliger Text blendet am Rand aus, scrollt langsam und
gleichmäßig (ca. 34 px/s) zur Seite und federt zurück. Er hat **keine eigenen Gesten**: Antippen und Wischen gehören der Zeile
(ein Test hat gezeigt, dass eine eigene Antippen-Geste das Antippen langer Namen verschluckt hätte). Chips nutzen `MarqueeLabel`
(feste Breite, weil Chips Größen ohne Layout abfragen). Eingebaut in Posten, Personen-Chips, Zahler-Chip, Rechnungskacheln,
Gruppenzeilen, Notizen und Zusammenfassung. Nicht eingebaut (noch harter Schnitt, mehrzeilig oder schmal): Chat-Reiterbeschriftung,
Ort-Zeile.

