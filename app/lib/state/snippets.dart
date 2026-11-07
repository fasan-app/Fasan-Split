// Fasan Split – line pictures cut from a shared scan (06.11.): a bill from the group arrives with its scan (photo_sync.dart)
// and each item's place on it (BillItem.boxes); the line pictures under the items are cut here exactly as the phone that
// scanned cut them (recognition/pipeline.dart, snippet()). Uses the platform's own image decoder (dart:ui), so the browser
// decodes natively instead of in Dart. MPL-2.0
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fasan_core/bill.dart';
import 'package:image/image.dart' as im;

/// Fills [BillItem.snippet] for items that have boxes but no picture yet. Returns width/height of the scan (or null).
Future<double?> fillSnippets(Bill b, Uint8List scan) async {
  final codec = await ui.instantiateImageCodec(scan);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  try {
    final w = image.width.toDouble(), h = image.height.toDouble();
    final all = [for (final it in b.its) ...it.boxes];
    if (all.isEmpty) return w / h;
    // line pictures span the common text width of all items, so the quantity column is always inside (pipeline.dart)
    final left = all.map((x) => x.x0).reduce(math.min) * w, right = all.map((x) => x.x1).reduce(math.max) * w;
    for (final it in b.its) {
      if (it.snippet != null || it.boxes.isEmpty) continue;
      final y0 = it.boxes.map((x) => x.y0).reduce(math.min) * h, y1 = it.boxes.map((x) => x.y1).reduce(math.max) * h;
      // same crop as pipeline.dart snippet(): 76 % of the line height from 12 % below its top, 4 % margin, ≤ 56 px high
      final h0 = y1 - y0, hh = h0 * 0.76, pad = h0 * 0.04;
      final x0 = math.max(0.0, left - pad), yy = math.max(0.0, y0 + h0 * 0.12 - pad);
      final bw = math.min(w - x0, right - left + 2 * pad), bh = math.min(h - yy, hh + 2 * pad);
      if (bw < 8 || bh < 6) continue;
      final f = math.min(1.0, 56 / bh);
      final ow = math.max(1, (bw * f).round()), oh = math.max(1, (bh * f).round());
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawImageRect(image, ui.Rect.fromLTWH(x0, yy, bw, bh), ui.Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.medium);
      final pic = rec.endRecording();
      final out = await pic.toImage(ow, oh);
      // Raw pixels and our own PNG, not toByteData(format: png): the WebAssembly renderer (skwasm, Flutter 3.47.7) returned a PNG
      // of the whole window size (786 × 1746) with the crop tiny in the top left corner (07.11., browser build with --wasm).
      // The crop is small (≤ 56 px high), encoding it in Dart costs next to nothing and is the same in every renderer.
      final raw = await out.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      out.dispose();
      pic.dispose();
      if (raw != null) {
        it.snippet = im.encodePng(im.Image.fromBytes(width: ow, height: oh, bytes: raw.buffer, numChannels: 4, order: im.ChannelOrder.rgba));
      }
    }
    return w / h;
  } finally {
    image.dispose();
  }
}
