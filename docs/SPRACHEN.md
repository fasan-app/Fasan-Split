# Sprachen und Texte

Kein Text der Oberfläche steht im Code. Alle Texte liegen in `app/lib/l10n/`:

| Datei | Inhalt |
|---|---|
| `strings_de.dart`, `strings_en.dart`, … | eine Tabelle je Sprache: Schlüssel → Text |
| `languages.dart` | die Liste der Sprachen (`appLanguages`) und die Regel für Mehrzahl |
| `tr.dart` | `context.tr('bill.done')`, `context.trn('bill.open', 3)` |

Im Code steht nur der Schlüssel. `{0}`, `{1}` im Text werden aus den Argumenten gefüllt: `context.tr('bill.checkDiff', [betrag])`.
Mehrzahl: Schlüssel `x.one` und `x.other`, Aufruf `context.trn('x', n)`; Sprachen mit mehr Formen bekommen in
`languages.dart` eine eigene Regel.

## Neue Sprache hinzufügen (ohne den Code zu lesen)

1. `strings_en.dart` nach `strings_<code>.dart` kopieren, die Werte übersetzen. **Schlüssel und `{0}` nicht ändern.**
2. In `languages.dart` eine Zeile in `appLanguages` ergänzen: `AppLanguage('fr', 'Français', stringsFr)`.
3. `flutter test test/l10n_test.dart` prüft: alle Schlüssel vorhanden, gleiche Platzhalter, nichts leer.

Fehlt ein Schlüssel in einer Sprache, gilt Englisch, dann Deutsch, sonst der Schlüssel selbst (im Test sichtbar).

## Stand

Neuer Code (Bon-Bildschirm, Personenauswahl, Einladen) nutzt die Tabellen. Ältere Texte stehen noch in `lib/l10n*.dart` (`S`)
und in `de ? … : …` im Code; sie werden mit `tool/l10n_extract.py` in die Tabellen überführt (siehe `STAND.md`).
