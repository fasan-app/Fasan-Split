// Fasan Split – recognition in the browser: entry point of a Web Worker (compiled on its own with
// `dart compile js -o build/web/recognition_worker.js lib/recognition/web_worker.dart`, see .github/workflows/web.yml).
// Same job as the background isolate in recognition_service.dart: the page stays smooth while a receipt is read.
// Messages are JSON strings in both directions, bytes as base64; the lists are the same as the isolate's
// (scan_events.dart). Models come from the web build's assets, ONNX Runtime Web from <base>/ort/. MPL-2.0
// importScripts, fetch, postMessage in workers: developer.mozilla.org/docs/Web/API/DedicatedWorkerGlobalScope.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'onnx.dart' if (dart.library.js_interop) 'onnx_web.dart';
import 'paddle.dart';
import 'pipeline.dart';
import 'scan_events.dart';

@JS('self')
external web.DedicatedWorkerGlobalScope get _self;

@JS('importScripts')
external void _importScripts(JSString url);

@JS('ort.env.wasm')
external JSObject get _wasmEnv;

extension on JSObject {
  external void operator []=(String key, JSAny? value);
}

Future<Uint8List> _fetch(String url) async {
  final r = await _self.fetch(url.toJS).toDart;
  if (!r.ok) throw StateError('$url: ${r.status}');
  return (await r.arrayBuffer().toDart).toDart.asUint8List();
}

void main() {
  Future<Recognizer>? ready;
  var queue = Future<void>.value();
  void send(List<Object?> m) => _self.postMessage(jsonEncode(m).toJS);

  Future<Recognizer> start(String models, String ort) async {
    _importScripts('${ort}ort.wasm.min.js'.toJS);
    _wasmEnv['wasmPaths'] = ort.toJS;
    _wasmEnv['numThreads'] = 1.toJS;
    final det = await OnnxModel.load(await _fetch('${models}det.onnx'));
    final rec = await OnnxModel.load(await _fetch('${models}rec-latin.onnx'));
    final dict = utf8.decode(await _fetch('${models}dict-latin.txt'));
    OnnxModel? uv;
    try {
      uv = await OnnxModel.load(await _fetch('${models}uvdoc.onnx'));
    } catch (_) {
      uv = null; // optional model, like on the phone
    }
    return Recognizer(PaddleOcr(det, rec, dict, uvdoc: uv));
  }

  _self.onmessage = (web.MessageEvent e) {
    final msg = jsonDecode((e.data as JSString).toDart) as List;
    if (msg[0] == 'init') {
      ready = start(msg[1] as String, msg[2] as String);
      ready!.then((_) => send(['ready']), onError: (Object err) => send(['fatal', '$err']));
      return;
    }
    if (msg[0] != 'job') return;
    final id = msg[1] as int;
    queue = queue.then((_) async {
      try {
        final rec = await ready!;
        final x = await rec.recognize(base64Decode(msg[2] as String), onProgress: progressMessages(id, send, base64Encode));
        send(['done', id, encodeRecognition(x, base64Encode)]);
      } catch (err, st) {
        send(['error', id, '$err\n${st.toString().split('\n').take(4).join('\n')}']);
      }
    });
  }.toJS;
}
