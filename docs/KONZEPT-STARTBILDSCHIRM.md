# Konzept Startbildschirm, Profil, Menü (Nutzer 09.11. 09:22)

Stand: Entwurf, umgesetzt in Web 0.1.88 (APK ruht). Alle Regeln stammen aus `docs/recherche/` und der Lesung vom 09.11.; **neu** heißt: nur Websuche 09.11., nicht vollständig gelesen.

## Befund
Der Startbildschirm hatte sieben Ebenen über der Liste (Kopfzeile mit 6–7 Symbolen, Tipp, Offen|Archiv|Papierkorb, Gruppen-Chips, Rechnungen|Posten, Kopf, Zählzeile). Die Seiten waren verschieden aufgebaut, darum sprangen Elemente.

## Entscheidungen
1. **Kopfzeile immer gleich:** links das Fasan-Symbol, rechts Neuigkeiten und Profil (Avatar + mein Stand). Kein Titel: die Tabs unten sagen, wo man ist (Apple HIG Tab-Leiste: Tabs sind Orte; neu: Instagram-Muster auf Wunsch des Nutzers).
2. **Profil von überall sichtbar:** ja, es ist der Avatar rechts oben. Einstellungen liegen im Profil oben rechts (Apple HIG „Settings“: Einstellungen in Profil- oder Kontoansicht anbieten – neu, Websuche 09.11.).
3. **Stellvertretung im Profil:** Schalter „Andere dürfen für mich eintragen“ direkt unter „Mein Stand“; vorher unter Konto versteckt. Ein = Standard. Aus = Änderungen anderer über mich warten auf meine Bestätigung.
4. **Kontextzeile, auf allen drei Tabs gleich hoch:** links der beschriftete Gruppenschalter („Alle Gruppen ▾“, „Ohne Gruppe“, Name) öffnet ein Fenster mit Suche ab 7 Gruppen; rechts Filter-Symbol (mit Punkt, wenn etwas aktiv ist) und ⋮. Auf Freunde steht dort nur der Name des Tabs, die Höhe bleibt (Platz für spätere Suche).
5. **Filter-Fenster:** Anzeigen (Rechnungen | Posten), nur offene Posten, Sortierung, Kategorie. Sortieren verlässt die Kopfzeile.
6. **⋮-Menü:** „Auswählen“ (vorher eigenes Symbol); bei gewählter Gruppe zusätzlich Einladen, Verlauf, Verlassen/Löschen. Einträge werden ausgegraut, nicht versteckt.
7. **Freunde ohne Zahl:** ein nackter Betrag ohne Wort ist unklar (Saldo = Vorzeichen + Wort + Symbol, Farbe nur zusätzlich; Regelwerk 5.8). Der Stand steht in Abrechnung und Profil.
8. **Hinweiszeile aus:** kein Platz mehr dafür; Tipps bleiben in den Einstellungen und am Element.

## Offen (Rückfrage nicht nötig, Entwurf)
- Untere Leiste schlanker mit klareren Symbolen: Vorschlag Gruppe = `receipt_long`, Abrechnung = `balance`/`swap_horiz`, Freunde = `people`; Höhe nicht geprüft (Material 3 Seite nicht lesbar).
- Einstellungen neu gliedern (höchstens 2 Ebenen, ~8 Gruppen mit Zustandszeile, „Oft genutzt“ oben, „Über“ unten).
- Rechnungsfarben, Suche, eigener Betrag in der Kopfzeile bleiben als Platz reserviert.
- Wunsch „Gruppenchips als Ziehziel für Bons“ entfällt; Ziehen geht weiter über die Leiste unten.
