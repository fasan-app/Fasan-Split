// Fasan Split – backup of everything on this device into one file, and restoring it (Nutzer 03.11.: the switch to
// the release key needs one uninstall; nothing may get lost). Same file on phone and in the browser.
// Contents: bills (with photos and logs as base64), app and look settings; optionally the account (key, 12 words) and
// the shared groups (group keys, documents) – then the file is secret like the 12 words. Restoring adds bills that are
// not here yet (by id) and never deletes. MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import '../collab/service.dart';
import '../model/bill.dart';
import 'images.dart';
import 'store.dart';

const backupFormat = 'fasan-split-backup';

Future<Uint8List> makeBackup(BillStore store, {CollabService? collab}) async {
  final files = <String, String>{};
  for (final b in store.bills) {
    for (final p in [b.imagePath, b.originalPath, b.logPath]) {
      if (p == null) continue;
      final bytes = await readImage(p);
      if (bytes != null) files[p] = base64Encode(bytes);
    }
  }
  final m = <String, Object?>{
    'format': backupFormat,
    'v': 1,
    'created': DateTime.now().toIso8601String(),
    'bills': [for (final b in store.bills) b.toJson()],
    'files': files,
    'app': store.appSettings,
    'look': store.settingsJson,
    if (collab != null) 'secret': await collab.exportSecrets(),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(m)));
}

/// What a restore did: bills added, bills that were already here, whether the account and groups came back.
typedef RestoreResult = ({int added, int skipped, bool secret});

/// Throws [FormatException] for a file that is not a backup.
Future<RestoreResult> restoreBackup(BillStore store, Uint8List data, {CollabService? collab}) async {
  final Object? j;
  try {
    j = jsonDecode(utf8.decode(data));
  } catch (_) {
    throw const FormatException('not a backup');
  }
  if (j is! Map || j['format'] != backupFormat) throw const FormatException('not a backup');
  final files = (j['files'] as Map? ?? const {}).cast<String, String>();
  final have = {for (final b in store.bills) b.id};
  var added = 0, skipped = 0;
  for (final raw in (j['bills'] as List? ?? const [])) {
    final b = Bill.fromJson((raw as Map).cast<String, dynamic>());
    if (have.contains(b.id)) {
      skipped++;
      continue;
    }
    // photos get a new place on this device (other folder after reinstall, IndexedDB in the browser)
    Future<String?> put(String? old, String suffix) async {
      final s = old == null ? null : files[old];
      return s == null ? null : saveImage('${b.id}$suffix', base64Decode(s));
    }

    b.imagePath = await put(b.imagePath, _ext(b.imagePath, '.jpg'));
    b.originalPath = await put(b.originalPath, '.orig${_ext(b.originalPath, '.jpg')}');
    b.logPath = await put(b.logPath, '.log.json');
    store.bills.add(b);
    added++;
  }
  if (store.appSettings.isEmpty && j['app'] is Map) store.appSettings = (j['app'] as Map).cast<String, Object?>();
  if (store.settingsJson == null && j['look'] is String) store.saveSettings(j['look'] as String);
  store.upsertAll();
  var secret = false;
  if (collab != null && j['secret'] is Map) secret = await collab.importSecrets((j['secret'] as Map).cast<String, Object?>());
  return (added: added, skipped: skipped, secret: secret);
}

String _ext(String? p, String fallback) {
  if (p == null) return fallback;
  final i = p.lastIndexOf('.');
  return i < 0 ? fallback : p.substring(i);
}
