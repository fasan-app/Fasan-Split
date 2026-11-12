# Vorschlag 12.11.: Mitglieder, Profil, Abrechnung, Senden, Auswählen (zu ANFORDERUNGEN 29)

Stand: Entwurf, nichts gebaut. Nur lesend recherchiert. Stärke der Belege: **P** Primär-/Herstellertext, **S** Sekundärquelle, **E** eigener Code,
**G** Schlussfolgerung (geraten). Beispiele ohne echte Namen.

## 0. Was im Code heute steht (E, geprüft 12.11.)
- Mitgliederzeile (`groups.dart` ~375): „In der App“ / „Ohne App“ je nach `memberOfPerson`. Das sagt nur, ob ein Konto verknüpft ist, aber in Worten, die
  falsch klingen (ein Konto ohne App-Installation gibt es nicht, im Browser läuft dieselbe App).
- Tipp auf eine Person öffnet nur ein Aktionsblatt („einladen“, „mit Mitglied verknüpfen“, „Verknüpfung lösen“, „Rechte und Verwaltung“): kein Profil.
- Senden (`home.dart` `_sendVisible`, `send_items.dart` `sendItemsOfBills`): das Symbol oben schickt **sofort alle gerade sichtbaren Posten** als je eine
  Karte je Bon in den Chat der Gruppe. Keine Vorschau, keine Frage, kein Zurück. Die Meldung `send.doneMany` heißt „In {0} Chats geschickt“, zählt aber
  Karten (Textfehler: es ist ein Chat).
- Gruppenmenü oben rechts (`groupActions(... onSelect)`) bietet „Auswählen“ unabhängig davon, ob schon ausgewählt wird (nicht bis ins Letzte geprüft: G).
- Der Saldo je Person (`groups.dart` ~385) erscheint nur, wenn er ≠ 0 ist; sonst bleibt die Zeile leer. „0 €“, „nichts fertig“ und „unbekannt“ sehen gleich aus.
- Mitgliederzahl 7 gegen 8: nicht reproduziert; Kopfzeile der Gruppe und Liste zeigen beide 8. Ursache unbekannt, Test mit erfundenen Daten nötig.

## 1. Belege (Recherche 12.11.)
- **Auswählen**: Material Design: Die obere Leiste wird zur Aktionsleiste, das Navigationssymbol wird durch ein **Schließen-Symbol** ersetzt, der Titel zeigt den
  Zustand (Zahl), Farbe wechselt (material.io/components/app-bars-top, **P**). Ausgang: Einträge abwählen oder Aktion tippen (m2.material.io/design/interaction/selection, **P**).
  GNOME HIG: Kopfleiste mit Abbrechen und Zahl, Aktionsleiste **unten** (developer.gnome.org/hig/patterns/containers/selection-mode, **P**). Folge: kein „Auswählen“ im Menü, solange
  ausgewählt wird; stattdessen X + „3 ausgewählt“.
- **Anklickbar wirkt, muss es sein**: NN/g: Klickbares deutlich zeigen, Nicht-Klickbares nie wie einen Knopf gestalten (nngroup.com/articles/clickable-elements, **P**); flache Gestaltung
  hat schwache Signale und zwingt zum Ausprobieren (nngroup.com/articles/flat-design-long-exposure, **P**). Folge: Prüfliste „jedes Ding, das wie ein Knopf aussieht, tut etwas; jedes Ding, das etwas tut, sieht danach aus“.
- **Senden/Löschen**: Bestätigung nur bei Unumkehrbarem, mit genauem Satz („an 1 247 Empfänger senden, nicht zurücknehmbar“) und Knopf mit Verb statt Ja/Nein; Rückgängig-Fenster
  statt Dauerfrage, Gmail 20 s (uxpsychology.substack.com, dev.to/137foundry, **S**; Nielsen „Confirmation Dialogs Can Prevent User Errors – If Not Overused“ nur über Zitate gelesen). Folge: Senden
  = Vorschau + Ziel + Knopf mit Zahl + 10 s Rückgängig; Papierkorb getrennt und rot.
- **Gruppenrechte**: WhatsApp und Signal trennen **Rechte der Mitglieder** („Mitglieder dürfen: Info ändern, Mitglieder hinzufügen, Nachrichten senden“) von **Admin machen** je Person; Admins entfernen Mitglieder
  und ernennen Admins (support.signal.org/hc/articles/360050427692, signal.org/blog/new-groups, **P**; WhatsApp über guidingtech.com, **S**). Folge: Rechte-Matrix je Gruppe + Schalter je Person.
- **Saldo mit Unsicherheit**: Banken trennen bestätigt und vorgemerkt (arc.io-Blog, Foren, **S**: schwach); Splitwise zeigt hinter jedem Saldo die Einzelbuchungen (tapsmart.com, **S**). Nur-Farbe reicht nicht
  (eigene Regel G3, uxmagic.ai **S**). Folge: drei Zustände mit Text.
- Keine Studie gefunden, die genau „Profil in Rechnungs-Apps“ prüft (G: Vorschlag folgt Messenger-Mustern).

## 2. Ehrliche Grenzen (E, KONZEPT-SICHTBARKEIT und KONZEPT-STELLVERTRETER)
- Eine Gruppe hat **einen** Schlüssel. Jedes Mitglied kann alles lesen und technisch alles schreiben. **Admin-Rechte und Freigaben sind Absprache der Apps, keine kryptografische Sperre**, außer bei Rechnungen mit Stufe
  „Beteiligte“ (eigener Schlüssel je Rechnung, seit 0.1.99). Das muss in der Oberfläche stehen, nicht verschwiegen werden. [Certain]
