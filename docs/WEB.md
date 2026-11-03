# Web-App und Einladungslinks

Adresse: https://fasan-app.github.io/Fasan-Split/ (Workflow `.github/workflows/web.yml`, bei jedem Push auf main).
Einladung: `https://fasan-app.github.io/Fasan-Split/join/#<code>`. Der Teil nach „#“ geht nie an einen Server.

## Was die Web-App kann

Dieselbe App wie auf dem Handy, im Browser gebaut. Beitreten, Bons ohne Foto, Saldo, Notizen, Chat. Bon-Lesen geht nicht:
ONNX Runtime läuft über `dart:ffi`, das gibt es im Browser nicht (`lib/recognition/onnx_web.dart` ersetzt es). Kamera und
Galerie sind im Web ausgeblendet, die Einführung auch. CanvasKit liegt mit auf der Seite (`--no-web-resources-cdn`),
im Test (Chromium, 03.11.) gab es keine Anfragen an fremde Hosts.

Ablauf einer Einladung im Browser: `web_extra/join/index.html` legt den Code in `sessionStorage` und öffnet `../` ohne Code
in der Adresszeile; `lib/web_platform_web.dart` liest und löscht ihn, die App öffnet „Gruppe beitreten“. Geprüft in Chromium.
Nicht geprüft: echter Beitritt aus dem Browser (würde öffentliche Relays nutzen), Schlüssel-Speicher im Browser
(flutter_secure_storage Web), Safari und Firefox.

## Einmalig einzurichten (Nutzer, GitHub-Oberfläche)

1. Fasan-Split → Settings → Pages → Source: „GitHub Actions“. Ohne das schlägt der Schritt „deploy“ fehl.
2. Damit https-Einladungen direkt die App öffnen (Android App Link): Android sucht die Datei an der Wurzel des Hosts,
   `https://fasan-app.github.io/.well-known/assetlinks.json` (developer.android.com/training/app-links/verify-android-applinks).
   Ein Projekt-Repo kann dort nichts ablegen. Dafür ein Repo `fasan-app/fasan-app.github.io` anlegen (öffentlich, Pages an)
   mit `.nojekyll` und dieser Datei unter `.well-known/assetlinks.json`:

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "app.fasan.split",
    "sha256_cert_fingerprints": [
      "7C:2B:13:B4:23:99:FA:7E:50:7C:34:15:2F:9A:BF:7B:FF:79:3C:DB:05:7F:C1:DD:79:90:AC:01:B2:BD:FE:A8",
      "57:68:A2:A6:C6:62:3E:5C:29:22:C1:CF:3E:1A:AD:BF:2F:AC:E3:FA:9C:F5:8E:37:88:EB:8A:2D:AC:E5:94:02"
    ]
  }
}]
```

Erledigt 03.11.: Datei liegt im Repo fasan-app.github.io. Erster Fingerabdruck: Release-Schlüssel (erzeugt 03.11., RSA 4096, 30 Jahre, nur als Secret). Zweiter: Testschlüssel `ci/fasan-split-test.p12` (laut `ci-logs/key.log` signiert die CI damit,
03.11.). Der Schlüssel ist öffentlich: jeder könnte eine App mit ihm signieren. Mit dem Release-Schlüssel (Secret
`FASAN_KEYSTORE_B64`) dessen Fingerabdruck dazuschreiben und den Testschlüssel später entfernen.
Ohne die Datei öffnet der Link den Browser; dort führt „In der App öffnen“ über `fasansplit://join` in die App.
