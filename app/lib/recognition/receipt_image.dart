// Fasan Split – find the receipt in the photo and pull it straight. MPL-2.0
//
// Port of Fasan-Karte/site/bonbild.js (own method, no library; tested in the web app since 24.10.2026):
// 1. Photo to 1400 px. "Paper" = smooth (local std 7×7 small), bright, hardly coloured.
// 2. Mask on blocks, fill holes (text, QR), connected regions, score by area and share of text. Best region = receipt.
// 3. Convex hull → smallest enclosing rectangle (−45° … 45°) → four corners (perspective kept).
// 4. Four-point rectification (homography), upscaling to about 1300 px width.
// 5. Residual slant: shear that changes with height, from the sharpest line profile per strip [gerade].
// ignore_for_file: non_constant_identifier_names, constant_identifier_names
import 'dart:math' as math;
import 'dart:typed_data';

import 'image.dart';

class FoundReceipt {
  const FoundReceipt(this.corners, this.angle, this.share, this.text, this.sdT);

  /// TL, TR, BR, BL in pixels of the original photo.
  final List<List<double>> corners;
  final double angle, share, text, sdT;
}

class Rectified {
  const Rectified(this.image, this.scale);

  final Img image;
  final double scale;
}

class ReceiptImage {
  ReceiptImage._();

  static Float64List _integral(Float32List v, int w, int h) {
    final I = Float64List((w + 1) * (h + 1));
    for (var j = 0; j < h; j++) {
      double z = 0;
      for (var i = 0; i < w; i++) {
        z += v[j * w + i];
        I[(j + 1) * (w + 1) + i + 1] = I[j * (w + 1) + i + 1] + z;
      }
    }
    return I;
  }

  static double _box(Float64List I, int w, int h, int i, int j, int r) {
    final a = math.max(0, j - r), b = math.min(h, j + r + 1), l = math.max(0, i - r), q = math.min(w, i + r + 1);
    return (I[b * (w + 1) + q] - I[a * (w + 1) + q] - I[b * (w + 1) + l] + I[a * (w + 1) + l]) / ((b - a) * (q - l));
  }

