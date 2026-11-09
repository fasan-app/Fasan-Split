# Sprachen und Texte

Kein Text der Oberfläche steht im Code. Alle Texte liegen in `app/lib/l10n/`:

| Datei | Inhalt |
|---|---|
| `strings_de.dart`, `strings_en.dart`, … | eine Tabelle je Sprache: Schlüssel → Text |
| `tips_de.dart`, `tips_en.dart`, … | die Tipp-Zeile unter dem Hauptmenü, ein Text je Tipp (`tip.<id>`) |
| `tutorial_de.dart`, `tutorial_en.dart`, … | die Anleitung (`tutorial.<id>.title` / `.body`) |
| `languages.dart` | die Liste der Sprachen (`appLanguages`) und die Regel für Mehrzahl |
| `tr.dart` | `context.tr('bill.done')`, `context.trn('bill.open', 3)` |

Im Code steht nur der Schlüssel. `{0}`, `{1}` im Text werden aus den Argumenten gefüllt: `context.tr('bill.checkDiff', [betrag])`.
Mehrzahl: Schlüssel `x.one` und `x.other`, Aufruf `context.trn('x', n)`; Sprachen mit mehr Formen bekommen in
`languages.dart` eine eigene Regel.

## Neue Sprache hinzufügen (ohne den Code zu lesen)

1. `strings_en.dart`, `tips_en.dart` und `tutorial_en.dart` nach `…_<code>.dart` kopieren, die Werte übersetzen. **Schlüssel und `{0}` nicht ändern.**
2. In `languages.dart` eine Zeile in `appLanguages` ergänzen: `AppLanguage('fr', 'Français', {...stringsFr, ...tipsFr, ...tutorialFr})`.
3. `flutter test test/l10n_test.dart test/tips_test.dart` prüft: alle Schlüssel vorhanden, gleiche Platzhalter, nichts leer, jeder Tipp und jeder Anleitungsschritt in jeder Sprache.

**Tipps und Anleitung bleiben aktuell (Nutzer 07.11.):** Jede Änderung an Bedienung, Ablauf oder Einstellungen ändert im selben Paket die Anleitung (`tutorialIds` in `ui/tutorial.dart`) und, wenn sinnvoll, einen Tipp (`tipIds` in `ui/tips.dart`), in allen Sprachen.

Fehlt ein Schlüssel in einer Sprache, gilt Englisch, dann Deutsch, sonst der Schlüssel selbst (im Test sichtbar).

## Stand

Neuer Code (Bon-Bildschirm, Personenauswahl, Einladen) nutzt die Tabellen. Ältere Texte stehen noch in `lib/l10n*.dart` (`S`)
und in `de ? … : …` im Code; sie werden mit `tool/l10n_extract.py` in die Tabellen überführt (siehe `STAND.md`).
