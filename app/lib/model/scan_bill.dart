// Fasan Split – turns a recognition result into a bill (shared by the single-photo screen and the queue). MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import '../recognition/place.dart';
import '../recognition_service.dart';
import '../state/store.dart';
import 'bill.dart';
import 'category.dart';

/// Saves the scan image, the log and (unless [saveOriginal] is false) the photo as taken, and builds the bill from the result.
/// The header comes from the best read pass (bestHeader); the lines of the winner are only the fallback.
Future<Bill> billFromScan(ScanResultData r, Uint8List photo,
    {String? id, String? group, DateTime? created, bool saveOriginal = true}) async {
  id ??= DateTime.now().microsecondsSinceEpoch.toString();
  final img = await BillStore.saveFile('$id.jpg', r.display);
  // utf8, not codeUnits (UTF-16 units broke every character outside Latin-1 in 0.1.2)
  final log = await BillStore.saveFile('$id.log.json', Uint8List.fromList(utf8.encode(r.log)));
  // the photo exactly as taken (Beschluss 02.11.: Original immer sichtbar, für alle)
  final orig = saveOriginal ? await BillStore.saveFile('$id.orig.jpg', photo) : null;
  final meta = extractMeta([for (final l in r.lines) l.$1]);
  final b = Bill(
    id: id,
    receiptDate: r.date ?? meta.date,
    placeAddress: r.address ?? meta.address,
    taxId: r.taxId ?? meta.taxId,
    created: created ?? DateTime.now(),
    purpose: r.shop.isNotEmpty ? titleCase(r.shop) : r.kind,
    total: r.total,
    items: r.items,
    imagePath: img,
    imageAspect: r.width / r.height,
    checked: r.checked && !r.contradiction,
    advance: r.advance,
    logPath: log,
    originalPath: orig,
    group: group,
    originalQuad: r.photoQuad,
    originalAspect: r.photoAspect,
  );
  b.category = guessCategory(b); // first guess, changed with one tap (category.dart)
  return b;
}

String titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');
