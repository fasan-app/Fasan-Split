// Fasan Split – browser side of the recognition worker (recognition/web_worker.dart). Starts the worker once and keeps
// it, like the isolate on the phone. Relative URLs are resolved against document.baseURI (<base href="/Fasan-Split/">).
// Web Worker: developer.mozilla.org/docs/Web/API/Worker. MPL-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'recognition/scan_events.dart';

web.Worker? _worker;
Future<void>? _ready;
final _jobs = <int, StreamController<ScanEvent>>{};
var _next = 0;

Uint8List _unwrap(Object? o) => base64Decode(o as String);

Future<void> _start() => _ready ??= () {
      final base = web.document.baseURI;
      String at(String p) => Uri.parse(base).resolve(p).toString();
      final ready = Completer<void>();
      final w = web.Worker(at('recognition_worker.js').toJS);
      w.onmessage = (web.MessageEvent e) {
        final msg = jsonDecode((e.data as JSString).toDart) as List;
        if (msg[0] == 'ready') return ready.complete();
        if (msg[0] == 'fatal') {
          if (!ready.isCompleted) ready.completeError(StateError(msg[1] as String));
          return;
        }
        final job = _jobs[msg[1] as int];
        final ev = scanEventFrom(msg, _unwrap);
        if (job == null || ev == null) return;
        job.add(ev);
        if (ev is ScanDone || ev is ScanError) {
          job.close();
          _jobs.remove(msg[1]);
        }
      }.toJS;
      w.onerror = (web.Event e) {
        if (!ready.isCompleted) ready.completeError(StateError('Worker konnte nicht starten'));
      }.toJS;
      w.postMessage(jsonEncode(['init', at('assets/assets/models/'), at('ort/')]).toJS);
      _worker = w;
      return ready.future;
    }();

Stream<ScanEvent> recognizeInBrowser(Uint8List photo) {
  final id = _next++;
  final c = StreamController<ScanEvent>();
  _jobs[id] = c;
  () async {
    try {
      c.add(ScanProgress('Erkennung wird geladen', 0.02));
      await _start();
      _worker!.postMessage(jsonEncode(['job', id, base64Encode(photo)]).toJS);
    } catch (e) {
      _ready = null; // next photo tries again
      c.add(ScanError('$e'));
      await c.close();
      _jobs.remove(id);
    }
  }();
  return c.stream;
}
