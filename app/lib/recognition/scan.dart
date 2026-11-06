// Fasan Split – receipt scan: straighten text lines, crop to the paper, flatten the lighting. MPL-2.0
//
// Port of Fasan-Karte/site/scan.js (3.19). Method (classical, no extra model): in a flat scan every text line is
// horizontal, the left margin is vertical and the text has the same size everywhere. Each line is measured as a smooth
// curve, plus the left margin and the text size; then a smooth surface (tensor-product cubic B-spline, robust least
// squares) maps the flat scan to the photo. Text-line constraint as in Li et al., ICCV 2023, and Zucker's page_dewarp
// (2016), here with a free-form surface. Lighting: morphological closing of the paper brightness, divided out.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:typed_data';

import 'image.dart';
import 'package:fasan_reader/model.dart';
import 'package:fasan_core/text_util.dart';

class Paper {
  const Paper(this.left, this.right, this.top, this.bottom, this.feather);

  final double left, right, top, bottom, feather;
}

class ScanResult {
  ScanResult(this.image, this.toScan, this.toSource, this.paper, this.textHeightOut, this.stats);

  final Img image;
  final List<double> Function(double x, double y) toScan;
  final List<double> Function(double x, double y) toSource;
  final Paper paper;
  final int textHeightOut;
  final Map<String, Object> stats;

  /// Axis-aligned box in the photo → axis-aligned box in the scan (corners and edge midpoints mapped).
  Box boxToScan(Box b) {
    final ps = [
      toScan(b.x0, b.y0),
      toScan(b.x1, b.y0),
      toScan(b.x0, b.y1),
      toScan(b.x1, b.y1),
      toScan(b.cx, b.y0),
      toScan(b.cx, b.y1),
    ];
    return Box(math.max(0, minOf(ps.map((p) => p[0]))), math.max(0, minOf(ps.map((p) => p[1]))), math.min(image.w.toDouble(), maxOf(ps.map((p) => p[0]))),
        math.min(image.h.toDouble(), maxOf(ps.map((p) => p[1]))));
  }
}

class _Pt {
  const _Pt(this.x, this.y, this.h);

  final double x, y, h;
}

class _SLine {
  _SLine(this.words, this.pts, this.h, this.xs, this.xe, this.x0, this.coef, this.slopeKnown, this.pitch);

  final List<Word> words;
  final List<_Pt> pts;
  final double h, xs, xe, x0;
  List<double> coef;
  final bool slopeKnown;
  final double? pitch;
  double yRef = 0, scale = 1, xm = 0, V = 0;
}

double _median(Iterable<double> v) => medianOf(v);
double _clamp(double v, double lo, double hi) => math.max(lo, math.min(hi, v));

double _wordHeight(Word w) {
  final bh = w.box.h, bw = w.box.w;
  return math.max(3, bw < 3 * bh || w.tilt == null || w.tilt == 0 ? bh : math.max(0.5 * bh, bh - w.tilt!.abs() * bw));
}

double? _wordPitch(Word w) {
  final n = w.text.replaceAll(RegExp(r'\s'), '').length;
  return n >= 3 ? w.box.w / (n + 0.8) : null;
}

List<_Pt> _wordPoints(Word w) {
  final cx = w.box.cx, cy = w.box.cy, ww = w.box.w, h = _wordHeight(w);
  if (w.tilt != null && ww > 3 * h) {
    return [
      for (final f in const [0.15, 0.5, 0.85])
        () {
          final x = w.box.x0 + f * ww;
          return _Pt(x, cy + w.tilt! * (x - cx), h);
        }()
    ];
  }
  return [_Pt(cx, cy, h)];
}

