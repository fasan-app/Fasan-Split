# Konzept: Stellvertreter-Stufen und „vllt“-Vorschläge (Paket F, Nutzer 09.11. 19:04)

Stand 10.11.: Konzept, nichts umgesetzt. Grundlage ist der vorhandene Mechanismus in `lib/collab/service.dart` (`confirmAll`, `distrusted`,
`HeldChange`, `decideHeld`, `_accept`).

## Was es schon gibt
- Schalter „Andere dürfen für mich eintragen“ (global, `confirmAll`) und eine Liste `distrusted` (einzelne Personen, ohne Oberfläche).
- Änderungen anderer, die meine Anteile, meine Person oder den Zahler berühren, werden **nur auf meinem Gerät** zurückgehalten
  (`HeldChange`) und warten auf mein Ja/Nein. Bei den anderen sieht der Eintrag so aus, als wäre er gültig.

## Was der Nutzer will
1. Je Person wählbar, was sie für mich darf: **voll** (trägt mich ein, als wäre es offen), **nur vorschlagen**, oder **nichts**.
2. Ein Vorschlag steht sichtbar im Posten, anders markiert („vllt Mama“). Der Posten bleibt **offen**, bis die Person bestätigt.
   Die Person bekommt eine Benachrichtigung.
3. Pro Vorschlag **eine** Person (kein „Mama oder Papa“).
4. Rechte lassen sich innerhalb der Gruppe verteilen.

## Entwurf
- **Stufe je Person:** `trust/<fremder Schlüssel> = full | propose | none`, dazu `trust/default`. Standard bleibt `full`
  (heutiges Verhalten, „alle vertrauen allen“). Ablage lokal wie `_kTrust`; die Stufe wird zusätzlich im eigenen Profil-Dokument der
  Gruppe veröffentlicht (`profile:<pub>`, Schlüssel `delegates`), damit die anderen Geräte schon vor dem Schreiben wissen, was
  erlaubt ist (kein Raten beim Eintragen).
- **Vorschlag als eigener Schlüssel** im Bon-Dokument: `sv/<posten>/<person> = <Vorschlagender>`. Er zählt in keiner Summe
  (`fill` bleibt offen oder teilweise) und erscheint als Marke „vllt“ am Personen-Kreis. Bestätigen = `s/<posten>/<person>` setzen
  und `sv/…` löschen; Ablehnen = `sv/…` löschen. Ältere Geräte kennen `sv/` nicht und ignorieren ihn (keine Verschlechterung).
- **Schreibregel (`_accept`):** Stufe `none` → Schreiben auf mich wird abgelehnt; `propose` → ein Schreiben auf `s/…/<ich>` wird
  beim Empfang in `sv/…` umgewandelt (die Gerätekopie der anderen zeigt dann „vllt“); `full` → wie bisher.
- **Benachrichtigung:** neue Art `ActivityKind.proposal`, Ziel: der Bon, Posten mittig mit Puls (`PulseOnFocus`, `focusItem`).
- **Oberfläche:** Profil → „Wer darf für mich eintragen?“ (Liste der Gruppenmitglieder, je Zeile drei Stufen); im Posten-Blatt bei
  einem Vorschlag eine Zeile „Mama schlägt dich vor: Bestätigen / Ablehnen“; im Personen-Wähler ein Eintrag „vielleicht“.

## Offene Fragen an den Nutzer (nur falls er sie beantworten will; Standard in Klammern)
- Soll „voll“ auch für **neue** Gruppen gelten, die ich später beitrete? (Ja, über `trust/default`.)
- Darf ein Vorschlagender seinen eigenen Vorschlag zurückziehen? (Ja.)

## Grenzen
- Es gibt keine kryptografische Durchsetzung: Gruppenmitglieder werden wie überall in diesen Dokumenten vertraut (Dokument ist
  Last-writer-wins, jedes Gerät prüft nur beim Empfang). Ein manipuliertes Gerät könnte `none` umgehen. Das bleibt Hinweis in der Hilfe.
