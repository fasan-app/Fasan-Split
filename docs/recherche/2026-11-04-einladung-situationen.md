# Einladung: alle Situationen (04.11.)

Anlass: Angi landete nach dem Link in einer leeren App, danach fand sie im Browser kein Namensfeld, danach schickte der
Browser die Anfrage gar nicht ab (pointycastle-Poly1305 wirft im Browser „full width integer not supported“). Nutzer:
„Fehler wie bei der Einladung dürfen niemals auftreten … unter allen Bedingungen“. Jede Zeile unten ist ein Test oder
als „nicht geprüft“ markiert.

## Ursachen bisher (Belege)

| Fehler | Ursache | Behebung | Test |
|---|---|---|---|
| Leere App nach Klick | Code ging beim ersten Laden (coi-Neuladen) verloren | Code in sessionStorage bis zur Anfrage | Playwright joiner (lokal) |
| Kein Namensfeld gefunden | Name leer, Feld unauffällig | Name vorbefüllt (Konto, sonst „Das bin ich“) | joiner prüft „Angi“ |
| Anfrage nie gesendet (Web) | pointycastle Poly1305 nutzt 64-Bit-Ganzzahlen, die dart2js nicht hat | eigenes ChaCha20-Poly1305 (RFC 8439), gleiche Bytes | crypto_web_test (RFC-Werte + Vergleich) |
| Einladung nach App-Update weg | Einladungen nur im Speicher | gespeichert (Tresor) | invite_robust_test |
| Admin muss „Annehmen“ tippen | manuelles Freigeben als Standard | automatisch (Standard), manuell wählbar | invite_robust_test |

## Situationen

| # | Situation | Erwartung | Stand |
|---|---|---|---|
| 1 | Link im Browser (Chrome Android), erster Besuch | Name vorbefüllt, 1 Tipp, sofort in der Gruppe, Bon sichtbar | CI-Schranke `web.yml` Job e2e (Modus normal) |
| 2 | Einladende App ist zu / Handy aus | trotzdem sofort drin | gebaut (offener Link, Schritt 4b in group.dart); `invite_open_test`, e2e läuft immer mit Admin offline |
| 3 | Link in der Android-App (App Link) | öffnet Beitritt in der App | Gerät: nicht geprüft seit 0.1.52 |
| 4 | Link in WhatsApp-/Instagram-In-App-Browser | wie 1; Speicher kann flüchtig sein | nachgestellt: ohne Service Worker (e2e nosw); echte In-App-Browser nicht geprüft. Fehler in coi-serviceworker behoben |
| 5 | Privates Fenster / Speicher gesperrt | Beitritt klappt, Hinweis „Daten bleiben nicht“ | e2e nostorage: App startete vorher gar nicht; jetzt Speicher im Arbeitsspeicher, Code über die Adresse, Warnkarte |
| 6 | iPhone Safari | wie 1 | nicht geprüft (kein iPhone) |
| 7 | Link doppelt geöffnet / Anfrage zweimal | kein Fehler, einmal Mitglied | Wiederholungsanfrage: Test grün |
| 8 | Schon Mitglied | direkt in die Gruppe statt Fehler | Meldung „schon Mitglied“; Sprung in die Gruppe offen |
| 9 | Link abgelaufen (7 Tage) | klare Meldung, „neuen Link anfordern“ | Meldung da; Text prüfen |
| 10 | Link abgeschnitten (Messenger kürzt) | klare Meldung | „ungültig“ |
| 11 | Relay nicht erreichbar | anderes Relay; Hinweis erst nach Wartezeit | mehrere Relays; Test offen |
| 12 | Langsames Netz | Wartehinweis, kein Doppeltippen | Knopf gesperrt während Senden |
| 13 | Gleicher Name schon in der Gruppe | trotzdem richtig zugeordnet | person im Link verknüpft; Test grün |
| 14 | Mehrere Leute, ein Link oder mehrere Links | jede klappt | e2e: 3 Browser über einen Link; `invite_open_test`: 2 Links |
| 15 | Neuinstallation der eingeladenen Person | Konto-Sicherung oder erneuter Link | Wiederholungsanfrage grün |
| 16 | Eingeladene bearbeitet im Browser | Änderung kommt beim Admin an | Android↔Android grün; Browser offen |

## Sicherheit des offenen Links

- Wer den Link hat, kommt rein (wie Gruppenlinks in Messengern). Der Schlüssel steht nur im Teil nach „#“, der nie an
  einen Server geht. Manuell freigeben bleibt möglich (`create(auto: false)`: kein Schlüssel im Link).
- Geprüft (`invite_open_test`): ohne Ticket, mit Admin-Flag, für fremden Schlüssel, mit fremder Person → abgelehnt.
- Zurückziehen: Tickets gelöscht, neuer Gruppenschlüssel; wer den alten Link nutzt, sieht nichts Neues (Test).

## Nächste Schritte (alt, Stand vor dem Umbau)

1. Freigabe im Link (Situation 2): Verwalter legt beim Erstellen `i/<id>` = Hash eines Einmal-Tokens im Mitglieder-
   dokument ab; der Link trägt Gruppenschlüssel und Token im Fragment (geht nie an einen Server). Eingeladene trägt
   sich selbst als `m/<pub>` mit Token ein; alle Geräte prüfen den Hash. Sicherheit gleich wie automatische Freigabe:
   wer den Link hat, kommt rein (wie WhatsApp-Gruppenlinks). Widerruf: `i/<id>` löschen + neuer Schlüssel.
2. Browser-E2E als CI-Job (lokales Relay im Runner, kein fremder Dienst).
3. Situationen 4, 5, 8, 11, 14, 16 als Tests.
