# Zusammenarbeit: verschlüsselt, live, ohne Download (Recherche 03.11., nur lesend)

Auftrag (Nutzer 03.11.): Rechnungen und Notizen live gemeinsam bearbeiten, verschlüsselte Nachrichten, höchste
Industriestandards, Einladungen für App und für Web ohne Download, Konto und Daten wiederherstellbar.
Beschlüsse aus der Fragerunde: Nostr-Relays + CRDT, volle Flutter-Web-App, Schlüssel auf dem Gerät mit Wiederherstellung
und Import eines eigenen Nostr-Kontos, Gruppen-Link mit Ablauf und Bestätigung durch den Ersteller.
Regel: In fremde Relays wird nichts geschrieben, auch nicht zum Testen, ohne ausdrückliche Freigabe für genau diesen Test.

Vertrauensmarken: [Certain] aus Quelle gelesen, [Likely] Schluss aus Quellen, [Guessing] nicht geprüft.

## 1. Verschlüsselung und Transport

- **NIP-44 v2** ist der aktuelle Nostr-Standard für verschlüsselte Nutzdaten: secp256k1-ECDH, HKDF, Padding, ChaCha20,
  HMAC-SHA256, Base64 [Certain, nips/44.md]. Die Spezifikation nennt selbst die Grenzen: keine Metadaten-Verbergung,
  keine Forward Secrecy, keine Post-Compromise Security [Certain]. Die JS-Referenz wurde im Dezember 2023 von Cure53
  geprüft, die übrigen Umsetzungen nicht [Certain, paulmillr/nip44 README]. Es gibt eine Dart-Umsetzung (MIT,
  chebizarro/dart-nip44), ihr Reifegrad ist nicht geprüft [Guessing].
- **NIP-17 + NIP-59 (Gift Wrap)** verbergen Absender, Empfänger-Beziehung und echte Zeit vor den Relays: Nachricht (unsigniert,
  „Rumor“) → Seal (Kind 13) → Gift Wrap (Kind 1059, Einmalschlüssel, Zeit bis 2 Tage zurückgestreut) [Certain, nips/17.md].
  Sichtbar bleiben das `p`-Tag des Wraps und das Netzwerk-Muster; Relays dürfen Wraps nur an den Empfänger ausliefern
  (NIP-42 AUTH) [Certain]. NIP-17 sagt ausdrücklich: Nachrichten laufen über öffentliche Relays ohne Verlust an Privatsphäre [Certain].
- **MLS (RFC 9420)** ist der IETF-Standard für Gruppenschlüssel mit Forward Secrecy und Post-Compromise Security, für
  Gruppen von 2 bis tausenden [Certain]. Für Dart habe ich keine ausgereifte Bibliothek gefunden [Likely, nicht erschöpfend
  gesucht]; ein Weg wäre OpenMLS (Rust) über FFI [Guessing].

**Entscheidung (Vorschlag, Stufen):**
1. Stufe 1 (baubar): Gruppenschlüssel (256 Bit, zufällig) pro Gruppe, per NIP-17-Gift-Wrap an jedes Mitglied verteilt;
   Inhalte mit AEAD (XChaCha20-Poly1305 oder NIP-44-Format) verschlüsselt. Bei Entfernen eines Mitglieds: neuer Schlüssel an
   alle übrigen (Epoche). Grenze: innerhalb einer Epoche keine Forward Secrecy [Certain, folgt aus dem Aufbau].
2. Stufe 2: MLS über FFI, wenn Stufe 1 trägt. Erst nach Prüfung der Bibliothek, Lizenz und APK-Größe.

## 2. Live-Bearbeitung (Rechnung und Notizen)

- **CRDT** löst gleichzeitige Änderungen ohne Server: Automerge, Yjs, Loro [Certain]. Für Dart: `dart_crdt` (rein Dart, Yjs-nah,
  läuft auf VM, Flutter und Web, aber vor 1.0) und `y_crdt` (Port von Yjs, 0.0.1) [Certain, pub.dev]. Loro hat keine
  Dart-Anbindung (Rust, JS, Swift) [Certain, loro.dev]. Reifegrad und Lizenz von `dart_crdt` sind vor der Wahl zu prüfen [Guessing].
- **Geld bleibt außerhalb der CRDT-Arithmetik.** Das CRDT speichert nur Eingaben (Posten, Anteile je Person als Tausendstel,
  Zahler, Notiztext). Beträge je Person rechnet jedes Gerät mit dem gleichen ganzzahligen Rechenkern (`SplitMath`) neu aus:
  gleiche Eingaben, gleiches Ergebnis, kein Gerät „speichert“ ein fremdes Ergebnis. Die Rechenprüfung läuft nach jedem
  eingehenden Update.
