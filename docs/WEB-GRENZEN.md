# Was die Web-App nicht kann (und warum) – Stand 05.11.

Frage des Nutzers: Was kann im Browser grundsätzlich nicht wie in der Android-App sein? Alles hier sind **Grenzen der
Plattform**, keine Auslassungen. Kennzeichen: **[Sekundär]** Suchergebnis / Wissen ohne gelesene Primärseite,
**[nicht geprüft]** nicht auf einem echten iPhone ausprobiert. Wir haben kein iPhone in der Cloud-Sitzung.

Was gleich ist (gleicher Dart-Code, gleiche Widgets): Kachel-Liste mit Bon-Kacheln, Bon-Bildschirm, Einladung, Chat,
Ergebnis, Export, Sprachen. Unterschiede gibt es nur dort, wo `kIsWeb` im Code steht: Beitritts-Hinweis, Anfrage für
dauerhaften Speicher, Update-Hinweis, Deep Links, Benachrichtigungen.

## Echte Grenzen

| Thema | Android-App | Browser | Folge für uns |
|---|---|---|---|
| **Daten bleiben** | App-Speicher, bleibt bis Deinstallation | Safari/iOS löscht Website-Daten nach ca. 7 Tagen ohne Besuch (ITP) [Sekundär]; zusätzlich getrennter Speicher zwischen Safari-Tab und Home-Bildschirm-App [Sekundär] | Konto-Sicherung (12 Wörter, Sicherungsdatei) ist vorn: Beitrittsbildschirm und Home-Hinweis. Dauerhaften Speicher anfragen (`navigator.storage.persist`), Wirkung auf iOS [nicht geprüft] |
| **Home-Bildschirm-App (iPhone)** | – | Eigener Speicher: Konto aus dem Safari-Tab ist dort nicht da [Sekundär] | Hinweis „Zum Home-Bildschirm“ vor dem Anlegen; sonst Konto per 12 Wörtern übertragen |
| **Push im Hintergrund** | Benachrichtigung auch bei geschlossener App | Web-Push auf iPhone nur für Home-Bildschirm-Apps [Sekundär]; Relay-Verbindung bricht ab, sobald der Tab schläft | Nachrichten kommen beim Öffnen nach (`wake()`); kein Hintergrund-Sync |
| **Vibration/Haptik** | Haptik-API | Vibration API fehlt in iOS Safari [Sekundär] | Haptik entfällt auf iPhone-Browsern |
| **Ton** | Sofort | Audio braucht erst eine Nutzergeste (Autoplay-Regeln) [Sekundär] | Ton erst nach dem ersten Tippen; vorher stumm |
| **Kamera / Scan** | Direkt, volle Auflösung | Dateiauswahl oder `getUserMedia` mit Berechtigungsabfrage; keine Kamera-Steuerung (Fokus, Blitz) wie nativ [Sekundär] | Foto per Auswahl; Qualität hängt vom Browser ab |
| **Neigungssensor** (Effekte) | Frei | iOS fragt erst nach Erlaubnis (`DeviceOrientationEvent.requestPermission`) [Sekundär] | Effekt nur nach Zustimmung, sonst ruhig |
| **Rechenlast der Erkennung** | Nativ, mehrere Kerne | ONNX im Browser (WASM); Mehrfädigkeit braucht `SharedArrayBuffer`, also Cross-Origin-Isolation (auf GitHub Pages nur mit Service-Worker-Trick) [Sekundär]; Speichergrenze der Tabs [Sekundär] | Erkennung auf dem Handy-Browser langsamer, bei großen Bildern kann der Tab abbrechen [nicht geprüft] |
| **Dateien, Zwischenablage** | Frei | Teilen/Speichern über Browser-Dialoge, Zwischenablage nur nach Geste | Export als Download; „Link kopieren“ nur nach Tippen |
| **Updates** | In-App-Update der APK | Neue Version beim nächsten Laden; Service-Worker-Cache kann alte Version halten | Update-Hinweis in der Web-App |
| **Links in die App** | App-Links | Link öffnet sich im Browser oder im In-App-Browser von Messengern (kein Speicher, oft abgeschnittene URLs) | Link v2 mit Prüfsumme, Einfügefeld, Landing-Seite erklärt Fehler |
| **Kein Konto, kein Server** | – | Browser-Daten löschen = Konto weg | Sicherung vorn; Wiederherstellung per 12 Wörtern |

## Nicht übertragbar

- Hintergrundbetrieb und echte Push-Nachrichten bei geschlossenem Browser.
- Haptik auf iPhone-Browsern.
- Garantierte Dauer der Daten auf iPhone-Safari ohne Sicherung.
- Gleiche Erkennungsgeschwindigkeit wie nativ.

## Noch zu prüfen (ehrlich offen)

- Echtes iPhone (Safari und Home-Bildschirm-App): kein Gerät verfügbar; Chromium-Läufe mit Playwright ersetzen das nicht.
- Messenger-In-App-Browser (WhatsApp, Telegram, Instagram): Verhalten beim Beitrittslink nur aus Berichten bekannt [Sekundär].
