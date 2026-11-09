// SPDX-License-Identifier: MPL-2.0
// Fasan Split – where receipt photos live: files on the phone (images_io.dart), IndexedDB in the browser
// (images_web.dart). The bill keeps a path string either way; the UI asks here instead of using dart:io. MPL-2.0
export 'images_io.dart' if (dart.library.js_interop) 'images_web.dart';