- Konflikte: gleiche Zelle (Posten × Person) gleichzeitig geändert → letzte Änderung gewinnt, beide Seiten sehen das Ergebnis;
  Notizen als Text-CRDT (Zeichen werden verschmolzen).
- Verbreitung: Updates als verschlüsselte Nostr-Ereignisse an mindestens drei Relays; Mitglieder holen Verpasstes beim Start
  (Zustandsvektor-Abgleich) [Likely]. Relays verwerfen und begrenzen (Rate-Limits); darum Relay-Liste einstellbar und
  Option „eigener Relay“ [Likely].

## 3. Einladung ohne Download (Web)

- Der Teil einer URL nach `#` wird vom Browser nicht an den Server gesendet [Certain, URL-Standard]. Darum: Link
  `https://…/#/beitreten?gruppe=<id>&schluessel=<Gruppenschlüssel oder Einladungsschlüssel>`. Der Server (GitHub Pages) sieht den
  Schlüssel nie.
- Der Gruppen-Link hat Ablauf (einstellbar) und kann widerrufen werden. Neue Mitglieder erscheinen als Anfrage; der Ersteller
  bestätigt (dann erst bekommt die Person den Gruppenschlüssel per Gift Wrap).
- Web-Gast: Einmalschlüssel im Browser (IndexedDB), „Als App-Konto sichern“ führt zur Wiederherstellung unten.
- Flutter Web auf GitHub Pages ohne eigenen Server. Die Texterkennung (ONNX) bleibt zunächst in der App; Web bekommt Zuordnen,
  Notizen, Chat, Ergebnis [Likely, Web-ONNX nicht geprüft].
- App-Einladung: derselbe Link öffnet die App (Android App Links), sonst die Web-App.

## 4. Konto und Daten wiederherstellen

- **Schlüssel**: Nostr-Schlüsselpaar auf dem Gerät. **NIP-06**: 12 oder 24 Wörter (BIP-39) → BIP-32-Pfad m/44'/1237'/0'/0/0
  [Certain]. Dart-Paket `nip06` existiert (Reife nicht geprüft) [Certain/Guessing]. Eigenes Nostr-Konto kann importiert werden (nsec/NIP-49).
- **NIP-49 (ncryptsec)**: Schlüssel mit Passwort verschlüsselt exportieren (scrypt + XChaCha20-Poly1305) als Datei oder QR [Certain].
- **Gruppendaten** liegen verschlüsselt bei den Relays und bei den anderen Mitgliedern: neues Gerät + Schlüssel → Sync holt alles
  [Likely]. Nur lokale Rechnungen (nie geteilt) brauchen eine **verschlüsselte Sicherungsdatei** (Schlüssel per HKDF aus dem Seed,
  XChaCha20-Poly1305), die der Nutzer selbst ablegt (Teilen-Dialog). Keine Cloud von uns.
- Später, optional: **soziale Wiederherstellung** (Shamir-Teile bei vertrauten Mitgliedern) [Guessing, nicht geprüft].
- Verlust von Gerät und Wörtern bedeutet: Konto weg, Gruppen weiter bei den anderen. Das wird in der App klar gesagt.

## 5. Reihenfolge der Umsetzung

1. Datenmodell bereit machen: Anteile als Tausendstel (ist: `SplitMath`), Bill als Menge von Eingaben (CRDT-fähig).
2. Schlüssel, Wiederherstellung (Wörter, NIP-49), Sicherungsdatei: **ohne Netz**, vollständig testbar.
3. Kryptografie als eigenes Paket mit Testvektoren aus den NIPs (NIP-06, NIP-44), Gruppenschlüssel, Gift Wrap.
4. Relay-Client; getestet gegen einen lokalen Relay in der Sitzung (nostr-rs-relay oder strfry, Verfügbarkeit im Netz der Sitzung
   nicht geprüft) und gegen einen In-Memory-Relay in Tests. Öffentliche Relays nur mit Freigabe je Test.
5. CRDT-Anbindung Rechnung, dann Notizen, dann Chat.
6. Web-Build, Einladungs-Link, Bestätigung durch den Ersteller.
7. Dritte Prüfung der Kryptografie (Audit), bevor „sicher“ in der App steht.

## Quellen

nips/44.md, nips/17.md, nips/59.md, nips/06.md, nips/49.md (nostr-protocol/nips, gelesen über Spiegel: docs.rs/nips,
nips.4rs.nl); github.com/paulmillr/nip44 (Audit Cure53, 2023-12); RFC 9420 und RFC 9750 (rfc-editor.org); pub.dev/documentation/dart_crdt;
pub.dev/packages/y_crdt; loro.dev/docs; crdt.tech/implementations; pub.dev/documentation/nip06.
