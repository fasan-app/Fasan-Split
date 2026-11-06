// Prints what the recognizer reads in one image (developer tool, not part of the suite): FASAN_FILE=… LD_LIBRARY_PATH=…
// flutter test test/ocr_dump_test.dart. Without FASAN_FILE it does nothing. MPL-2.0
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:fasan_split/recognition/onnx.dart';
import 'package:fasan_split/recognition/paddle.dart';
import 'package:fasan_split/recognition/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final f = Platform.environment['FASAN_FILE'];
  test('dump', () async {
    if (f == null) return;
    final m = 'assets/models';
    final ocr = PaddleOcr(
      OnnxModel.fromBytes(File('$m/det.onnx').readAsBytesSync(), threads: 2),
      OnnxModel.fromBytes(File('$m/rec-latin.onnx').readAsBytesSync(), threads: 2),
      File('$m/dict-latin.txt').readAsStringSync(),
    );
    final x = await Recognizer(ocr, earlyStop: Platform.environment['FASAN_EARLYSTOP'] != '0').recognize(File(f).readAsBytesSync());
    for (final l in x.result.lines) {
      // ignore: avoid_print
      print('LINE ${l.type}|${l.text}');
    }
    for (final q in x.result.items) {
      // ignore: avoid_print
      print('ITEM ${q.name} = ${q.amount} qty ${q.qty} unit ${q.unit}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
