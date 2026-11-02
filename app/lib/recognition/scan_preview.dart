// Fasan Split – geometry for the scan animation: rotated boxes along the text lines (verified lines only) and the mesh
// that straightens the kinked receipt. Pure Dart, no Flutter. MPL-2.0
//
// Nutzer 02.11. (S23): Die Kästen lagen waagerecht über dem schrägen Bon, teils zwei pro Zeile. Jetzt: ein gedrehter Kasten
// je Zeile, entlang der Zeile (Neigung der Wörter), nur für Zeilen, die die Summe bestätigt hat. Die Begradigung
// kommt aus dem Entzerrungsgitter von scan.dart (toSource), nicht aus den Wortkästen.
import 'dart:math' as math;
import 'dart:typed_data';

import 'image.dart';
import 'model.dart';
import 'scan.dart';

/// Lines whose amounts the check confirmed: all item lines when the total adds up, else only the items read as sure.
/// Includes the name lines, extras (Pfand, Rabatt …) and the total line.
Set<int> verifiedLines(ReadResult r) {
  final s = <int>{};
  for (final p in r.items) {
    if (p.dropped || p.merged) continue;
    if (!r.check.ok && !p.sure) continue;
    s
      ..add(p.line)
      ..add(p.nameLine);
    for (final x in p.extras) {
      s.add(x.line);
    }
  }
  if (r.check.ok) s.add(r.totalLine);
  s.removeWhere((i) => i < 0 || i >= r.lines.length);
  return s;
}

double _wordHeight(Word x) {
  final bw = x.box.w, bh = x.box.h;
  return x.tilt == null || x.tilt == 0 || bw < 3 * bh ? bh : math.max(0.5 * bh, bh - x.tilt!.abs() * bw);
}

double _median(List<double> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// One rotated box along a text line: 8 numbers (x, y of the four corners, clockwise from top left), divided by [w] and [h].
/// The slope is the median slope of the words (PaddleOCR box slope); without it, a line fit through the word centres.
List<double>? lineQuad(List<Word> words, double w, double h) {
  final ws = [
    for (final x in words)
      if (x.box.w > 0 && x.box.h > 0) x,
  ]..sort((a, b) => a.box.x0.compareTo(b.box.x0));
  if (ws.isEmpty || w <= 0 || h <= 0) return null;
  var xl = ws.first.box.x0, xr = ws.map((x) => x.box.x1).reduce(math.max);
  final xm = (xl + xr) / 2;
  final slopes = [
    for (final x in ws)
      if (x.tilt != null && x.box.w > 2 * _wordHeight(x)) x.tilt!,
  ];
  var slope = 0.0;
  if (slopes.isNotEmpty) {
    slope = _median(slopes);
  } else if (ws.length >= 2) {
    var sxx = 0.0, sxy = 0.0;
    final my = ws.fold<double>(0, (a, x) => a + x.box.cy) / ws.length;
    for (final x in ws) {
      final dx = x.box.cx - xm;
      sxx += dx * dx;
      sxy += dx * (x.box.cy - my);
    }
    if (sxx > 1e-6) slope = (sxy / sxx).clamp(-0.6, 0.6);
  }
  final ym = _median([for (final x in ws) x.box.cy - slope * (x.box.cx - xm)]);
  final lh = _median([for (final x in ws) _wordHeight(x)]) * 1.15, pad = 0.2 * lh;
  xl -= pad;
  xr += pad;
  double y(double x) => ym + slope * (x - xm);
  return [xl / w, (y(xl) - lh / 2) / h, xr / w, (y(xr) - lh / 2) / h, xr / w, (y(xr) + lh / 2) / h, xl / w, (y(xl) + lh / 2) / h];
}

/// Rotated boxes (8 numbers each, normalised to [w] × [h] of the read image) of the verified lines of one pass.
/// [lines] are the lines the result was read from (a result line shares its [Box] with its source line).
List<List<double>> verifiedQuads(ReadResult r, List<Line> lines, double w, double h) {
  final out = <List<double>>[];
  for (final i in verifiedLines(r).toList()..sort()) {
    final lo = r.lines[i];
    Line? src;
    for (final l in lines) {
      if (identical(l.box, lo.box)) {
        src = l;
        break;
      }
    }
    final q = src != null && src.words.isNotEmpty ? lineQuad(src.words, w, h) : null;
    if (q != null) {
      out.add(q);
    } else if (lo.box.w > 0 && lo.box.h > 0) {
      final b = lo.box;
      out.add([b.x0 / w, b.y0 / h, b.x1 / w, b.y0 / h, b.x1 / w, b.y1 / h, b.x0 / w, b.y1 / h]);
    }
  }
  return out;
}

/// Mesh that turns the kinked receipt (the image the scan was made from) into the straight scan, plus the verified
/// line boxes in both states. All coordinates are normalised to their own image.
class WarpData {
  const WarpData({
    required this.jpeg,
    required this.cols,
    required this.rows,
    required this.preAspect,
    required this.scanAspect,
    required this.src,
    required this.quads,
  });

  /// The kinked receipt (small JPEG).
  final Uint8List jpeg;
  final int cols, rows;

  /// Width / height of the kinked image and of the scan.
  final double preAspect, scanAspect;

  /// Per node (row by row) its position in the kinked image; in the scan the nodes lie on a regular grid.
  final List<double> src;

  /// Per verified line 16 numbers: four corners in the scan (8), then the same four corners in the kinked image (8).
  final List<List<double>> quads;
}

/// Builds the mesh from the scan mapping (`toSource`: scan → kinked image). Null if the mapping is not finite.
WarpData? straighteningWarp(ScanResult s, Img pre, ReadResult r, {int maxWidth = 640}) {
  final ow = s.image.w.toDouble(), oh = s.image.h.toDouble(), pw = pre.w.toDouble(), ph = pre.h.toDouble();
  if (ow < 8 || oh < 8 || pw < 8 || ph < 8) return null;
  const cols = 10;
  final rows = (cols * oh / ow).round().clamp(8, 24);
  final src = <double>[];
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final p = s.toSource(i / (cols - 1) * ow, j / (rows - 1) * oh);
      if (!p[0].isFinite || !p[1].isFinite) return null;
      src
        ..add(p[0] / pw)
        ..add(p[1] / ph);
    }
  }
  final quads = <List<double>>[];
  for (final i in verifiedLines(r).toList()..sort()) {
    final b = r.lines[i].box;
    if (b.w <= 0 || b.h <= 0) continue;
    final dst = [b.x0, b.y0, b.x1, b.y0, b.x1, b.y1, b.x0, b.y1];
    final q = <double>[
      for (var k = 0; k < 8; k += 2) ...[dst[k] / ow, dst[k + 1] / oh],
    ];
    var ok = true;
    for (var k = 0; k < 8; k += 2) {
      final p = s.toSource(dst[k], dst[k + 1]);
      if (!p[0].isFinite || !p[1].isFinite) ok = false;
      q
        ..add(p[0] / pw)
        ..add(p[1] / ph);
    }
    if (ok) quads.add(q);
  }
  final f = math.min(1.0, maxWidth / pw);
  final small = pre.resized(math.max(1, (pw * f).round()), math.max(1, (ph * f).round()));
  return WarpData(jpeg: small.jpeg(80), cols: cols, rows: rows, preAspect: pw / ph, scanAspect: ow / oh, src: src, quads: quads);
}
