// SPDX-License-Identifier: MPL-2.0
// Fasan Split – browser helpers. MPL-2.0
// Invitation: join/index.html moves the code from the link fragment into sessionStorage and opens the app without the
// code in the address bar (the code is the group secret; it must not stay in the history).
// Update: the workflow web.yml writes the commit into build.txt and passes the same value as FASAN_BUILD at compile
// time; a different build.txt on the server means a newer version. Same-origin GET only.
// sessionStorage, fetch, location.reload: developer.mozilla.org; package:web (BSD-3, Dart team).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _key = 'fasan-join';
const _build = String.fromEnvironment('FASAN_BUILD');

/// Reads the code but keeps it in the tab until the join request is out ([clearJoinCode]): on the very first visit
/// coi-serviceworker reloads the page once, and a code removed before that reload was lost – the invited person landed
/// in an empty app (Nutzer 04.11., Lena).
String? takeJoinCode() {
  if (_urlCode != null) return _urlCode;
  try {
    final c = web.window.sessionStorage.getItem(_key);
    return c == null || c.isEmpty ? null : c;
  } catch (_) {
    return null; // storage blocked: the code came in the address (prepareWebStart)
  }
}

void clearJoinCode() {
  _urlCode = null;
  try {
    web.window.sessionStorage.removeItem(_key);
  } catch (_) {}
}

String? _urlCode;
bool _storageOk = true;

/// False when the browser refuses localStorage/sessionStorage (private window, blocked site data, some in-app
/// browsers): the app then keeps everything in memory and says so (04.11., stress test „nostorage“).
bool get browserStorageWorks => _storageOk;

/// First thing in main(): checks storage and takes an invitation code that join/index.html had to put into the address
/// (storage blocked), then removes it from the address bar and the history entry.
void prepareWebStart() {
  // write and read back: a bare property access may be dropped by the compiler (dart2js did, 04.11.)
  try {
    for (final st in [web.window.localStorage, web.window.sessionStorage]) {
      st.setItem('fasan-probe', '1');
      if (st.getItem('fasan-probe') != '1') _storageOk = false;
      st.removeItem('fasan-probe');
    }
  } catch (_) {
    _storageOk = false;
  }
  final h = web.window.location.hash;
  if (h.startsWith('#fasan-join=')) {
    _urlCode = h.substring('#fasan-join='.length);
    try {
      web.window.history.replaceState(null, '', web.window.location.pathname);
    } catch (_) {}
  }
}

Future<bool> webUpdateAvailable() async => (await webUpdateCheck()) == true;

/// Browser app (settings show the build instead of the APK version, the update button reloads the page).
const bool isBrowserApp = true;

/// Short id of the running build ("abc1234"), null for local builds without the define.
String? webBuildShort() => _build.isEmpty ? null : _build.substring(0, _build.length < 7 ? _build.length : 7);

