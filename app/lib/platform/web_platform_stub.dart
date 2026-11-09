// SPDX-License-Identifier: MPL-2.0
// Fasan Split – phone and tests: no browser. MPL-2.0
import 'dart:io' show Platform;

/// The invitation code the page join/index.html left for the app, or null. Removes it after reading.
String? takeJoinCode() => null;

void clearJoinCode() {}

/// True when the server has a newer web build than the one running.
Future<bool> webUpdateAvailable() async => false;

/// Phone and tests: not the browser app.
const bool isBrowserApp = false;
String? webBuildShort() => null;
Future<bool?> webUpdateCheck() async => null;

/// Loads the page again (newer web build).
void reloadPage() {}

Future<bool> askPersistentStorage() async => false;

bool needsHomeScreenHint() => false;

/// Native: storage always works, nothing to prepare (see web_platform_web.dart).
bool get browserStorageWorks => true;
void prepareWebStart() {}

/// Limits for the photo picker. Phone: cap the long side at 4000 px against memory spikes, quality 95 (the plugin re-encodes).
double? get photoMaxSide => 4000;
int? get photoQuality => 95;

/// Native: drawn with the graphics chip (Impeller/Skia), nothing to say (see web_platform_web.dart).
String webGlInfo() => 'native';

/// Native: nothing to read ahead (the browser build reads the battery asynchronously).
void readBatteryOnce() {}

/// Device facts for the performance test (the browser build answers with browser, graphics and screen).
Map<String, Object?> deviceFacts() => {'os': Platform.operatingSystem, 'version': Platform.operatingSystemVersion, 'kerne': Platform.numberOfProcessors};
