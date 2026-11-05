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
   sie dort an/aus (schnell für viele Posten). Danach **„Bezahlt von“** als eigene Zeile (Chris ▾; Mehrere mit Beträgen im Blatt).
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
