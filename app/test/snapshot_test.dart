// Writes what the user would see for every receipt in a folder (developer tool for the recognition gate):
// FASAN_BONORDNER=<folder> FASAN_SNAPSHOT=<out.json> LD_LIBRARY_PATH=… flutter test test/snapshot_test.dart
// Per receipt: items as the app builds them (name, quantity, unit price, amount, sure), total, checked, contradiction.
// Without FASAN_SNAPSHOT it does nothing. MPL-2.0
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:fasan_split/recognition/onnx.dart';
import 'package:fasan_split/recognition/paddle.dart';
import 'package:fasan_split/recognition/pipeline.dart';
import 'package:fasan_split/recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final out = Platform.environment['FASAN_SNAPSHOT'];
  final dir = Platform.environment['FASAN_BONORDNER'];
  test('snapshot', () async {
    if (out == null || dir == null) return;
    final m = 'assets/models';
    final uv = File('$m/uvdoc.onnx');
    final ocr = PaddleOcr(
      OnnxModel.fromBytes(File('$m/det.onnx').readAsBytesSync(), threads: 2),
      OnnxModel.fromBytes(File('$m/rec-latin.onnx').readAsBytesSync(), threads: 2),
      File('$m/dict-latin.txt').readAsStringSync(),
      uvdoc: uv.existsSync() ? OnnxModel.fromBytes(uv.readAsBytesSync(), threads: 2) : null,
    );
    final rec = Recognizer(ocr, earlyStop: Platform.environment['FASAN_EARLYSTOP'] != '0');
    final pick = RegExp(Platform.environment['FASAN_BONS'] ?? r'\.(png|jpg|jpeg)$', caseSensitive: false);
    final files = Directory(dir).listSync().whereType<File>().map((f) => f.path).where((p) => pick.hasMatch(p)).toList()..sort();
    final res = <String, Object?>{};
    for (final f in files) {
      final sw = Stopwatch()..start();
      final x = await rec.recognize(File(f).readAsBytesSync());
      final d = RecognitionService.fromRecognition(x);
      res[f.split('/').last] = {
        'total': d.total,
        'checked': d.checked,
        'contradiction': d.contradiction,
        'shop': d.shop,
        'ms': sw.elapsedMilliseconds,
        'items': [for (final i in d.items) {'name': i.name, 'qty': i.qty, 'unit': i.unit, 'amount': i.amount, 'sure': i.sure}],
      };
      // ignore: avoid_print
      print('SNAP ${f.split('/').last} ${d.items.length} Posten, Summe ${d.total}, geprüft ${d.checked}, ${sw.elapsedMilliseconds} ms');
    }
    File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(res));
  }, timeout: const Timeout(Duration(hours: 2)));
}
