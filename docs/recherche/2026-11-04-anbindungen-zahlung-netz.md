# Recherche 04.11. nachts: Anbindungen (Zahlung, Fediverse, Tor/I2P) und weitere Messenger-Funktionen

Frage des Nutzers: Welche Dienste lassen sich datenschutzfreundlich und auf offiziellen Wegen anbinden (PayPal, Krypto,
Fediverse, Tor, I2P)? Welche Messenger-/Netzwerk-Funktionen fehlen noch? Nur lesend recherchiert; „nicht geprüft“ heißt:
keine offizielle Quelle gelesen. Keine Rechtsberatung – rechtliche Punkte unten sind Einschätzung, vor Veröffentlichung
mit einer Fachperson prüfen.

## Grundsatz für alle Anbindungen

Fasan Split bewegt kein Geld und schickt niemandem Daten. Eine Anbindung ist nur ein Knopf, der auf Tipp die App oder
Seite des Dienstes mit vorausgefülltem Betrag öffnet (Link, QR). Kein Konto bei uns, kein API-Schlüssel, keine Daten an
den Dienst, bevor der Nutzer selbst dort bestätigt. Damit bleiben wir außerhalb von Zahlungsdienste-Regeln (wir führen
keine Zahlung aus) – Einschätzung, nicht geprüft.

## Zahlung

| Weg | Wie | Offizielle Grundlage | Datenschutz | Empfehlung |
|---|---|---|---|---|
| SEPA-Überweisung per QR (GiroCode/EPC-QR) | QR mit IBAN, Name, Betrag, Zweck; jede Banking-App liest ihn | European Payments Council, EPC069-12 v3.x (Format BCD/001-002/SCT, Fehlerkorrektur M) | bestens: nichts verlässt das Gerät, keine Drittfirma | **zuerst bauen** (DE, AT, BE, FI, NL) |
| PayPal.Me | Link `paypal.me/<name>/<betrag><WÄHRUNG>` öffnet PayPal | PayPal-Hilfe „What is PayPal.Me?“ (Name nur A–Z/0–9, max. 20; Betrag + ISO-Code) | Link nur auf Tipp; PayPal sieht die Zahlung, nicht unsere Daten | **bauen** (Nutzer trägt seinen PayPal.Me-Namen im Profil ein) |
| Wero (EPI) | bisher nur Händler-API über Banken (ABN AMRO Early Access, Produktion ab Okt. 2026) | developer.abnamro.com | – | später, wenn es Links für Privatleute gibt |
| Bitcoin / Lightning | `bitcoin:<adresse>?amount=…&lightning=<bolt11>` öffnet die Wallet | BIP 21 / BIP 321 (Primärtext noch lesen, nicht geprüft) | gut, nur Wallet-App | als Option (Adresse/Lightning-Adresse im Profil) |
| Monero | `monero:<adresse>?tx_amount=…&recipient_name=…` | monero-project `docs/URI_SCHEME.md` (über Spiegel gelesen) | sehr gut | als Option |
| Revolut, Wise u. a. | eigene Zahlungslinks | nicht recherchiert | – | später |

Zum Ausgleichen: Bei „Du gibst Angi 12,30 €“ ein Knopf „Bezahlen“ mit den Wegen, die Angi in ihrem Profil freigegeben hat
(IBAN → QR, PayPal.Me, Wallet). Die Angaben liegen verschlüsselt im Profil-Dokument der Gruppe, nur Gruppenmitglieder
sehen sie. Nach dem Bezahlen „als bezahlt markieren“ (Bon ausgleichen) bleibt beim Nutzer.

## Fediverse

- Teilen in Mastodon & Co.: Das Teilen-Menü des Systems erreicht jede installierte Fediverse-App schon heute (kein Code
  nötig). Eine Web-Adresse `https://<instanz>/share?text=…` nutzen viele (Mastodon, Misskey), ist aber nur in
  Drittquellen beschrieben (palant.info, Share₂Fedi) – nicht offiziell geprüft.
- Gruppen über ActivityPub: würde einen Server pro Gruppe brauchen und öffentliche Profile – passt nicht zu „keine
  Server, Ende-zu-Ende verschlüsselt“. Nicht empfohlen. Nostr bleibt die Grundlage.

