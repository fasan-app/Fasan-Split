// SPDX-License-Identifier: MPL-2.0
// Fasan Split – browser-only helpers (conditional import): invitation handed over by join/index.html, update check,
// reload. On the phone and in tests the stub answers. MPL-2.0
export 'web_platform_stub.dart' if (dart.library.js_interop) 'web_platform_web.dart';
