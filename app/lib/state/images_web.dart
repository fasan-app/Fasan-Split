// Fasan Split – receipt photos in the browser: IndexedDB (database „fasan-split“, store „files“), mirrored in memory
// so the UI can ask synchronously. Paths look like „idb:<name>“. Stays on this device like on the phone.
// IndexedDB: developer.mozilla.org/docs/Web/API/IndexedDB_API. MPL-2.0
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

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

/// Loads all photos into memory once at start (receipts are small JPEGs).
Future<void> initImages() async {
  final db = await _database();
  if (db == null) return;
  try {
    final keys = await _req<JSArray<JSAny?>>(_tx(db, 'readonly').getAllKeys());
    for (final k in keys?.toDart ?? const <JSAny?>[]) {
      final name = (k as JSString).toDart;
      final v = await _req<JSUint8Array>(_tx(db, 'readonly').get(k));
      if (v != null) _mem['$_prefix$name'] = v.toDart;
    }
  } catch (_) {}
}

Future<String?> saveImage(String name, Uint8List bytes) async {
  final path = '$_prefix$name';
  _mem[path] = bytes;
  final db = await _database();
  if (db != null) {
    try {
      await _req<JSAny?>(_tx(db, 'readwrite').put(bytes.toJS, name.toJS));
    } catch (_) {}
  }
  return path;
}

bool imageExists(String? path) => path != null && _mem.containsKey(path);

Future<Uint8List?> readImage(String path) async => _mem[path];

void deleteImage(String path) {
  _mem.remove(path);
  final db = _open;
  if (db == null || !path.startsWith(_prefix)) return;
  try {
    _tx(db, 'readwrite').delete(path.substring(_prefix.length).toJS);
  } catch (_) {}
}

ImageProvider imageProvider(String path) => MemoryImage(_mem[path] ?? Uint8List(0));