/// Asks the server which build it holds: true = newer than the running one, false = same, null = no answer (offline, local build).
Future<bool?> webUpdateCheck() async {
  if (_build.isEmpty) return null; // local build without the define
  try {
    final r = await web.window.fetch('build.txt?t=${DateTime.now().millisecondsSinceEpoch}'.toJS, web.RequestInit(cache: 'no-store')).toDart;
    if (!r.ok) return null;
    final s = (await r.text().toDart).toDart.trim();
    if (s.isEmpty) return null;
    return s != _build;
  } catch (_) {
    return null;
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

/// Browser: no limits. image_picker_for_web re-encodes every photo whenever a limit or a quality is given (image_resizer.dart:
/// load into an <img>, draw on a canvas, toBlob on the main thread) – measured 07.11. for a 12 MP photo: a ~0.4–0.5 s freeze
/// (long task) and a lossy copy. The recognition worker reads the photo as it is (docs/WEB-GRENZEN.md, „Foto-Größe“).
double? get photoMaxSide => null;
int? get photoQuality => null;

String? _gl;

/// 'webgl2', 'webgl' or 'none': can the browser draw with the graphics chip? Flutter's CanvasKit draws on the processor, inside
/// WebAssembly, when no WebGL context can be made – measured 08.11. in Firefox without WebGL: ~130 ms per frame when scrolling the
/// list, 87 % of the time inside Skia `drawPicture` (Firefox profiler). The diagnosis log and a hint on the first screen say so.
String webGlInfo() => _gl ??= _probeGl();

String _probeGl() {
  for (final k in const ['webgl2', 'webgl']) {
    try {
      final c = web.document.createElement('canvas') as web.HTMLCanvasElement;
      if (c.getContext(k) != null) return k;
    } catch (_) {
      // not available in this browser or switched off (privacy settings, driver block list)
    }
  }
  return 'none';
}

/// Battery state, read once asynchronously (developer.mozilla.org: Navigator.getBattery, Chromium only, secure context).
/// Low battery switches the phone to power saving and lowers the frame rate, so runs with different levels do not compare.
Map<String, Object?>? _battery;
void readBatteryOnce() {
  try {
    final p = (web.window.navigator as JSObject).callMethod<JSPromise<JSObject>>('getBattery'.toJS);
    p.toDart.then((b) {
      _battery = {
        'prozent': ((b['level'] as JSNumber).toDartDouble * 100).round(),
        'ladend': (b['charging'] as JSBoolean).toDart,
      };
    }).catchError((_) {});
  } catch (_) {/* no battery API in this browser */}
}

/// Browser facts for the performance test (developer.mozilla.org: Navigator.userAgent, hardwareConcurrency, devicePixelRatio;
/// WEBGL_debug_renderer_info: UNMASKED_RENDERER_WEBGL 0x9246 names the real renderer, „SwiftShader“/„llvmpipe“ = drawn by software).
Map<String, Object?> deviceFacts() {
  String? renderer;
  try {
    final c = web.document.createElement('canvas') as web.HTMLCanvasElement;
    final gl = c.getContext('webgl2') ?? c.getContext('webgl');
    if (gl != null) {
      final ext = gl.callMethod<JSObject?>('getExtension'.toJS, 'WEBGL_debug_renderer_info'.toJS);
      if (ext != null) renderer = gl.callMethod<JSAny?>('getParameter'.toJS, 0x9246.toJS).dartify()?.toString();
    }
  } catch (_) {/* not readable */}
  final nav = web.window.navigator as JSObject;
  // Every probe is optional: browsers differ (Firefox has no deviceMemory/connection/userAgentData, privacy modes round values).
  Object? probe(Object? Function() f) {
    try {
      return f();
    } catch (_) {
      return null; // not available here
    }
  }

  Object? glParam(String name, int code) => probe(() {
        final c = web.document.createElement('canvas') as web.HTMLCanvasElement;
        final gl = c.getContext('webgl2') ?? c.getContext('webgl');
        return gl?.callMethod<JSAny?>('getParameter'.toJS, code.toJS).dartify();
      });
  bool media(String q) => web.window.matchMedia(q).matches;
  final conn = probe(() => nav['connection']) as JSObject?;
  final uad = probe(() => nav['userAgentData']) as JSObject?;
  return {
    'os': 'web',
    'browser': web.window.navigator.userAgent,
    // Low-entropy browser hints (developer.mozilla.org: Navigator.deviceMemory is rounded, max 8; connection = Chromium only).
    'speicherGB': probe(() => nav['deviceMemory'].dartify()),
    'sprache': web.window.navigator.language,
    'beruehrungspunkte': web.window.navigator.maxTouchPoints,
    'mobil': probe(() => uad?['mobile'].dartify()),
    'plattform': probe(() => uad?['platform'].dartify() ?? web.window.navigator.platform),
    'netz': {
      'typ': probe(() => conn?['effectiveType'].dartify()),
      'datensparen': probe(() => conn?['saveData'].dartify()),
      'online': web.window.navigator.onLine,
    },
    'systemEinstellung': {
      'animationenReduzieren': media('(prefers-reduced-motion: reduce)'),
      'dunkel': media('(prefers-color-scheme: dark)'),
      'hoherKontrast': media('(prefers-contrast: more)'),
      'sparmodusDaten': media('(prefers-reduced-data: reduce)'),
      'anzeigeStandalone': media('(display-mode: standalone)'),
      'bildwiederholungHoch': media('(update: fast)'),
    },
    'farbtiefe': web.window.screen.colorDepth,
    'sichtfenster': probe(() => '${web.window.visualViewport?.width}×${web.window.visualViewport?.height}@${web.window.visualViewport?.scale}'),
    'isolation': probe(() => (web.window as JSObject)['crossOriginIsolated'].dartify()), // needed for multi-threaded wasm
    'akku': _battery, // Chromium only; null elsewhere
    'grafikDetails': {
      'version': glParam('VERSION', 0x1F02),
      'anbieter': glParam('VENDOR', 0x1F00),
      'maxTextur': glParam('MAX_TEXTURE_SIZE', 0x0D33),
      'maxSampler': glParam('MAX_TEXTURE_IMAGE_UNITS', 0x8872),
    },
    'kerne': web.window.navigator.hardwareConcurrency,
    'pixelDichte': web.window.devicePixelRatio,
    'fenster': '${web.window.innerWidth}×${web.window.innerHeight}',
    'bildschirm': '${web.window.screen.width}×${web.window.screen.height}',
    'grafik': webGlInfo(),
    'renderer': renderer,
    'build': _build.isEmpty ? null : _build.substring(0, _build.length < 7 ? _build.length : 7),
  };
}
