# Start einer neuen Sitzung an Fasan Split

Als erste Nachricht einfügen (Sitzung mit dem Repo `fasan-app/Fasan-Split` starten):

```
Lies nur CLAUDE.md und in STAND.md die Abschnitte „Noch offen – Reihenfolge“ und den letzten Sitzungsabschnitt.
Große Dateien nur per grep. Antworte kurz, Deutsch, Du-Form. Ich arbeite vom Handy.
Mein Punkt: <Nummer und Titel>. Branch: <name/thema>, nicht main.
Vor dem Push: git fetch origin, flutter analyze, flutter test grün. Mergen nach main nur nach grüner CI und meiner Freigabe.
fasan_ui nur anbinden, wenn der Punkt Design betrifft.
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