List<double>? _solveDense(List<Float64List> A, int n) {
  for (var c = 0; c < n; c++) {
    var piv = c;
    for (var r = c + 1; r < n; r++) {
      if (A[r][c].abs() > A[piv][c].abs()) piv = r;
    }
    if (A[piv][c].abs() < 1e-12) return null;
    if (piv != c) {
      final t = A[c];
      A[c] = A[piv];
      A[piv] = t;
    }
    for (var r = c + 1; r < n; r++) {
      final f = A[r][c] / A[c][c];
      if (f == 0) continue;
      for (var k = c; k <= n; k++) {
        A[r][k] -= f * A[c][k];
      }
    }
  }
  final x = List<double>.filled(n, 0);
  for (var r = n - 1; r >= 0; r--) {
    var s = A[r][n];
    for (var k = r + 1; k < n; k++) {
      s -= A[r][k] * x[k];
    }
    x[r] = s / A[r][r];
  }
  return x;
}

/// Least squares polynomial y = Σ c_k (x − x0)^k, degree 1 or 2.
List<double>? _fitPoly(List<_Pt> pts, int degree, double x0) {
  final n = degree + 1;
  final A = List.generate(n, (_) => Float64List(n + 1));
  for (final p in pts) {
    final t = p.x - x0, pw = [1.0, t, t * t];
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        A[i][j] += pw[i] * pw[j];
      }
      A[i][n] += pw[i] * p.y;
    }
  }
  return _solveDense(A, n);
}

double _evalCoef(List<double> c, double t) => c[0] + (c.length > 1 ? c[1] : 0) * t + (c.length > 2 ? c[2] : 0) * t * t;
double _slopeCoef(List<double> c, double t) => (c.length > 1 ? c[1] : 0) + 2 * (c.length > 2 ? c[2] : 0) * t;

_SLine _makeLine(List<Word> words) {
  final pts = words.expand(_wordPoints).toList(), h = _median(words.map(_wordHeight));
  final xs = minOf(words.map((w) => w.box.x0)), xe = maxOf(words.map((w) => w.box.x1));
  final x0 = (xs + xe) / 2;
  List<double>? coef;
  var kept = pts;
  for (var round = 0; round < 2; round++) {
    final span = maxOf(kept.map((p) => p.x)) - minOf(kept.map((p) => p.x));
    final degree = kept.length >= 6 && span > 10 * h ? 2 : (kept.length >= 2 && span > 1.5 * h ? 1 : 0);
    coef = degree != 0 ? _fitPoly(kept, degree, x0) : null;
    coef ??= [_median(kept.map((p) => p.y)), 0];
    // curvature limit: a receipt line does not bend more than ~1.5 text heights over its length
    if (coef.length > 2) {
      final lim = (1.5 * h) / math.max(1, math.pow((xe - xs) / 2, 2));
      coef[2] = _clamp(coef[2], -lim, lim);
    }
    final c = coef;
    final next = kept.where((p) => (p.y - _evalCoef(c, p.x - x0)).abs() < 0.6 * h).toList();
    if (next.length == kept.length || next.length < math.max(1, kept.length * 0.6)) break;
    kept = next;
  }
  final pitches = <double>[];
  for (final w in words) {
    final p = _wordPitch(w);
    if (p != null && p != 0) pitches.add(p * math.sqrt(1 + math.pow(_slopeCoef(coef!, w.box.cx - x0), 2)));
  }
  return _SLine(words, kept, h, xs, xe, x0, coef!, kept.length >= 2, pitches.isNotEmpty ? _median(pitches) : null);
}

double _lineY(_SLine L, double x) {
  final cx = _clamp(x, L.xs, L.xe), t = cx - L.x0;
  return _evalCoef(L.coef, t) + _slopeCoef(L.coef, t) * (x - cx);
}

double _lineSlope(_SLine L, double x) => _slopeCoef(L.coef, _clamp(x, L.xs, L.xe) - L.x0);

class _Surface {
  _Surface(this.at, this.weights);

  final List<double> Function(double, double) at;
  final List<double> weights;
}

