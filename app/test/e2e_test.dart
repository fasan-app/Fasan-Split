// Ende-zu-Ende-Regression der Dart-Erkennung auf den synthetischen Test-Bons (fasan-diagnose/tests/bons).
// Vergleich wie e2e.mjs: Posten-Beträge als Menge (Pfand/Rabatt wieder getrennt) und Summe. Web 3.19: 11/11 + 30/30.
// Braucht: assets/models/*.onnx, libonnxruntime.so.1.22.0 im LD_LIBRARY_PATH, FASAN_DIAGNOSE=…/fasan-diagnose/tests.
// Aufruf: LD_LIBRARY_PATH=… FASAN_DIAGNOSE=… flutter test test/e2e_test.dart [--dart-define=…]; Auswahl mit FASAN_BONS=regex
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:fasan_split/recognition/onnx.dart';
import 'package:fasan_split/recognition/paddle.dart';
import 'package:fasan_split/recognition/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final diag = Platform.environment['FASAN_DIAGNOSE'] ?? '../../fasan-diagnose/tests';
  // FASAN_BONORDNER: anderer Ordner, z. B. fasan-diagnose/tests/echt (echte Bons, nur dort).
  final dir = Directory(Platform.environment['FASAN_BONORDNER'] ?? '$diag/bons');
  final ready = dir.existsSync() && File('assets/models/det.onnx').existsSync();
  test('e2e synthetische Bons', () {
    final threads = int.tryParse(Platform.environment['FASAN_THREADS'] ?? '') ?? 2;
    final uv = File('assets/models/uvdoc.onnx');
    final ocr = PaddleOcr(
      OnnxModel.fromBytes(File('assets/models/det.onnx').readAsBytesSync(), threads: threads),
      OnnxModel.fromBytes(File('assets/models/rec-latin.onnx').readAsBytesSync(), threads: threads),
      File('assets/models/dict-latin.txt').readAsStringSync(),
      uvdoc: uv.existsSync() && Platform.environment['FASAN_UVDOC'] != '0' ? OnnxModel.fromBytes(uv.readAsBytesSync(), threads: threads) : null,
    );
    final pick = RegExp(Platform.environment['FASAN_BONS'] ?? r'\.(png|jpg)$');
    final files = (dir.listSync().whereType<File>().map((f) => f.path).where((p) => RegExp(r'\.(png|jpg)$').hasMatch(p) && pick.hasMatch(p)).toList()..sort());
    final groups = <String, List<int>>{'png': [0, 0], 'jpg': [0, 0]};
    var postenOk = 0, postenAll = 0;
    final rec = Recognizer(ocr);
    for (final f in files) {
      final truth = jsonDecode(File(f.replaceFirst(RegExp(r'(-mild|-hart|-extrem|-kopf|-quer)?\.(png|jpg)$'), '.json')).readAsStringSync()) as Map<String, dynamic>;
      final sw = Stopwatch()..start();
      final x = rec.recognize(File(f).readAsBytesSync());
      final r = x.result;
      final ist = <int>[
        for (final q in r.items)
          if (q.extras.isNotEmpty) ...[q.amount - q.extras.fold<int>(0, (a, z) => a + z.amount), ...q.extras.map((z) => z.amount)] else q.amount
      ]..sort();
      final soll = (truth['posten'] as List).cast<int>().toList()..sort();
      final rest = List<int>.of(ist);
      var hit = 0;
      for (final s in soll) {
        final k = rest.indexOf(s);
        if (k >= 0) {
          hit++;
          rest.removeAt(k);
        }
      }
      final allRight = hit == soll.length && rest.isEmpty;
      final g = groups[f.endsWith('png') ? 'png' : 'jpg']!;
      g[1]++;
      if (allRight && r.total == truth['total']) g[0]++;
      postenOk += hit;
      postenAll += soll.length;
      // ignore: avoid_print
      print('${f.split('/').last.padRight(18)} ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s Posten $hit/${soll.length}${rest.isNotEmpty ? ' +${rest.length} falsch' : ''} '
          'Summe ${r.total == truth['total'] ? 'ok' : '${r.total}≠${truth['total']}'} geprüft ${r.check.ok ? 'ja' : 'nein'} [${x.source}; ${x.tries.join(' ')}]');
      if (!allRight) {
        // ignore: avoid_print
        print('    ${r.items.map((q) => '${q.name}=${q.amount}${q.sure ? '' : '?'}').join(' | ')}');
      }
    }
    // ignore: avoid_print
    print('GESAMT dart: png ${groups['png']![0]}/${groups['png']![1]}, jpg ${groups['jpg']![0]}/${groups['jpg']![1]} komplett richtig, Posten $postenOk/$postenAll');
  }, skip: ready ? false : 'Testbons oder Modelle fehlen', timeout: const Timeout(Duration(hours: 3)));
}
