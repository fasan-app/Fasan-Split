# Selbst-Update und Delta-Updates (Recherche 2026-11-02)

Nur lesend recherchiert. Nichts gesendet, nichts hochgeladen.
Quellen-Kürzel stehen am Ende. „nicht geprüft“ = keine Quelle gefunden oder Seite nicht lesbar.

## Kurzfassung

1. Empfehlung: erst Stufe A, dann Stufe B. Stufe C nur, wenn nötig. Splits (D) nicht.
2. A, Vorab-Anzeige: Die Release-API liefert je Datei `size`, `digest` (sha256) und im Release `body` [Q1, Q2]. Ohne Token 60 Anfragen/Stunde je IP [Q3]. Eine Prüfung pro Start reicht.
3. B, Modelle aus der APK lösen: ONNX-Dateien als eigene Release-Dateien mit Versions-Manifest (Name, Größe, SHA-256). App lädt nur bei geändertem Hash. Das ist der größte Hebel bei kleinstem Risiko.
4. Erwartete Ersparnis B: APK sinkt von ~60–80 MB auf ~25–45 MB (Schätzung: Modelle ~35 MB abziehen, nicht gemessen). Jedes Code-Update spart dann ~35 MB. Modell-Updates kosten nur das geänderte Modell.
5. C, Binär-Patch der APK: Gerät baut die neue APK aus der alten und installiert sie voll [Q10]. Die v2-Signatur deckt die ganze Datei ab [Q8]. Das Ergebnis muss also byte-genau die signierte neue APK sein. Das geht mit archive-patcher [Q9], nicht mit „irgendeinem“ Diff, der die Signatur bricht.
6. Ersparnis C: Play spricht im Schnitt von ~65 % [Q11]. Für uns nicht gemessen. Steckt Stufe B schon drin, bleibt wenig zu holen.
7. C kostet viel: Java/Dart-Werkzeug für archive-patcher fehlt als gepflegtes Flutter-Paket (nicht gefunden). Patch-Server pro Versionspaar nötig. Nur sinnvoll bei vielen Nutzern.
8. D, Split-APK mit `MODE_INHERIT_EXISTING`: technisch möglich (einzelnen Split ersetzen) [Q4, Q12], aber Splits teilen versionCode und Signatur mit der Basis [Q12]. Flutter-Assets aus Splits ohne Play: nicht geprüft. Nicht empfohlen.
9. Installation: `PackageInstaller`-Session, `REQUEST_INSTALL_PACKAGES`, Nutzer bestätigt [Q4, Q5, Q6]. Ohne Rückfrage nur unter Bedingungen (siehe Abschnitt 4). Mit Rückfrage planen.
10. Flutter-Pakete: `ota_update` (MIT, hat SHA-256-Prüfung, PackageInstaller opt-in) [Q13]. `android_package_installer` (BSD-3) [Q14]. Beide MPL-2.0-verträglich, nicht GPL. Eigener kleiner Kotlin-Teil ist die Alternative.
11. F-Droid: Das Nachladen von Daten verbietet die Richtlinie nicht; sie nennt ausführbare Dateien [Q7]. Feste Server können das Label NonFreeNet auslösen (Fall Organic Maps) [Q15].

## 1. GitHub-REST: Größe, Text, Digest, Limits

- Release-Datei hat `size` (Bytes), `digest` (String, Beispiel mit Präfix `sha256:`), `content_type`, `browser_download_url`, `download_count` [Q2: Drittseite zur GitHub-API, nicht die GitHub-Doku selbst; docs.github.com war im Werkzeug gesperrt].
- GitHub bestätigt: Release-Dateien zeigen SHA-256-Digests in UI, REST, GraphQL und `gh` [Q1]. Seit 2025-06-03. Ob ältere Dateien nachträglich einen Digest haben: Seite sagt dazu nichts, nicht geprüft. Ohne Digest: Hash selbst ins Manifest schreiben.
- Das Feld `body` des Release (Änderungstext) steht in der Release-Antwort. Quelle dafür: nicht direkt gelesen, nicht geprüft (Wissen aus der API-Praxis). Vor dem Bau gegen die echte Antwort prüfen (nur GET).
- Ratenlimit ohne Token: 60 Anfragen pro Stunde, an die IP gebunden. Header: `x-ratelimit-limit`, `-remaining`, `-used`, `-reset`, `-resource` [Q3].
- Ob der Download über `browser_download_url` auf das API-Limit zählt: die Seite sagt nichts dazu, nicht geprüft.
- Obtainium läuft mit der GitHub-API in dasselbe Limit und rät Nutzern mit vielen Apps zu einem Token [Q16]. Für uns: wenige Anfragen, kein Token nötig; Ergebnis kurz zwischenspeichern (ETag nicht geprüft).
- Wichtig für unsere Regel: Alle Aufrufe sind GET. Kein Token, nichts schreiben.

