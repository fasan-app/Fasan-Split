// Fasan Split – events of one scan and their encoding as plain messages. Pure Dart: used by the background isolate
// (recognition_service.dart, bytes as TransferableTypedData) and by the browser worker (recognition/web_worker.dart,
// bytes as base64 in JSON). Both sides send the same lists: [type, job id, …]. MPL-2.0
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fasan_core/bill.dart';
import 'package:fasan_reader/model.dart';
import 'pipeline.dart';
import 'package:fasan_reader/reader.dart' show suspiciousName;

sealed class ScanEvent {}

class ScanProgress extends ScanEvent {
  ScanProgress(this.stage, this.progress);

  final String stage;
  final double progress;
}

class ScanPreview extends ScanEvent {
  ScanPreview(this.jpeg, this.boxes, this.straight);

  final Uint8List jpeg;
  final List<List<double>> boxes;
  final bool straight;
}

/// End of the scan animation: the kinked receipt (JPEG) straightens along a mesh; verified line boxes turn with it.
class ScanWarp extends ScanEvent {
  ScanWarp(this.jpeg, this.cols, this.rows, this.preAspect, this.scanAspect, this.src, this.quads);

  final Uint8List jpeg;
  final int cols, rows;
  final double preAspect, scanAspect;
  final List<double> src;
  final List<List<double>> quads;
}

/// First findings of the first pass: shop, address, date, total in cents.
class ScanPartial extends ScanEvent {
  ScanPartial(this.shop, this.address, this.dateIso, this.total);

  final String shop;
  final String? address, dateIso;
  final int? total;
}

class ScanDone extends ScanEvent {
  ScanDone(this.result);

  final ScanResultData result;
}

class ScanError extends ScanEvent {
  ScanError(this.message);

  final String message;
}

/// Plain result that crosses the isolate boundary.
class ScanResultData {
  ScanResultData({
    required this.items,
    required this.total,
    required this.checked,
    required this.contradiction,
    required this.display,
    required this.width,
    required this.height,
    required this.shop,
    required this.kind,
    required this.advance,
    required this.log,
    required this.lines,
    this.photoQuad,
    this.photoAspect,
    this.date,
    this.address,
    this.taxId,
  });

  final List<BillItem> items;
  final int? total;
  final bool checked, contradiction;

  /// Receipt corners in the photo as taken (8 numbers) and the photo's width / height; null without a cut-out.
  final List<double>? photoQuad;
  final double? photoAspect;
  final Uint8List display;
  final int width, height;
  final String shop, kind;
  final int advance;
  final String log;

  /// All lines with type (for the receipt view): (text, box, type, item index or -1).
  final List<(String, NBox, String, int)> lines;

  /// From the best read header of all passes (place.dart bestHeader), not only the item winner.
  final DateTime? date;
  final String? address, taxId;
}


/// The progress callback of [Recognizer.recognize] as messages (same order and throttling on phone and web).
void Function(RecognitionProgress) progressMessages(int id, void Function(List<Object?>) send, Object Function(Uint8List) wrap) {
  var lastP = -1.0;
  return (p) {
    final w = p.warp, pt = p.partial;
    if (pt != null) {
      send(['partial', id, pt.shop, pt.address, pt.date?.toIso8601String(), pt.total]);
    } else if (w != null) {
      send(['warp', id, wrap(w.jpeg), w.cols, w.rows, w.preAspect, w.scanAspect, w.src, w.quads]);
    } else if (p.preview != null) {
      send(['preview', id, wrap(p.preview!), p.boxes ?? const <List<double>>[], p.straight]);
    } else if (p.progress - lastP >= 0.01 || p.progress >= 1) {
      lastP = p.progress;
      send(['progress', id, p.stage, p.progress]);
    }
  };
}

/// One message back to the event of the scan; null for messages that are not about a job.
ScanEvent? scanEventFrom(List msg, Uint8List Function(Object?) unwrap) => switch (msg[0]) {
      'progress' => ScanProgress(msg[2] as String, (msg[3] as num).toDouble()),
      'preview' => ScanPreview(unwrap(msg[2]), [for (final b in msg[3] as List) [for (final v in b as List) (v as num).toDouble()]], msg[4] as bool),
      'partial' => ScanPartial(msg[2] as String, msg[3] as String?, msg[4] as String?, (msg[5] as num?)?.toInt()),
      'warp' => ScanWarp(unwrap(msg[2]), (msg[3] as num).toInt(), (msg[4] as num).toInt(), (msg[5] as num).toDouble(), (msg[6] as num).toDouble(),
          [for (final v in msg[7] as List) (v as num).toDouble()], [for (final q in msg[8] as List) [for (final v in q as List) (v as num).toDouble()]]),
      'done' => ScanDone(decodeRecognition(msg[2] as Map, unwrap)),
      'error' => ScanError(msg[2] as String),
      _ => null,
    };

