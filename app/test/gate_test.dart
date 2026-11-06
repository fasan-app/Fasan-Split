// Recognition gate (Nutzer 06.11.: „Erkennung darf nie wieder unbemerkt schlechter werden“). Unlike e2e_test.dart, which only prints,
// this test FAILS. For every photo in FASAN_BONORDNER (folders separated by ':') with a truth JSON next to it, it checks what the user
// sees (items as the app builds them, RecognitionService.fromRecognition):
//   - total and the multiset of item amounts (truth `posten`, cents),
//   - per item, where the truth has `posten_detail` [{name, menge, betrag, einzel?}]: an item with that amount, that quantity and a
//     matching name (normalised, small edit distance) – „13 Croissants“ (06.11.) only shows here, the amounts were right,
//   - „geprüft“ on a wrong result is the worst failure and is never allowed.
// A receipt may carry `bekannt: "<reason>"` in its truth: its failure is reported but allowed (known, documented, to be fixed).
// Run: FASAN_BONORDNER=…/tests/echt:…/tests/bons LD_LIBRARY_PATH=…/onnxruntime/lib flutter test test/gate_test.dart
// Without FASAN_BONORDNER the test is skipped (CI sets it from the private fasan-diagnose checkout). MPL-2.0
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fasan_split/recognition/onnx.dart';
import 'package:fasan_split/recognition/paddle.dart';
import 'package:fasan_split/recognition/pipeline.dart';
import 'package:fasan_split/recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';

String norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[àáâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c')
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp('[^a-z0-9]'), '');

int lev(String a, String b) {
  final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0)..[0] = i);
  for (var j = 1; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      d[i][j] = math.min(math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
  }
  return d[a.length][b.length];
}

/// The name is good enough when it is the printed name up to small OCR slips: edit distance ≤ 15 % of the letters (at least 1).
/// Leftovers like „Cafe Duplo nm“, „TULIPA 238“, „í Cesta de pao“ count as wrong – the user sees them (Nutzer 06.11.).
bool nameOk(String truth, String read) {
  final t = norm(truth), r = norm(read);
  if (t.isEmpty) return true;
  // a short foreign word at the start or end (≤ 3 characters, not part of the printed name) is OCR debris, not a slip
  final tw = truth.split(RegExp(r'\s+')).map(norm).where((w) => w.isNotEmpty).toSet();
  final rw = read.split(RegExp(r'\s+')).map(norm).where((w) => w.isNotEmpty).toList();
  if (rw.length > tw.length) {
    for (final w in [rw.first, rw.last]) {
      if (w.length <= 3 && !tw.contains(w)) return false;
    }
  }
  return lev(t, r) <= math.max(1, (t.length * 0.15).round());
}

