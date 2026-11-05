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
  b.alignSigns(); // „-198,00“ printed for a charge: items and total must agree in sign before the difference is looked at
  b.category = guessCategory(b); // first guess, changed with one tap (category.dart)
  // Amount without an item line, visible only in the VAT table as a 0 % row (Ferreiras LX 04.11.: „0.00 e 7.90 e 0.00
  // e 7.90“, items 79,00, total 86,90): added as its own item, marked unsure, so the bill adds up and nothing is lost.
  final sum = b.its.fold<int>(0, (a, x) => a + x.amount);
  final diff = (b.total ?? 0) - sum;
  if (diff > 0) {
    final euros = '${diff ~/ 100}', cents = (diff % 100).toString().padLeft(2, '0');
    final amount = RegExp('(^|\\s)$euros[.,]$cents(\\s|\$)');
    final zeroRow = r.lines.map((l) => l.$1).any((t) => RegExp(r'^\s*0[.,]00\b').hasMatch(t) && amount.hasMatch(t));
    // Nutzer 04.11.: the 7,90 must be visible and shared like the items. Any amount the receipt has more than its items
    // becomes its own line; a usual service share (5, 10, 12, 15 % of the items) is named so.
    b.its.add(BillItem(name: remainderName(diff, sum, zeroRow: zeroRow), amount: diff, sure: false, note: 'anteilig verteilt', proportional: true));
  }
  return b;
}

/// Name of the line for what a receipt has more than its items: „Bedienung 10 %“ when it is a usual service share,
/// else where it came from.
String remainderName(int diff, int itemSum, {bool zeroRow = false}) {
  for (final p in const [5, 10, 12, 15]) {
    if (itemSum > 0 && (itemSum * p / 100 - diff).abs() <= 1) return 'Bedienung $p %';
  }
  return zeroRow ? 'Ohne Postenzeile (0 % MwSt.)' : 'Ohne Postenzeile';
}

String titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');