ScanResultData decodeRecognition(Map m, Uint8List Function(Object?) unwrap) {
  final items = [for (final j in (m['items'] as List)) BillItem.fromJson((j as Map).cast<String, dynamic>())];
  return ScanResultData(
    items: items,
    total: m['total'] as int?,
    checked: m['checked'] as bool,
    contradiction: m['contradiction'] as bool,
    // toDouble per element: jsonDecode gives int for 0 / 1, and cast<double> on ints throws later in the WebAssembly build (dart2wasm keeps int and double apart)
    photoQuad: [for (final v in (m['photoQuad'] as List?) ?? const []) (v as num).toDouble()],
    photoAspect: (m['photoAspect'] as num?)?.toDouble(),
    display: unwrap(m['display']),
    width: m['width'] as int,
    height: m['height'] as int,
    shop: m['shop'] as String,
    date: DateTime.tryParse(m['date'] as String? ?? ''),
    address: m['address'] as String?,
    taxId: m['taxId'] as String?,
    kind: m['kind'] as String,
    advance: m['advance'] as int,
    log: m['log'] as String,
    lines: [for (final l in (m['lines'] as List)) (l[0] as String, NBox.fromJson(l[1])!, l[2] as String, l[3] as int)],
  );
}
Map<String, Object?> encodeRecognition(Recognition x, Object Function(Uint8List) wrap) {
  final r = x.result, W = x.display.w.toDouble(), H = x.display.h.toDouble();
  NBox nb(Box b) => NBox((b.x0 / W).clamp(0, 1), (b.y0 / H).clamp(0, 1), (b.x1 / W).clamp(0, 1), (b.y1 / H).clamp(0, 1));
  final items = <Map<String, Object?>>[];
  for (var i = 0; i < r.items.length; i++) {
    final p = r.items[i];
    // every line that belongs to the item (name above, quantity line, Pfand, Rabatt …) → one continuous shape
    final boxes = <NBox>[
      for (final l in r.lines)
        if (l.item == i && const ['posten', 'teil', 'pfand', 'rabatt', 'extra'].contains(l.type)) nb(l.box)
    ];
    if (boxes.isEmpty && p.frame != null) boxes.add(nb(p.frame!));
    final notes = [for (final z in p.extras) '${z.kind == 'pfand' ? 'Pfand' : z.kind == 'rabatt' ? 'Rabatt' : z.name} ${money(z.amount)}'];
    items.add(BillItem(
      name: p.name,
      amount: p.amount,
      qty: p.qty >= 1 && p.qty == p.qty.roundToDouble() ? p.qty.toInt() : 1,
      unit: p.unit?.round(),
      sure: p.sure && !suspiciousName(p.name),
      certainty: suspiciousName(p.name) ? math.min(p.certainty ?? 100, 58) : p.certainty,
      suggestions: p.suggestions,
      boxes: boxes,
      snippet: p.snippet == null ? null : Uint8List.fromList(p.snippet!),
      note: notes.isEmpty ? p.surcharge : notes.join(', '),
    ).toJson());
  }
  final disp = x.display.jpeg(85);
  return {
    'items': items,
    'total': r.total,
    'checked': r.check.ok,
    'contradiction': r.check.contradiction,
    'photoQuad': x.photoQuad,
    'photoAspect': x.photoAspect,
    'display': wrap(disp),
    'width': x.display.w,
    'height': x.display.h,
    // the header of all passes beats the winner's first line (Nutzer 02.11.: Name und Adresse „Unfug“)
    'shop': (x.header?.shop.isNotEmpty ?? false) ? x.header!.shop : '',
    'date': x.header?.meta.date?.toIso8601String(),
    'address': x.header?.meta.address,
    'taxId': x.header?.meta.taxId,
    'kind': r.kind?.name ?? '',
    'advance': r.advance,
    'log': jsonEncode(x.log),
    'lines': [for (final l in r.lines) [l.text, nb(l.box).toJson(), l.type, l.item ?? -1]],
  };
}