(Float64List, Float64List)? _solveTwo(List<Float64List> A, int n) {
  for (var c = 0; c < n; c++) {
    var piv = c;
    for (var r = c + 1; r < n; r++) {
      if (A[r][c].abs() > A[piv][c].abs()) piv = r;
    }
    if (A[piv][c].abs() < 1e-14) return null;
    if (piv != c) {
      final t = A[c];
      A[c] = A[piv];
      A[piv] = t;
    }
    final rc = A[c], inv = 1 / rc[c];
    for (var r = c + 1; r < n; r++) {
      final rr = A[r], f = rr[c] * inv;
      if (f == 0) continue;
      for (var k = c; k < n + 2; k++) {
        rr[k] -= f * rc[k];
      }
    }
  }
  final x = Float64List(n), y = Float64List(n);
  for (var r = n - 1; r >= 0; r--) {
    var sx = A[r][n], sy = A[r][n + 1];
    for (var k = r + 1; k < n; k++) {
      sx -= A[r][k] * x[k];
      sy -= A[r][k] * y[k];
    }
    x[r] = sx / A[r][r];
    y[r] = sy / A[r][r];
  }
  return (x, y);
}

List<double> _basis(double t) => [
      math.pow(1 - t, 3) / 6,
      (3 * t * t * t - 6 * t * t + 4) / 6,
      (-3 * t * t * t + 3 * t * t + 3 * t + 1) / 6,
      t * t * t / 6,
    ];

/// Tensor-product cubic B-spline A → B, nu × nv control points, second-difference smoothness, Cauchy reweighting
/// with scale 0.35 text heights [fitSurface].
_Surface? _fitSurface(List<List<double>> A, List<List<double>> B, List<double> H, List<double> box, int nu, int nv, double smooth, [List<double>? startWeights]) {
  final x0 = box[0], y0 = box[1], x1 = box[2], y1 = box[3];
  final su = (nu - 3) / math.max(1e-6, x1 - x0), sv = (nv - 3) / math.max(1e-6, y1 - y0), M = nu * nv;
  ({int iu, int iv, List<double> bu, List<double> bv, double ex, double ey}) locate(double x, double y) {
    final tu = _clamp((x - x0) * su, 0, nu - 3.0), tv = _clamp((y - y0) * sv, 0, nv - 3.0);
    final iu = math.min(nu - 4, tu.floor()), iv = math.min(nv - 4, tv.floor());
    return (iu: iu, iv: iv, bu: _basis(tu - iu), bv: _basis(tv - iv), ex: x - _clamp(x, x0, x1), ey: y - _clamp(y, y0, y1));
  }

  final rows = [for (final p in A) locate(p[0], p[1])];
  var w = startWeights != null ? List<double>.of(startWeights) : List<double>.filled(A.length, 1);
  Float64List? cx, cy;
  final lam = smooth * math.max(1, A.length / M) * 0.5;
  for (var it = 0; it < 5; it++) {
    final N = List.generate(M, (_) => Float64List(M + 2));
    final idx = List<int>.filled(16, 0), val = List<double>.filled(16, 0);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      var n = 0;
      for (var a = 0; a < 4; a++) {
        for (var b = 0; b < 4; b++) {
          idx[n] = (r.iv + a) * nu + r.iu + b;
          val[n] = r.bv[a] * r.bu[b];
          n++;
        }
      }
      for (var p = 0; p < 16; p++) {
        final row = N[idx[p]], vp = val[p] * w[i];
        for (var q = 0; q < 16; q++) {
          row[idx[q]] += vp * val[q];
        }
        row[M] += vp * B[i][0];
        row[M + 1] += vp * B[i][1];
      }
    }
    void pen(int k0, int k1, int k2) {
      final ks = [k0, k1, k2];
      const cs = [1.0, -2.0, 1.0];
      for (var p = 0; p < 3; p++) {
        for (var q = 0; q < 3; q++) {
          N[ks[p]][ks[q]] += lam * cs[p] * cs[q];
        }
      }
    }

    for (var v = 0; v < nv; v++) {
      for (var u = 1; u < nu - 1; u++) {
        pen(v * nu + u - 1, v * nu + u, v * nu + u + 1);
      }
    }
    for (var u = 0; u < nu; u++) {
      for (var v = 1; v < nv - 1; v++) {
        pen((v - 1) * nu + u, v * nu + u, (v + 1) * nu + u);
      }
    }
    for (var k = 0; k < M; k++) {
      N[k][k] += 1e-6;
    }
    final sol = _solveTwo(N, M);
    if (sol == null) return null;
    (cx, cy) = sol;
    w = [
      for (var i = 0; i < rows.length; i++)
        () {
          final r = rows[i];
          double x = 0, y = 0;
          for (var a = 0; a < 4; a++) {
            for (var b = 0; b < 4; b++) {
              final k = (r.iv + a) * nu + r.iu + b, f = r.bv[a] * r.bu[b];
              x += f * cx![k];
              y += f * cy![k];
            }
          }
          final d = math.sqrt(math.pow(x - B[i][0], 2) + math.pow(y - B[i][1], 2)) / (0.35 * H[i]);
          return 1 / (1 + d * d);
        }()
    ];
  }
  final fx = cx!, fy = cy!;
  List<double> atIn(double x, double y) {
    final r = locate(x, y);
    double px = 0, py = 0;
    for (var a = 0; a < 4; a++) {
      for (var b = 0; b < 4; b++) {
        final k = (r.iv + a) * nu + r.iu + b, f = r.bv[a] * r.bu[b];
        px += f * fx[k];
        py += f * fy[k];
      }
    }
    return [px, py];
  }

  List<double> at(double x, double y) {
    final r = locate(x, y);
    var p = atIn(x, y);
    if (r.ex != 0 || r.ey != 0) {
      // linear continuation with the local derivative at the border
      final cxp = _clamp(x, x0, x1), cyp = _clamp(y, y0, y1);
      double sgn(double v) => v == 0 ? 1 : v.sign;
      final p0 = atIn(cxp, cyp), pu = atIn(cxp - sgn(r.ex), cyp), pv = atIn(cxp, cyp - sgn(r.ey));
      p = [
        p0[0] + (p0[0] - pu[0]) * r.ex.abs() + (p0[0] - pv[0]) * r.ey.abs(),
        p0[1] + (p0[1] - pu[1]) * r.ex.abs() + (p0[1] - pv[1]) * r.ey.abs(),
      ];
    }
    return p;
  }

  return _Surface(at, w);
}

