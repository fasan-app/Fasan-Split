# Gruppe über Nostr für Fasan Split (Flutter), kompatibel zu funk.js

Stand 2026-11-02. Eine Frage, ein Dokument. Messungen habe ich selbst am 2026-11-02 gemacht (Skripte in /tmp, nicht im Repo).
Ungeprüftes ist mit „nicht geprüft“ markiert.

## Kurzfassung

1. Die Web-App sendet flüchtige Ereignisse (Art 20777), Inhalt AES-256-GCM mit einem 32-Byte-Schlüssel aus dem Gruppen-Link (`#g=…`). Kein Schlüsselaustausch pro Person, keine Signaturen auf Inhaltsebene.
2. Flutter kann das 1:1 nachbauen (AES-GCM, SHA-256, deflate-raw, WebSocket). Alles in Dart mit MIT/BSD/Apache-Paketen. Das Dart-Paket `nostr` (2.0.0) ist LGPL-3.0 und fällt raus.
3. Relays: sicher bleiben unter ca. 48 KB je Ereignis. Gemessen: nos.lol lehnt ab 64 KB ab, obwohl NIP-11 131072 nennt. Fotos gehören nie in Relays.
4. Fotos: client-seitig verschlüsseln, als `application/octet-stream` zu Blossom. Gemessen: nur cdn.hzrd149.com und nostr.download nahmen verschlüsselte Blobs an. blossom.primal.net, blossom.nostr.build und blossom.band lehnen sie ab (prüfen den Inhalt). Aufbewahrung ist bei keinem Server zugesagt.
5. Sichtbarkeit je Rechnung: eigener Rechnungsschlüssel (32 Byte), per NIP-44 (Gift Wrap, NIP-59) an die gewählten Geräteschlüssel verteilt. „Für alle“ bleibt beim Gruppenschlüssel und bleibt für die Web-App lesbar.
6. Rechte: Änderungen werden mit dem Geräteschlüssel signiert (innen), Rollen stehen in einer vom Besitzer signierten Mitgliederliste. Ohne das kann jeder mit dem Link jede Rechnung als jede Person ändern (heute so in funk.js/app.js).
7. Daten: Feld-für-Feld „letzter Schreiber gewinnt“ mit Zeitstempel in Millisekunden wie `m` im Web, dazu Tombstones. Neue Felder nur in Nachrichten mit `v:2`: die Web-App ignoriert `v !== 1` und kann nichts beschädigen.
8. Offline: Ausgangswarteschlange in der lokalen Datenbank, Wiederholung mit Backoff; flüchtige Ereignisse reichen nicht, deshalb zusätzlich ein speicherbares Ereignis (Art 30777, adressierbar) – Relays hielten es im Test.
9. Rückbau nötig in funk.js: Gruppenschlüssel-Regel „älterer gewinnt“ ist angreifbar, `ko`-Felder gehen bei alten Clients verloren, Fotos sind heute bewusst nur lokal (Beschluss 2026-10-24) – das muss neu beschlossen werden.
10. Offen/nicht geprüft: Aufbewahrungsdauer der Relays und Blossom-Server, Verhalten von relay.snort.social bei gespeicherten Ereignissen (kein OK im Test), Zeitverhalten der reinen Dart-Kryptografie auf schwachen Geräten.

---

## 1. Ist-Zustand der Web-App (gelesen: funk.js ganz, app.js per grep)

Quellen: `/home/claude/fasan-karte/site/funk.js`, `/home/claude/fasan-karte/site/app.js` (Zeilen ca. 229–545, 574–615).

### Ereignisse und Relays
- Art `20777` (flüchtig nach NIP-01: 20000 ≤ n < 30000, „not expected to be stored by relays“). In der README-Kindtabelle der NIPs steht 20777 nicht (Stand 2026-11-02, grep).
- Tags: nur `['t', thema]`. `thema` = Hex der ersten 16 Byte von SHA-256(`"fasan-karte/1:"` ‖ roher 32-Byte-Schlüssel).
- Filter: `{kinds:[20777], '#t':[themen…], since: jetzt-120}`.
- Absender: pro `starte()` ein neuer Zufallsschlüssel (`generateSecretKey()`), damit Relays Sitzungen nicht verknüpfen.
- Relays: `wss://relay.snort.social`, `wss://nostr-pub.wellorder.net`, `wss://nos.lol`, `wss://relay.primal.net`. Bibliothek nostr-tools 2.25.2 (Unlicense), `SimplePool` mit `enableReconnect`.
- Getestet wurden 2 KB und 24 KB (Kommentar in funk.js, Relaistest 2026-10-24).

