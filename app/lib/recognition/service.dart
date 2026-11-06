// Fasan Split – runs the recognition in a background isolate (UI stays smooth). MPL-2.0
//
// Models are loaded once from the app assets (rootBundle) and handed to the isolate as transferable bytes; the isolate
// keeps its ONNX sessions for further scans. Messages back: progress, preview (JPEG + boxes), result, error.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

import 'onnx.dart' if (dart.library.js_interop) 'onnx_web.dart';
import 'paddle.dart';
import 'pipeline.dart';
import 'scan_events.dart';
import 'browser.dart';

export 'scan_events.dart';

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
            final e = scanEventFrom(msg, _unwrap);
            if (e == null) return;
            job.add(e);
            if (e is ScanDone || e is ScanError) {
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
    // Browser: a Web Worker with ONNX Runtime Web does the same work (recognition_browser_web.dart).
    if (kIsWeb) return recognizeInBrowser(photo);
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
  static ScanResultData fromRecognition(Recognition x) => decodeRecognition(encodeRecognition(x, _wrap), _unwrap);


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
  // Jobs one after another: recognize() is async now (onnx_web.dart), two photos must not interleave in one Recognizer.
  var queue = Future<void>.value();
  inbox.listen((msg) {
    if (msg is! List || msg[0] != 'job') return;
    queue = queue.then((_) => _job(rec, out, msg));
  });
}

Object _wrap(Uint8List b) => TransferableTypedData.fromList([b]);

Uint8List _unwrap(Object? o) => (o as TransferableTypedData).materialize().asUint8List();

Future<void> _job(Recognizer rec, SendPort out, List msg) async {
    final id = msg[1] as int;
    try {
      final photo = (msg[2] as TransferableTypedData).materialize().asUint8List();
      final x = await rec.recognize(photo, onProgress: progressMessages(id, out.send, _wrap));
      out.send(['done', id, encodeRecognition(x, _wrap)]);
    } catch (e, st) {
      out.send(['error', id, '$e\n${st.toString().split('\n').take(4).join('\n')}']);
    }
}