## 2. Delta-Wege

### 2a. Binär-Patch der APK

- Prinzip (Play „File-by-File“): geänderte Dateien finden und nur diese laden [Q11]. Durchschnitt ~65 %, Beispiel Netflix: 1,2 MB, 92 % weniger. Das ist Googles Schätzung für Play-Apps, nicht für uns.
- archive-patcher (Apache-2.0): entpackt geänderte Einträge, bsdiff darauf, baut beim Anwenden eine „perfekte Binärkopie“ der neuen Datei. Gilt nur für genau die alte Datei, aus der der Patch erzeugt wurde. Byte-genau nur, wenn zlib dieselben Deflate-Daten erzeugt; sonst bricht der Patch ab. Läuft auf ART ab API 15. Zip64 nicht unterstützt [Q9]. Zur Lizenz: Fork-README sagt Apache-2.0; die AOSP-Metadaten führen sie als „RECIPROCAL“ [Q17]. Widerspruch, vor Nutzung die LICENSE-Datei lesen.
- Signatur: v2 schützt Zip-Einträge, Central Directory und EOCD; jede Änderung macht die Prüfung ungültig [Q8]. Folge (Schlussfolgerung): Der Patch muss die fertig signierte neue APK ergeben. Dann passt die Signatur. Ein Patch auf unsignierte Teile mit späterem Neusignieren ginge nur mit unserem Schlüssel auf dem Gerät. Das wäre falsch.
- bsdiff und zstd als Alternative: `zstd --patch-from=alt neu -o patch` und `zstd -d --patch-from=alt patch -o neu` [Q18]. Stufe 19 etwa gleich klein wie bsdiff, deutlich schneller und sparsamer im Speicher [Q18]. Aber es arbeitet auf dem komprimierten Zip. Die APK enthält komprimierte Einträge. Die Ersparnis ist dann klein: nicht gemessen. Hier sollte man vorher mit zwei echten Releases messen (Aufwand: ein Skript auf dem Rechner, kein Upload).
- Alte APK auf dem Gerät lesen (`ApplicationInfo.sourceDir`): nicht geprüft.
- Was es spart: nur den Download. Installiert wird immer die volle APK [Q10]. Speicherplatz und Installationszeit bleiben.
- Flutter-Pakete: `binary_patch` 1.0.0 (bsdiff, Lizenz laut Seite MIT, README sagt BSD-3: widersprüchlich; unverifizierter Uploader, 106 Downloads) [Q19]. `zstd_dart` 1.1.0 (MIT; Dictionary/patch-from nicht dokumentiert) [Q20]. Beide unreif. Kein archive-patcher-Paket für Flutter gefunden.

### 2b. Split-APKs mit MODE_INHERIT_EXISTING

- Doku: Sitzung erbt vorhandene APKs, außer ein Split gleichen Namens überschreibt; „kann genutzt werden, um Splits zu einer Installation hinzuzufügen“. Ohne vorhandene Installation wie `MODE_FULL_INSTALL` [Q4].
- Ein einzelner Split lässt sich ersetzen (Teil-Update, so nutzt es Feature-Lieferung) [Q12, Abschnitt 6.2/9.5; Drittanalyse des AOSP-Codes, nicht Primärquelle].
- Bedingungen laut dieser Analyse: alle Teile haben denselben versionCode; Signatur muss zur Installation passen; Fehler `INSTALL_FAILED_INVALID_APK` bei Verstoß [Q12]. Play-Bundles setzen ebenfalls einen gemeinsamen versionCode [Q21].
- Offen (nicht geprüft): Ob ein Split gleichen versionCodes mit anderem Inhalt ohne Basis-Wechsel angenommen wird; ob Flutter Assets aus einem Split lädt (Flutters „deferred components“ hängen an Play Feature Delivery, hier nicht gelesen); ob eine bereits installierte Nicht-Split-APK Splits erben kann, ohne dass die Basis dafür vorbereitet wurde.
- Urteil: viel Risiko, wenig Gewinn gegenüber 2c. Nicht empfohlen.

### 2c. Große Daten getrennt laden

Vorteile:
- Größter, sicherster Gewinn: ~35 MB weniger in jeder APK (Schätzung).
- Modell-Update ohne App-Update und umgekehrt.
- SHA-256 je Datei, GitHub liefert Digest mit [Q1].
- Kein Eingriff in Signatur oder Installer.

