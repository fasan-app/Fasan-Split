# Neuigkeiten für das Update-Fenster

Hier stehen die Texte für „Was ist neu“ in der App – **eine Datei je Sprache** (`de.md`, `en.md`, …), wie alle Texte der App getrennt.
Die CI hängt sie beim Veröffentlichen an die Release-Notizen (`neueste`); die App liest den Block ihrer Sprache (Ausweichen: Englisch).

Regeln:
- Format: Überschrift `## 0.1.N` (N = Nummer des ersten Builds mit dieser Änderung), darunter `- ` Zeilen. Neueste Version oben.
- Höchstens 5 Zeilen je Abschnitt, jede ein kurzer Satz (unter 70 Zeichen) mit Vorteil zuerst, beginnend mit „Neu:“, „Besser:“ oder „Behoben:“ (Recherche 08.11.: Store-Richtlinien, kurze Nutzen-Listen).
- Kurze Sätze in einfacher Sprache, was **du** jetzt anders machen kannst – keine Commit-Texte, keine Fachwörter.
- Jede Sprache hat dieselben Überschriften und gleich viele Zeilen (`app/test/news_test.dart` prüft das).
- Die App zeigt höchstens 8 Zeilen, nur Abschnitte neuer als der installierte Build.
