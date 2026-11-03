// Fasan Split – neural text recognition with PaddleOCR PP-OCRv5. MPL-2.0
//
// Port of Fasan-Karte/site/ocr.js (3.19). Models: PP-OCRv5 mobile det and the Latin reader (Apache-2.0), as ONNX from
// ppu-paddle-ocr-models (assets/models/DATEIEN.txt). Parameters from the official PaddleOCR configs
// (configs/det/PP-OCRv5/PP-OCRv5_mobile_det.yml, configs/rec/PP-OCRv5/multi_language/latin_PP-OCRv5_mobile_rec.yml):
// - detection: BGR, (x/255 − mean)/std with mean 0.485/0.456/0.406 and std 0.229/0.224/0.225, sides multiples of 32;
//   DB post-processing: threshold 0.3, box threshold 0.6, unclip 1.5
// - reading: height 48 px, width by aspect ratio, (x/255 − 0.5)/0.5; CTC with a space class (use_space_char)
// Each character also gets the second-best reading with its probability (alternatives for unsure digits).
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:typed_data';

import 'image.dart';
import 'model.dart';
import 'onnx.dart' if (dart.library.js_interop) 'onnx_web.dart';
import 'text_util.dart';

class DetBox {
  DetBox(this.x0, this.y0, this.x1, this.y1, this.score, this.tilt);

  double x0, y0, x1, y1;
  final double score;
  final double? tilt;
  bool limited = false;

  double get w => x1 - x0;
  double get h => y1 - y0;

  DetBox copyWithY(double y0, double y1) => DetBox(x0, y0, x1, y1, score, tilt);
}

class RecResult {
  const RecResult(this.text, this.conf, this.glyphs);

  final String text;
  final double conf;
  final List<Glyph> glyphs;
}

class PaddleOcr {
  PaddleOcr(this.det, this.rec, String dictText, {this.uvdoc}) : _chars = _dict(dictText);

  final OnnxModel det, rec;
  final OnnxModel? uvdoc;
  final List<String> _chars;
  List<String>? _classes;

  static List<String> _dict(String t) {
    final z = t.replaceAll('\r', '').split('\n');
    while (z.isNotEmpty && z.last.isEmpty) {
      z.removeLast();
    }
    return z;
  }

  /// BGR tensor as in PaddleOCR (cv2 reads BGR) [bgrTensor].
  static Float32List _bgr(Img g, List<double> mean, List<double> std) {
    final n = g.w * g.h, t = Float32List(3 * n), p = g.rgba;
    for (var i = 0, j = 0; i < n; i++, j += 4) {
      t[i] = (p[j + 2] / 255 - mean[0]) / std[0];
      t[n + i] = (p[j + 1] / 255 - mean[1]) / std[1];
      t[2 * n + i] = (p[j] / 255 - mean[2]) / std[2];
    }
    return t;
  }

  /// Size for detection: ≤ ~2.4 MP and 2560 px longest side, ≥ 32; [stretch] > 1 stretches vertically [detGroesse].
  static (int, int, double, double) _detSize(int w, int h, double stretch) {
    final f = [1.0, 2560 / math.max(w, h * stretch), math.sqrt(2.4e6 / (w * h * stretch))].reduce(math.min);
    final ww = math.max(32, jsRound((w * f) / 32) * 32), hh = math.max(32, jsRound((h * f * stretch) / 32) * 32);
    return (ww, hh, ww / w, hh / h);
  }

  /// Where is text? Axis-parallel boxes in image pixels [finde].
  Future<List<DetBox>> find(Img c, {List<double>? scale, double stretch = 1}) async {
    int ww, hh;
    double fx, fy;
    if (scale != null) {
      ww = math.max(32, jsRound((c.w * scale[0]) / 32) * 32);
      hh = math.max(32, jsRound((c.h * scale[1]) / 32) * 32);
      fx = ww / c.w;
      fy = hh / c.h;
    } else {
      (ww, hh, fx, fy) = _detSize(c.w, c.h, stretch);
    }
    final g = c.resized(ww, hh);
    final out = await det.run(_bgr(g, const [0.485, 0.456, 0.406], const [0.229, 0.224, 0.225]), [1, 3, hh, ww]);
    return _boxes(out.data, ww, hh)
        .map((k) => DetBox(k.x0 / fx, k.y0 / fy, k.x1 / fx, k.y1 / fy, k.score, k.tilt == null ? null : (k.tilt! * fx) / fy))
        .toList();
  }