Nachteile:
- Erster Start braucht Netz (oder Modelle sind „optional, später laden“). Das widerspricht „alles offline nutzbar“ aus den Familien-Regeln der Kamera-App. Für Split zu klären und als Entscheidung festhalten.
- Eigener Download-, Wiederaufnahme- und Prüfcode; Speicherplatz doppelt, bis das alte Modell gelöscht ist.
- Versionspaarung: App und Modell müssen zueinander passen (Manifest mit `min_app`/`format`).

F-Droid:
- Richtlinie: keine zusätzlichen ausführbaren Binärdateien ohne Zustimmung; die Regel betrifft Ausführbares, nicht Daten [Q7]. ONNX ist Daten, wird aber von einer Laufzeit „ausgeführt“. Grenzfall, nicht geprüft.
- Feste Download-Server können das Label NonFreeNet bekommen (Organic Maps, Streit um Wortlaut) [Q15].
- Nicht erlaubt: nicht offengelegte Anti-Features [Q7]. Also in der Beschreibung nennen.

## 3. Wie andere FOSS-Apps es lösen

- Organic Maps: Karten getrennt, `maps/{dataVersion}/{Datei}`; Deltas als `diffs/{dataVersion}/{diffVersion}/{Datei}` mit bsdiff, laut Beitrag 5–30 % der Originalgröße; der Server baut Diffs, offen ist, wie der Client sie findet [Q22]. Stand der Umsetzung in dieser Diskussion unklar. Das ist unser Modell 2c, plus Delta nur für Daten.
- Obtainium: GitHub-API, Filter, Token gegen das Limit [Q16]. Kein Delta. Wie es installiert: Seite sagt es nicht, nicht geprüft.
- Signal-Web-APK: Seite beschreibt nur die Zertifikatsprüfung vor der Installation; Play ist der empfohlene Weg [Q23]. Aussage zu einem eigenen Updater: nicht belegt, nicht geprüft.
- Tor Browser Android: Update über Play, F-Droid oder neue APK über die alte [Q24]. Kein Delta. Desktop hat einen eigenen Updater [Q24].
- F-Droid-Client: Delta für APKs nicht gefunden, nicht geprüft.

## 4. Installationsablauf

- Seit Android 8 ist „Unbekannte Apps installieren“ eine Berechtigung je Quelle; Manifest braucht `REQUEST_INSTALL_PACKAGES` (Ziel-API ≥ 26); Prüfung mit `canRequestPackageInstalls()`; Nutzer führt `ACTION_MANAGE_UNKNOWN_APP_SOURCES` an [Q5].
- `PackageInstaller`-Session statt Intent: Fortschritt und Ergebnis kommen per Callback `STATUS_PENDING_USER_ACTION`; der Installer muss damit rechnen [Q4].
- Ohne Rückfrage (Android 12+, `setRequireUserAction(USER_ACTION_NOT_REQUIRED)`, API 31) [Q4]. Bedingungen laut AOSP-Commit [Q6]: Installer hat `REQUEST_INSTALL_PACKAGES` und `UPDATE_PACKAGES_WITHOUT_USER_ACTION`; Ziel-API der App ≥ 29 (steigt in Zukunft); Installer ist Installer of Record (Update oder Selbst-Update). Die Doku sagt dazu: Sitzungsbesitzer müssen immer `STATUS_PENDING_USER_ACTION` behandeln [Q4]. Quelle ist der erste Commit von 2021; heutige Bedingungen: nicht geprüft.
- Wichtig für uns: Ist die erste Installation per Browser oder Dateimanager geschehen, ist unsere App nicht „Installer of Record“. Dann fragt Android. Erst Selbst-Updates nach einer Installation durch uns laufen leiser. Nicht in dieser Reihenfolge belegt, nicht geprüft.
- Android 14: `setRequestUpdateOwnership(true)` (API 34) setzt Update-Besitz bei Erstinstallation; andere Installer brauchen dann Nutzeraktion. Braucht `ENFORCE_UPDATE_OWNERSHIP`; bei Updates wirkungslos [Q4, Q25]. Die Berechtigung bekommt eine normale App vermutlich nicht: nicht geprüft. Kein Nutzen für uns, solange wir nur uns selbst aktualisieren.
- Paketquelle: `setPackageSource` (API 33) ist rein informativ [Q4].

## 5. Flutter-Pakete und Lizenzen

| Paket | Zweck | Lizenz | Hinweis |
|---|---|---|---|
| `ota_update` 7.1.0 | Download, SHA-256-Prüfung, Install per Intent oder PackageInstaller (opt-in) | MIT [Q13] | Manifest-Einträge nötig (Provider, Receiver, `REQUEST_INSTALL_PACKAGES`); iOS nicht nutzbar |
| `android_package_installer` 0.0.3 | Install per Package Installer | BSD-3 [Q14] | Nur Installation; Download selbst |
| `binary_patch` 1.0.0 | bsdiff | MIT oder BSD-3 (Widerspruch) [Q19] | unreif |
| `zstd_dart` 1.1.0 | zstd | MIT [Q20] | patch-from unklar |

