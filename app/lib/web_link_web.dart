// Fasan Split – browser: join/index.html moves the code from the link fragment into sessionStorage and opens the app
// without the code in the address bar (the code is the group secret; it must not stay in the history). MPL-2.0
// sessionStorage: developer.mozilla.org/docs/Web/API/Window/sessionStorage; package:web (BSD-3, Dart team).
import 'package:web/web.dart' as web;

const _key = 'fasan-join';

/// The invitation code the page join/index.html left for the app, or null. Removes it after reading.
String? takeJoinCode() {
  final s = web.window.sessionStorage;
  final c = s.getItem(_key);
  s.removeItem(_key);
  return c == null || c.isEmpty ? null : c;
}