  /// DB post-processing: threshold → 4-connected regions → mean probability ≥ box threshold → unclip [kaesten].
  static List<DetBox> _boxes(Float32List p, int w, int h, {double thr = 0.3, double boxThr = 0.6, double unclip = 1.5}) {
    final mark = Int32List(w * h), stack = Int32List(w * h), out = <DetBox>[];
    var nr = 0;
    for (var s = 0; s < w * h; s++) {
      if (mark[s] != 0 || p[s] <= thr) continue;
      nr++;
      var top = 0;
      stack[top++] = s;
      mark[s] = nr;
      var x0 = w, y0 = h, x1 = 0, y1 = 0, cnt = 0;
      double sum = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
      while (top > 0) {
        final i = stack[--top], x = i % w, y = i ~/ w;
        sum += p[i];
        cnt++;
        sx += x;
        sy += y;
        sxx += x * x;
        syy += y * y;
        sxy += x * y;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
        if (x > 0 && mark[i - 1] == 0 && p[i - 1] > thr) {
          mark[i - 1] = nr;
          stack[top++] = i - 1;
        }
        if (x < w - 1 && mark[i + 1] == 0 && p[i + 1] > thr) {
          mark[i + 1] = nr;
          stack[top++] = i + 1;
        }
        if (y > 0 && mark[i - w] == 0 && p[i - w] > thr) {
          mark[i - w] = nr;
          stack[top++] = i - w;
        }
        if (y < h - 1 && mark[i + w] == 0 && p[i + w] > thr) {
          mark[i + w] = nr;
          stack[top++] = i + w;
        }
      }
      final bw = x1 - x0 + 1, bh = y1 - y0 + 1;
      if (cnt < 12 || math.min(bw, bh) < 3) continue;
      final score = sum / cnt;
      if (score < boxThr) continue;
      final d = (bw * bh * unclip) / (2 * (bw + bh));
      // tilt of the text line from the region's moments (main axis); reliable only for long regions
      final mx = sx / cnt, my = sy / cnt, cxx = sxx / cnt - mx * mx, cyy = syy / cnt - my * my, cxy = sxy / cnt - mx * my;
      final th = 0.5 * math.atan2(2 * cxy, cxx - cyy);
      final tilt = bw > 2.5 * bh && th.abs() < 0.35 ? math.tan(th) : null;
      out.add(DetBox(math.max(0, x0 - d), math.max(0, y0 - d), math.min(w.toDouble(), x1 + 1 + d), math.min(h.toDouble(), y1 + 1 + d), score, tilt));
    }
    return out;
  }

  /// What is in the box? CTC greedy decoding with second-best character [liesKasten].
  Future<RecResult?> readBox(Img c, double x0, double y0, double x1, double y1) async {
    final kh = y1 - y0, kw = x1 - x0;
    if (kh < 4 || kw < 4) return null;
    const H = 48;
    final W = math.max(16, math.min(1600, jsRound((H * kw) / kh)));
    final g = c.region(x0, y0, kw, kh, W, H);
    final o = await rec.run(_bgr(g, const [0.5, 0.5, 0.5], const [0.5, 0.5, 0.5]), [1, 3, H, W]);
    final T = o.dims[1], C = o.dims[2], d = o.data;
    if (_classes == null) {
      // blank class first, space last (if the output has one class more); the Latin dict already starts with a blank line
      final k = _chars.isNotEmpty && _chars[0] == '' ? List<String>.of(_chars) : ['', ..._chars];
      if (C == k.length + 1) k.add(' ');
      _classes = k;
    }
    final cls = _classes!;
    final glyphs = <Glyph>[];
    var prev = 0;
    double sum = 0;
    for (var i = 0; i < T; i++) {
      var b1 = 0, b2 = 0;
      double p1 = -1, p2 = -1;
      final o0 = i * C;
      for (var j = 0; j < C; j++) {
        final v = d[o0 + j];
        if (v > p1) {
          b2 = b1;
          p2 = p1;
          b1 = j;
          p1 = v;
        } else if (v > p2) {
          b2 = j;
          p2 = v;
        }
      }
      if (b1 != 0 && b1 != prev) {
        glyphs.add(Glyph(b1 < cls.length ? cls[b1] : '', p1, alt: b2 != 0 ? (b2 < cls.length ? cls[b2] : '') : '', p2: p2));
        sum += p1;
      }
      prev = b1;
    }
    final text = glyphs.map((z) => z.ch).join();
    return RecResult(text.trim(), glyphs.isNotEmpty ? (sum / glyphs.length) * 100 : 0, glyphs);
  }