Alle genannten sind MPL-2.0-verträglich (keine GPL). `ota_update` bringt Altlasten mit (WRITE_EXTERNAL_STORAGE); Alternative: 100 Zeilen Kotlin mit PackageInstaller, dann ohne Fremdcode. Pflegezustand der Pakete: nicht geprüft.

## 6. Empfohlene Reihenfolge

1. Stufe A (klein): Beim Start eine GET-Anfrage auf das neueste Release. Anzeigen: Version, `size`, `body`, Digest. Download erst nach Tipp. SHA-256 prüfen. Installieren per PackageInstaller.
2. Stufe B: Modelle als eigene Release-Dateien + `models.json` (Dateiname, Größe, SHA-256, `min_app`). Beim Update nur geänderte laden. Entscheidung zum Offline-Anspruch in `ENTSCHEIDUNGEN.md` eintragen. Vor Bau messen: echte APK-Größe ohne Modelle.
3. Stufe C erst nach Messung: zwei echte Releases lokal mit bsdiff, zstd und archive-patcher vergleichen. Nur bauen, wenn Rest-APK noch groß ist.
4. D streichen.

## Quellen

- Q1 https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/
- Q2 https://withone.ai/knowledge/github/conn_mod_def%3A%3AGJ3Z_wZw0GU%3A%3APX84CNMRTA2F4aOxZ-dNJw (Drittseite; GitHub-Doku gesperrt)
- Q3 https://docs.github.com/rest/using-the-rest-api/rate-limits-for-the-rest-api
- Q4 https://developer.android.com/reference/kotlin/android/content/pm/PackageInstaller.SessionParams (Abschnitte MODE_INHERIT_EXISTING, setRequireUserAction, setRequestUpdateOwnership, setPackageSource)
- Q5 https://android-developers.googleblog.com/2017/08/making-it-safer-to-get-apps-on-android-o.html
- Q6 https://android.googlesource.com/platform/frameworks/base/+/c17bbf82ce4b%5E%21/
- Q7 https://f-droid.org/uk/docs/Inclusion_Policy/
- Q8 https://source.android.com/docs/security/apksigning/v2
- Q9 https://github.com/oppia/archive-patcher (Fork von google/archive-patcher)
- Q10 Schlussfolgerung aus Q9 und Q4: Install-Sitzung erhält eine vollständige APK.
- Q11 https://9to5google.com/2016/12/07/google-made-application-updates-through-play-store-roughly-65-smaller/
- Q12 https://utzcoz.github.io/2026/03/07/aosp-split-apk-architecture.html (Drittanalyse)
- Q13 https://pub.dev/packages/ota_update/changelog und https://pub.dev/documentation/ota_update/latest/
- Q14 https://pub.dev/packages/android_package_installer/license
- Q15 https://gitlab.com/fdroid/fdroid-website/-/merge_requests/1070
- Q16 https://imranr98.github.io/Obtainium-Wiki/sources
- Q17 https://android.googlesource.com/platform/external/archive-patcher/+/refs/heads/main/METADATA
- Q18 https://github.com/facebook/zstd/wiki/Zstandard-as-a-patching-engine
- Q19 https://pub.dev/packages/binary_patch
- Q20 https://pub.dev/packages/zstd_dart
- Q21 https://developer.android.com/guide/app-bundle/configure-base
- Q22 https://github.com/organicmaps/organicmaps/issues/2317
- Q23 https://signal.org/android/apk
- Q24 https://support.torproject.org/tor-browser/getting-started/updating/
- Q25 https://source.android.com/docs/setup/create/app-ownership

## Nicht geprüft (Liste)

- `body`-Feld und Digest bei älteren Release-Dateien (GitHub-Doku gesperrt).
- Zählt `browser_download_url` zum API-Limit.
- Flutter-Assets aus Split-APK ohne Play; Split gleichen versionCodes mit neuem Inhalt.
- Heutige Bedingungen für Update ohne Rückfrage; Installer-of-Record bei Erstinstallation per Browser.
- Lesen der alten APK über `sourceDir`; echte Ersparnis von bsdiff/zstd/archive-patcher auf unseren APKs.
- Lizenz von archive-patcher (Apache-2.0 vs. „RECIPROCAL“) und von `binary_patch`.
- F-Droid-Einstufung von ONNX-Modellen als „ausführbar“; delta-Fähigkeit des F-Droid-Clients.
