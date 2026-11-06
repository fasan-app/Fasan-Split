// Scan-Animation: gedrehte Kästen entlang der Zeilen (nur geprüfte Zeilen) und das Begradigungsgitter.
import 'dart:async';
import 'dart:math' as math;

import 'package:fasan_split/main.dart';
import 'package:fasan_split/recognition/image.dart';
import 'package:fasan_split/recognition/model.dart';
import 'package:fasan_split/recognition/scan.dart';
import 'package:fasan_split/recognition/scan_preview.dart';
import 'package:fasan_split/recognition/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/scan_screen.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

Word _w(String t, double x0, double cy, double w, {double? tilt, double h = 20}) =>
    Word(text: t, conf: 99, box: Box(x0, cy - h / 2, x0 + w, cy + h / 2), tilt: tilt);

ReadResult _result({required bool ok, List<bool> sure = const [true, false]}) {
  LineOut lo(int i) => LineOut(text: 'z$i', box: Box(0, i * 30.0, 300, i * 30.0 + 24), conf: 99, type: 'posten');
  return ReadResult(
    lines: [for (var i = 0; i < 5; i++) lo(i)],
    items: [
      Item(name: 'A', amount: 100, line: 1)..sure = sure[0],
      Item(name: 'B', amount: 200, line: 2)..sure = sure[1],
    ],
    total: 300,
    totalLine: 4,
    sum: 300,
    dec: ',',
    advance: 0,
    check: Check(ok: ok),
  );
}

void main() {
  group('lineQuad', () {
    test('Neigung der Wörter dreht den Kasten entlang der Zeile', () {
      const slope = 0.1;
      final q = lineQuad([_w('Cafe', 100, 200, 80, tilt: slope), _w('Latte', 200, 210, 100, tilt: slope)], 1000, 1000)!;
      // oben links → oben rechts: Steigung dy/dx = 0.1
      final dx = (q[2] - q[0]) * 1000, dy = (q[3] - q[1]) * 1000;
      expect(dy / dx, closeTo(slope, 1e-9));
      // untere Kante parallel zur oberen
      expect((q[5] - q[7]) * 1000 / ((q[4] - q[6]) * 1000), closeTo(slope, 1e-9));
      // ein Kasten je Zeile, überdeckt beide Wörter
      expect(q[0] * 1000, lessThan(100));
      expect(q[2] * 1000, greaterThan(300));
    });

    test('ohne Neigung: Gerade durch die Wortmitten', () {
      final q = lineQuad([_w('a', 0, 100, 50), _w('b', 100, 110, 50), _w('c', 200, 120, 50)], 400, 400)!;
      expect((q[3] - q[1]) / (q[2] - q[0]), closeTo(0.1, 0.02));
    });

    test('keine Wörter: kein Kasten', () {
      expect(lineQuad(const [], 100, 100), isNull);
    });
  });

  group('verifiedLines', () {
    test('Summe stimmt: alle Posten und die Summenzeile', () {
      expect(verifiedLines(_result(ok: true)), {1, 2, 4});
    });
    test('Summe stimmt nicht: nur sichere Posten, keine Summenzeile', () {
      expect(verifiedLines(_result(ok: false)), {1});
    });
  });

  group('verifiedQuads', () {
    test('ein gedrehter Kasten je geprüfter Zeile, nicht mehr', () {
      final r = _result(ok: true);
      final lines = [for (final l in r.lines) Line([_w('x', l.box.x0, l.box.cy, l.box.w, tilt: 0.05)])..box = l.box];
      final q = verifiedQuads(r, lines, 300, 150);
      expect(q.length, 3);
      for (final b in q) {
        expect(b.length, 8);
      }
    });
  });

  group('straighteningWarp', () {
    // Scherung: das Bild des Fotos ist gegenüber dem Scan um 0,2·y nach rechts verschoben.
    ScanResult shear() => ScanResult(
          Img(100, 200),
          (x, y) => [x - 0.2 * y, y],
          (x, y) => [x + 0.2 * y, y],
          const Paper(0, 0, 0, 0, 0),
          20,
          const {},
        );

    test('Gitter bildet auf das Foto ab, Kästen tragen beide Zustände', () {
      final wd = straighteningWarp(shear(), Img(140, 200), _result(ok: true), maxWidth: 70)!;
      expect(wd.src.length, wd.cols * wd.rows * 2);
      // Knoten oben links (0,0) liegt im Foto bei (0,0); unten links (0,200) bei (40/140, 1)
      expect(wd.src[0], 0);
      final last = (wd.rows - 1) * wd.cols * 2;
      expect(wd.src[last], closeTo(40 / 140, 1e-9));
      expect(wd.src[last + 1], closeTo(1, 1e-9));
      expect(wd.quads.length, 3);
      for (final q in wd.quads) {
        expect(q.length, 16);
      }
      expect(wd.preAspect, closeTo(0.7, 1e-9));
      expect(wd.scanAspect, closeTo(0.5, 1e-9));
    });

    test('nicht endliche Abbildung: kein Gitter', () {
      final bad = ScanResult(Img(100, 200), (x, y) => [x, y], (x, y) => [double.nan, y], const Paper(0, 0, 0, 0, 0), 20, const {});
      expect(straighteningWarp(bad, Img(100, 200), _result(ok: true)), isNull);
    });
  });

  group('ScanScreen', () {
    Future<void> run(WidgetTester tester, {required bool reduceMotion}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      // fasan_ui reads the tilt sensor over a platform channel; none exists in the test environment
      const tilt = MethodChannel('app.fasan.ui/tilt');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, (_) async => null);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, null));
      final photo = im.encodePng(im.Image(width: 8, height: 8));
      final jpeg = im.encodeJpg(im.Image(width: 70, height: 100));
      final events = StreamController<ScanEvent>();
      addTearDown(events.close);
      final ui = FasanController(settings: FasanSettings(reduceMotion: reduceMotion));
      await tester.pumpWidget(SplitApp(store: BillStore.memory(), ui: ui, home: ScanScreen(photo: photo, events: events.stream)));
      // Vorschau mit gedrehtem Kasten (8 Zahlen) und einem alten Rechteck (4 Zahlen)
      events.add(ScanPreview(jpeg, const [
        [0.1, 0.1, 0.9, 0.12, 0.9, 0.17, 0.1, 0.15],
        [0.1, 0.3, 0.9, 0.35],
      ], false));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1000));
      // Begradigung
      final src = <double>[for (var j = 0; j < 8; j++) for (var i = 0; i < 10; i++) ...[i / 9 * 0.9 + 0.05 * j / 7, j / 7]];
      events.add(ScanWarp(jpeg, 10, 8, 0.7, 0.5, src, [
        [0.1, 0.1, 0.9, 0.1, 0.9, 0.15, 0.1, 0.15, 0.12, 0.1, 0.9, 0.12, 0.9, 0.16, 0.12, 0.15],
      ]));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('warp')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    testWidgets('Begradigung mit Bewegung', (tester) => run(tester, reduceMotion: false));
    testWidgets('Begradigung ohne Bewegung (Animationen entfernt)', (tester) => run(tester, reduceMotion: true));
  });

  test('Kasten-Winkel bleibt klein genug für Zeilen (Neigung ±0,6)', () {
    final q = lineQuad([_w('a', 0, 100, 50), _w('b', 100, 500, 50)], 400, 600)!;
    expect(math.atan(((q[3] - q[1]) * 600) / ((q[2] - q[0]) * 400)).abs(), lessThan(math.atan(0.6) + 1e-9));
  });
}