## Tor und I2P

- Tor über Orbot (Guardian Project): Orbot bietet SOCKS 127.0.0.1:9050 und HTTP-Proxy 127.0.0.1:8118 sowie einen
  VPN-Modus für ausgewählte Apps (Privacy Guides; ältere Orbot-Quellen, aktuelle Orbot-Doku noch lesen). Ohne Code: Nutzer
  nimmt Fasan Split in Orbots VPN-Modus auf. Mit Code: Schalter „Über Tor verbinden“ – die WebSockets laufen dann über
  Orbots HTTP-Proxy (dart:io `WebSocket.connect(customClient: HttpClient()..findProxy=…)`, api.dart.dev noch lesen).
  Zusätzlich .onion-Relays (z. B. relay.nostr.net laut d-central-Liste, nicht geprüft). **Empfehlung: als Option bauen.**
- I2P: SAM-Schnittstelle (geti2p.net/en/docs/api/sam), aber kein Nostr-über-I2P-Weg und keine fertige Android-Bibliothek
  gefunden. **Nicht jetzt.**

## Weitere Messenger- und Netzwerk-Funktionen (Backlog)

Gebaut: Chat zu zweit und in Gruppen, ungelesen, letzte Nachricht, online/zuletzt online, gelesen, Bons im Chat,
Notizen mit @, Neuigkeiten, Benachrichtigungen, Konto löschen.

Fehlt, nach Nutzen sortiert:
1. Bezahlen-Knopf beim Ausgleichen (siehe oben).
2. Antworten auf eine Nachricht (Zitat), Reaktionen (👍 ❤️ 😂), eigene Nachricht bearbeiten/löschen.
3. @Erwähnung auch im Chat (wie in Notizen).
4. Umfrage in der Gruppe („Wer kommt mit?“, „Wer zahlt die Getränke?“).
5. „schreibt gerade“ als flüchtiges Nostr-Ereignis (NIP-01: Kinds 20000–29999 werden nicht gespeichert; prüfen).
6. Profilbild und Status, Gruppenbild (klein, verschlüsselt im Profil-Dokument).
7. Chat stumm schalten, anpinnen, Suche im Chat.
8. Blockieren (Nachrichten einer Person ausblenden, keine Zweier-Verbindung mehr).
9. Freund in echt hinzufügen: QR-Code im Profil scannen.
10. Fotos im Chat (Größe! verschlüsselt, klein gerechnet).

## Quellen

- PayPal: paypal.com/us/cshelp/article/what-is-paypalme-help432
- EPC QR: europeanpaymentscouncil.eu (EPC069-12 v3.0 PDF; v3.1 gelistet)
- Wero: developer.abnamro.com/api-products/wero-merchant-payment/overview
- Bitcoin/Lightning: github.com/lnurl/luds/issues/177; spark.money Vergleich (Sekundärquelle)
- Monero: librejo.monerodevs.org/monero-project/monero/wiki/URI-Formatting
- Orbot: privacyguides.org-Spiegel; Orbot-Strings (alt)
- I2P: geti2p.net/en/docs/api/sam
- Fediverse-Teilen: palant.info/2023/10/19/implementing-a-share-on-mastodon-button-for-a-blog/
- Nostr über Tor: d-central.tech/nostr-relay-directory/

## Nachtrag 04.11. spät: Primärquellen gelesen (raw.githubusercontent.com)

- BIP 21: `bitcoin:` groß/klein egal, `amount` in dezimalen BTC mit Punkt, `label`, `message`. BIP 321 (ersetzt BIP 21):
  Abfrageschlüssel groß/klein egal, `lightning` (BOLT 11), `lno` (BOLT 12), Adresse darf leer sein; eine On-Chain-Adresse
  in einer URI ist eine Einmal-Anweisung, keine dauerhafte Kontaktangabe → im Profil besser eigene Adresse/Lightning-Angebot.
