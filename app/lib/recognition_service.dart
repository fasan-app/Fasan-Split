// Fasan Split – runs the recognition in a background isolate (UI stays smooth). MPL-2.0
//
// Models are loaded once from the app assets (rootBundle) and handed to the isolate as transferable bytes; the isolate
// keeps its ONNX sessions for further scans. Messages back: progress, preview (JPEG + boxes), result, error.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import 'model/bill.dart';
import 'recognition/model.dart';
import 'recognition/onnx.dart' if (dart.library.js_interop) 'recognition/onnx_web.dart';
import 'recognition/paddle.dart';
import 'recognition/pipeline.dart';
import 'recognition/reader.dart' show suspiciousName;

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

class RecognitionService {
  RecognitionService._();

  static final instance = RecognitionService._();

  SendPort? _send;
  Future<void>? _starting;
  final _jobs = <int, StreamController<ScanEvent>>{};
  var _next = 0;

  Future<void> _start() => _starting ??= () async {
        Future<TransferableTypedData> asset(String name) async =>
            TransferableTypedData.fromList([(await rootBundle.load('assets/models/$name')).buffer.asUint8List()]);
        TransferableTypedData? uv;
        try {
          uv = await asset('uvdoc.onnx');
        } catch (_) {
          uv = null; // optional model
        }
        final recv = ReceivePort();
        final ready = Completer<void>();
        recv.listen((msg) {
          if (msg is SendPort) {
            _send = msg;
            return;
          }
          if (msg is List && msg.isNotEmpty) {
            if (msg[0] == 'ready') {
              ready.complete();
              return;
            }
            if (msg[0] == 'fatal') {
              if (!ready.isCompleted) ready.completeError(StateError(msg[1] as String));
              return;
            }
            final job = _jobs[msg[1] as int];
            if (job == null) return;
            switch (msg[0]) {
              case 'progress':
                job.add(ScanProgress(msg[2] as String, msg[3] as double));
              case 'preview':
                job.add(ScanPreview((msg[2] as TransferableTypedData).materialize().asUint8List(), (msg[3] as List).cast<List<double>>(), msg[4] as bool));
              case 'partial':
                job.add(ScanPartial(msg[2] as String, msg[3] as String?, msg[4] as String?, msg[5] as int?));
              case 'warp':
                job.add(ScanWarp((msg[2] as TransferableTypedData).materialize().asUint8List(), msg[3] as int, msg[4] as int, msg[5] as double,
                    msg[6] as double, (msg[7] as List).cast<double>(), (msg[8] as List).map((q) => (q as List).cast<double>()).toList()));
              case 'done':
                job.add(ScanDone(_decode(msg[2] as Map)));
                job.close();
                _jobs.remove(msg[1]);
              case 'error':
                job.add(ScanError(msg[2] as String));
                job.close();
                _jobs.remove(msg[1]);
            }
          }
        });
        await Isolate.spawn(_main, [recv.sendPort, await asset('det.onnx'), await asset('rec-latin.onnx'), utf8.decode((await rootBundle.load('assets/models/dict-latin.txt')).buffer.asUint8List()), uv]);
        await ready.future;
      }();

  /// Recognises one photo (JPEG/PNG bytes).
  Stream<ScanEvent> recognize(Uint8List photo) {
    final id = _next++;
    final c = StreamController<ScanEvent>();
    _jobs[id] = c;
    () async {
      try {
        c.add(ScanProgress('Erkennung wird geladen', 0.02));
        await _start();
        _send!.send(['job', id, TransferableTypedData.fromList([photo])]);
      } catch (e) {
        c.add(ScanError('$e'));
        await c.close();
        _jobs.remove(id);
      }
    }();
    return c.stream;
  }

  /// Same result as the worker sends, built in this isolate (tests, screenshots with real receipts).
  @visibleForTesting
  static ScanResultData fromRecognition(Recognition x) => _decode(_encode(x));

  static ScanResultData _decode(Map m) {
    final items = [for (final j in (m['items'] as List)) BillItem.fromJson((j as Map).cast<String, dynamic>())];
    return ScanResultData(
      items: items,
      total: m['total'] as int?,
      checked: m['checked'] as bool,
      contradiction: m['contradiction'] as bool,
      photoQuad: (m['photoQuad'] as List?)?.cast<double>(),
      photoAspect: (m['photoAspect'] as num?)?.toDouble(),
      display: (m['display'] as TransferableTypedData).materialize().asUint8List(),
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
}

// ---------------------------------------------------------------------------------------------------------------------
// isolate side

void _main(List<Object?> args) {
  final out = args[0] as SendPort;
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  late final Recognizer rec;
  try {
    final threads = math.max(2, math.min(4, Platform.numberOfProcessors));
    final det = OnnxModel.fromBytes((args[1] as TransferableTypedData).materialize().asUint8List(), threads: threads);
    final recm = OnnxModel.fromBytes((args[2] as TransferableTypedData).materialize().asUint8List(), threads: threads);
    final uvBytes = args[4] as TransferableTypedData?;
    final uv = uvBytes == null ? null : OnnxModel.fromBytes(uvBytes.materialize().asUint8List(), threads: threads);
    rec = Recognizer(PaddleOcr(det, recm, args[3] as String, uvdoc: uv));
    out.send(['ready']);
  } catch (e) {
    out.send(['fatal', '$e']);
    return;
  }
  inbox.listen((msg) {
    if (msg is! List || msg[0] != 'job') return;
    final id = msg[1] as int;
    try {
      final photo = (msg[2] as TransferableTypedData).materialize().asUint8List();
      var lastP = -1.0;
      final x = rec.recognize(photo, onProgress: (p) {
        final w = p.warp, pt = p.partial;
        if (pt != null) {
          out.send(['partial', id, pt.shop, pt.address, pt.date?.toIso8601String(), pt.total]);
        } else if (w != null) {
          out.send(['warp', id, TransferableTypedData.fromList([w.jpeg]), w.cols, w.rows, w.preAspect, w.scanAspect, w.src, w.quads]);
        } else if (p.preview != null) {
          out.send(['preview', id, TransferableTypedData.fromList([p.preview!]), p.boxes ?? const <List<double>>[], p.straight]);
        } else if (p.progress - lastP >= 0.01 || p.progress >= 1) {
          lastP = p.progress;
          out.send(['progress', id, p.stage, p.progress]);
        }
      });
      out.send(['done', id, _encode(x)]);
    } catch (e, st) {
      out.send(['error', id, '$e\n${st.toString().split('\n').take(4).join('\n')}']);
    }
  });
}

Map<String, Object?> _encode(Recognition x) {
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
    'display': TransferableTypedData.fromList([disp]),
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