### Verschlüsselung
- AES-GCM 256 bit (WebCrypto). Der rohe 32-Byte-Schlüssel wird direkt importiert, **keine Schlüsselableitung (KDF)**, keine zusätzlichen authentifizierten Daten (AAD).
- IV 12 Byte zufällig je Nachricht.
- `content` = `base64url(iv)` + `"."` + `base64url(Chiffretext ‖ 16-Byte-Tag)` (WebCrypto hängt den Tag an). base64url ohne `=`.
- Klartext = `JSON.stringify(Nachricht)`.

### Einladung
- Link: `https://<origin><pfad>#g=<paket>`; der Teil hinter `#` geht nicht an den Server (Kommentar in app.js, RFC 3986 Abschn. 3.5). Regex beim Import: `^#g=([zj][A-Za-z0-9_-]+)$`.
- Paket = `'z' + base64url(deflate-raw(JSON))`, ersatzweise `'j' + base64url(JSON)`.
- JSON: `{v:1, l, u, tp, pn, k, n, ko, ep, gs, ek, eo}`. `k = [Schlüssel (base64url, 43 Zeichen), Erstellzeit in ms]`.
- QR-Code: derselbe Link (QR-Fehlerkorrektur „L“). Zu groß → Fallback `{v:1, l, k}` nur eigener Eintrag und Schlüssel (`nurIch`). Sonst Hinweis „Link per WhatsApp“.
- Schlüsselstreit: kleinere Erstellzeit gewinnt, bei Gleichstand der kleinere String. Alte Schlüssel (`altK`, bis 4) werden weiter mitgehört; wer auf einem alten Schlüssel Post bekommt, antwortet auf diesem.

### Nachrichtenarten (Klartext-JSON)
| `a` | Inhalt | Felder |
|---|---|---|
| `z` | ganzer Gruppenstand | `{v:1,a:'z',von:<Personen-ID>,d:<Paket wie im Link, mit Chat>}` |
| `o` | Standort | `{v:1,a:'o',id,n,lat,lon,acc,ts}` oder `{…,aus:1,ts}` zum Beenden; Annahme nur wenn `ts` in [jetzt−3 h, jetzt+5 min] |
| `w` | „Wo seid ihr?“ | `{v:1,a:'w',von,n,ts}`, nur gültig wenn `ts` jünger als 10 min |

Verhalten: Jedes offene Handy sendet den Stand bei Änderung (nach 1,5 s), alle 120 s und antwortet, wenn die Gegenseite etwas nicht hat (`ihnenFehlt`). Kein Senden bei geschlossener App.

### Rechnungen im Stand (`ko`, je Rechnung ein Array)
`[v, b, z, f, t, m, x, a, an, za, art, pos, tip]`
- `v` Zahler-ID, `b` Betrag in Cent (Ganzzahl), `z` Zweck, `f` Liste der Beteiligten-IDs, `t` Anlage, `m` letzte Änderung (ms), `x` gelöscht (Tombstone), `a` Ausgleich, `an`/`za` Cent-Maps (Anteile / Zahlungen), `art` ∈ gleich|betrag|anteile|posten, `pos` Posten `[Name, Cent, [IDs]]` (max. 80), `tip` `[‘%’|‘€’, Wert]`.
- Zusammenführen: pro Rechnungs-ID gewinnt die größere `m`; bei Gleichstand bleibt die lokale. Gleiches Muster bei Personen (`t`), Plänen, Einkauf.
- Personen: `l[id] = [name, t, Stimmen, …, Markierungen, ohne]`. Die eigene ID wird nie überschrieben („eigene Daten bleiben maßgeblich“).
- Personen-IDs sind 10 Zeichen Zufall, **keine** Nostr-Schlüssel. Es gibt keine Signatur: wer den Link hat, kann als jede Person schreiben.
- Rechnungsfoto: bleibt auf dem Handy (IndexedDB), Beschluss 2026-10-24 (ENTSCHEIDUNGEN.md, Zeile „Kosten 2“).

---

## 2. Relays: Ereignisgröße (NIP-11 und eigene Messung)

NIP-11: Abruf per HTTP mit `Accept: application/nostr+json`. `max_message_length` = größte eingehende JSON-Nachricht in Bytes, begrenzt auch Ereignisse; `max_content_length` zählt Zeichen im Feld `content`. Eine Aufbewahrungsangabe (Retention) kennt NIP-11 laut Text nicht. Quelle: https://github.com/nostr-protocol/nips/blob/master/11.md

Gemessen am 2026-11-02:

| Relay | Software | NIP-11 `max_message_length` | Messung (flüchtiges Ereignis 20777, Inhalt zufällig) |
|---|---|---|---|
| relay.primal.net | strfry 1.1.3 | 1.000.000 | 16/64/120/200 KB angenommen; 500 KB: „event too large: 512376“ |
| nos.lol | strfry 1.1.3 | 131.072 | 16 KB ok; **64 KB abgelehnt („event too large: 65912“)**, 120 KB abgelehnt |
| relay.snort.social | memlay 0.2.0 | 524.288 | kein OK in 8 s, auch nicht für gespeicherte Arten (siehe Abschn. 6) |
| nostr-pub.wellorder.net | nostr-rs-relay 0.9.0 | (kein Wert) | bis 200 KB ok; 500 KB: NOTICE „message too large (512386 > 262144)“ |

