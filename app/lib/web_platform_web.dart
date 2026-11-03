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

String? takeJoinCode() {
  final s = web.window.sessionStorage;
  final c = s.getItem(_key);
  s.removeItem(_key);
  return c == null || c.isEmpty ? null : c;
}

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