void main() {
  final dirs = (Platform.environment['FASAN_BONORDNER'] ?? '').split(':').where((d) => d.isNotEmpty && Directory(d).existsSync()).toList();
  // Stage B (Korpus, 06.11.): public data sets and single finds; measured per folder, may not get worse than the stored best
  final korpus = (Platform.environment['FASAN_KORPUS'] ?? '').split(':').where((d) => d.isNotEmpty && Directory(d).existsSync()).toSet();
  dirs.addAll(korpus.where((d) => !dirs.contains(d)));
  final ready = dirs.isNotEmpty && File('assets/models/det.onnx').existsSync();
  test('Erkennungs-Tor', () async {
    const m = 'assets/models';
    final uv = File('$m/uvdoc.onnx');
    final threads = int.tryParse(Platform.environment['FASAN_THREADS'] ?? '') ?? 2;
    final ocr = PaddleOcr(
      OnnxModel.fromBytes(File('$m/det.onnx').readAsBytesSync(), threads: threads),
      OnnxModel.fromBytes(File('$m/rec-latin.onnx').readAsBytesSync(), threads: threads),
      File('$m/dict-latin.txt').readAsStringSync(),
      uvdoc: uv.existsSync() ? OnnxModel.fromBytes(uv.readAsBytesSync(), threads: threads) : null,
    );
    final rec = Recognizer(ocr);
    final pick = RegExp(Platform.environment['FASAN_BONS'] ?? r'\.(png|jpg|jpeg)$', caseSensitive: false);
    final failures = <String>[], known = <String>[];
    final okPer = <String, int>{}, nPer = <String, int>{};
    var checkedBons = 0;
    for (final dir in dirs) {
      final files = Directory(dir).listSync().whereType<File>().map((f) => f.path).where((p) => pick.hasMatch(p)).toList()..sort();
      for (final f in files) {
        final tf = File(f.replaceFirst(RegExp(r'(-mild|-hart|-extrem|-kopf|-quer)?\.(png|jpg|jpeg)$', caseSensitive: false), '.json'));
        if (!tf.existsSync()) continue;
        final truth = jsonDecode(tf.readAsStringSync()) as Map<String, dynamic>;
        final x = await rec.recognize(File(f).readAsBytesSync());
        final d = RecognitionService.fromRecognition(x);
        checkedBons++;
        final problems = <String>[];
        var amountsWrong = false;
        if (d.total != truth['total']) {
          problems.add('Summe ${d.total} statt ${truth['total']}');
          amountsWrong = true;
        }
        // with a per-item truth: amounts as the app shows them; without: the printed lines, deposit/discount lines counted
        // separately like e2e_test.dart (the app adds them to the article)
        final ist = (truth['posten_detail'] != null
            ? [for (final i in d.items) i.amount]
            : [
                for (final q in x.result.items)
                  if (q.extras.isNotEmpty) ...[q.amount - q.extras.fold<int>(0, (a, z) => a + z.amount), ...q.extras.map((z) => z.amount)] else q.amount
              ])
          ..sort();
        // with a per-item truth, its amounts are what the user sees (deposit and discounts on the article, Karte 3.13); else the
        // printed lines (`posten`)
        final detail = truth['posten_detail'] as List?;
        final soll = (detail != null ? [for (final p in detail) (p as Map)['betrag'] as int] : (truth['posten'] as List).cast<int>().toList())..sort();
        if (ist.join(',') != soll.join(',')) {
          problems.add('Beträge $ist statt $soll');
          amountsWrong = true;
        }
        for (final p in (detail ?? const [])) {
          final q = p as Map<String, dynamic>;
          final match = d.items.where((i) => i.amount == q['betrag'] && i.qty == (q['menge'] ?? 1) && nameOk(q['name'] as String, i.name));
          if (match.isEmpty) {
            // wrong quantity counts like a wrong amount (the check vouches for it); a wrong name alone does not
            if (!d.items.any((i) => i.amount == q['betrag'] && i.qty == (q['menge'] ?? 1))) amountsWrong = true;
            final same = d.items.where((i) => i.amount == q['betrag']).map((i) => '${i.qty}× ${i.name}').join(' / ');
            problems.add('Posten ${q['menge'] ?? 1}× ${q['name']} = ${q['betrag']} fehlt (gelesen: ${same.isEmpty ? '–' : same})');
          }
        }
        final name = f.split('/').last;
        nPer[dir] = (nPer[dir] ?? 0) + 1;
        if (problems.isEmpty) okPer[dir] = (okPer[dir] ?? 0) + 1;
        if (korpus.contains(dir)) {
          // ignore: avoid_print
          print('${problems.isEmpty ? 'K-OK' : 'K-FEHLER'} $name${problems.isEmpty ? '' : ': ${problems.join('; ')}'}');
          continue;
        }
        if (problems.isEmpty) {
          // ignore: avoid_print
          print('OK   $name');
          continue;
        }
        final line = '$name${d.checked && amountsWrong ? ' [FALSCH ALS GEPRÜFT GEMELDET]' : ''}: ${problems.join('; ')}';
        // wrong amounts, quantities or total reported as checked are never allowed, known or not; a known name problem is
        if (truth['bekannt'] != null && !(d.checked && amountsWrong)) {
          known.add('$line (bekannt: ${truth['bekannt']})');
          // ignore: avoid_print
          print('BEKANNT $line');
        } else {
          failures.add(line);
          // ignore: avoid_print
          print('FEHLER $line');
        }
      }
    }
    final minFile = Platform.environment['FASAN_KORPUS_MIN'];
    final min = minFile != null && File(minFile).existsSync() ? jsonDecode(File(minFile).readAsStringSync()) as Map<String, dynamic> : const {};
    for (final d in korpus) {
      final key = d.split('/').where((x) => x.isNotEmpty).last;
      // ignore: avoid_print
      print('KORPUS $key: ${okPer[d] ?? 0}/${nPer[d] ?? 0} ganz richtig (Bestwert ${min[key] ?? '–'})');
      if (min[key] is int && (okPer[d] ?? 0) < (min[key] as int)) failures.add('Korpus $key schlechter: ${okPer[d] ?? 0} < ${min[key]}');
    }
    // ignore: avoid_print
    print('TOR: $checkedBons Bons, ${failures.length} Fehler, ${known.length} bekannt');
    expect(checkedBons, greaterThan(0), reason: 'keine Bons mit Wahrheit gefunden');
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, skip: ready ? false : 'FASAN_BONORDNER oder Modelle fehlen', timeout: const Timeout(Duration(hours: 3)));
}
