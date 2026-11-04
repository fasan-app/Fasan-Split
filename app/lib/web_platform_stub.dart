// Fasan Split – phone and tests: no browser. MPL-2.0

/// The invitation code the page join/index.html left for the app, or null. Removes it after reading.
String? takeJoinCode() => null;

void clearJoinCode() {}

/// True when the server has a newer web build than the one running.
Future<bool> webUpdateAvailable() async => false;

/// Loads the page again (newer web build).
void reloadPage() {}

Future<bool> askPersistentStorage() async => false;

bool needsHomeScreenHint() => false;
