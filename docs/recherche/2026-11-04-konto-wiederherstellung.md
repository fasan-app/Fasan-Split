# Recherche 04.11.: Konto anmelden und wiederherstellen ohne eigenen Server

Frage des Nutzers: Telefonnummer oder E-Mail zum Verifizieren und Wiederherstellen? Welche anderen Wege sind in der
Open-Source-Welt üblich? Nur lesend recherchiert; Blogquellen gelten als „nicht geprüft“, bis die offizielle Doku gelesen ist.

## Rahmen (Beschlüsse)

Familie: keine Konten, keine eigenen Server, keine Telemetrie, FOSS-Weg ohne Google-Dienste (Fasan/GRUNDSAETZE,
ENTSCHEIDUNGEN 08.10./01.11.). Ein eigener VPS ist geplant, aber erst nach gemeinsamer Prüfung. Heute: Konto = Schlüssel
aus 12 Wörtern, Gruppenliste verschlüsselt an sich selbst auf den Relays (Entscheidung 04.11.).

## Wege im Vergleich

| Weg | Was es braucht | Passt zu Fasan? | Quelle |
|---|---|---|---|
| Telefonnummer (SMS-Code) | Server, der SMS verschickt und Nummer ↔ Konto speichert; kostet je SMS; Nummer ist ein starkes Identitätsmerkmal | Nein (Server, Kosten, Datenschutz). Höchstens später auf dem eigenen VPS | Signal braucht dafür eigene Server + SVR |
| E-Mail-Code | Mailserver und Zuordnung E-Mail ↔ Konto | Nein ohne Server; ABER: Sicherung „an mich selbst schicken“ geht ohne Server (Teilen-Dialog → eigene Mail) | – |
| 12 Wörter (BIP-39) | nichts, nur aufschreiben | Ja (gebaut) | – |
| Passwort-verschlüsselter Schlüssel (NIP-49) | Passwort; Datei/QR | Ja, als Ergänzung: Sicherung/Schlüssel mit eigenem Passwort, statt Wörter | d-central.tech nostr-key-management; NIP-49 |
| Passkey mit PRF | Passkey (Google Passwortmanager, iCloud-Schlüsselbund, 1Password); daraus Schlüssel ableiten | Gut für Bequemlichkeit: Konto-Schlüssel verschlüsselt (Hülle), Hülle per PRF entsperrt. Android ab API 28 über Credential Manager, iOS ab 18 (Fehler bis 18.3), Emulator ohne PRF. Nicht direkt als Datenschlüssel nutzen (Rat des WebAuthn-Mitautors: Hüllen-Verschlüsselung mit HKDF). WhatsApp nutzt das für Chat-Sicherungen | pub.dev maktub_passkey; 1password.com/blog/encrypt-data-saved-passkeys; lilting.ch (PRF-Risiko); dev.to/corbado |
| Gerät koppeln per QR | zweites Gerät zeigt QR, erstes überträgt Schlüssel verschlüsselt | Ja, ohne Server (über Relay oder direkt); üblich bei Signal/WhatsApp-Mehrgerät | – |
| Soziale Wiederherstellung (Shamir) | Schlüssel in z. B. 3 Teile, 2 davon bei Freunden in der Gruppe | Ja, passt zu Gruppen-App; in Nostr nur als offener Vorschlag (PR #2137), nicht Standard | d-central.tech; fiatjaf.com |
| NIP-46 Remote Signer (Bunker) | eigene Signer-App/-Dienst | Später für Profis; Schlüssel bleibt außerhalb der App | d-central.tech nostr-key-security |
| Android Block Store | Google Play Services; E2E nur mit Sperrbildschirm, ab Android 9 | Nur als Zusatz in der Play-Fassung, nicht im FOSS-Weg | developer.android.com/identity/block-store |
| PIN + Server mit Rate-Limit (Signal SVR3) | Server mit sicheren Enclaves | Nein (Server); SVR3 ist offen, aber Betrieb aufwendig | usenix.org osdi24-connell; eprint.iacr.org/2024/887 |

## Vorschlag der Sitzung (Reihenfolge)

1. Gerät koppeln per QR (kein Abtippen, alle Plattformen, kein Server).
2. Sicherung mit eigenem Passwort (NIP-49-artig) und „an mich selbst schicken/speichern“ (E-Mail, Cloud-Ordner) –
   ersetzt das Bedürfnis „E-Mail-Wiederherstellung“ ohne Server.
3. Passkey-Anmeldung (PRF, Hüllen-Verschlüsselung) für Android ≥ 9 / iOS ≥ 18.4 / Browser mit PRF; 12 Wörter bleiben
   der Rückfall. Erst offizielle Doku (developer.android.com Credential Manager, Apple AuthenticationServices) lesen.
4. Soziale Wiederherstellung über Gruppenmitglieder (2 von 3), nach Entwurf mit dem Nutzer.
5. Telefon/E-Mail-Codes nur, wenn der eigene VPS steht und der Nutzer es will.

## Zu bedenken

- Wer den Schlüssel hat, ist das Konto: kein Zurücksetzen durch einen Anbieter, kein „Passwort vergessen“.
- Kompromittierter Schlüssel lässt sich in Nostr nicht widerrufen; Gruppen schützen sich über Entfernen + neuen
  Gruppenschlüssel (gebaut).
- Gleiche Identität auf zwei Geräten: gleiche Lamport-Uhr-Autor-Kennung; Abgleich funktioniert (LWW), gleichzeitige
  Änderungen derselben Zeile entscheidet die Uhr.
- Relays können Ereignisse löschen: Gruppenliste auf mehreren Relays, Sicherungsdatei bleibt wichtig.
- Datenschutz: Telefonnummern verknüpfen Personen über Apps hinweg; Fasan sammelt keine.
