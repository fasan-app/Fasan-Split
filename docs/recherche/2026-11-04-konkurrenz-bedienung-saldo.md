# Recherche 04.11.: Konkurrenz, Bedienung, Saldo, Kategorien, Währung, Web-Technik

Nur lesend recherchiert (Websuche). Viele Quellen sind Vergleichsblogs von Anbietern: Angaben dort gelten als
„nicht geprüft“, bis sie in der App oder der offiziellen Doku bestätigt sind. Nicht recherchiert (offen): Splidu, Splidit,
Splital, Wexpense, Cashinator, Splitser, „Split by Finanzguru“ im Einzelnen; App-Store-Neuheiten iOS.

## 1. Konkurrenz (Stand der Quellen 2025/2026)

| App | Stärken | Schwächen / Probleme | Quelle |
|---|---|---|---|
| Splitwise | ausgereifte Web-App, „who should pay next“, Zahlungsintegrationen | Gratis nur ~3–4 Ausgaben/Tag, Werbung mit Wartezeit, Belegscan nur Pro (~40 $/Jahr), Sync-Probleme, Konto löschen schwer; viele 1-Stern-Bewertungen | dolio.org/compare/splitwise-alternatives; kimola.com Splitwise-Berichte; Trustpilot; App Store |
| Tricount (bunq) | gratis ohne Limit, Splitwise-Import, bunq-Karte bucht automatisch | Export laut einer Quelle entfernt (umstritten); an Bank gebunden | tripprof.com; sharli.app |
| Settle Up | flexibelste Aufteilung (Prozent, fest, Posten), erinnert an offene Schulden | Werbung, Wiederkehrendes/Export nur Premium | squadtrip.com; hipposplit.com |
| Splid | ohne Konto, ganz offline, „einfachster Ausgleich“, Einmalkauf | keine Web-App, nichts Wiederkehrendes | dolio.org; Play-Store-Text |
| Spliit (MIT, Web) | ohne Registrierung, selbst hostbar | Pflege laut einem Nutzer unsicher | alternativeto.net |
| IHateMoney, Cospend (Nextcloud), Abrechnung, Kittysplit | Open Source, selbst hostbar | Server nötig, Konto (Kittysplit) | alternativeto.net, Foren |

Gemeinsame Muster: Saldo je Person, „vereinfachter Ausgleich“ mit wenigen Überweisungen (wie `model/settle.dart`),
Zahlung außerhalb der App, nur als „bezahlt“ markiert. Splitwise zeigt „wer als Nächstes zahlen sollte“.

Was Fasan Split anders/besser macht (Ziel, teils gebaut): Belegscan mit Posten-Zuordnung ohne Abo und ohne Server (auf dem
Gerät, auch im Browser), Ende-zu-Ende-verschlüsselte Gruppen über Nostr-Relays ohne eigenes Konto beim Anbieter, gleiche
App auf Android und im Browser (iOS über die Web-App), keine Werbung, keine Limits, MPL-2.0.

Probleme der Anbieter, die wir vermeiden müssen: Limits/Paywall auf Grundfunktionen, Sync-Fehler, Lock-in ohne Export
(→ Sicherung und CSV sind da; Import aus Splitwise/Tricount-CSV in die Roadmap), Werbung.

## 2. Bedienung: Auswahl, Ziehen, Sortieren

- Android-Konvention „gedrückt halten zum Anheben“, Ziehen ohne Loslassen (Compose `detectDragGesturesAfterLongPress`).
- Mehrere markierte Einträge werden als Gruppe gezogen und hintereinander abgelegt (PatternFly). Beim Ziehen Platzhalter
  („Geist“), andere Einträge rücken zur Seite (SAP Fiori).
- Umsetzung bei uns: Langdruck hebt sofort an (und markiert), Ablegen auf Gruppe, auf einen Bon (davor einsortieren), auf
  die Reiter unten (Archiv, Papierkorb, Gruppen → Gruppe wählen oder neu). Kein Verschieben des Inhalts beim Wechsel in den
  Auswahlmodus (Aktionsleiste über der Kopfzeile, gleiche Höhe).
