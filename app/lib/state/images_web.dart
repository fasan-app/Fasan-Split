// SPDX-License-Identifier: MPL-2.0
// Fasan Split – receipt photos in the browser: IndexedDB (database „fasan-split“, store „files“), mirrored in memory
// so the UI can ask synchronously. Paths look like „idb:<name>“. Stays on this device like on the phone.
// IndexedDB: developer.mozilla.org/docs/Web/API/IndexedDB_API. MPL-2.0
import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const _db = 'fasan-split', _store = 'files', _prefix = 'idb:';
final _mem = <String, Uint8List>{};
web.IDBDatabase? _open;

Future<T?> _req<T extends JSAny?>(web.IDBRequest r) {
  final c = Completer<T?>();
  r.onsuccess = ((web.Event _) => c.complete(r.result as T?)).toJS;
  r.onerror = ((web.Event _) => c.completeError(StateError('IndexedDB: ${r.error?.message}'))).toJS;
  return c.future;
}

Future<web.IDBDatabase?> _database() async {
  if (_open != null) return _open;
  try {
    final r = web.window.indexedDB.open(_db, 1);
    r.onupgradeneeded = (web.Event _) {
      (r.result as web.IDBDatabase).createObjectStore(_store);
    }.toJS;
    _open = await _req<web.IDBDatabase>(r);
  } catch (_) {
    _open = null; // private mode or blocked: photos stay for this visit only
  }
  return _open;
}

web.IDBObjectStore _tx(web.IDBDatabase db, String mode) => db.transaction(_store.toJS, mode).objectStore(_store);

/// Names stored in IndexedDB; the bytes load only when a photo is shown (06.11.: all photos were read into memory at start –
/// with the group's photos that slowed the start on weak phones, Nutzer: „selbst auf 10 Jahre alten Geräten“).
final _known = <String>{};

/// At start: only the list of stored photos (one IndexedDB request), no image bytes.
Future<void> initImages() async {
  final db = await _database();
  if (db == null) return;
  try {
    final keys = await _req<JSArray<JSAny?>>(_tx(db, 'readonly').getAllKeys());
    for (final k in keys?.toDart ?? const <JSAny?>[]) {
      _known.add('$_prefix${(k as JSString).toDart}');
    }
  } catch (_) {}
}

/// Recently shown photos stay in memory (a few receipts), older ones are read again from IndexedDB when needed.
const _keep = 16;
void _remember(String path, Uint8List bytes) {
  _mem.remove(path);
  _mem[path] = bytes;
  while (_mem.length > _keep) {
    _mem.remove(_mem.keys.first);
  }
}

Future<String?> saveImage(String name, Uint8List bytes) async {
  final path = '$_prefix$name';
  _remember(path, bytes);
  _known.add(path);
  final db = await _database();
  if (db != null) {
    try {
      await _req<JSAny?>(_tx(db, 'readwrite').put(bytes.toJS, name.toJS));
    } catch (_) {}
  }
  return path;
}

bool imageExists(String? path) => path != null && (_mem.containsKey(path) || _known.contains(path));

Future<Uint8List?> readImage(String path) async {
  final m = _mem[path];
  if (m != null) return m;
  final db = await _database();
  if (db == null || !path.startsWith(_prefix) || !_known.contains(path)) return null;
  try {
    final v = await _req<JSUint8Array>(_tx(db, 'readonly').get(path.substring(_prefix.length).toJS));
    if (v == null) return null;
    final bytes = v.toDart;
    _remember(path, bytes);
    return bytes;
  } catch (_) {
    return null;
  }
}

void deleteImage(String path) {
  _mem.remove(path);
  _known.remove(path);
  final db = _open;
  if (db == null || !path.startsWith(_prefix)) return;
  try {
    _tx(db, 'readwrite').delete(path.substring(_prefix.length).toJS);
  } catch (_) {}
}

ImageProvider imageProvider(String path) {
  final m = _mem[path];
  return m != null ? MemoryImage(m) : _IdbImage(path);
}

/// A photo that is not in memory yet: read from IndexedDB when the image is first painted.
class _IdbImage extends ImageProvider<_IdbImage> {
  const _IdbImage(this.path);
  final String path;

  @override
  Future<_IdbImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<_IdbImage>(this);

  @override
  ImageStreamCompleter loadImage(_IdbImage key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(() async {
        final bytes = await readImage(path);
        if (bytes == null || bytes.isEmpty) throw StateError('photo not found: $path');
        final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        return ImageInfo(image: (await codec.getNextFrame()).image);
      }());

  @override
  bool operator ==(Object other) => other is _IdbImage && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
