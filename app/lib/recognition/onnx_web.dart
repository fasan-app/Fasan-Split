// Fasan Split – stand-in for onnx.dart in the web build. ONNX Runtime is used through dart:ffi, which does not exist in
// the browser (dart2js: "Dart library 'dart:ffi' is not available on this platform"). The web app joins groups and
// shows bills, balances, notes and chat; it does not read receipts. Same API as onnx.dart, every call fails. MPL-2.0
import 'dart:typed_data';

class OnnxOutput {
  const OnnxOutput(this.data, this.dims);

  final Float32List data;
  final List<int> dims;
}

class OnnxModel {
  OnnxModel._();

  static void ensureEnv() {}

  static OnnxModel fromBytes(Uint8List bytes, {int threads = 2}) => throw UnsupportedError('Receipt reading is not available on the web.');

  OnnxOutput run(Float32List input, List<int> shape) => throw UnsupportedError('Receipt reading is not available on the web.');

  void release() {}
}