  /// Finds the receipt; corners TL, TR, BR, BL or null [finde].
  static FoundReceipt? find(Img img) {
    const maxSide = 1400, BL = 4;
    final f = math.min(1.0, maxSide / math.max(img.w, img.h));
    final w = (img.w * f).round(), h = (img.h * f).round();
    final c = f < 1 ? img.resized(w, h) : img;
    final p = c.rgba, n = w * h;
    final y = Float32List(n), y2 = Float32List(n), sat = Float32List(n);
    for (var i = 0; i < n; i++) {
      final r = p[i * 4], g = p[i * 4 + 1], b = p[i * 4 + 2];
      final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
      final v = 0.299 * r + 0.587 * g + 0.114 * b;
      y[i] = v;
      y2[i] = v * v;
      sat[i] = mx != 0 ? (mx - mn) / mx : 0;
    }
    final I1 = _integral(y, w, h), I2 = _integral(y2, w, h);
    final sd = Float32List(n);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        final m = _box(I1, w, h, i, j, 3), m2 = _box(I2, w, h, i, j, 3);
        sd[j * w + i] = math.sqrt(math.max(0, m2 - m * m));
      }
    }
    final sorted = Float32List.fromList(y)..sort();
    final p98 = sorted[(n * 0.98).floor()];
    final bright = math.max(110.0, 0.62 * p98);
    for (final sdT in const [4.5, 8.0, 13.0]) {
      final bw = (w / BL).ceil(), bh = (h / BL).ceil();
      var d = Uint8List(bw * bh);
      for (var bj = 0; bj < bh; bj++) {
        for (var bi = 0; bi < bw; bi++) {
          var ok = 0, tot = 0;
          for (var j = bj * BL; j < math.min(h, bj * BL + BL); j++) {
            for (var i = bi * BL; i < math.min(w, bi * BL + BL); i++) {
              final k = j * w + i;
              tot++;
              if (sd[k] < sdT && sat[k] < 0.22 && y[k] > bright) ok++;
            }
          }
          d[bj * bw + bi] = ok >= tot * 0.6 ? 1 : 0;
        }
      }
      d = _morph(_morph(d, bw, bh, true), bw, bh, true);
      d = _morph(_morph(d, bw, bh, false), bw, bh, false);
      d = _fillHoles(d, bw, bh);
      final regions = _regions(d, bw, bh), total = bw * bh;
      ({double value, List<List<double>> corners, double angle, double share, double text})? best;
      for (final cells in regions) {
        final share = cells.length / total;
        if (share < 0.02 || share > 0.85) continue;
        var dark = 0, px = 0;
        for (final k in cells) {
          final bi = k % bw, bj = k ~/ bw;
          for (var j = bj * BL; j < math.min(h, bj * BL + BL); j++) {
            for (var i = bi * BL; i < math.min(w, bi * BL + BL); i++) {
              px++;
              if (y[j * w + i] < 110) dark++;
            }
          }
        }
        final text = dark / px;
        if (text < 0.01 || text > 0.4) continue;
        final edge = <List<double>>[];
        for (final k in cells) {
          final bi = k % bw, bj = k ~/ bw;
          if (bi == 0 || bj == 0 || bi == bw - 1 || bj == bh - 1 || d[k - 1] == 0 || d[k + 1] == 0 || d[k - bw] == 0 || d[k + bw] == 0) {
            edge.add([bi + 0.5, bj + 0.5]);
          }
        }
        if (edge.length < 8) continue;
        final hull = convexHull(edge);
        final (angle, corners) = minQuad(hull);
        double area = 0;
        for (var i = 0; i < hull.length; i++) {
          final a = hull[i], q = hull[(i + 1) % hull.length];
          area += a[0] * q[1] - q[0] * a[1];
        }
        area = area.abs() / 2;
        final fill = cells.length / math.max(1, area);
        final double value = cells.length * math.min(1.0, text / 0.03) * (fill > 0.8 ? 1 : 0.3);
        if (best == null || value > best.value) best = (value: value, corners: corners, angle: angle, share: share, text: text);
      }
      if (best != null) {
        final k = BL / f; // block coordinate → original pixel
        return FoundReceipt([for (final q in best.corners) [q[0] * k, q[1] * k]], best.angle, best.share, best.text, sdT);
      }
    }
    return null;
  }

  static Uint8List _morph(Uint8List d, int bw, int bh, bool dilate) {
    final o = Uint8List(d.length);
    for (var j = 0; j < bh; j++) {
      for (var i = 0; i < bw; i++) {
        var v = dilate ? 0 : 1;
        for (var dj = -1; dj <= 1; dj++) {
          for (var di = -1; di <= 1; di++) {
            final a = i + di, b = j + dj;
            final x = a < 0 || b < 0 || a >= bw || b >= bh ? (dilate ? 0 : 1) : d[b * bw + a];
            if (dilate) {
              if (x != 0) v = 1;
            } else if (x == 0) {
              v = 0;
            }
          }
        }
        o[j * bw + i] = v;
      }
    }
    return o;
  }

  static Uint8List _fillHoles(Uint8List d, int bw, int bh) {
    final outside = Uint8List(d.length), stack = <int>[];
    void start(int i, int j) {
      final k = j * bw + i;
      if (d[k] == 0 && outside[k] == 0) {
        outside[k] = 1;
        stack.add(k);
      }
    }

    for (var i = 0; i < bw; i++) {
      start(i, 0);
      start(i, bh - 1);
    }
    for (var j = 0; j < bh; j++) {
      start(0, j);
      start(bw - 1, j);
    }
    while (stack.isNotEmpty) {
      final k = stack.removeLast(), i = k % bw, j = k ~/ bw;
      if (i > 0) start(i - 1, j);
      if (i < bw - 1) start(i + 1, j);
      if (j > 0) start(i, j - 1);
      if (j < bh - 1) start(i, j + 1);
    }
    final o = Uint8List(d.length);
    for (var k = 0; k < d.length; k++) {
      o[k] = outside[k] != 0 ? 0 : 1;
    }
    return o;
  }

  static List<List<int>> _regions(Uint8List d, int bw, int bh) {
    final lab = Int32List(d.length), list = <List<int>>[];
    var nr = 0;
    for (var s = 0; s < d.length; s++) {
      if (d[s] == 0 || lab[s] != 0) continue;
      nr++;
      final st = [s];
      lab[s] = nr;
      final cells = <int>[];
      while (st.isNotEmpty) {
        final k = st.removeLast();
        cells.add(k);
        final i = k % bw, j = k ~/ bw;
        if (i > 0 && d[k - 1] != 0 && lab[k - 1] == 0) {
          lab[k - 1] = nr;
          st.add(k - 1);
        }
        if (i < bw - 1 && d[k + 1] != 0 && lab[k + 1] == 0) {
          lab[k + 1] = nr;
          st.add(k + 1);
        }
        if (j > 0 && d[k - bw] != 0 && lab[k - bw] == 0) {
          lab[k - bw] = nr;
          st.add(k - bw);
        }
        if (j < bh - 1 && d[k + bw] != 0 && lab[k + bw] == 0) {
          lab[k + bw] = nr;
          st.add(k + bw);
        }
      }
      list.add(cells);
    }
    return list;
  }

  /// Monotone chain convex hull [huelle].
  static List<List<double>> convexHull(List<List<double>> pts0) {
    final pts = List<List<double>>.of(pts0)..sort((a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]));
    double cross(List<double> o, List<double> a, List<double> b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
    final lower = <List<double>>[];
    for (final p in pts) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <List<double>>[];
    for (var i = pts.length - 1; i >= 0; i--) {
      final p = pts[i];
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// Smallest rectangle (−45° … 45°), corners as extreme points in the rotated frame [viereck].
  static (double, List<List<double>>) minQuad(List<List<double>> hull) {
    double? bestA, bestGr, bc, bs;
    for (var gr = -45.0; gr < 45; gr += 0.5) {
      final t = gr * math.pi / 180, c = math.cos(t), s = math.sin(t);
      var u0 = 1e9, u1 = -1e9, v0 = 1e9, v1 = -1e9;
      for (final p in hull) {
        final u = p[0] * c + p[1] * s, v = -p[0] * s + p[1] * c;
        if (u < u0) u0 = u;
        if (u > u1) u1 = u;
        if (v < v0) v0 = v;
        if (v > v1) v1 = v;
      }
      final a = (u1 - u0) * (v1 - v0);
      if (bestA == null || a < bestA) {
        bestA = a;
        bestGr = gr;
        bc = c;
        bs = s;
      }
    }
    final uv = [for (final p in hull) [p[0] * bc! + p[1] * bs!, -p[0] * bs + p[1] * bc, p[0], p[1]]];
    List<double> pick(double Function(List<double>) fn) => uv.reduce((b, p) => fn(p) < fn(b) ? p : b);
    final tl = pick((p) => p[0] + p[1]), tr = pick((p) => -(p[0] - p[1])), br = pick((p) => -(p[0] + p[1])), bl = pick((p) => p[0] - p[1]);
    return (bestGr!, [for (final p in [tl, tr, br, bl]) [p[2], p[3]]]);
  }

  /// Homography output (0,0 … W,H) → source quad; Gaussian elimination for 8 unknowns [homographie].
  static List<double> homography(List<List<double>> q, double W, double H) {
    final z = [
      [0.0, 0.0],
      [W, 0.0],
      [W, H],
      [0.0, H]
    ];
    final A = <List<double>>[], b = <double>[];
    for (var i = 0; i < 4; i++) {
      final x = z[i][0], y = z[i][1], u = q[i][0], v = q[i][1];
      A.add([x, y, 1, 0, 0, 0, -x * u, -y * u]);
      b.add(u);
      A.add([0, 0, 0, x, y, 1, -x * v, -y * v]);
      b.add(v);
    }
    for (var i = 0; i < 8; i++) {
      var p = i;
      for (var j = i + 1; j < 8; j++) {
        if (A[j][i].abs() > A[p][i].abs()) p = j;
      }
      final ta = A[i];
      A[i] = A[p];
      A[p] = ta;
      final tb = b[i];
      b[i] = b[p];
      b[p] = tb;
      for (var j = i + 1; j < 8; j++) {
        final f = A[j][i] / A[i][i];
        for (var k = i; k < 8; k++) {
          A[j][k] -= f * A[i][k];
        }
        b[j] -= f * b[i];
      }
    }
    final x = List<double>.filled(8, 0);
    for (var i = 7; i >= 0; i--) {
      var s = b[i];
      for (var k = i + 1; k < 8; k++) {
        s -= A[i][k] * x[k];
      }
      x[i] = s / A[i][i];
    }
    return x;
  }

  static double _dist(List<double> a, List<double> b) => math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2));

  /// Four-point rectification; short side to about [targetWidth], ≤ 3.5×, never smaller [entzerre].
  static Rectified rectify(Img img, List<List<double>> corners, [double targetWidth = 1300]) {
    final tl = corners[0], tr = corners[1], br = corners[2], bl = corners[3];
    final wq = math.max(_dist(tl, tr), _dist(bl, br)), hq = math.max(_dist(tl, bl), _dist(tr, br));
    final short = math.min(wq, hq);
    final k = math.max(1.0, math.min(3.5, targetWidth / short));
    var W = (wq * k).round(), H = (hq * k).round();
    const maxPx = 14e6;
    if (W * H > maxPx) {
      final r = math.sqrt(maxPx / (W * H));
      W = (W * r).round();
      H = (H * r).round();
    }
    final hg = homography(corners, W.toDouble(), H.toDouble());
    final out = Img(W, H), od = out.rgba, sd = img.rgba, sw = img.w, sh = img.h;
    for (var y = 0; y < H; y++) {
      for (var x = 0; x < W; x++) {
        final den = hg[6] * x + hg[7] * y + 1;
        final u = (hg[0] * x + hg[1] * y + hg[2]) / den, v = (hg[3] * x + hg[4] * y + hg[5]) / den;
        final o = (y * W + x) * 4;
        if (u < 0 || v < 0 || u >= sw - 1 || v >= sh - 1) continue; // white
        final x0 = u.floor(), y0 = v.floor(), fx = u - x0, fy = v - y0;
        final i00 = (y0 * sw + x0) * 4, i10 = i00 + 4, i01 = i00 + sw * 4, i11 = i01 + 4;
        for (var ch = 0; ch < 3; ch++) {
          od[o + ch] = (sd[i00 + ch] * (1 - fx) * (1 - fy) + sd[i10 + ch] * fx * (1 - fy) + sd[i01 + ch] * (1 - fx) * fy + sd[i11 + ch] * fx * fy).round();
        }
      }
    }
    return Rectified(out, k);
  }

  static List<({double y, double m, double g})> _stripAngles(Img c) {
    final f = math.min(1.0, 520 / c.w);
    final w = (c.w * f).round(), h = (c.h * f).round();
    final k = f < 1 ? c.resized(w, h) : c;
    final p = k.rgba;
    final height = math.max(160, (w * 0.5).round()), step = (height / 2).round();
    final out = <({double y, double m, double g})>[];
    for (var y0 = 0; y0 + height <= h + step / 2; y0 += step) {
      final pts = <int>[];
      final y1 = math.min(h, y0 + height);
      for (var j = y0; j < y1; j++) {
        for (var i = (w * 0.1).round(); i < (w * 0.95).round(); i++) {
          final o = (j * w + i) * 4;
          if (0.299 * p[o] + 0.587 * p[o + 1] + 0.114 * p[o + 2] < 100) pts.addAll([i, j]);
        }
      }
      if (pts.length < 300) continue;
      double bw = 0, bv = -1, sum = 0;
      var n = 0;
      for (var gr = -25.0; gr <= 25; gr += 0.5) {
        final m = math.tan(gr * math.pi / 180);
        final bins = <int, int>{};
        for (var q = 0; q < pts.length; q += 2) {
          final r = (pts[q + 1] - pts[q] * m + 0.5).floor();
          bins[r] = (bins[r] ?? 0) + 1;
        }
        double a = 0, a2 = 0;
        for (final v in bins.values) {
          a += v;
          a2 += v * v;
        }
        final v = a2 / bins.length - math.pow(a / bins.length, 2);
        sum += v;
        n++;
        if (v > bv) {
          bv = v;
          bw = gr;
        }
      }
      if (bv > 1.6 * (sum / n)) out.add((y: ((y0 + y1) / 2) / f, m: math.tan(bw * math.pi / 180), g: pts.length * (bv / (sum / n))));
    }
    return out;
  }

  /// Residual slant: shear that changes linearly with height; two passes [gerade].
  static Img straighten(Img c) {
    var cur = c;
    for (var pass = 0; pass < 2; pass++) {
      final sw = _stripAngles(cur);
      if (sw.isEmpty) break;
      double W = 0, Sy = 0, Sm = 0, Syy = 0, Sym = 0;
      for (final e in sw) {
        W += e.g;
        Sy += e.g * e.y;
        Sm += e.g * e.m;
        Syy += e.g * e.y * e.y;
        Sym += e.g * e.y * e.m;
      }
      final det = W * Syy - Sy * Sy;
      double a, b;
      if (sw.length < 2 || det.abs() < 1e-6) {
        a = Sm / W;
        b = 0;
      } else {
        b = (W * Sym - Sy * Sm) / det;
        a = (Sm - b * Sy) / W;
      }
      final H = cur.h, Wd = cur.w;
      double mAt(num y) => a + b * y;
      final mmax = math.max(mAt(0).abs(), mAt(H).abs());
      if (mmax < 0.007) break; // below 0.4°: nothing to do
      final off = (math.min(mmax, 0.6) * Wd).ceil(), HH = H + 2 * off;
      final sd = cur.rgba;
      final o = Img(Wd, HH), od = o.rgba;
      for (var y = 0; y < HH; y++) {
        final ys0 = y - off, m = mAt(ys0.clamp(0, H)).clamp(-0.6, 0.6);
        for (var x = 0; x < Wd; x++) {
          final v = ys0 + x * m, p = (y * Wd + x) * 4;
          if (v < 0 || v >= H - 1) continue; // white
          final y0 = v.floor(), fy = v - y0, i0 = (y0 * Wd + x) * 4, i1 = i0 + Wd * 4;
          for (var ch = 0; ch < 3; ch++) {
            od[p + ch] = (sd[i0 + ch] * (1 - fy) + sd[i1 + ch] * fy).round();
          }
        }
      }
      cur = o;
    }
    return cur;
  }
}
