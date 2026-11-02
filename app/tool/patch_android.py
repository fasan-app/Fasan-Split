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
    // ota_update 7.x requires core library desugaring (its README „Migrating to 7.0.0+“; the plugin itself uses
    // desugar_jdk_libs 2.1.4). Java source/target level stays as flutter create set it.
    compileOptions {{
        isCoreLibraryDesugaringEnabled = true
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
dependencies {{
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
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
# In-app updates (ota_update, MIT; README „Android“): FileProvider + install result receiver inside <application>,
# res/xml/filepaths.xml for files/ota_update/. Permissions the plugin declares but Fasan Split does not need are removed
# (we download into the app's own files dir, and we are no system app): WRITE_EXTERNAL_STORAGE, INSTALL_PACKAGES,
# ACCESS_WIFI_STATE. Kept: INTERNET, ACCESS_NETWORK_STATE, REQUEST_INSTALL_PACKAGES (user confirms every install).
if 'ota_update_provider' not in m:
    m = m.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android"',
                  '<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools"', 1)
    remove = ''.join(f'    <uses-permission android:name="android.permission.{p}" tools:node="remove"/>\n'
                     for p in ('WRITE_EXTERNAL_STORAGE', 'INSTALL_PACKAGES', 'ACCESS_WIFI_STATE'))
    m = re.sub(r'(<manifest[^>]*>\n)', lambda x: x.group(1) + remove, m, count=1)
    provider = '''        <provider
            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
            android:authorities="${applicationId}.ota_update_provider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/filepaths" />
        </provider>
        <receiver android:name="sk.fourq.otaupdate.InstallResultReceiver" android:exported="false">
            <intent-filter>
                <action android:name="${applicationId}.ACTION_INSTALL_COMPLETE"/>
            </intent-filter>
        </receiver>
'''
    m = m.replace('</application>', provider + '    </application>', 1)
manifest.write_text(m)
xml = root / 'src' / 'main' / 'res' / 'xml'
xml.mkdir(parents=True, exist_ok=True)
(xml / 'filepaths.xml').write_text('<?xml version="1.0" encoding="utf-8"?>\n<paths xmlns:android="http://schemas.android.com/apk/res/android">\n    <files-path name="internal_apk_storage" path="ota_update/"/>\n</paths>\n')
print('Manifest angepasst')

icons = app / 'assets' / 'icon'
res = root / 'src' / 'main' / 'res'
for d in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
    src = icons / f'ic_launcher-{d}.png'
    if src.exists():
        shutil.copy(src, res / f'mipmap-{d}' / 'ic_launcher.png')
print('Symbole kopiert' if (icons / 'ic_launcher-mdpi.png').exists() else 'Keine Symbole in assets/icon (Standard bleibt)')
