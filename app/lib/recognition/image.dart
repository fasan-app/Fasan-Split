// Fasan Split – small RGBA image type and the image operations the reader needs. MPL-2.0
//
// The web app works on <canvas>: drawImage with imageSmoothingQuality 'high'. Browsers do not specify that filter;
// here downscaling averages several bilinear samples per output pixel (≈ area filter) and upscaling is bilinear.
// Pixel values therefore differ slightly from the browser; the regression tests measure the effect (fasan-diagnose).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;

class Img {
  Img(this.w, this.h, [Uint8List? rgba]) : rgba = rgba ?? (Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255));

  final int w, h;
  final Uint8List rgba;

  static Img decode(Uint8List bytes) {
    final d = im.decodeImage(bytes);
    if (d == null) throw const FormatException('Bild nicht lesbar');
    return fromImage(im.bakeOrientation(d));
  }

  static Img fromImage(im.Image d) {
    final c = d.numChannels == 4 && d.format == im.Format.uint8 ? d : d.convert(format: im.Format.uint8, numChannels: 4);
    return Img(c.width, c.height, Uint8List.fromList(c.getBytes(order: im.ChannelOrder.rgba)));
  }

  im.Image toImage() => im.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4, order: im.ChannelOrder.rgba);

  Uint8List jpeg([int quality = 85]) => im.encodeJpg(toImage(), quality: quality);

  Uint8List png() => im.encodePng(toImage());

  Img copy() => Img(w, h, Uint8List.fromList(rgba));

  /// Luma 0–255 (0.299 R + 0.587 G + 0.114 B) [grau].
  Float32List gray() {
    final n = w * h, y = Float32List(n);
    for (var i = 0, j = 0; i < n; i++, j += 4) {
      y[i] = 0.299 * rgba[j] + 0.587 * rgba[j + 1] + 0.114 * rgba[j + 2];
    }
    return y;
  }

  static Img fromGray(List<double> v, int w, int h) {
    final o = Img(w, h);
    for (var i = 0, j = 0; i < w * h; i++, j += 4) {
      final x = v[i].clamp(0, 255).round();
      o.rgba[j] = o.rgba[j + 1] = o.rgba[j + 2] = x;
      o.rgba[j + 3] = 255;
    }
    return o;
  }

  /// Whole image to W×H (canvas drawImage(c, 0, 0, W, H)).
  Img resized(int W, int H) => region(0, 0, w.toDouble(), h.toDouble(), W, H);

  /// Source rectangle (fractional) to W×H (canvas drawImage(c, sx, sy, sw, sh, 0, 0, W, H)).
  /// Outside the image the result is white like a cleared canvas filled with #fff… but drawImage leaves it transparent;
  /// all callers clamp their rectangles to the image, so edges simply repeat the border pixel.
  Img region(double sx, double sy, double sw, double sh, int W, int H) {
    W = math.max(1, W);
    H = math.max(1, H);
    final out = Img(W, H);
    final o = out.rgba, s = rgba;
    final fx = sw / W, fy = sh / H;
    final nx = math.max(1, math.min(4, fx.ceil())), ny = math.max(1, math.min(4, fy.ceil()));
    // per output column: nx sample positions → (x0 index, x1 index, weight)
    final xi0 = Int32List(W * nx), xi1 = Int32List(W * nx), xw = Float32List(W * nx);
    for (var x = 0; x < W; x++) {
      for (var a = 0; a < nx; a++) {
        final px = sx + (x + (a + 0.5) / nx) * fx - 0.5;
        final c = px.clamp(0.0, w - 1.0);
        final i0 = c.floor(), i1 = math.min(w - 1, i0 + 1);
        xi0[x * nx + a] = i0 * 4;
        xi1[x * nx + a] = i1 * 4;
        xw[x * nx + a] = c - i0;
      }
    }
    final inv = 1 / (nx * ny);
    final acc = Float64List(3);
    for (var y = 0; y < H; y++) {
      for (var x = 0; x < W; x++) {
        acc[0] = acc[1] = acc[2] = 0;
        for (var b = 0; b < ny; b++) {
          final py = (sy + (y + (b + 0.5) / ny) * fy - 0.5).clamp(0.0, h - 1.0);
          final j0 = py.floor(), j1 = math.min(h - 1, j0 + 1), v = py - j0;
          final r0 = j0 * w * 4, r1 = j1 * w * 4;
          for (var a = 0; a < nx; a++) {
            final k = x * nx + a, u = xw[k], p0 = xi0[k], p1 = xi1[k];
            for (var ch = 0; ch < 3; ch++) {
              final top = s[r0 + p0 + ch] * (1 - u) + s[r0 + p1 + ch] * u;
              final bot = s[r1 + p0 + ch] * (1 - u) + s[r1 + p1 + ch] * u;
              acc[ch] += top * (1 - v) + bot * v;
            }
          }
        }
        final q = (y * W + x) * 4;
        o[q] = (acc[0] * inv).round();
        o[q + 1] = (acc[1] * inv).round();
        o[q + 2] = (acc[2] * inv).round();
        o[q + 3] = 255;
      }
    }
    return out;
  }

  /// Integer crop (getImageData(x, y, w, h)).
  Img crop(int x, int y, int cw, int ch) {
    final out = Img(cw, ch);
    for (var j = 0; j < ch; j++) {
      final sy = (y + j).clamp(0, h - 1);
      for (var i = 0; i < cw; i++) {
        final sx = (x + i).clamp(0, w - 1);
        final s = (sy * w + sx) * 4, d = (j * cw + i) * 4;
        out.rgba[d] = rgba[s];
        out.rgba[d + 1] = rgba[s + 1];
        out.rgba[d + 2] = rgba[s + 2];
        out.rgba[d + 3] = 255;
      }
    }
    return out;
  }

  /// Rotated by 180° [drehen180].
  Img rotated180() {
    final out = Img(w, h);
    final n = w * h;
    for (var i = 0; i < n; i++) {
      final s = i * 4, d = (n - 1 - i) * 4;
      out.rgba[d] = rgba[s];
      out.rgba[d + 1] = rgba[s + 1];
      out.rgba[d + 2] = rgba[s + 2];
      out.rgba[d + 3] = 255;
    }
    return out;
  }

  /// Rotated by 90° clockwise.
  Img rotated90() {
    final out = Img(h, w);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final s = (y * w + x) * 4, d = (x * h + (h - 1 - y)) * 4;
        out.rgba[d] = rgba[s];
        out.rgba[d + 1] = rgba[s + 1];
        out.rgba[d + 2] = rgba[s + 2];
        out.rgba[d + 3] = 255;
      }
    }
    return out;
  }

  /// Bilinear sample of channel [ch] at (x, y), clamped.
  double sample(double x, double y, int ch) {
    final cx = x.clamp(0.0, w - 1.001), cy = y.clamp(0.0, h - 1.001);
    final xi = cx.floor(), yi = cy.floor(), a = cx - xi, b = cy - yi;
    final p0 = (yi * w + xi) * 4 + ch, p1 = p0 + w * 4;
    return (rgba[p0] * (1 - a) + rgba[p0 + 4] * a) * (1 - b) + (rgba[p1] * (1 - a) + rgba[p1 + 4] * a) * b;
  }
}

/// Fit the longest side to [max] (fotoLeinwand).
Img fitLongest(Img img, [int max = 2200]) {
  final f = math.min(1.0, max / math.max(img.w, img.h));
  if (f >= 1) return img;
  return img.resized((img.w * f).round(), (img.h * f).round());
}
