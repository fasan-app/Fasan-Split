// Fasan Split – browser helpers. MPL-2.0
// Invitation: join/index.html moves the code from the link fragment into sessionStorage and opens the app without the
// code in the address bar (the code is the group secret; it must not stay in the history).
// Update: the workflow web.yml writes the commit into build.txt and passes the same value as FASAN_BUILD at compile
// time; a different build.txt on the server means a newer version. Same-origin GET only.
// sessionStorage, fetch, location.reload: developer.mozilla.org; package:web (BSD-3, Dart team).
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _key = 'fasan-join';
const _build = String.fromEnvironment('FASAN_BUILD');

/// Reads the code but keeps it in the tab until the join request is out ([clearJoinCode]): on the very first visit
/// coi-serviceworker reloads the page once, and a code removed before that reload was lost – the invited person landed
/// in an empty app (Nutzer 04.11., Angi).
String? takeJoinCode() {
  final c = web.window.sessionStorage.getItem(_key);
  return c == null || c.isEmpty ? null : c;
}

void clearJoinCode() => web.window.sessionStorage.removeItem(_key);

Future<bool> webUpdateAvailable() async {
  if (_build.isEmpty) return false; // local build without the define
  try {
    final r = await web.window.fetch('build.txt?t=${DateTime.now().millisecondsSinceEpoch}'.toJS, web.RequestInit(cache: 'no-store')).toDart;
    if (!r.ok) return false;
    final s = (await r.text().toDart).toDart.trim();
    return s.isNotEmpty && s != _build;
  } catch (_) {
    return false;
  }
}

void reloadPage() => web.window.location.reload();

/// Asks the browser to keep IndexedDB and localStorage (no automatic eviction). Returns whether it is granted.
Future<bool> askPersistentStorage() async {
  try {
    return (await web.window.navigator.storage.persist().toDart).toDart;
  } catch (_) {
    return false;
  }
}

/// iPhone/iPad in Safari, not added to the home screen: Safari may delete the data after 7 days without a visit
/// (WebKit tracking prevention; home-screen apps are exempt).
bool needsHomeScreenHint() {
  final ua = web.window.navigator.userAgent;
  final ios = RegExp(r'iPhone|iPad|iPod').hasMatch(ua) || (ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);
  final standalone = web.window.matchMedia('(display-mode: standalone)').matches;
  return ios && !standalone;
}
