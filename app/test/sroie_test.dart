// Echte Bons (SROIE 2019, gescannt, Malaysia): erkannte Summe gegen die Wahrheit. Gegenstück zu
// fasan-diagnose/tests/sroie.mjs (Web 3.19: 55/60, kein falsches „geprüft“).
// Daten nicht im Repo: git clone https://github.com/zzzDavid/ICDAR-2019-SROIE /home/claude/sroie
// Aufruf: LD_LIBRARY_PATH=… FASAN_SROIE=/home/claude/sroie flutter test test/sroie_test.dart; Bereich mit FASAN_VON/FASAN_BIS.
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:fasan_split/recognition/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ocr_cache.dart';

void main() {
  final env = Platform.environment;
  final root = env['FASAN_SROIE'] ?? '/home/claude/sroie';
  final ready = Directory('$root/data/img').existsSync() && File('assets/models/det.onnx').existsSync();
  test('SROIE Summe', () async {
    final threads = int.tryParse(env['FASAN_THREADS'] ?? '') ?? 2;
    final ocr = testOcr('assets/models', threads);
    final rec = Recognizer(ocr, earlyStop: env['FASAN_EARLYSTOP'] != '0');
    final from = int.tryParse(env['FASAN_VON'] ?? '') ?? 0, to = int.tryParse(env['FASAN_BIS'] ?? '') ?? 60;
    var ok = 0, n = 0, checked = 0, checkedWrong = 0;
    for (var k = from; k < to; k++) {
      final id = '$k'.padLeft(3, '0');
      final img = File('$root/data/img/$id.jpg');
      if (!img.existsSync()) continue;
      final truth = jsonDecode(File('$root/data/key/$id.json').readAsStringSync()) as Map<String, dynamic>;
      // Wie sroie.mjs: Wahrheit in Cent, alles außer Ziffern und Punkt entfernt, dann wie JavaScripts parseFloat
      // (führende Zahl). Leere Wahrheit (z. B. 033) ergibt dort NaN und zählt als falsch; hier null, ebenso.
      final lead = RegExp(r'^(\d+\.?\d*|\.\d+)').firstMatch('${truth['total']}'.replaceAll(RegExp(r'[^0-9.]'), ''));
      final want = lead == null ? null : (double.parse(lead.group(0)!) * 100).round();
      final sw = Stopwatch()..start();
      int? got;
      var sure = false, items = 0, source = '';
      try {
        cacheFor(ocr, img.path);
        final x = await rec.recognize(img.readAsBytesSync());
        cacheDone(ocr);
        got = x.result.total;
        sure = x.result.check.ok;
        items = x.result.items.length;
        source = x.source;
      } catch (e) {
        source = 'FEHLER $e'.substring(0, 60.clamp(0, 'FEHLER $e'.length));
      }
      n++;
      if (got == want) ok++;
      if (sure) {
        checked++;
        if (got != want) checkedWrong++;
      }
      // ignore: avoid_print
      print('$id soll $want ist $got ${got == want ? 'OK' : 'FALSCH'} geprüft $sure posten $items '
          '${(sw.elapsedMilliseconds / 1000).toStringAsFixed(0)}s [$source]');
    }
    // ignore: avoid_print
    print('GESAMT SROIE $from-$to dart: Summe richtig $ok/$n, als geprüft gemeldet $checked (davon falsch $checkedWrong)');
  }, skip: ready ? false : 'SROIE-Daten oder Modelle fehlen', timeout: const Timeout(Duration(hours: 3)));
}
