# Start einer neuen Sitzung an Fasan Split

Als erste Nachricht einfügen (Sitzung mit dem Repo `fasan-app/Fasan-Split` starten):

```
Führe zuerst CLAUDE.md, Abschnitt „PFLICHT vor jeder Arbeit“, vollständig aus, Schritt 0 bis 4, ohne Ausnahme:
Repos Fasan, fasan_ui, fasan-diagnose, Fasan-Karte und Fasan-Camera anhängen (ausdrücklich von mir freigegeben, lesen) und klonen,
die Prüfschleife aus Schritt 0.2 laufen lassen und mir ihr Ergebnis zeigen. Fehlt etwas: stoppen und melden.
Vor Design-/Bedienarbeit alle Recherchen vollständig lesen (nicht per grep) und docs/PRUEFLISTE-OBERFLAECHE.md anwenden.
Danach STAND.md: „Beschlüsse“ oben und „Noch offen – Reihenfolge“; arbeite nach „Arbeitsplan ab 06.11.“ dort, Paket für Paket,
und melde ein Paket erst als fertig, wenn alle Punkte von „Fertig heißt“ erfüllt sind – mit Nachweis.
Antworte Deutsch, Du-Form, kurze Sätze. Ich arbeite vom Handy. Branch: mitarbeit/<thema>. main nur über das Tor in CLAUDE.md.
```

## Setup-Skript der Cloud-Umgebung (Umgebung bearbeiten, „Setup script“)

Installiert Flutter wie die CI, damit nicht jede Sitzung das selbst tut. Das Skript sieht keine Geheimnisse; private Repos
(fasan-diagnose) bindet die Sitzung selbst an.

```bash
set -e
mkdir -p ~/tools && cd ~/tools
[ -d flutter ] || curl -sSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.7-stable.tar.xz | tar xJ
git config --global --add safe.directory ~/tools/flutter
~/tools/flutter/bin/flutter config --no-analytics
```

Danach in der Sitzung: `export PATH=~/tools/flutter/bin:$PATH FLUTTER_SUPPRESS_ANALYTICS=true`.
Nicht geprüft: ob das Setup-Skript als derselbe Nutzer läuft wie die Sitzung (sonst liegt `~/tools` woanders).
