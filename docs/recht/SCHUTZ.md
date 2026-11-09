# Was ist unser, und was lässt sich schützen?

Stand 08.11.2026. Frage des Nutzers (08.11.): Was ist tatsächlich auf unserer Idee gewachsen und lässt sich rechtlich schützen? Vertrauensmarken siehe [README](README.md). Keine Rechtsberatung.

## Kurzfassung

- **Die Idee selbst ist nicht schützbar** [sicher]: „Bon fotografieren, Posten zuordnen, wer hat bezahlt, Gruppe“ ist eine Idee; das deutsche Urheberrecht schützt bei Software nur die Ausdrucksform, nicht die zugrunde liegenden Ideen und Grundsätze (§ 69a Abs. 2 UrhG, https://lexetius.com/UrhG/69a,4).
- **Schützbar sind** unsere konkrete Umsetzung (Quelltext, Texte, Gestaltung) über das **Urheberrecht**, ohne Anmeldung, und der **Name** über eine **Marke** (Anmeldung nötig).
- **Patente:** praktisch nein [wahrscheinlich]. Software „als solche“ ist in Deutschland und Europa ausgenommen (§ 1 PatG, Art. 52 EPÜ), und unsere Bausteine sind bekannte Techniken.
- **Offene Frage mit Gewicht** [wahrscheinlich, nicht geprüft]: Großer Teil des Codes entstand mit KI-Sitzungen. Urheberrecht setzt eine menschliche „persönliche geistige Schöpfung“ voraus; für rein maschinell erzeugte Teile ist der Schutz unsicher. Das betrifft auch die Durchsetzbarkeit der MPL-Lizenz. Menschlicher Anteil (Vorgaben, Auswahl, Prüfung, Entscheidungen, Tests) festhalten und mit einer Fachperson klären.

## Was bei Fasan Split Eigenleistung ist

| Bereich | Was | Schutzweg |
|---|---|---|
| Quelltext der App | Oberfläche, Abläufe, Kollaboration (gemeinsame Rechnungen über Nostr mit „letzter Schreiber gewinnt“, Vorhängeschloss), Konten ohne Server | Urheberrecht (automatisch) |
| `fasan_core` | Rechenkern: Aufteilen mit Gewichten und Festbeträgen, Rundung ohne Cent-Verlust, Ausgleich mit wenigen Überweisungen (gegen Brute-Force geprüft) | Urheberrecht auf den Code; **das Verfahren selbst nicht** (mathematische Methode) |
| `fasan_reader` und Erkennungsablauf | Lesen eines Bons aus Textzeilen, Vor-/Nachbearbeitung, Erkennungs-Tor (Regressionsprüfung gegen echte Bons) | Urheberrecht auf Code und Regeln; Modelle gehören Dritten |
| `fasan_ui` | Gestaltung, Shader, Bewegung, Bedienregeln | Urheberrecht; Geschmacksmuster/Designschutz wäre möglich, lohnt kaum [geraten] |
| Texte | Oberfläche, Anleitung, Tipps, Neuigkeiten (de/en), Dokumentation, Recherchen | Urheberrecht |
| Name „Fasan“, „Fasan Split“, Logo | Kennzeichen der App-Familie | **Marke** (Anmeldung), sonst nur schwacher Schutz gegen Verwechslung durch Benutzung |
| Test-Bons und Wahrheiten | echte Kassenzettel Dritter | **nicht unser**, privat halten (Persönliches, Rechte Dritter) |

## Was auf Fremdem aufbaut (nicht unser, aber frei nutzbar)

OCR- und Entzerr-Modelle (PaddleOCR Apache-2.0, UVDoc MIT), Flutter und Pub-Pakete (BSD/MIT/Apache), Nostr (offenes Protokoll), BIP-39 (12 Wörter), SEPA/EPC-QR, EZB-Kurse (freie Weiterverwendung mit Quellenangabe).
Auch Prinzipien wie „letzter Schreiber gewinnt“ (LWW-CRDT) oder Schuldenvereinfachung sind bekannte Verfahren [wahrscheinlich]. Details: [LIZENZEN.md](LIZENZEN.md).

## Wettbewerb

Es gibt etablierte Abrechnungs-Apps für Gruppen [geraten: z. B. Splitwise, Tricount – in dieser Recherche **nicht** untersucht, auch nicht deren Funktionen oder Patente]. Der Unterschied liegt bisher faktisch, nicht rechtlich:
keine Konten, kein Zwangsserver, offen lesbar, keine Telemetrie, Browser = App, Bon-Erkennung im Gerät. Das lässt sich nicht schützen, aber kopieren darf man es nur als **Idee**, nicht als unseren Code ohne MPL-Pflichten.

## Schutzwege im Einzelnen

### Urheberrecht

- Entsteht mit dem Werk, keine Anmeldung [sicher, § 69a Abs. 3 UrhG: Schutz für individuelle Werke als Ergebnis eigener geistiger Schöpfung, keine ästhetischen oder qualitativen Kriterien; https://lxgesetze.de/urhg/69a].
- Nachweis: Commit-Historie (310 Commits, alle als „Fasan“), Datum, Inhalte. Wer **Urheber** ist, steht dort nicht eindeutig: Commits laufen unter einer gemeinsamen Kennung. Für die Zukunft: Urheber und Inhaber der Nutzungsrechte klar benennen (Person/Verein/Firma), damit der Lizenzgeber der MPL feststeht.
- MPL-2.0 gibt anderen Nutzungsrechte, **behält das Urheberrecht** bei uns. Beiträge Dritter nur mit Zustimmungserklärung (Beschluss 08.10.), sonst lässt sich die Lizenz später nicht ändern (Datei `CONTRIBUTING.md` fehlt noch).

### Marke („Fasan“)

- Amtsgebühren 2026 beim DPMA: **290 € elektronisch (300 € Papier) bis drei Klassen**, jede weitere Klasse 100 €; Verlängerung nach 10 Jahren 750 € [sicher, https://www.dpma.de/service/gebuehren/marken]. EU-Marke (EUIPO) ca. 850 € [Zweitquelle: https://gesetz-ratgeber.de/rechtsgebiete/markenrecht/markenanmeldung-ablauf-kosten].
- Für eine App kommen Klasse 9 (herunterladbare Software) und Klasse 42 (Software als Dienst, falls eigene Server-Dienste) infrage [Zweitquelle: https://www.windweiss.de/anwalt/markenrecht/marke-anmelden-dpma/].
- **Vorher recherchieren** (Beschluss 08.10.): Register DPMAregister, EUIPO/TMview, Suche nach „Fasan“ in Klasse 9/35/36/42 und ähnlichen Zeichen **[nicht geprüft]**. „Fasan“ ist ein gewöhnliches deutsches Wort (Vogel); als Name für Software meist unterscheidungskräftig [wahrscheinlich], aber ältere Marken in nahen Klassen sind möglich [geraten].
- Nutzen: Eine Marke ist der **einzige** Hebel gegen unerwünschte Forks unter gleichem Namen oder Täuschung (MPL erlaubt Forks). Reihenfolge: Recherche → Entscheidung → Anmeldung; bis dahin nicht als „®“ ausgeben.

### Patent

- Software „als solche“ nicht patentierbar; technische Erfindungen mit Computerhilfe schon, wenn neu, erfinderisch und technisch [sicher, Art. 52 EPÜ, § 1 PatG; https://www.haufe.de/id/beitrag/3-recht-der-werknutzung-2-software-bezogene-erfindungen-HI15189542.html].
- Unsere Bausteine (OCR mit bekannten Modellen, LWW-Dokumente, Aufteilen, Saldo) sind bekannt; eine Anmeldung wäre teuer und aussichtsarm [wahrscheinlich].
- Der öffentliche Quelltext ist **Stand der Technik** und erschwert, dass Dritte später darauf Patente anmelden [wahrscheinlich]. Fremde Patente auf Teilverfahren (Bon-Erkennung, Aufteilen) kennen wir nicht [nicht geprüft]; die MPL-Patentlizenz schützt Nutzer vor Ansprüchen der Beitragenden, nicht vor Dritten [sicher laut MPL-FAQ].

### Geschäftsgeheimnis, Datenbank, Design

- Geschäftsgeheimnis: entfällt, was öffentlich liegt. Privat bleiben nur Test-Bons und Wahrheiten.
- Datenbankschutz: nicht einschlägig; die privaten Test-Daten sind keine eigene Sammlung zum Weitergeben.

## Weitere Pflichten bei öffentlicher Veröffentlichung [nicht geprüft]

- **Datenschutz:** Keine Telemetrie (Beschluss), aber Datenschutzerklärung und Angaben zum Verantwortlichen sind für Store-Einträge üblich; Bons und Gruppen enthalten Daten Dritter.
- **Impressum:** für geschäftsmäßige Angebote in Deutschland üblich [wahrscheinlich].
- **Haftung:** MPL-2.0 schließt Gewährleistung aus („as is“) [sicher]; bei Geldbeträgen (Rechenfehler) deshalb Prüfregeln und Tests beibehalten (Zweitprüfung `audit()` ist schon da). Wirksamkeit von Haftungsausschlüssen gegenüber Verbrauchern nicht geprüft.

## Quellen (gelesen 08.11.2026)

- § 69a UrhG: https://lexetius.com/UrhG/69a,4 und https://lxgesetze.de/urhg/69a
- Softwarepatente (Art. 52 EPÜ / § 1 PatG): https://www.haufe.de/id/beitrag/3-recht-der-werknutzung-2-software-bezogene-erfindungen-HI15189542.html ; https://oncourse.uni-bremen.de/pluginfile.php/4642/mod_label/intro/k11_e02.pdf
- DPMA-Gebühren: https://www.dpma.de/service/gebuehren/marken
- MPL-2.0-FAQ: https://www.mozilla.org/en-US/MPL/2.0/FAQ/
