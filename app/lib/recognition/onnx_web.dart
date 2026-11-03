// Fasan Split – onnx.dart for the browser: the same models through onnxruntime-web (MIT, WebAssembly, CPU), which runs
// inside the recognition worker (web_worker.dart loads ort.wasm.min.js with importScripts). Same API as onnx.dart;
// sessions are created with load() because the browser can only do it asynchronously.
// API from the package typings (onnxruntime-common 1.22.0: inference-session.d.ts, tensor.d.ts, env.d.ts):
// InferenceSession.create(Uint8Array, options) → Promise; session.run({name: Tensor}) → Promise<{name: Tensor}>;
// new Tensor('float32', Float32Array, dims); env.wasm.numThreads = 1 (no SharedArrayBuffer without cross-origin
// isolation, which GitHub Pages cannot switch on). Results may differ from the phone in the last float digits. MPL-2.0
import 'dart:js_interop';
import 'dart:typed_data';

@JS('ort.InferenceSession.create')
external JSPromise<_Session> _create(JSUint8Array model, JSObject options);

extension type _Session._(JSObject _) implements JSObject {
  external JSArray<JSString> get inputNames;
  external JSArray<JSString> get outputNames;
  external JSPromise<JSObject> run(JSObject feeds);
  external JSPromise<JSAny?> release();
}

@JS('ort.Tensor')
extension type _Tensor._(JSObject _) implements JSObject {
  external factory _Tensor(String type, JSFloat32Array data, JSArray<JSNumber> dims);
  external JSFloat32Array get data;
  external JSArray<JSNumber> get dims;
}

extension type _Options._(JSObject _) implements JSObject {
  external factory _Options({JSArray<JSString> executionProviders, String graphOptimizationLevel});
}

extension on JSObject {
  external JSAny? operator [](String key);
  external void operator []=(String key, JSAny? value);
}

class OnnxOutput {
  const OnnxOutput(this.data, this.dims);

  final Float32List data;
  final List<int> dims;
}

class OnnxModel {
  OnnxModel._(this._s);

  final _Session _s;

  static void ensureEnv() {}

  /// Not possible in the browser (no synchronous session creation); use [load].
  static OnnxModel fromBytes(Uint8List bytes, {int threads = 2}) => throw UnsupportedError('Use OnnxModel.load in the browser.');

  static Future<OnnxModel> load(Uint8List bytes, {int threads = 2}) async {
    final s = await _create(bytes.toJS, _Options(executionProviders: ['wasm'.toJS].toJS, graphOptimizationLevel: 'all')).toDart;
    return OnnxModel._(s);
  }

  String get inputName => _s.inputNames.toDart.first.toDart;

  Future<OnnxOutput> run(Float32List input, List<int> shape) async {
    final feeds = JSObject();
    feeds[inputName] = _Tensor('float32', input.toJS, [for (final d in shape) d.toJS].toJS);
    final out = await _s.run(feeds).toDart;
    final t = out[_s.outputNames.toDart.first.toDart] as _Tensor;
    return OnnxOutput(Float32List.fromList(t.data.toDart), [for (final d in t.dims.toDart) d.toDartInt]);
  }

  void release() => _s.release();
}