Folgerungen:
- **NIP-11 nicht blind vertrauen**: nos.lol nennt 131072, lässt aber bei 65912 Byte Ereignisgröße ab. Vermutlich 65536 Byte Grenze von strfry (nicht geprüft in der strfry-Doku).
- nostr-rs-relay: Standard `max_event_bytes` 128 KB, `max_ws_message_bytes` 128 KB laut config.toml (https://raw.githubusercontent.com/scsibug/nostr-rs-relay/master/config.toml). wellorder hat laut NOTICE 262144 – also vom Standard abweichend.
- **Faustregel für Fasan: Ereignis ≤ 48 KB gesamt** (Inhalt nach base64 ca. ≤ 40 KB). Größere Zustände aufteilen (je Rechnung ein Ereignis statt ganzer Stand).
- `max_event_tags`, `created_at`-Grenzen: bei diesen vier Relays nicht in NIP-11 gesetzt.

Relays sehen: Zeit, Größe, Absenderschlüssel, `t`-Tag, IP. Nie Inhalt (wie heute).

---

## 3. Blossom für verschlüsselte Fotos

### Protokoll (offizielle BUDs, https://github.com/hzrd149/blossom)
- BUD-02: `PUT /upload` mit Binärkörper; Server **darf den Blob nicht verändern** und rechnet SHA-256 über genau die empfangenen Bytes („so users can re-upload blobs to other servers“). Antwort 201 (neu) oder 200 (existiert) mit Blob-Descriptor `{url, sha256, size, type, uploaded}`. Statuscodes u. a. 401, 402, 403, 409, 411, 413, 415, 429. https://github.com/hzrd149/blossom/blob/master/buds/02.md
- BUD-06: `HEAD /upload` mit `X-SHA-256`, `X-Content-Length`, `X-Content-Type` als Vorabprüfung (optional). https://github.com/hzrd149/blossom/blob/master/buds/06.md
- BUD-11: Berechtigung = signiertes Ereignis **Art 24242**, `content` lesbarer Text, Pflicht-Tags `t` (`upload`/`get`/`delete`/`list`/`media`) und `expiration`; für Upload Pflicht-Tag `x` = SHA-256 des Blobs; optional `server` (Domain) zur Eingrenzung. Header: `Authorization: Nostr <base64url ohne Padding>`. https://github.com/hzrd149/blossom/blob/master/buds/11.md
- BUD-01: GET `/<sha256>` (optional Endung), CORS `Access-Control-Allow-Origin: *`; BUD-04 Spiegeln (`PUT /mirror`); BUD-12 Löschen/Auflisten. https://github.com/hzrd149/blossom/blob/master/buds/01.md
- Ob client-seitiges Verschlüsseln erlaubt ist: Protokollseitig ja, Server speichern unveränderte Bytes. Ein Drittprojekt formuliert es so: Dateibytes sind öffentlich, es sei denn die App verschlüsselt vor dem Upload (https://shroominic.github.io/nostrbase/content/storage.md). Das ist keine Blossom-Quelle, passt aber zu BUD-02.

### Messung an öffentlichen Servern (2026-11-02, Wegwerf-Schlüssel, Zufallsbytes, `application/octet-stream`)
| Server | Ergebnis |
|---|---|
| cdn.hzrd149.com | 2 KB und 6 MB: **201 Created**; GET-Antwort `cache-control: public, max-age=31536000, immutable` (das ist Caching, keine Aufbewahrungszusage) |
| nostr.download | 2 KB und 6 MB: **201 Created**; gleiches Cache-Verhalten |
| blossom.nostr.build / blossom.band | **415** „File type not allowed“. Mit Etikett `image/jpeg` auf Zufallsbytes: **400** „Content-Type does not match the file content“ → der Server prüft den Inhalt, verschlüsselte Blobs gehen nicht |
| blossom.primal.net | Mit base64url-Header: 400 „invalid base64 for auth event“. Mit **Standard-base64** (mit Padding): 415 „unsupported media type application/octet-stream“. Also: weicht von BUD-11 ab und prüft Typ |

- Free-Stufe nostr.build laut eigener Seite: 20 MiB je Datei, „no expiry“, aber nur Bilder/Audio/Video (https://blossom.nostr.build/). Gilt für unverschlüsselte Medien.
- **Aufbewahrung**: Die BUDs sagen nichts dazu. Kein Server der Messung nennt eine Frist → „nicht geprüft“, nicht zusagbar. Ich konnte meine Test-Blobs nicht löschen (Wegwerf-Schlüssel verworfen): 2 KB auf nostr.download und cdn.hzrd149.com, je 6 MB auf beiden. Nur Zufallsdaten.
- Die Liste ist eine Momentaufnahme. Server ändern Regeln. Die App darf keinen festen Server voraussetzen.

### Empfohlener Ablauf für ein Rechnungsfoto
1. Foto verkleinern und EXIF/GPS entfernen (Foto verlassen heißt: Metadaten weg). Zielgröße ca. 200–400 KB JPEG (Schätzung, nicht geprüft).
2. Eigener Zufallsschlüssel je Foto (32 Byte), AES-256-GCM, Blob = `iv(12) ‖ Chiffretext ‖ Tag(16)`.
3. `sha256` über den Blob. Upload an 2 Server (Liste in Einstellungen, Voreinstellung cdn.hzrd149.com und nostr.download; Reihenfolge nach `HEAD /upload` Vorabprüfung). Auth-Token mit **Wegwerf-Schlüssel**, `x`-Tag und `server`-Tag, `expiration` +5 min.
4. In die verschlüsselte Rechnung schreiben: `{h: sha256, k: Fotoschlüssel, u: [URLs], n: Größe}`. Wer die Rechnung lesen darf, kann das Foto laden – Sichtbarkeit folgt der Rechnung ohne Extra-Regel.
5. Immer lokale Kopie behalten. Fehlt der Blob später auf allen Servern, kann jedes Mitglied, das ihn lokal hat, ihn unter demselben Hash erneut hochladen (BUD-02) oder per BUD-04 spiegeln. Anzeige: „Foto nicht mehr online“.
6. Server sehen: IP, Größe, Zeit, Hash. Nicht: Inhalt, Gruppe. Das gehört in die Datenschutzzeile der App (wie bei Relays).

---

## 4. Verschlüsselung je Empfänger: NIP-44 v2 und NIP-59

### NIP-44 v2 (https://github.com/nostr-protocol/nips/blob/master/44.md)
- Gemeinsames Geheimnis: secp256k1-ECDH, **ungehashte** x-Koordinate. `conversation_key` = HKDF-Extract(SHA-256, IKM = shared_x, Salt = `"nip44-v2"`).
- Je Nachricht: 32-Byte-Zufall `nonce`; HKDF-Expand(PRK = conversation_key, info = nonce, L = 76) → `chacha_key` (32), `chacha_nonce` (12), `hmac_key` (32).
- Auffüllen (Padding) auf Stufen, mindestens 32 Byte; Längenpräfix 2 Byte (< 65536) oder 6 Byte. ChaCha20 (Zähler 0), HMAC-SHA256 über `nonce ‖ Chiffretext`.
- Nutzlast: base64 von `0x02 ‖ nonce ‖ Chiffretext ‖ MAC`. Klartext 1 Byte bis 2^32−1 (Implementierungen sollen eigene Grenzen setzen).
- Testvektoren: `nip44.vectors.json` im Repo https://github.com/paulmillr/nip44. Cure53-Audit Dez. 2023 nur für TypeScript/Go/Rust-Implementierungen; Dart-Fassungen sind laut README **nicht auditiert**.

### NIP-59 Gift Wrap (https://github.com/nostr-protocol/nips/blob/master/59.md)
- Rumor (unsigniertes Ereignis) → Seal Art 13 (Inhalt NIP-44 an den Empfänger, vom echten Autor signiert, Tags leer) → Gift Wrap Art 1059 (Inhalt NIP-44, signiert mit **einmaligem Zufallsschlüssel**, `p`-Tag = Empfänger). Zeitstempel der äußeren Schichten zufällig in die Vergangenheit.
- Mehrere Empfänger: je Empfänger ein eigener Wrap.
- Art 21059 = flüchtiger Wrap (Echtzeit). Relays *sollten* Art 1059 nur dem Empfänger nach NIP-42-AUTH ausliefern; die vier Relays nennen in NIP-11 weder NIP-42 noch NIP-59 (relay.damus.io nennt 59) → bei diesen Relays **keine Zusage**; die Sicherheit liegt in der Verschlüsselung.
- Preis: die `p`-Tags zeigen den Relays die Gerätekeys der Empfänger (Gruppengröße, Kontaktgraph). Gegenmittel: Für die Gruppe einen aus dem Gerätekey abgeleiteten Gruppen-Pseudonymschlüssel nutzen (z. B. HKDF(Gerätekey, Thema)), nicht den Hauptkey (Vorschlag, nicht geprüft).

### Schlüsselverteilung im Entwurf
- Jedes Gerät hat ein **dauerhaftes** secp256k1-Schlüsselpaar (Android Keystore bzw. `flutter_secure_storage`, BSD-3; Eignung für Fasan nicht geprüft). Der öffentliche Teil steht signiert im Mitgliedseintrag.
- Rechnungsschlüssel `BK` (32 Byte) zufällig. An jeden gewählten Empfänger: ein Wrap (Rumor = `{bill:id, bk, rev}`), einmal je Rechnung und Gerät, ca. 1 KB.
- Danach laufen Änderungen der Rechnung **symmetrisch** mit `BK` (AES-GCM wie heute, Thema = SHA-256(`"fasan-karte/1:"‖BK`)). Billig, kein Wrap pro Änderung.
- **Entzug**: neuer `BK'`, neu an alle Verbleibenden wrappen. Wer die alte Fassung schon hatte, behält sie. Das gehört in die Oberfläche („sieht ab jetzt nichts Neues“).
- Web-App kann das später mitmachen: das ausgelieferte nostr-tools-Bundle exportiert `nip44` und `nip59` (geprüft per `Object.keys`).

---

## 5. Dart-Pakete (pub.dev API, Stand 2026-11-02)

| Paket | Version (Datum) | Lizenz | Zweck / Anmerkung |
|---|---|---|---|
| `cryptography` | 2.9.0 (2025-11-21) | Apache-2.0 | AES-GCM (96-Bit-Nonce Standard), HKDF, HMAC, ChaCha20. Reines Dart; `cryptography_flutter` optional (nicht geprüft) |
| `bip340` | 0.3.1 (2025-08-30) | MIT | Schnorr-Signatur/Prüfung nach BIP-340 (fiatjaf). Zeitkonstanz nicht geprüft |
| `elliptic` | 0.4.0 (2026-07-31) | MIT | Kurvenarithmetik für ECDH (secp256k1). Zeitkonstanz nicht geprüft |
| `secp256k1` | 0.4.1 (2026-07-31) | MIT | alternative reine Dart-Fassung, gleiche Fragen |
| `pointycastle` | 4.0.0 (2025-02-19) | MIT | allgemeine Primitiven |
| `web_socket_channel` | 3.0.3 (2025-04-17) | BSD-3 | WebSocket, Android/iOS/Web |
| `crypto`, `convert`, `http` | aktuell | BSD-3 | SHA-256, Hex/Base64, HTTP für Blossom |
| `ndk` | 0.10.1 (2026-10-02), 0.11.0-dev.2 (2026-10-28) | MIT | Nostr-Kit mit Gift Wrap (NIP-59), Blossom-Dateien, Relay-Pool. Vor 1.0, Dev-Fassungen im Takt von Wochen; zieht u. a. `sembast`, `rxdart`, `native_toolchain_rust`/`hooks` (alle MIT/BSD/Apache). **Build-Hooks mit Rust** → CI-Auswirkung nicht geprüft |
| `dart_nostr` | 10.0.1 (2026-04-23) | MIT | Relay-Client; NIP-44-Umfang nicht geprüft |
| `nostr` (ethicnology) | 2.0.0 (2026-05-22) | **LGPL-3.0** | NIP-44 und Gift Wrap vorhanden – **aber LGPL: nach Projektregel (MPL-2.0, keine GPL-Bausteine) nicht verwenden** |
| `nostr_core_dart` | 1.0.1 (2023-05-13) | LGPL-3.0 | veraltet, LGPL: nein |

Quellen: `https://pub.dev/packages/<name>` bzw. `https://pub.dev/api/packages/<name>` und `/score` (Lizenz-Tags). Transitive Lizenzen von `ndk` geprüft: bip32_keys, bip39_mnemonic, xxh3, cbor, equatable, native_toolchain_rust = MIT; rxdart = Apache-2.0; sembast, hooks, ffi, web, http = BSD-3.

Empfehlung: **schmal bleiben** und NIP-44 selbst (ca. 100 Zeilen) auf `cryptography` + `elliptic`/`bip340` bauen, gegen `nip44.vectors.json` testen. Grund: kleine Angriffsfläche, kein Build-Haken, kein Rust-Hook für etwas, das wir an einer Stelle brauchen. Alternative: `ndk`, wenn die Rechtefunktionen wachsen; dann Version festnageln. Beides nicht gebaut, daher „nicht geprüft“, ob die Leistung auf einem schwachen Gerät reicht (reine Dart-BigInt-Kurvenrechnung).

Weitere Dart-Dinge:
- Raw-Deflate wie `CompressionStream('deflate-raw')`: `dart:io` `ZLibCodec(raw: true)` (https://api.dart.dev/dart-io/ZLibCodec-class.html: „raw: deflate generates raw data with no zlib header or trailer“). Gleichwertigkeit mit der Web-Ausgabe: Austauschtest nötig.
- AES-GCM: `cryptography` liefert Chiffretext und MAC getrennt. Für die Web-Kompatibilität `Chiffretext ‖ mac.bytes` zusammenfügen. Austauschtest nötig.

---

## 6. Messung: speicherbare Ereignisse (Offline-Zustellung)

Warum: Art 20777 ist flüchtig. strfry hält flüchtige Ereignisse zwar kurz vor (Kommentar in funk.js: 300 s), das ist aber keine Zusage. Ein Handy, das eine Stunde aus war, verpasst alles. Dafür taugt ein gespeichertes Ereignis.

Test 2026-11-02 (200 Byte Inhalt, Tags `d`, `t`, `expiration` +1 h, zweite Verbindung nach 1,5 s):
| Relay | Art 7777 (normal) | Art 30777 (adressierbar) | Abruf mit `#t` |
|---|---|---|---|
| relay.primal.net | ok | ok | beide geliefert |
| nos.lol | ok | ok | beide geliefert |
| nostr-pub.wellorder.net | ok | ok | beide geliefert |
| relay.snort.social | **kein OK (Timeout)** | **kein OK** | nichts |

- NIP-01: adressierbare Arten (30000–39999) behalten je (Art, Pubkey, `d`) nur das neueste; Gleichstand beim Zeitstempel: kleinste ID gewinnt (https://github.com/nostr-protocol/nips/blob/master/01.md). Das begrenzt den Speicher auf den Relays – **aber nur, wenn der Absender-Pubkey bleibt.** Mit dem heutigen Wegwerf-Schlüssel je Start würden Ereignisse sich häufen. Für Art 30777 deshalb den Gruppen-Pseudonymschlüssel aus Abschn. 4 nutzen.
- NIP-40 `expiration`: Relays *sollen* abgelaufene Ereignisse nicht ausliefern und *dürfen* sie löschen; es ist **kein Datenschutz** (Quelle: https://github.com/nostr-protocol/nips/blob/master/40.md). Nützlich als Aufräumhinweis (z. B. 90 Tage).
- Dauer der Aufbewahrung: bei keinem der Relays zugesagt, nicht geprüft. Deshalb ist der **lokale Stand maßgeblich**; Relays sind nur Transport. Das passt zum Modell von funk.js (jedes Handy trägt alles).
- Snort (memlay) lieferte auch für ephemere Arten kein Ergebnis wie schon im Relaistest 2026-10-24. Für Split: Snort nur als Zusatz, nie als einziges Relay. Eigener Relay auf dem VPS (Beschluss „später“, ENTSCHEIDUNGEN.md 2026-10-24) löst Aufbewahrung und Ereignisgröße.

---

## 7. Entwurf, kompatibel zu funk.js

### 7.1 Was in funk.js bzw. app.js zu ändern ist (für Karte; Split zieht später dort ein)
1. **Version trennen**: Neue Nachrichten tragen `v:2`; `funkEmpfang` ignoriert schon `v !== 1`. Alt und neu laufen auf demselben Kanal, ohne sich zu stören. Für `v:1` nichts ändern.
2. **`fuehreZusammen` verliert unbekannte Felder**: es baut Einträge aus festen Positionen neu (z. B. `ko` bis Index 12). Alte Clients schicken Fremdfelder nicht weiter. Neue Daten deshalb **nicht** in `ko` anhängen, sondern in `v:2`-Nachrichten und eigenen Schlüssel (`bx`).
3. **Gruppenschlüssel-Regel**: „älterer gewinnt“ lässt jeden mit Schlüssel (auch einen Ausgeschlossenen) einen älteren Schlüssel einspielen. Neu: Wechsel nur mit Besitzer-Signatur (siehe 7.4). Bis dahin als bekannte Schwäche in der Doku.
4. **Gerätekey**: pro Person ein dauerhaftes Schlüsselpaar; im Mitgliedseintrag `pk` (Index 6 in `l[id]`; alte Clients lesen nur bis Index 5 und würden `pk` beim Neupacken verlieren → `pk` zusätzlich in `v:2`-Nachricht `{a:'m'}` führen).
5. **Größe**: heute ein Ereignis mit dem ganzen Stand (Chat inklusive, bis 80 Nachrichten, bis 80 Posten je Rechnung). Das reißt ca. 48 KB schnell. Neu: je Rechnung ein Ereignis (`v:2`, `a:'b'`), `z` bleibt für Kompatibilität, aber `ko` aus `z` in Chunks, wenn zu groß.
6. **Beschluss „Foto nur auf dem Handy“ (2026-10-24)** ersetzen durch „Foto verschlüsselt auf Blossom, Sichtbarkeit wie Rechnung, lokale Kopie bleibt“. Das ist eine ENTSCHEIDUNGEN-Änderung und braucht Datumseintrag (nicht hier gemacht).
7. Text der Datenschutzzeile (app.js ca. Zeile 1730) um Blossom-Server (IP, Größe, Zeit) und Gerätekey erweitern.

### 7.2 Nachrichten und Arten
| Zweck | Art | Inhalt | Schlüssel |
|---|---|---|---|
| Live (unverändert) | 20777 | `v:1` `z`/`o`/`w` | Gruppenschlüssel `GK` |
| Live neu | 20777 | `v:2` `b` (Rechnungsänderung), `m` (Mitglied) | `GK` oder `BK` |
| Gespeichert | 30777, `d` = Rechnungs-ID-Hash | Schnappschuss einer Rechnung | `GK` oder `BK` |
| Schlüsselübergabe `BK` | 1059 (NIP-59) | Rumor `{bill, bk, rev}` | NIP-44 an Gerätekey |
| Foto | Blossom | `iv ‖ ct ‖ tag` | Fotoschlüssel in der Rechnung |

Art 30777 und 20777 sind eigene, nicht in der NIP-Tabelle stehende Nummern (grep README, Stand 2026-11-02): Kollisionsrisiko mit anderen Apps nicht ausgeschlossen. Alternative: Ranges bei NIPs-Repo nachfragen (nicht gemacht).

### 7.3 Datenmodell einer Rechnung (v:2)
- `Bill {id, vis, created}` und **Felder als LWW-Register** `{wert, ts, von}`: `payer`, `amount`, `purpose`, `mode`, `tip`, `participants`, `photo`, `deleted`.
- `ts` in **Millisekunden** und monoton (`max(jetzt, zuletzt_gesehen+1)`), genauso wie `m` im Web. Gewinner: größtes `ts`, dann kleinste Gerätekey-ID als Gleichstandsregel (deterministisch, wie NIP-01 es für gleiche Zeit tut).
- `items`: Map `itemId → {name, cents, assignees}`; jeder Posten mit eigenen Registern; ein Posten löschen = Tombstone-Register. `assignees` als Menge mit Hinzufügen/Entfernen je Person (jede mit eigenem `ts`), damit zwei gleichzeitige Zuordnungen verschiedener Personen beide bleiben.
- `participants`: gleiche Mengen-Logik.
- Wiederaufleben: ein `deleted`-Register mit größerem `ts` gewinnt; neuere Änderungen *nach* dem Löschen heben es nicht auf, außer sie setzen `deleted:false` ausdrücklich.
- **Summenregel** („Summen müssen genau stimmen“, Beschluss Kosten 2): nach dem Zusammenführen kann sie verletzt sein (A ändert Betrag, B ändert Zuordnung). Die App rechnet nie stillschweigend um, sondern markiert „Unstimmig“ und führt zur Korrektur. Zwei Zahlen (Bon-Summe, Summe der Posten) sichtbar.
- Rückwärts: `v:1`-`ko` wird für „Für alle“ weiter geschrieben (Zahler, Betrag, Zweck, Beteiligte, `m`) und von Karte gelesen. Eingehendes `ko` ersetzt eine Split-Rechnung nur, wenn `m` größer als deren höchstes Feld-`ts` ist.

### 7.4 Rechte und Signaturen
- **Signierte Änderungen**: jede `v:2`-Änderung trägt `{pk, sig}` mit einer BIP-340-Signatur über die kanonische JSON-Form (Felder sortiert). Wer sie empfängt, prüft gegen `pk` und gegen die Mitgliederliste.
- **Mitgliederliste** `roster = [{id, name, pk, rolle}]`, vom **Besitzer** (Ersteller der Gruppe, `pk_owner` steht im Einladungslink) signiert, Version hochzählend. Rollen:
  - Besitzer: Mitglieder aufnehmen/entfernen, Gruppenschlüssel wechseln, jede Rechnung löschen.
  - Mitglied: eigene Rechnungen ändern/löschen; fremde nur Felder `assignees` für sich selbst (Zahlung bestätigen, Posten wählen).
  - Gast ohne App (`ohne` im Web): kein Schlüssel; Einträge von Mitgliedern „für“ ihn.
- Ersteinladung ist **TOFU** (erster Kontakt vertraut): der Link trägt `GK` und `pk_owner`. Beim Betreten zeigt die App einen Prüfcode (Kurzhash des `pk_owner`), der mündlich oder per QR abgleichbar ist (Vorschlag, noch nicht gebaut).
- Zeitgrenze für `ts`: Ereignisse mit `ts` > jetzt+5 min verwerfen (wie bei `o` in funk.js), gegen „für immer gewinnen“.
- Bekannt: `v:1`-Clients (Web) können weiterhin unsigniert in „Für alle“-Rechnungen schreiben. Das ist heutiger Stand und Preis der Kompatibilität; Rechte gelten voll erst, wenn alle Mitglieder `v:2` sprechen.

### 7.5 Sichtbarkeit je Rechnung
- `vis = alle`: Verschlüsselung mit `GK` (wie heute), Web-App sieht sie.
- `vis = auswahl`: `BK` zufällig, Wrap an die Gewählten (Abschn. 4). Das Mitglied-Verzeichnis (`l`) enthält die Rechnung nicht; `ko` wird **nicht** geschrieben (sonst Leck im `v:1`-Stand). Web-Clients zeigen sie nicht.
- Zahler und Ersteller sind immer in der Auswahl. Wer fehlt, sieht weder Betrag noch Zweck noch Foto.
- Entzug = neuer `BK'` (Abschn. 4). Beitritt nachträglich = Wrap der aktuellen Fassung.

### 7.6 Offline und Zustellung
- Alle Änderungen zuerst lokal in die Datenbank, dann in die **Ausgangswarteschlange** `(ereignis, relays_offen)`.
- Senden an alle konfigurierten Relays; „zugestellt“ = mindestens 2 Relays haben `OK true` (oder `duplicate:`) geliefert. Sonst Wiederholung mit Backoff (30 s, 2 min, 10 min, …). `rate-limited:` und `blocked:` getrennt behandeln (NIP-01-Präfixe).
- Beim Start und bei Wiederverbindung: Abfrage `{kinds:[30777], '#t':[Themen], since: letzter_Abgleich-10 min}` und `20777` wie heute; danach Gossip (Antwort bei Fehlendem) wie `ihnenFehlt`.
- Konflikte mit dem Hintergrundprozess: Android beendet Dienste; kein Senden bei geschlossener App ist bereits Beschluss (ENTSCHEIDUNGEN 2026-10-24). Bei Split ebenso, Wiederholung beim nächsten Öffnen.

### 7.7 Reihenfolge der Umsetzung (klein anfangen)
1. Dart-Gegenstück zu `funk.js` v:1: Schlüssel, Thema, AES-GCM, base64url, Paket `z/j`, Link- und QR-Import, nur Rechnungen (`ko`). Test: Austauschvektoren aus `Funk._intern.zu/auf` (Web) gegen Dart und zurück.
2. Gerätekey, `v:2` Rechnung mit Feld-LWW, Signatur, lokale Warteschlange.
3. Art 30777 Schnappschüsse.
4. Foto auf Blossom (2 Server, verschlüsselt).
5. `vis = auswahl` mit NIP-44 / NIP-59; Testvektoren von paulmillr.
6. Web-App nachziehen (v:2, `pk`, Wrap-Empfang) – oder bewusst nicht.

---

## 8. Offene Punkte / nicht geprüft

- Aufbewahrungszeit auf Relays und Blossom-Servern (keine Zusage gefunden).
- Warum relay.snort.social (memlay 0.2.0) keine OK-Antwort für gespeicherte Arten gab (Konfiguration? Schlüsselfilter?).
- `strfry`-Grenze 65536 Byte als Ursache bei nos.lol (nur gemessen, nicht in der strfry-Doku gelesen).
- Leistung und Zeitkonstanz der Dart-Kurvenrechnung (`bip340`, `elliptic`) auf schwachen Geräten.
- Rust-Hooks von `ndk` in der GitHub-Actions-Kette (CLAUDE.md: gebaut wird nur in CI).
- Kind-Nummern 20777/30777: keine Kollision in der README-Tabelle gefunden, Praxis offen.
- Rechtliches/Datenschutz: Gerätekey als dauerhafte Kennung; Rechnungsfotos können Namen und Kartenteile zeigen (Teil-Maskierung nicht untersucht).
- Cross-Test AES-GCM Dart gegen WebCrypto (Tag-Anordnung): erwartet kompatibel, nicht geprüft.

## Quellen

- NIP-01: https://github.com/nostr-protocol/nips/blob/master/01.md
- NIP-11: https://github.com/nostr-protocol/nips/blob/master/11.md
- NIP-40: https://github.com/nostr-protocol/nips/blob/master/40.md
- NIP-44: https://github.com/nostr-protocol/nips/blob/master/44.md ; Testvektoren/Audit: https://github.com/paulmillr/nip44
- NIP-59: https://github.com/nostr-protocol/nips/blob/master/59.md
- Blossom: https://github.com/hzrd149/blossom (BUD-01, 02, 06, 11 unter `buds/`)
- nostr-rs-relay config: https://raw.githubusercontent.com/scsibug/nostr-rs-relay/master/config.toml
- NIP-11-Dokumente der Relays (HTTP, `Accept: application/nostr+json`): https://relay.primal.net, https://nos.lol, https://relay.snort.social, https://nostr-pub.wellorder.net
- nostr.build Blossom: https://blossom.nostr.build/
- pub.dev: https://pub.dev/packages/cryptography , /bip340 , /elliptic , /secp256k1 , /pointycastle , /web_socket_channel , /ndk , /dart_nostr , /nostr , /nostr_core_dart , /flutter_secure_storage
- Dart ZLibCodec: https://api.dart.dev/dart-io/ZLibCodec-class.html ; cryptography AesGcm: https://pub.dev/documentation/cryptography/latest/cryptography/AesGcm-class.html
- Lokal: `/home/claude/fasan-karte/site/funk.js`, `/home/claude/fasan-karte/site/app.js`, `/home/claude/fasan-karte/docs/ENTSCHEIDUNGEN.md`
