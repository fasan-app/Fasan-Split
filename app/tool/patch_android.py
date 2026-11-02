"""Ergänzt das von `flutter create` erzeugte Android-Projekt um Fasan Splits Vorgaben.

Vorlage: Fasan-Camera/app/tool/patch_android.py. Läuft in der CI nach `flutter create` (und lokal genauso).
- applicationId app.fasan.split, Name unter dem Symbol „Fasan Split“
- minSdk 26 (Android 8). Eigene Wahl für Split (Kamera: 30); ONNX Runtime braucht 21+, image_picker 21+.
- fester Signaturschlüssel: Ohne ihn erzeugt jeder CI-Runner einen eigenen Debug-Schlüssel, und Android lehnt jede
  neue APK als Update ab. Standard ist der Test-Schlüssel ci/fasan-split-test.p12 (öffentlich, nur für Tests!);
  mit den Secrets FASAN_KEYSTORE_B64 und FASAN_KEYSTORE_PASSWORD signiert die CI mit dem Release-Schlüssel.
- App-Symbol aus assets/icon/ (Fasan „Aufbruch“) in alle mipmap-Größen
"""
import pathlib
import re
import shutil
import sys

app = pathlib.Path(__file__).resolve().parent.parent
root = app / 'android' / 'app'
kts = root / 'build.gradle.kts'
manifest = root / 'src' / 'main' / 'AndroidManifest.xml'

# Pfad relativ zu app/android/app (dem Gradle-Projekt der App).
DEFAULT_KEYSTORE = '../../../ci/fasan-split-test.p12'

KTS_BLOCK = f'''
// Fasan: Ergänzungen nach `flutter create` (tool/patch_android.py)
android {{
    defaultConfig {{
        minSdk = 26
        manifestPlaceholders["fasanLabel"] = System.getenv("FASAN_LABEL") ?: "Fasan Split"
        // Nur arm64: Die CI baut Flutter nur für android-arm64. Ohne diesen Filter setzt das Flutter-Gradle-Plugin
        // (ab 3.35) armeabi-v7a, arm64-v8a und x86_64, und die APK trägt ONNX Runtime für zwei unbrauchbare
        // Architekturen mit (~37 MB). Quelle: docs.flutter.dev/release/breaking-changes/default-abi-filters-android
        ndk {{
            abiFilters.clear()
            abiFilters.addAll(listOf(System.getenv("FASAN_ABI") ?: "arm64-v8a")) // x86_64 only for emulator runs
        }}
    }}
    signingConfigs {{
        create("fasan") {{
            storeFile = file(System.getenv("FASAN_KEYSTORE") ?: "{DEFAULT_KEYSTORE}")
            storePassword = System.getenv("FASAN_KEYSTORE_PASSWORD") ?: "fasan-split-test"
            keyAlias = System.getenv("FASAN_KEY_ALIAS") ?: "fasan"
            keyPassword = System.getenv("FASAN_KEY_PASSWORD") ?: "fasan-split-test"
        }}
    }}
    buildTypes {{
        getByName("release") {{
            signingConfig = signingConfigs.getByName("fasan")
        }}
        getByName("debug") {{
            signingConfig = signingConfigs.getByName("fasan")
        }}
    }}
}}
'''

if not kts.exists():
    sys.exit('Kein build.gradle.kts gefunden – lief `flutter create`?')
s = kts.read_text()
s, n = re.subn(r'applicationId\s*=\s*"[^"]*"', 'applicationId = "app.fasan.split"', s)
if n != 1:
    sys.exit(f'applicationId nicht gefunden in {kts}')
if 'Fasan: Ergänzungen' not in s:
    s += KTS_BLOCK
kts.write_text(s)
print('build.gradle.kts angepasst')

m = manifest.read_text()
m, n = re.subn(r'android:label="[^"]*"', 'android:label="${fasanLabel}"', m, count=1)
if n != 1:
    sys.exit('android:label nicht gefunden im Manifest')
manifest.write_text(m)
print('Manifest angepasst')

icons = app / 'assets' / 'icon'
res = root / 'src' / 'main' / 'res'
for d in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
    src = icons / f'ic_launcher-{d}.png'
    if src.exists():
        shutil.copy(src, res / f'mipmap-{d}' / 'ic_launcher.png')
print('Symbole kopiert' if (icons / 'ic_launcher-mdpi.png').exists() else 'Keine Symbole in assets/icon (Standard bleibt)')