- Quellen: christophybarth.github.io/modifier-node-cookbook (drag-to-reorder), pf3.patternfly.org drag-and-drop,
  sap.com fiori drag-and-drop reorder, api.flutter.dev ReorderableListView. Material-3-Originaltext nicht gefunden.

## 3. Saldo „auf einen Blick“

- Alle Vergleichs-Apps zeigen den Saldo je Person in der Gruppe und einen Ausgleichsvorschlag; Splitwise zusätzlich den
  Gesamtsaldo über alle Gruppen und je Freund. Settle Up erinnert an offene Schulden.
- Vorschlag Fasan Split: Profil-Avatar oben auf jeder Hauptseite mit Ring/Zahl (grün = bekommst, rot = schuldest);
  Tipp → „Mein Stand“: gesamt, je Gruppe, je Person, „Wer zahlt als Nächstes?“ (die Person mit dem niedrigsten Saldo in der
  Gruppe, Hinweis an der Gruppe und beim Anlegen eines Bons).

## 4. Kategorien

Offizielle Splitwise-Liste nicht gefunden. Übliche Oberkategorien in den Quellen: Lebensmittel, Essen & Trinken,
Transport, Unterkunft/Reise, Unterhaltung, Wohnen (Miete, Nebenkosten), Persönliches. Splitwise kategorisiert nicht
automatisch nach Geschäft (Nutzerwunsch dort). Vorschlag: feste Grundliste mit Symbol und Farbe, Erkennung aus
Geschäftsname/Posten (vorhandene `speisen.dart`, Händlerliste), eigene Kategorien, Unterkategorien später.

## 5. Währung

- EZB-Referenzkurse: offizielle Datei eurofxref-daily.xml, Werktags ca. 16:00 MEZ, „nur zur Information“, kein RUB seit
  01.03.2022. Quelle: ecb.europa.eu/stats/eurofxref.
- Frankfurter (Open Source, ohne Schlüssel, historische Kurse, api.frankfurter.dev) als Alternative.
- Vorschlag: direkt von der EZB (keine Drittpartei), nur GET, abschaltbar, Datum des Kurses sichtbar, Knopf „Kurs
  aktualisieren“, Kurs am Bon gespeichert (Datum des Bons, später änderbar). Datenschutz: Abruf verrät die IP an die EZB →
  Einstellung, Hinweis.

## 6. Web-Technik

- Mehrere Threads für ONNX im Browser brauchen `crossOriginIsolated`; GitHub Pages setzt keine Header → coi-serviceworker
  (MIT) emuliert COOP/COEP, lädt die Seite beim ersten Besuch einmal neu; Skript nicht bündeln, vom eigenen Ursprung.
  onnxruntime-web fällt ohne Isolation auf 1 Thread zurück. `credentialless` nicht in Safari. Quellen: dev.to/osidorkin
  (cross-origin isolation), docs.wasmer.io coop-coep, onnxruntime wasm-factory.ts.
- Safari löscht Daten nach 7 Tagen ohne Besuch; zum Home-Bildschirm hinzugefügte Web-Apps haben eigene Zählung und sind
  ausgenommen (WebKit/Wilander, Apple-Forum 710157). `navigator.storage.persist()` auf iOS unzuverlässig. Folge: auf iOS
  „Zum Home-Bildschirm“ deutlich empfehlen, regelmäßig Sicherung anbieten.

## 7. KI-Schnittstelle (MCP)

Für Splitwise gibt es mehrere Community-MCP-Server (pypi splitwise-mcp-server, lobehub vishnujayvel/splitwise-mcp) über
die Splitwise-API. Für Fasan Split ohne Server: MCP-Server, der lokal eine Sicherung/Export liest oder als Gruppenmitglied
mit eigenem Schlüssel liest und Vorschläge macht (schreiben nur nach Freigabe). Roadmap, Entwurf nötig.