/// Last reason why [straighten] gave null (for the protocol).
String scanLastError = '';

ScanResult? _fail(String why) {
  scanLastError = why;
  return null;
}

/// Straightens a receipt photo from its text lines [straighten].
ScanResult? straighten(Img canvas, List<Line> lines, {double smooth = 1, double padX = 0.9, double padY = 1.2, int maxSide = 3600, double maxPixels = 6e6, double maxIgnored = 0.2, double maxFolds = 0.02}) {
  scanLastError = '';
  final W = canvas.w, H = canvas.h;
  var L = [
    for (final z in lines)
      if (z.words.any((w) => w.box.x1 > w.box.x0 && w.box.y1 > w.box.y0)) _makeLine(z.words.where((w) => w.box.x1 > w.box.x0 && w.box.y1 > w.box.y0).toList())
  ];
  if (L.length < 4) return _fail('few lines');
  var H0 = _median(L.map((l) => l.h));
  // only the receipt: similar height, one column, no large gaps
  L = L.where((l) => l.h < 2.6 * H0 && l.h > 0.35 * H0 && l.words.isNotEmpty).toList();
  if (L.length >= 4) {
    double q(List<double> a, double f) {
      final t = stableSorted<double>(a, numAsc);
      return t[math.min(t.length - 1, math.max(0, (t.length * f).floor()))];
    }

    final colL = q(L.map((l) => l.xs).toList(), 0.2), colR = q(L.map((l) => l.xe).toList(), 0.8);
    L = L.where((l) => math.min(l.xe, colR + H0) - math.max(l.xs, colL - H0) > 0.5 * (l.xe - l.xs)).toList();
    double ys(_SLine l) => (_lineY(l, l.xs) + _lineY(l, l.xe)) / 2;
    final sorted = stableSorted<_SLine>(L, (a, b) => numAsc(ys(a), ys(b)));
    final groups = <List<_SLine>>[];
    for (final l in sorted) {
      final g = groups.isNotEmpty ? groups.last : null;
      if (g != null && ys(l) - ys(g.last) < 8 * H0) {
        g.add(l);
      } else {
        groups.add([l]);
      }
    }
    final main = groups.fold<List<_SLine>>(<_SLine>[], (a, g) => g.length > a.length ? g : a);
    final mL = minOf(main.map((l) => l.xs)), mR = maxOf(main.map((l) => l.xe));
    L = [
      for (final g in groups)
        if (identical(g, main) || g.every((l) => math.min(l.xe, mR) - math.max(l.xs, mL) > 0.6 * (l.xe - l.xs))) ...g
    ];
  }
  if (L.length < 4) return _fail('few receipt lines');
  H0 = _median(L.map((l) => l.h));
  final xRef = _median(L.expand((l) => l.pts.map((p) => p.x)));
  for (final l in L) {
    l.yRef = _lineY(l, xRef);
  }
  stableSort<_SLine>(L, (a, b) => numAsc(a.yRef, b.yRef));
  for (final l in L) {
    if (!l.slopeKnown) {
      final nb = [
        for (final o in L)
          if (!identical(o, l) && o.slopeKnown && (o.yRef - l.yRef).abs() < 6 * H0) _lineSlope(o, (l.xs + l.xe) / 2)
      ];
      if (nb.isNotEmpty) {
        l.coef = [l.coef[0], _median(nb)];
        l.yRef = _lineY(l, xRef);
      }
    }
  }
  stableSort<_SLine>(L, (a, b) => numAsc(a.yRef, b.yRef));
  // pieces of one printed line become one line
  for (var i = 0; i + 1 < L.length; i++) {
    final a = L[i], b = L[i + 1];
    final overlapX = math.min(a.xe, b.xe) - math.max(a.xs, b.xs);
    final xm = overlapX > 0 ? (math.max(a.xs, b.xs) + math.min(a.xe, b.xe)) / 2 : (a.xe < b.xs ? (a.xe + b.xs) / 2 : (b.xe + a.xs) / 2);
    if (overlapX < 0.5 * H0 && (_lineY(a, xm) - _lineY(b, xm)).abs() < 0.35 * math.min(a.h, b.h)) {
      final m = _makeLine([...a.words, ...b.words]);
      L.replaceRange(i, i + 2, [m]);
      L[i].yRef = _lineY(L[i], xRef);
      i--;
    }
  }
  if (L.length < 4) return _fail('few lines after merge');
  // scale: text gets smaller with distance (perspective), from the character pitch, robust linear trend
  {
    final withP = L.where((l) => l.pitch != null).toList();
    var P0 = _median(withP.map((l) => l.pitch!));
    if (P0 == 0) P0 = 1;
    final yc = _median(L.map((l) => l.yRef));
    var c = <double>[P0, 0];
    var wts = List<double>.filled(withP.length, 1);
    for (var it = 0; it < 6 && withP.length >= 3; it++) {
      final pts = <_Pt>[
        for (var i = 0; i < withP.length; i++)
          if (wts[i] > 0.5) _Pt(withP[i].yRef, withP[i].pitch!, 0)
      ];
      final f = _fitPoly(pts, 1, yc);
      if (f != null) c = f;
      final cc = c;
      wts = [for (final l in withP) (l.pitch! - _evalCoef(cc, l.yRef - yc)).abs() < 0.15 * P0 ? 1 : 0];
    }
    double pAt(double y) => math.max(0.3 * P0, _evalCoef(c, y - yc));
    final pref = pAt(yc);
    for (final l in L) {
      l.scale = _clamp(pref / pAt(l.yRef), 0.6, 1.6);
    }
  }
  // left margin x = m(y): robust fit through line starts that are not indented
  final starts = [for (final l in L) (y: _lineY(l, l.xs), x: l.xs, h: l.h)];
  var mc = <double>[_median(starts.map((s) => s.x)), 0];
  final y0m = _median(starts.map((s) => s.y));
  var wts = List<double>.filled(starts.length, 1);
  for (var it = 0; it < 6; it++) {
    final use = [
      for (var i = 0; i < starts.length; i++)
        if (wts[i] > 0.5) _Pt(starts[i].y, starts[i].x, 0)
    ];
    if (use.length >= 2) {
      final c = _fitPoly(use, 1, y0m);
      if (c != null) mc = c;
    }
    final m = mc;
    wts = [for (final s in starts) s.x - _evalCoef(m, s.y - y0m) < 0.9 * s.h ? 1 : 0];
  }
  double marginX(double y) => _evalCoef(mc, y - y0m);
  double arc(_SLine l, double xa, double xb) {
    const n = 8;
    final d = (xb - xa) / n;
    double s = 0;
    for (var k = 0; k <= n; k++) {
      final f = k == 0 || k == n ? 1 : (k % 2 == 1 ? 4 : 2), sl = _lineSlope(l, xa + k * d);
      s += f * math.sqrt(1 + sl * sl);
    }
    return (s * d) / 3;
  }

  for (final l in L) {
    var xm = marginX(l.yRef);
    for (var it = 0; it < 3; it++) {
      xm = marginX(_lineY(l, xm));
    }
    l.xm = xm;
  }
  double U(_SLine l, double x) => l.scale * arc(l, l.xm, x);
  L[0].V = 0;
  for (var i = 1; i < L.length; i++) {
    final a = L[i - 1], b = L[i];
    final ox0 = math.max(a.xs, b.xs), ox1 = math.min(a.xe, b.xe);
    final xm = ox1 > ox0 ? (ox0 + ox1) / 2 : xRef, sl = (_lineSlope(a, xm) + _lineSlope(b, xm)) / 2;
    final d = (_lineY(b, xm) - _lineY(a, xm)) / math.sqrt(1 + sl * sl), s = (a.scale + b.scale) / 2;
    b.V = a.V + math.max(0.6 * H0, s * d);
  }
  final T = <List<double>>[], S = <List<double>>[], Hs = <double>[];
  for (final l in L) {
    for (final p in l.pts) {
      T.add([U(l, p.x), l.V]);
      S.add([p.x, p.y]);
      Hs.add(l.h);
    }
  }
  final pX = padX * H0, pY = padY * H0;
  final uMin = math.min(0.0, minOf(L.map((l) => U(l, l.xs)))) - pX, uMax = maxOf(L.map((l) => U(l, l.xe))) + pX;
  final vMin = L[0].V - L[0].h / 2 - pY, vMax = L.last.V + L.last.h / 2 + pY;
  var OW = (uMax - uMin).round(), OH = (vMax - vMin).round();
  final k0 = [1.0, maxSide / math.max(OW, OH), math.sqrt(maxPixels / (OW * OH))].reduce(math.min);
  OW = math.max(16, (OW * k0).round());
  OH = math.max(16, (OH * k0).round());
  final nv = _clamp((L.length / 1.6).roundToDouble(), 5, 40).toInt(), nu = _clamp(((uMax - uMin) / (6 * H0)).roundToDouble(), 4, 10).toInt();
  final back = _fitSurface(T, S, Hs, [uMin, vMin, uMax, vMax], nu, nv, smooth);
  if (back == null) return _fail('surface singular');
  final ignored = back.weights.where((w) => w < 0.3).length / math.max(1, back.weights.length);
  if (ignored > maxIgnored) return _fail('inconsistent lines ${ignored.toStringAsFixed(2)}');
  final sx0 = minOf(S.map((p) => p[0])) - 3 * H0, sy0 = minOf(S.map((p) => p[1])) - 3 * H0;
  final sx1 = maxOf(S.map((p) => p[0])) + 3 * H0, sy1 = maxOf(S.map((p) => p[1])) + 3 * H0;
  final fwd = _fitSurface(S, T, Hs, [sx0, sy0, sx1, sy1], _clamp(((sx1 - sx0) / (6 * H0)).roundToDouble(), 4, 10).toInt(), nv, smooth, back.weights);
  if (fwd == null) return _fail('inverse surface singular');
  List<double> toSource(double ox, double oy) => back.at(uMin + ox / k0, vMin + oy / k0);
  List<double> toScan(double x, double y) {
    final r = fwd.at(x, y);
    return [(r[0] - uMin) * k0, (r[1] - vMin) * k0];
  }

  // render: mapping on a coarse grid, bilinear in between, bilinear sampling of the photo
  const step = 8;
  final gw = (OW / step).ceil() + 1, gh = (OH / step).ceil() + 1;
  final gx = Float32List(gw * gh), gy = Float32List(gw * gh);
  for (var j = 0; j < gh; j++) {
    for (var i = 0; i < gw; i++) {
      final p = toSource(i * step.toDouble(), j * step.toDouble());
      gx[j * gw + i] = p[0];
      gy[j * gw + i] = p[1];
    }
  }
  var folds = 0;
  for (var j = 0; j + 1 < gh; j++) {
    for (var i = 0; i + 1 < gw; i++) {
      final a = j * gw + i, ax = gx[a + 1] - gx[a], ay = gy[a + 1] - gy[a], bx = gx[a + gw] - gx[a], by = gy[a + gw] - gy[a];
      if (ax * by - ay * bx <= 0) folds++;
    }
  }
  final foldShare = folds / ((gw - 1) * (gh - 1));
  if (foldShare > maxFolds) return _fail('folds ${foldShare.toStringAsFixed(3)}');
  final sd = canvas.rgba;
  final out = Img(OW, OH), od = out.rgba;
  for (var y = 0; y < OH; y++) {
    final gj = y / step, j0 = math.min(gh - 2, gj.floor()), fy = gj - j0;
    for (var x = 0; x < OW; x++) {
      final gi = x / step, i0 = math.min(gw - 2, gi.floor()), fx = gi - i0, a = j0 * gw + i0;
      final sx = (gx[a] * (1 - fx) + gx[a + 1] * fx) * (1 - fy) + (gx[a + gw] * (1 - fx) + gx[a + gw + 1] * fx) * fy;
      final sy = (gy[a] * (1 - fx) + gy[a + 1] * fx) * (1 - fy) + (gy[a + gw] * (1 - fx) + gy[a + gw + 1] * fx) * fy;
      final o = (y * OW + x) * 4;
      if (sx < 0 || sy < 0 || sx >= W - 1 || sy >= H - 1) continue; // white
      final x0 = sx.floor(), y0 = sy.floor(), ux = sx - x0, uy = sy - y0, p = (y0 * W + x0) * 4, q = p + W * 4;
      for (var c = 0; c < 3; c++) {
        od[o + c] = ((sd[p + c] * (1 - ux) + sd[p + 4 + c] * ux) * (1 - uy) + (sd[q + c] * (1 - ux) + sd[q + 4 + c] * ux) * uy).round();
      }
    }
  }
  final wav = _median(L.map((l) {
    final ys = l.pts.map((p) => p.y - _lineY(l, p.x)).toList();
    return math.sqrt(ys.fold<double>(0, (a, v) => a + v * v) / math.max(1, ys.length)) / l.h;
  }));
  final paper = Paper(
    (-0.3 * H0 - uMin) * k0,
    (maxOf(L.map((l) => U(l, l.xe))) + 0.3 * H0 - uMin) * k0,
    (L[0].V - math.max(L[0].h, H0) * 0.75 - vMin) * k0,
    (L.last.V + math.max(L.last.h, H0) * 0.75 - vMin) * k0,
    0.3 * H0 * k0,
  );
  return ScanResult(out, toScan, toSource, paper, (H0 * k0).round(), {
    'ignored': toFixed(ignored, 3),
    'textHeightOut': (H0 * k0).round(),
    'lines': L.length,
    'points': T.length,
    'textHeight': H0.round(),
    'size': '$OW×$OH',
    'folds': toFixed(foldShare, 4),
    'lineFit': toFixed(wav, 3),
  });
}

