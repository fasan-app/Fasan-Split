// SPDX-License-Identifier: MPL-2.0
// Fasan Split – thin wrapper around ONNX Runtime (C API via the onnxruntime_v2 plugin). MPL-2.0
//
// The plugin's high-level tensor API copies every element into nested Dart lists, which is far too slow for the text
// detection map (up to 2.4 million floats). Here input tensors are created from a native buffer and output data is
// read directly with GetTensorMutableData (ONNX Runtime C API, onnxruntime.ai/docs/api/c/struct_ort_api.html).
// Execution provider: CPU only, like the web app (onnxruntime-web, wasm): same results on every device.
// ignore_for_file: implementation_imports
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:onnxruntime_v2/src/bindings/onnxruntime_bindings_generated.dart' as bg;

class OnnxOutput {
  const OnnxOutput(this.data, this.dims);

  final Float32List data;
  final List<int> dims;
}

class OnnxModel {
  OnnxModel._(this._session);

  final OrtSession _session;
  static bool _envReady = false;

  static void ensureEnv() {
    if (_envReady) return;
    OrtEnv.instance.init();
    _envReady = true;
  }

  /// [threads]: intra-op threads (phones: 2–4; the web app runs single-threaded).
  /// Same as [fromBytes]; the browser version (onnx_web.dart) can only create sessions asynchronously.
  static Future<OnnxModel> load(Uint8List bytes, {int threads = 2}) async => fromBytes(bytes, threads: threads);

  static OnnxModel fromBytes(Uint8List bytes, {int threads = 2}) {
    ensureEnv();
    final o = OrtSessionOptions()
      ..setIntraOpNumThreads(threads)
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    final s = OrtSession.fromBuffer(bytes, o);
    o.release();
    return OnnxModel._(s);
  }

  String get inputName => _session.inputNames.first;

  /// Runs the model with one float32 input of [shape]; returns the first output.
  /// Async because the browser engine (onnx_web.dart, onnxruntime-web) only offers a Promise; here it finishes at once.
  Future<OnnxOutput> run(Float32List input, List<int> shape) async {
    final api = OrtEnv.instance.ortApiPtr.ref;
    final n = input.length;
    final dataPtr = calloc<ffi.Float>(n);
    dataPtr.asTypedList(n).setAll(0, input);
    final shapePtr = calloc<ffi.Int64>(shape.length);
    for (var i = 0; i < shape.length; i++) {
      shapePtr[i] = shape[i];
    }
    final memPP = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
    OrtStatus.checkOrtStatus(api.CreateCpuMemoryInfo.asFunction<bg.OrtStatusPtr Function(int, int, ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>)>()(
        bg.OrtAllocatorType.OrtDeviceAllocator, bg.OrtMemType.OrtMemTypeCPU, memPP));
    final valuePP = calloc<ffi.Pointer<bg.OrtValue>>();
    OrtStatus.checkOrtStatus(api.CreateTensorWithDataAsOrtValue.asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtMemoryInfo>, ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Int64>, int, int,
                ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
        memPP.value, dataPtr.cast(), n * 4, shapePtr, shape.length, bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, valuePP));
    final tensor = OrtValueTensor(valuePP.value, dataPtr.cast());
    api.ReleaseMemoryInfo.asFunction<void Function(ffi.Pointer<bg.OrtMemoryInfo>)>()(memPP.value);
    calloc.free(memPP);
    calloc.free(valuePP);
    calloc.free(shapePtr);
    final ro = OrtRunOptions();
    final outs = _session.run(ro, {inputName: tensor});
    ro.release();
    tensor.release(); // frees dataPtr too
    try {
      final out = outs.first!;
      return _read(out.ptr);
    } finally {
      for (final o in outs) {
        o?.release();
      }
    }
  }

  static OnnxOutput _read(ffi.Pointer<bg.OrtValue> v) {
    final api = OrtEnv.instance.ortApiPtr.ref;
    final infoPP = calloc<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>();
    OrtStatus.checkOrtStatus(api.GetTensorTypeAndShape.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>)>()(v, infoPP));
    final info = infoPP.value;
    final cntP = calloc<ffi.Size>();
    OrtStatus.checkOrtStatus(
        api.GetDimensionsCount.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Size>)>()(info, cntP));
    final nd = cntP.value;
    final dimsP = calloc<ffi.Int64>(nd);
    OrtStatus.checkOrtStatus(api.GetDimensions.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Int64>, int)>()(
        info, dimsP, nd));
    final dims = [for (var i = 0; i < nd; i++) dimsP[i]];
    api.ReleaseTensorTypeAndShapeInfo.asFunction<void Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>)>()(info);
    calloc.free(infoPP);
    calloc.free(cntP);
    calloc.free(dimsP);
    final count = dims.fold<int>(1, (a, d) => a * d);
    final dataPP = calloc<ffi.Pointer<ffi.Void>>();
    OrtStatus.checkOrtStatus(
        api.GetTensorMutableData.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(v, dataPP));
    final data = Float32List.fromList(dataPP.value.cast<ffi.Float>().asTypedList(count));
    calloc.free(dataPP);
    return OnnxOutput(data, dims);
  }

  void release() => _session.release();
}