- Monero `docs/URI_SCHEME.md`: `monero:<adresse>`, `tx_amount`, `recipient_name`, `tx_description`; `tx_payment_id` veraltet.
- Orbot (guardianproject/orbot-android): `HTTP_PROXY_PORT_DEFAULT = "8118"`, `SOCKS_PROXY_PORT_DEFAULT = "9050"`,
  Tor-Konfiguration `HTTPTunnelPort` (CONNECT-Tunnel) – passt zum Tor-Schalter.
- Passkey PRF: weiterhin keine developer.android.com-Seite; nur das experimentelle Paket maktub_passkey (pub.dev).
- (Stand des Nachtrags davor; siehe nächsten Nachtrag für das, was inzwischen lesbar ist.)

## Nachtrag 04.11. spät, 2: Netz-Freigabe wirkt, weitere Quellen gelesen

- **Dart `HttpClient.findProxy`** (api.dart.dev, gelesen): Ohne gesetzte Funktion immer direkte Verbindung. Die Funktion liefert
  eine Zeichenkette im PAC-Format: `"DIRECT"` oder `"PROXY host:port"`, mehrere durch Semikolon (`"PROXY a:1; PROXY b:2; DIRECT"`).
  Es gibt `HttpClient.findProxyFromEnvironment`. Passt zu `ws_connect_io.dart` (`'PROXY $proxy'`). Ohne `DIRECT` am Ende
  keine Rückfallverbindung: gewollt beim Tor-Schalter (nichts läuft an Tor vorbei). [geprüft]
- **Mastodon-Teilen-URL** (Quelltext github.com/mastodon/mastodon, main): Route `resource :share, only: [:show]`
  (`config/routes.rb`), Aufruf nur eingeloggt (`before_action :authenticate_user!`, `shares_controller.rb`). Der Text kommt aus
  `[params[:title], params[:text], params[:url]].compact.join(' ')` (`app/helpers/application_helper.rb`). Also
  `https://<instanz>/share?text=…` auf der eigenen Instanz des Nutzers; Fasan kennt die Instanz nicht → Teilen-Menü des Systems
  bleibt der Weg ohne Instanzfrage. docs.joinmastodon.org-Seite dazu nicht gefunden (Methoden-Index ohne Share). [geprüft: Quelltext]
- **GitHub Release-Datei** (docs.github.com, „Get a release asset“): Antwortbeispiel enthält `"digest": "sha256:…"`, außerdem
  `size`, `content_type`, `browser_download_url`, `download_count`. Download: `browser_download_url` oder Header
  `Accept: application/octet-stream`, die API leitet um (200 oder 302 behandeln). [geprüft]
- **EZB-Abruf im Browser:** `eurofxref-daily.xml` antwortet 200, auch mit Header `Origin: https://example.org`, aber **ohne**
  `Access-Control-Allow-Origin`. Ein Browser darf die Antwort von einer anderen Herkunft also nicht lesen → die Web-App kann den
  Kurs nicht direkt holen (Handbetrieb bleibt). Gemessen aus der Sitzung mit curl; Verhalten im echten Browser nicht gesehen. Der Hinweis
  „im Browser CORS offen“ in `NACHPRUEFEN.md` Zeile 9 war falsch bzw. ungeprüft.
- **EPC-QR** (Wikipedia „EPC QR code“, Zweitquelle; europeanpaymentscouncil.eu liegt hinter einer Cloudflare-Prüfung, nicht umgangen):
  Beispiel `BCD / 001 / 1 / SCT / BIC / Name / IBAN / EUR1 / CHAR / (Referenz oder Text) / Info`. Feldfolge, UTF-8 (`1`), `SCT`,
  `EUR` + Betrag mit Punkt und „Referenz **oder** Text“ stimmen mit `epcPayload` überein. Der Code nutzt Version `002` (BIC optional);
  die Wikipedia-Seite nennt nur `001` mit BIC. Ob `002` und leeres BIC-Feld von Banking-Apps gelesen werden, ist **nicht geprüft** →
  Messprobe mit Banking-App (S23); `NACHPRUEFEN.md` Zeile 1 bleibt offen.
- **Weiter offen:** nostr.watch (Seite lädt nur per JavaScript, kein Text im Abruf), docs.joinmastodon.org (siehe oben),
  Passkey-PRF (keine offizielle Seite).

