// SPDX-License-Identifier: MPL-2.0
// Stress test of the recognition: every receipt of a corpus folder is read again in variants – other resolution, tilt, brightness, blur,
// JPEG quality – and compared with the same truth. Two hard rules:
//  1. NEVER „geprüft“ (check.ok) with wrong items – the error of 05.11. (Bäckerei Probe at full phone resolution: three nameless
//     „Posten“ and a checked sum). Not one false „geprüft“ in any variant.
//  2. A minimum share of the variants must come out completely right (FASAN_MINRATE, default 0.85).
// Corpus: fasan-diagnose/tests/echt (real receipts, only there, never in an app repo). Models and ONNX runtime as for e2e_test.dart.
// Call: LD_LIBRARY_PATH=… FASAN_BONORDNER=…/tests/echt flutter test test/variants_test.dart; choose with FASAN_BONS=regex and
// FASAN_VARIANTEN=up2,s60,… (default: all below). One run is ~15 s per variant on two cores: run it as a background script.
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fasan_split/recognition/onnx.dart';
import 'package:fasan_split/recognition/paddle.dart';
import 'package:fasan_split/recognition/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

typedef _Make = img.Image Function(img.Image src);

img.Image _scale(img.Image s, double k) => img.copyResize(s, width: (s.width * k).round(), height: (s.height * k).round(), interpolation: img.Interpolation.cubic);

final Map<String, _Make> _variants = {
  'up2': (s) => _scale(s, 2.0),
  'up3': (s) => _scale(s, 3.0),
  's60': (s) => _scale(s, 0.6),
  's40': (s) => _scale(s, 0.4),
  'r4': (s) => img.copyRotate(s, angle: 4, interpolation: img.Interpolation.cubic),
  'rm7': (s) => img.copyRotate(s, angle: -7, interpolation: img.Interpolation.cubic),
  'dark': (s) => img.adjustColor(s, brightness: 0.7, contrast: 1.1),
  'bright': (s) => img.adjustColor(s, brightness: 1.3, contrast: 0.9),
  'blur': (s) => img.gaussianBlur(s, radius: 2),
  'q30': (s) => s, // re-encoded at JPEG quality 30 below
};

void main() {
  final env = Platform.environment;
  final diag = env['FASAN_DIAGNOSE'] ?? '../../fasan-diagnose/tests';
  final dir = Directory(env['FASAN_BONORDNER'] ?? '$diag/echt');
  final ready = dir.existsSync() && File('assets/models/det.onnx').existsSync();
  test('Stresstest: Varianten jedes Bons (Auflösung, Drehung, Helligkeit, Unschärfe, JPEG)', () async {
    final uv = File('assets/models/uvdoc.onnx');
    final ocr = PaddleOcr(
      OnnxModel.fromBytes(File('assets/models/det.onnx').readAsBytesSync(), threads: int.tryParse(env['FASAN_THREADS'] ?? '') ?? 2),
      OnnxModel.fromBytes(File('assets/models/rec-latin.onnx').readAsBytesSync(), threads: int.tryParse(env['FASAN_THREADS'] ?? '') ?? 2),
      File('assets/models/dict-latin.txt').readAsStringSync(),
      uvdoc: uv.existsSync() ? OnnxModel.fromBytes(uv.readAsBytesSync(), threads: int.tryParse(env['FASAN_THREADS'] ?? '') ?? 2) : null,
    );
    final rec = Recognizer(ocr, earlyStop: true);
    final pick = RegExp(env['FASAN_BONS'] ?? r'\.jpg$');
    final names = (env['FASAN_VARIANTEN'] ?? _variants.keys.join(',')).split(',').where(_variants.containsKey).toList();
    final files = dir.listSync().whereType<File>().map((f) => f.path).where((p) => p.endsWith('.jpg') && pick.hasMatch(p)).toList()..sort();
    var total = 0, right = 0;
    final falseChecked = <String>[], wrong = <String>[];
    for (final f in files) {
      final truth = jsonDecode(File(f.replaceFirst(RegExp(r'\.jpg$'), '.json')).readAsStringSync()) as Map<String, dynamic>;
      final soll = (truth['posten'] as List).cast<int>().toList()..sort();
      final src = img.decodeImage(File(f).readAsBytesSync())!;
      for (final v in names) {
        final bytes = img.encodeJpg(_variants[v]!(src), quality: v == 'q30' ? 30 : 88);
        final x = await rec.recognize(bytes);
        final r = x.result;
        final ist = <int>[
          for (final q in r.items)
            if (q.extras.isNotEmpty) ...[q.amount - q.extras.fold<int>(0, (a, z) => a + z.amount), ...q.extras.map((z) => z.amount)] else q.amount
        ]..sort();
        final same = ist.length == soll.length && List.generate(ist.length, (i) => ist[i] == soll[i]).every((e) => e) && r.total == truth['total'];
        total++;
        if (same) right++;
        final tag = '${f.split('/').last} / $v';
        if (!same) {
          wrong.add('$tag: ${r.items.map((q) => '${q.name}=${q.amount}${q.sure ? '' : '?'}').join(' | ')} total ${r.total} (want $soll, ${truth['total']}) checked=${r.check.ok}');
          if (r.check.ok) falseChecked.add(tag);
        }
        // ignore: avoid_print
        print('${same ? 'OK    ' : 'FALSCH'} $tag ${r.check.ok ? 'geprüft' : 'nicht geprüft'}');
      }
    }
    final rate = total == 0 ? 1.0 : right / total;
    // ignore: avoid_print
    print('GESAMT Varianten: $right/$total komplett richtig (${(rate * 100).toStringAsFixed(1)} %), falsch aber „geprüft“: ${falseChecked.length}');
    for (final w in wrong) {
      // ignore: avoid_print
      print('  $w');
    }
    expect(falseChecked, isEmpty, reason: 'a wrong reading must never count as checked');
    expect(rate, greaterThanOrEqualTo(double.tryParse(env['FASAN_MINRATE'] ?? '') ?? 0.85), reason: 'too many variants are read wrong');
    expect(math.min(total, 1), 1);
  }, skip: ready ? false : 'Testbons oder Modelle fehlen', timeout: const Timeout(Duration(hours: 4)));
}
