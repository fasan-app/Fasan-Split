// SPDX-License-Identifier: MPL-2.0
// Prints what the recognizer reads in one image (developer tool, not part of the suite): FASAN_FILE=… LD_LIBRARY_PATH=…
// flutter test test/ocr_dump_test.dart. Without FASAN_FILE it does nothing. MPL-2.0
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:fasan_split/recognition/pipeline.dart';
import 'package:fasan_split/recognition/service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ocr_cache.dart';

void main() {
  final f = Platform.environment['FASAN_FILE'];
  test('dump', () async {
    if (f == null) return;
    final ocr = testOcr('assets/models', 2);
    cacheFor(ocr, f);
    final x = await Recognizer(ocr, earlyStop: Platform.environment['FASAN_EARLYSTOP'] != '0').recognize(File(f).readAsBytesSync());
    cacheDone(ocr);
    // ignore: avoid_print
    print('TRIES ${x.tries.join(' ')}');
    for (final l in x.result.lines) {
      // ignore: avoid_print
      print('LINE ${l.type}|${l.text}');
    }
    for (final q in x.result.items) {
      // ignore: avoid_print
      print('ITEM ${q.name} = ${q.amount} qty ${q.qty} unit ${q.unit}');
    }
    final d = RecognitionService.fromRecognition(x);
    for (final i in d.items) {
      // ignore: avoid_print
      print('APP ${i.qty}× ${i.name} = ${i.amount}${i.unit != null ? ' (je ${i.unit})' : ''}');
    }
    // ignore: avoid_print
    print('TOTAL ${d.total} geprüft ${d.checked}');
    // which target vouched for the items (summe, betrag, gegeben, qr …) and on which line – the first question for „wrong as checked“
    // ignore: avoid_print
    print('CHECK ok ${x.result.check.ok} quelle ${x.result.check.source} zeile ${x.result.totalLine} ziele ${x.result.check.targets}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