  /// Whole page: find boxes, read each. Fixes stacked digit columns of fixed-pitch receipts and tall merged boxes [woerter].
  Future<List<Word>> words(Img c, {double? stretch, void Function(double)? progress}) async {
    var k = await find(c, stretch: stretch ?? 1);
    final out = <Word>[];
    if (stretch == null) {
      double area(DetBox q) => math.max(1, q.w * q.h);
      double cut(DetBox q, DetBox r) => math.max(0, math.min(q.x1, r.x1) - math.max(q.x0, r.x0)) * math.max(0, math.min(q.y1, r.y1) - math.max(q.y0, r.y0));
      final hs0 = stableSorted<double>(k.where((q) => q.w > 1.5 * q.h).map((q) => q.h), numAsc);
      final med0 = hs0.isNotEmpty ? hs0[hs0.length >> 1] : 0.0;
      final tall = med0 != 0 ? k.where((q) => q.h > 2.2 * med0 && q.h > 0.8 * q.w).toList() : <DetBox>[];
      if (tall.isNotEmpty) {
        final k2 = await find(c, stretch: 2.2);
        var neu = k2.where((q) => tall.any((t) => cut(q, t) > 0.25 * area(q))).toList();
        final sx0 = minOf(tall.map((q) => q.x0)), sx1 = maxOf(tall.map((q) => q.x1));
        for (var more = neu.isNotEmpty; more;) {
          more = false;
          final top = minOf(neu.map((q) => q.y0)), bottom = maxOf(neu.map((q) => q.y1)), tol = 0.05 * med0;
          for (final q in k2) {
            if (neu.contains(q) || math.min(q.x1, sx1) - math.max(q.x0, sx0) < 0.5 * q.w) continue;
            if ((q.y0 < top && q.y1 >= top - tol) || (q.y1 > bottom && q.y0 <= bottom + tol)) {
              neu.add(q);
              more = true;
            }
          }
        }
        final hNs = stableSorted<double>(neu.map((q) => q.h), numAsc);
        final hN = hNs.isNotEmpty ? hNs[neu.length >> 1] : 0.0;
        final good = stableSorted<DetBox>(neu.where((q) => q.h < 1.5 * hN), (a, b) => numAsc(a.y0 + a.y1, b.y0 + b.y1));
        final gaps = <double>[];
        for (var i = 1; i < good.length; i++) {
          final d = (good[i].y0 + good[i].y1 - good[i - 1].y0 - good[i - 1].y1) / 2;
          if (d > 0.5 * hN && d < 1.6 * hN) gaps.add(d);
        }
        stableSort<double>(gaps, numAsc);
        final p = gaps.isNotEmpty ? gaps[gaps.length >> 1] : 0.0;
        if (p != 0) {
          neu = [
            for (final t in neu)
              ...() {
                if (t.h < 1.5 * hN) return [t];
                DetBox? g;
                for (final q in good) {
                  if (g == null || (q.y0 + q.y1 - t.y0 - t.y1).abs() < (g.y0 + g.y1 - t.y0 - t.y1).abs()) g = q;
                }
                if (g == null) return <DetBox>[];
                final parts = <DetBox>[], c0 = (g.y0 + g.y1) / 2;
                for (var j = ((t.y0 + 0.3 * p - c0) / p).ceil(); c0 + j * p <= t.y1 - 0.3 * p; j++) {
                  final cc = c0 + j * p;
                  parts.add(t.copyWithY(cc - hN / 2, cc + hN / 2));
                }
                return parts;
              }()
          ];
        }
        if (neu.length >= tall.length) {
          k = [
            ...k.where((q) => !tall.contains(q) && !neu.any((n) => cut(q, n) > 0.3 * area(q))),
            ...neu,
          ];
        }
      }
    }
    // dense receipts: limit each box's height to the distance of the next line above/below
    for (final q in k) {
      final cy = (q.y0 + q.y1) / 2;
      var ab = double.infinity;
      for (final r in k) {
        if (identical(r, q)) continue;
        final over = math.min(q.x1, r.x1) - math.max(q.x0, r.x0);
        if (over < 0.3 * math.min(q.w, r.w)) continue;
        final d = ((r.y0 + r.y1) / 2 - cy).abs();
        if (d > 2 && d < ab) ab = d;
      }
      if (ab < double.infinity && q.h > 1.12 * ab) {
        final hh = math.max(ab * 1.04, 8) / 2;
        q.y0 = cy - hh;
        q.y1 = cy + hh;
        q.limited = true;
      }
    }
    final hs = stableSorted<double>(k.where((q) => q.w > 1.5 * q.h).map((q) => q.h), numAsc);
    final med = hs.isNotEmpty ? hs[hs.length >> 1] : 0.0;
    for (var i = 0; i < k.length; i++) {
      final q = k[i], h = q.h;
      final r = await readBox(c, q.x0, q.y0, q.x1, q.y1);
      List<(RecResult, Box)>? parts;
      // too tall box with modest confidence: read n equal strips; keep them only if they read more surely
      if (med != 0 && h > 1.45 * med && (r == null || r.conf < 93)) {
        final n = math.max(2, jsRound(h / med)), sh = h / n, list = <(RecResult, Box)>[];
        for (var j = 0; j < n; j++) {
          final t = Box(q.x0, q.y0 + j * sh - sh * 0.08, q.x1, q.y0 + (j + 1) * sh + sh * 0.08);
          final l = await readBox(c, t.x0, t.y0, t.x1, t.y1);
          if (l != null && l.text.isNotEmpty) list.add((l, t));
        }
        final mean = list.isNotEmpty ? list.fold<double>(0, (a, x) => a + x.$1.conf) / list.length : 0.0;
        if (list.length >= 2 && mean > (r?.conf ?? 0) + 3) parts = list;
      }
      if (parts != null) {
        for (final (l, t) in parts) {
          out.add(Word(text: l.text, conf: l.conf, box: t, glyphs: l.glyphs, tilt: q.tilt));
        }
      } else if (r != null && r.text.isNotEmpty) {
        out.add(Word(text: r.text, conf: r.conf, box: Box(q.x0, q.y0, q.x1, q.y1), glyphs: r.glyphs, tilt: q.tilt));
      }
      if (progress != null && (i % 4 == 0 || i == k.length - 1)) progress((i + 1) / k.length);
    }
    return out;
  }

