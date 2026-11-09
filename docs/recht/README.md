# Recht, Lizenzen, Finanzierung

Eigener Bereich für alles Rechtliche und Wirtschaftliche rund um Fasan Split (Nutzer 08.11.): Rechte, Lizenzen, Finanzierung, Veröffentlichungsmodelle.
Stand der Recherche: **08.11.2026**. **Das ist keine Rechtsberatung.** Es sind Arbeitsnotizen mit Quellen; vor Entscheidungen mit Geld oder
Haftung (Marke, Rechtsform, Steuer) fragt man eine Fachperson.

Vertrauensmarken in diesen Dateien: **[sicher]** = belegt (Quelle oder eigene Prüfung im Repo), **[wahrscheinlich]** = starke Schlussfolgerung,
**[geraten]** = Lücke gefüllt, **[nicht geprüft]** = offen.

| Datei | Inhalt |
|---|---|
| [LIZENZEN.md](LIZENZEN.md) | Unter welcher Lizenz wir stehen, was wir benutzen (144 Pakete, Modelle, Schrift), was daraus für uns folgt, Lücken |
| [FINANZIERUNG.md](FINANZIERUNG.md) | Kostenlos + Premium gegen „alles offen + Spendenbitte“, Zahlen, Empfehlung, Steuer und Rechtsform grob |
| [SCHUTZ.md](SCHUTZ.md) | Was auf unserer Idee gewachsen ist und was sich rechtlich schützen lässt (Urheberrecht, Marke, Patent) |

## Offene Punkte (Reihenfolge)

1. **LICENSE-Datei fehlte im Repo** [sicher: `git ls-files` zeigte keine]. **Erledigt 08.11.:** `LICENSE` (MPL-2.0, Wortlaut unverändert aus dem Pub-Paket `dbus`, Mozilla-Standardtext; die `LICENSE` von `fasan_ui` unterscheidet sich nur durch „https“ statt „http“ in der Exhibit-A-Zeile, also leicht verändert – bei Gelegenheit angleichen) liegt im Wurzelverzeichnis.
   Offen: SPDX-Zeile in die 33 Dart-Dateien ohne Kopfzeile; **Inhaber des Urheberrechts** in die Datei/Kopfzeilen eintragen (Nutzer entscheidet, wer genannt wird).
2. **Lizenzseite der App zeigt nur Pub-Pakete.** Modelle (Apache-2.0, MIT), Schrift (OFL), ONNX-Runtime-Android-Bibliothek (MIT) fehlen dort
   [sicher: kein `LicenseRegistry` im Code]. Apache-2.0 und MIT verlangen den Lizenztext beim Weitergeben. Nachholen.
3. **Marke „Fasan“ prüfen** (Beschluss 08.10.), bevor Name, Logo oder Kaufangebote öffentlich werden. Siehe SCHUTZ.md.
4. **Entscheidung Finanzierung** beim Nutzer (Empfehlung in FINANZIERUNG.md). Danach: Spenden-Plattform, Rechtsform, Steuer klären.
5. **CLA/Beitragsbedingung** (Beschluss 08.10.: „Beiträge anderer nur mit Zustimmungserklärung“): es gibt noch kein `CONTRIBUTING.md`. Vor dem ersten fremden Beitrag anlegen.
6. Fasan-Karte (die Modelle liegen dort öffentlich) hat ebenfalls keine LICENSE-Datei im Wurzelverzeichnis [sicher]; Herkunft und Lizenz der Modelle stehen nur in `app/assets/models/DATEIEN.txt`.