- „Verlauf der Beträge nur wenn freigegeben“ ist damit nur so stark wie die Rechnungsstufe: Ist eine Rechnung für alle lesbar, kann jede Person ihre Beträge ohnehin sehen. Echtes Verbergen = Stufe „Beteiligte“. [Certain]
- Zahlungsangaben (IBAN, PayPal): im Gruppenprofil abgelegt wären sie für alle Mitglieder lesbar und für immer auf den Relays. Deshalb nur **auf Anfrage als Direktnachricht** an das verknüpfte Konto. Wer nur ein Name ist, hat
  kein Postfach: dort „keine Angaben möglich“ zeigen. [Likely]

## 3. Vorschlag in Paketen (Reihenfolge nach Nutzer: Mitglieder zuerst)
1. **Mitglieder und Profil (Gerüst)**: Zeile zeigt „Konto verknüpft“ oder „Nur Name“ (statt In der App/Ohne App; Symbol + Text). Tipp = **Profil** (ein Bildschirm, gleicher Aufbau überall): Kopf (Name, Status, Saldo mit Zustand), gemeinsame Gruppen,
   „Hat eingetragen/geändert“ (aus dem Verlauf), Knöpfe „Chat“, „Zahlungsangaben anfragen“, „Mit Konto verknüpfen“. Chat-Kopf (Name) und Kreis in Bons/Verlauf führen ins selbe Profil. Zählfehler 7/8 beheben mit Test.
2. **Abrechnung**: Saldo nur aus **fertigen** Rechnungen. Pro Person drei Zustände: Betrag (fertig), „0,00 €“ (nichts fertig, nichts offen), „ungewiss“ mit Grund (z. B. „Zahler fehlt in 2 Rechnungen“) und kleiner Zeile „vorläufig ±x“.
   Tipp auf den Saldo (auch 0 und ungewiss) öffnet die Abrechnung **nur dieser Person** (vorhandener Aufschlüsselungsbildschirm mit Filter). „Alle Gruppen“ zeigt Mitgliederzahl und öffnet denselben Gruppenbildschirm wie die Hauptgruppe.
3. **Senden und Auswählen**: Senden = Vorschau (genau diese Posten/Rechnungen) → Ziel (Chat der Gruppe vorbelegt, ändern möglich) → Knopf „10 Posten in Chat ‚X‘ senden“ → 10 s Rückgängig. Text „In {0} Chats“ korrigieren.
   Auswahl: X + „3 ausgewählt“, Aktionsleiste unten gleich hoch wie die Navigation, Auswahl auch in Posten, „Auswählen“ verschwindet aus dem Menü während der Auswahl, „Ausgleichen“ je Rechnung wandert aus der Hauptleiste ins Rechnungsmenü,
   Papierkorb rot und getrennt vom Senden. Chat öffnet nur den Chat dieser Gruppe (kein Zwischenfenster).
4. **Rechte der Person (Stellvertreter)**: im Profil drei Stufen (voll / nur vorschlagen / nichts) je Person, Standard **voll**, jederzeit im eigenen Profil änderbar (Konzept liegt vor, `KONZEPT-STELLVERTRETER.md`).
5. **Admin-Bereich**: Rechte-Matrix je Gruppe (Mitglieder einladen · entfernen · Rechnungen anlegen · Rechnungen/Posten ändern · Notizen und Einträge · Gruppe umbenennen/löschen; je Zeile „Alle | Nur Admins“), Schalter „Admin“ je Person (nur wenn „Alle sind Admin“ aus ist).
   Hinweis in der Oberfläche: gilt zwischen den Apps, ist keine technische Sperre.
6. **Zahlungsangaben**: eigene Angaben nur auf dem Gerät; „Meine Angaben schicken“ im Profil der anderen Person (Direktnachricht, Vorschau, Bestätigung); „Angaben anfragen“ schickt eine Bitte, die die Person mit einem Tipp beantwortet.
7. **Betragsverlauf der Person mit Freigabe**: Schalter im eigenen Profil „Mein Verlauf für Mitglieder sichtbar“ (Standard aus); gilt als Absprache; echtes Verbergen über Rechnungsstufe „Beteiligte“.
8. **Favoriten/Anpinnen** für Posten und Rechnungen (nur auf dem eigenen Gerät; steigen in der Liste nach oben, Stern am Eintrag).

Jedes Paket: Tutorial und Tipps (de/en), Bildschirmvergleich Browser, Test mit erfundenen Daten, Prüfliste (Klickziele ≥ 48 dp, kein Pulsieren, deaktiviert-mit-Grund statt weglassen).

## 4. Offene Entscheidungen (Standard in Klammern)
- Senden: Bestätigen + 10 s Rückgängig, oder nur Bestätigen? (beides)
- Betragsverlauf: Schalter als Absprache, oder echter Schlüssel je Person (aufwendig, nicht vor Paket 7)? (Absprache)
- Zahlungsangaben nur per Direktnachricht auf Anfrage, nicht im Gruppenprofil? (ja)
- Reihenfolge: wie vom Nutzer (Mitglieder/Profil zuerst) oder erst die kleinen Fehler aus Paket 3? (Mitglieder/Profil zuerst)
