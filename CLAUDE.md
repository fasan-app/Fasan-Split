# Fasan Split – Arbeitsregeln

Fasan Split (`app.fasan.split`, Flutter) ist die Rechnungs-App der Fasan-Familie: Bon scannen, Summe, wer war dabei,
Posten zuordnen, wer hat bezahlt, Export. Der Code zieht später in Fasan Karte.

## Vor der Arbeit lesen (nur diese Dateien)

1. `STAND.md` in diesem Repo.
2. `../fasan/ENTSCHEIDUNGEN.md`, `GRUNDSAETZE.md`, `ZUSTAENDE-UND-PROFILE.md` (Repo fasan-app/Fasan).
3. `../fasan-karte/docs/PLAN-FLUTTER.md`, Abschnitte „Stile und Effekte“ und „Rechnung“.
4. `../fasan-diagnose/README.md` (Regression der Erkennung; Dart-Gegenstücke in `app/test/`).
5. `../fasan-karte/docs/ENTSCHEIDUNGEN.md`: alle Beschlüsse zu Bon und Kosten. Das ist der Soll-Umfang dieser App.
6. Vor Design- und Bedienarbeit die Kurzfassungen der Recherchen: `../fasan-karte/docs/recherche/` (gestaltung-psychologie,
   ui-design-2026, natives-gefuehl, rechnung-teilen-ux, gemeinsam-bearbeiten, bon-ansicht-und-farben, scan-und-bedienung,
   kosten-und-fuehrung), `../fasan-camera/docs/recherche/` (psychologie-bedienung, gestaltung-start-einstellungen, haptik),
   `../fasan_ui/docs/recherche/`. Details per grep.
7. Prüfen heißt: Emulator-Bildschirmfotos mit echtem Bon (aus `fasan-diagnose`) ansehen, nicht nur grep.

## Regeln

- Nichts raten: Vor System-APIs, Plugins und Shadern die offizielle Doku lesen (api.flutter.dev, pub.dev,
  developer.android.com, onnxruntime.ai). Annahmen mit Quelle oder als „nicht geprüft“.
- Englische Bezeichner, Kommentare für spätere Bearbeiter, modular. Lizenz MPL-2.0, keine GPL-Bausteine.
- Oberfläche Deutsch und Englisch, Du-Form, kurze Sätze. Keine Telemetrie; Diagnose nur nach Zustimmung.
- Echte Bonfotos nie ins Repo und nie in den Code; bekannte Test-Bons nicht in der App hinterlegen.
- Tippfläche ≥ 48 dp (Profil „Einfach“ 60 dp), Bewegung folgt „Animationen entfernen“ und der App-Einstellung.
- Token sparen: große Dateien nur per grep lesen; nach jedem Arbeitspaket `STAND.md` aktualisieren.
- Commits als `Fasan <fasan@christopherziehm.de>`.
