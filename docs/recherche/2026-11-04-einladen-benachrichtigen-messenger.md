# Recherche 04.11. nachts: Einladen, Benachrichtigungen, Messenger- und Netzwerk-Funktionen

Anlass (Nutzer 04.11., nach Test auf dem S23): Einladen ist „eine Katastrophe“ – zwei Einladungen nötig, Beigetretene
stehen nicht als Person in der Gruppe, als Gast eingetragene Person ist nicht mit dem Konto verknüpft, „Verknüpft mit
Test“ in der App, im Browser fehlt „Test“, selbst angelegtes „test“ lässt sich nicht verknüpfen; keine Benachrichtigungen
(Einladung angenommen, Nachrichten, neue Bons); keine Ungelesen-Anzeige, keine letzte Nachricht in der Freundesliste.
Nur lesend recherchiert; Herstellerseiten und Blogs gelten als „nicht geprüft“, offizielle Doku ist markiert.

## Was andere machen

| Thema | Beobachtung | Quelle |
|---|---|---|
| Beitritt per Link ohne Konto | Tricount: „the only thing you need is the access link“, Freunde sehen, tragen ein, gleichen aus – ohne Anmeldung | tricount.com/en/do-i-need-a-login-or-account (Hersteller) |
| Beitritt per Link, Konto entsteht still | Olik Split: Beitritt legt ein anonymes Konto an | oliksplit.app/features/group-sharing (Hersteller, nicht geprüft) |
| Splitwise | Beitritt verlangt Konto (nur Blog, nicht geprüft) | robots.net |
| Gruppenlinks Messenger | Signal/WhatsApp: ein Gruppenlink; Freigabe durch Verwaltung ist ein Schalter je Gruppe, nicht je Link; Widerruf = „Link zurücksetzen“; Ablaufzeit je Link nicht belegt | support.signal.org 360051086971; macrumors 2023 |
| Benachrichtigungen Splitwise | „neue Ausgabe, die dich betrifft“, Änderung, Löschung, Kommentar, Gruppenänderung; Mail/Push wählbar | IFTTT-Trigger, docs.rs splitwise notifications (nicht geprüft) |
| Chatliste | Zeile: letzte Nachricht + Zeit, Ungelesen-Zahl als Plakette, ungelesene Zeilen hervorheben | CometChat, getstream.io, uxcel (Hersteller-Ratschläge) |

## Technik ohne Server (offizielle Doku)

- Android 13+: Benachrichtigungen brauchen `POST_NOTIFICATIONS`, neue Installationen starten mit „aus“; im Zusammenhang
  fragen (Knopf „Benachrichtigungen einschalten“), nicht beim Start (developer.android.com/develop/ui/views/notifications/notification-permission).
- Ohne Google-Push (FOSS-Weg, Grundsatz) kommt nichts, wenn die App ganz beendet ist. WorkManager-Abruf frühestens alle
  15 Minuten, vom System verzögert (developer.android.com/reference/androidx/work/PeriodicWorkRequest).
- Paket `flutter_local_notifications` 22.3.3, BSD-3, Android/iOS/Web; braucht Desugaring, compileSdk ≥ 35 (pub.dev).

## Entscheidung für Fasan Split (umgesetzt in dieser Reihenfolge)

1. **Ein Einladen.** Ein Knopf „Einladen“ in Gruppe und Freunde. Wählen: wie lange gültig (1 Tag, 7 Tage, 30 Tage). Ein
   Link. Wer öffnet: Konto entsteht still, ist sofort in der Gruppe (offener Link) und steht dort als Person mit seinem
   Namen; Gruppenmitglieder sind automatisch Freunde (wie Kontakte im Messenger). Freigabe von Hand nur noch als Schalter
   der Gruppe, nicht als zweite Art Link.
2. **Kein Verknüpfen von Hand im Normalfall.** Mitglied = Person mit seinem Namen. Steht ein gleicher Name schon in Bons,
   gehört er automatisch dazu. Nur bei abweichender Schreibweise: „Das ist …“ im Menü der Person.
3. **Schreiben an jedes Mitglied.** Aus der Freundesliste „Nachricht“: eine Zweier-Verbindung entsteht auf Zuruf
   (Gruppenschlüssel für zwei, per NIP-44 an den anderen), ohne zweiten Link.
4. **Ungelesen.** Freundesliste und Gruppen: letzte Nachricht mit Zeit, Ungelesen-Zahl, Zeile fett; Zahl am Reiter unten.
5. **Glocke „Neuigkeiten“.** Beigetreten, neuer Bon, Bon geändert, neue Nachricht, Einladung angenommen. Eine Stelle für
   Schalter (Einstellungen → Benachrichtigungen): Nachrichten, Beitritte, neue Bons und Änderungen.
6. **System-Benachrichtigungen** (flutter_local_notifications) während die App läuft oder im Hintergrund ist; ganz beendet:
   beim nächsten Öffnen in der Glocke. Ehrlich im Text sagen. Erlaubnis erst beim Einschalten fragen.

Weitere Messenger-/Netzwerk-Funktionen (Backlog): online/zuletzt online (abschaltbar), gelesen-Häkchen, schreibt gerade,
Profilbild/Status, Erwähnungen (@Bon), Antworten auf eine Nachricht, Reaktionen, anpinnen, stumm schalten, Privatnachricht
in der Gruppe.
