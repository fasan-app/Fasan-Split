// SPDX-License-Identifier: MPL-2.0
// Fasan Split – German texts of the guide (Einstellungen → Anleitung). Per step in `tutorialIds` (ui/tutorial.dart): `tutorial.<id>.title`
// and `tutorial.<id>.body`. Kept current with every change of the operation (CLAUDE.md, Nutzer 07.11.). MPL-2.0
const Map<String, String> tutorialDe = {
  'tutorial.title': 'Anleitung',
  'tutorial.intro': 'So rechnest du mit Fasan Split ab: Bon scannen, Leute eintragen, Posten zuordnen, ausgleichen.',
  'tutorial.idea.title': 'Die Idee',
  'tutorial.idea.body': 'Du fotografierst den Bon, sagst wer dabei war und tippst, wer was hatte. Die App rechnet alles automatisch aus. Es gibt kein Konto, alles bleibt auf deinem Gerät, solange du nichts teilst.',
  'tutorial.scan.title': 'Bon scannen',
  'tutorial.scan.body': 'Tippe unten rechts auf das Plus. Du kannst den Bon mit der Kamera fotografieren, ein Foto oder eine Datei aus der Galerie wählen (auch mehrere auf einmal) oder „Ohne Bon“ von Hand eintragen. Die App liest Posten und Summe selbst.',
  'tutorial.check.title': 'Prüfen',
  'tutorial.check.body': 'Vergleiche Summe und Posten mit dem Bon. Mit dem Bon-Symbol oben siehst du das Foto. Ein Posten, der nicht stimmt, lässt sich antippen und ändern. Alles wird sofort gespeichert; „Später weiter“ schließt den Bon nur. Der Rahmen von Posten und Bons zeigt, wie viel zugeordnet ist: rot offen, gelb teilweise, grün vollständig. Mit „Nur offene Posten“ siehst du nur, was noch fehlt. Die Liste ist nach Status sortiert, darin das neueste zuerst; andere Sortierungen und Filter findest du oben unter dem Sortier-Symbol.',
  'tutorial.assign.title': 'Wer war dabei, wer hatte was',
  'tutorial.assign.body': 'Füge unter „Wer war dabei?“ die Personen hinzu. Wähle eine Person und tippe die Posten, die sie hatte. Teilen sich mehrere einen Posten, ordnest du ihn mehreren zu. Die Anteile rechnet die App aus.',
  'tutorial.paid.title': 'Wer hat bezahlt',
  'tutorial.paid.body': 'Stelle „Bezahlt von“ auf die Person, die das Geld ausgelegt hat. Daraus ergibt sich, wer wem wie viel schuldet.',
  'tutorial.group.title': 'Gruppe anlegen',
  'tutorial.group.body': 'Tippe oben im Gruppenwähler auf das Ordner-Symbol, um eine Gruppe zu benennen, zum Beispiel für einen Urlaub oder eine WG. Ist eine Gruppe gewählt, startet das Plus einen neuen Bon, der gleich dort liegt. Du kannst auch einen Bon gedrückt halten und auf den Namen der Gruppe im Wähler ziehen. „Alle“ zeigt alles, „Ohne Gruppe“ nur Bons ohne Gruppe. Oben in der Gruppe siehst du Anzahl, Summe und Personen. Der Rahmen zeigt, wie viele Posten erledigt, in Arbeit oder offen sind; die Summe öffnet die Aufteilung. „Rechnungen | Posten“ schaltet zwischen den Bons und allen Posten der Gruppe um.',
  'tutorial.invite.title': 'Leute einladen',
  'tutorial.invite.body': 'Öffne die Gruppe und tippe oben auf das Personen-Symbol. Teile den Link oder den Code. Wer ihn öffnet, ist in der Gruppe und sieht die Bons. Mit „Live teilen“ halten alle ihren Stand synchron.',
  'tutorial.together.title': 'Zusammen eintragen',
  'tutorial.together.body': 'In einer Gruppe kann jeder für jeden eintragen. Die App rechnet automatisch weiter. Unter „Personen“ siehst du schon zwischendurch, wer wem was schuldet. Abgerechnet wird, wenn alle Rechnungen eingetragen sind. Willst du etwas schützen, sperrst du es mit dem Schloss: einen Posten im Posten-Blatt, eine ganze Rechnung im Menü (⋮). Dann ändern nur du und der Gruppen-Admin, Notizen gehen weiter.',
  'tutorial.history.title': 'Stand und Verlauf',
  'tutorial.history.body': 'Im Profil zeigt „So ergibt sich dein Stand“ jede Rechnung mit Plus und Minus. Im Menü (⋮) eines Bons, einer Gruppe und im Profil findest du den Verlauf: wer hat was geändert und wie sich dein Saldo bewegt hat. Hat jemand einen Bon geändert, zeigt ein Zähler an der Vorschau, wie viel, und im Bon steht „Neu seit deinem letzten Besuch“. Ist ein geteilter Bon durcheinander geraten, holt „Früheren Stand holen“ oben im Verlauf des Bons den letzten Stand eines Mitglieds zurück.',
  'tutorial.settle.title': 'Ausgleichen',
  'tutorial.settle.body': 'Sind alle Rechnungen drin, zeigt das Personen-Symbol oben in der Gruppe, wer wem wie viel zahlt. Wische einen Bon nach rechts oder tippe „Ausgleichen“, wenn bezahlt ist. Ausgeglichene Bons liegen im Archiv. Zwischendurch bezahlt oder Geld geliehen? Im Personen-Fenster trägst du es mit „Zahlung oder Leihgabe eintragen“ ein; der Stand ändert sich sofort.',
  'tutorial.settings.title': 'Einstellungen und Sicherung',
  'tutorial.settings.body': 'In den Einstellungen findest du Aussehen, Sprache, Leistung und diese Anleitung. Läuft die App bei dir ruckelig, startet der „Leistungstest“ unter Diagnose eine Messung mit Probedaten und erzeugt einen Bericht zum Teilen. Die kleinen Tipps oben auf der Startseite kannst du dort abschalten. Im Profil sicherst du deine Daten mit „Sicherung speichern“. Im Browser zeigt „Jetzt nach Updates suchen“ den Stand deiner Seite und lädt sie bei einem neueren Stand neu; dein Login bleibt.',
};