  /// Is the text sideways? Detection on a small copy; tall boxes outnumbering wide ones → turned by 90° [hochkant].
  Future<bool> sideways(Img c) async {
    final f = math.min(1.0, 960 / math.max(c.w, c.h));
    final small = f < 1 ? c.resized(jsRound(c.w * f), jsRound(c.h * f)) : c;
    final k = await find(small);
    var wide = 0, tall = 0;
    for (final q in k) {
      if (q.w > 1.6 * q.h) {
        wide++;
      } else if (q.h > 1.6 * q.w) {
        tall++;
      }
    }
    return tall > math.max(3, wide * 1.5);
  }

  static const defaultVariants = <(double, double, bool)>[(0.12, 0, false), (0.3, 0, false), (0.12, 0.1, false), (0.45, -0.05, false), (0.2, 0, true)];

  /// Reads the same area with several crops (margin, top/bottom, stretched contrast); voting by confidence
  /// (cf. Reul et al. 2017, arXiv:1711.09670) [mehrfach].
  Future<List<Reading>> multiRead(Img c, Box k, {List<(double, double, bool)> variants = defaultVariants}) async {
    final h = k.h, out = <Reading>[];
    for (final (margin, inset, contrast) in variants) {
      var x0 = math.max(0.0, k.x0 - h * margin), x1 = math.min(c.w.toDouble(), k.x1 + h * margin);
      var y0 = math.max(0.0, k.y0 - h * (margin * 0.5 - inset)), y1 = math.min(c.h.toDouble(), k.y1 + h * (margin * 0.5 - inset));
      var src = c;
      if (contrast) {
        final cw = jsRound(x1 - x0), ch = jsRound(y1 - y0);
        if (cw < 1 || ch < 1) continue;
        final g = c.region(x0, y0, cw.toDouble(), ch.toDouble(), cw, ch);
        final px = g.rgba;
        double lo = 255, hi = 0;
        for (var i = 0; i < px.length; i += 4) {
          final v = (px[i] + px[i + 1] + px[i + 2]) / 3;
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
        final sp = math.max(1.0, hi - lo);
        for (var i = 0; i < px.length; i += 4) {
          final v = (((px[i] + px[i + 1] + px[i + 2]) / 3 - lo) * 255 / sp).clamp(0, 255).round();
          px[i] = px[i + 1] = px[i + 2] = v;
        }
        src = g;
        x1 -= x0;
        y1 -= y0;
        x0 = 0;
        y0 = 0;
      }
      try {
        final l = await readBox(src, x0, y0, x1, y1);
        if (l != null && l.text.isNotEmpty) out.add(Reading(l.text, l.conf));
      } catch (_) {/* next variant */}
    }
    return out;
  }

  /// UVDoc: grid 2×gh×gw of source coordinates in [−1, 1] for a flat sheet. Input RGB 488×712, values 0–1 [uvdoc].
  Future<(Float32List, List<int>)?> uvGrid(Img c) async {
    final m = uvdoc;
    if (m == null) return null;
    const W = 488, H = 712;
    final g = c.resized(W, H);
    final n = W * H, t = Float32List(3 * n), p = g.rgba;
    for (var i = 0, j = 0; i < n; i++, j += 4) {
      t[i] = p[j] / 255;
      t[n + i] = p[j + 1] / 255;
      t[2 * n + i] = p[j + 2] / 255;
    }
    final o = await m.run(t, [1, 3, H, W]);
    return (o.data, o.dims);
  }
}
