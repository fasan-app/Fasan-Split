// SPDX-License-Identifier: MPL-2.0
// The line pictures must have the size of the crop, not of the window: the WebAssembly renderer's PNG encoder returned the whole
// window size with the crop tiny in a corner (07.11.). The VM renderer was always right, so this guards the contract, and the
// browser walk with the --wasm build (tool/e2e/screens.js, Bildvergleich) guards the renderer.
import 'dart:typed_data';

import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/snippets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

void main() {
  testWidgets('Zeilenbild hat die Größe des Ausschnitts und zeigt dessen Inhalt', (tester) async {
    await tester.runAsync(() async {
      final scan = im.Image(width: 600, height: 1000)..clear(im.ColorRgb8(255, 255, 255));
      im.fillRect(scan, x1: 60, y1: 200, x2: 400, y2: 230, color: im.ColorRgb8(0, 0, 0)); // the item's line: a black bar
      final b = Bill(id: 's', created: DateTime(2026, 11, 7), items: [
        BillItem(name: 'A', amount: 100, boxes: const [NBox(0.08, 0.19, 0.94, 0.24)]),
      ]);
      final aspect = await fillSnippets(b, Uint8List.fromList(im.encodeJpg(scan, quality: 95)));
      expect(aspect, closeTo(0.6, 1e-9));
      final out = im.decodePng(b.its.first.snippet!)!;
      // box 0.05 × 1000 = 50 px high → crop 76 % + margins ≈ 40 px, scaled to ≤ 56 px; width ≈ the box width (516 px)
      expect(out.height, inInclusiveRange(30, 56));
      expect(out.width, inInclusiveRange(480, 560));
      // the black bar is inside the crop (not a blank picture, not a tiny corner)
      var dark = 0;
      for (final p in out) {
        if (p.r < 80) dark++;
      }
      expect(dark, greaterThan(out.width * out.height ~/ 4));
    });
  });
}