/// Document look: white paper, dark text, no shadows; tone curve keeps soft edges [documentLook].
Img documentLook(Img canvas, {int? textHeight, Paper? paper, double reach = 0.6, double lo = 0.55, double hi = 0.85, double gamma = 1.3}) {
  final w = canvas.w, h = canvas.h, p = canvas.rgba;
  final textH = textHeight != null && textHeight > 0 ? textHeight : math.max(12, (math.min(w, h) / 45).round());
  final f = math.max(1, (textH / 10).round()), sw = (w / f).ceil(), sh = (h / f).ceil();
  final lum = Float32List(w * h);
  for (var i = 0, o = 0; i < w * h; i++, o += 4) {
    lum[i] = 0.299 * p[o] + 0.587 * p[o + 1] + 0.114 * p[o + 2];
  }
  final small = Float32List(sw * sh), cnt = Float32List(sw * sh);
  for (var y = 0; y < h; y++) {
    final j = y ~/ f;
    for (var x = 0; x < w; x++) {
      final k = j * sw + x ~/ f;
      small[k] += lum[y * w + x];
      cnt[k]++;
    }
  }
  for (var k = 0; k < small.length; k++) {
    small[k] /= math.max(1, cnt[k]);
  }
  Float32List filt(Float32List src, int r, String mode) {
    var a = src;
    for (final horiz in [true, false]) {
      final o = Float32List(sw * sh), L = horiz ? sw : sh, Q = horiz ? sh : sw;
      for (var q = 0; q < Q; q++) {
        for (var l = 0; l < L; l++) {
          double acc = mode == 'min' ? 1e9 : 0;
          var n = 0;
          for (var t = math.max(0, l - r); t <= math.min(L - 1, l + r); t++) {
            final v = a[horiz ? q * sw + t : t * sw + q];
            if (mode == 'max') {
              if (v > acc) acc = v;
            } else if (mode == 'min') {
              if (v < acc) acc = v;
            } else {
              acc += v;
              n++;
            }
          }
          o[horiz ? q * sw + l : l * sw + q] = mode == 'mean' ? acc / n : acc;
        }
      }
      a = o;
    }
    return a;
  }

  final rMax = math.max(1, (reach * textH / f).round());
  final bg = filt(filt(filt(small, rMax, 'max'), rMax, 'min'), math.max(1, (rMax / 2).round()), 'mean');
  final out = Img(w, h), od = out.rgba;
  for (var y = 0; y < h; y++) {
    final gj = _clamp(y / f - 0.5, 0, sh - 1.0), j0 = math.min(math.max(0, sh - 2), gj.floor()), fy = sh < 2 ? 0.0 : gj - j0;
    for (var x = 0; x < w; x++) {
      final gi = _clamp(x / f - 0.5, 0, sw - 1.0), i0 = math.min(math.max(0, sw - 2), gi.floor()), fx = sw < 2 ? 0.0 : gi - i0, a = j0 * sw + i0;
      final b = sh < 2 || sw < 2 ? bg[0] : (bg[a] * (1 - fx) + bg[a + 1] * fx) * (1 - fy) + (bg[a + sw] * (1 - fx) + bg[a + sw + 1] * fx) * fy;
      final o = (y * w + x) * 4, v = lum[y * w + x] / math.max(30, b);
      var t = _clamp((v - lo) / (hi - lo), 0, 1);
      if (paper != null) {
        final dOut = [paper.left - x, x - paper.right, paper.top - y, y - paper.bottom].reduce(math.max);
        final al = _clamp((dOut + 0.5 * paper.feather) / paper.feather, 0, 1);
        if (al > 0) t = t + al * (1 - t);
      }
      final g = (255 * math.pow(t, gamma)).round();
      od[o] = od[o + 1] = od[o + 2] = g;
    }
  }
  return out;
}
