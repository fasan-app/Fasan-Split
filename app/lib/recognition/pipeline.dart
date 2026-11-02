// Fasan Split – the whole recognition of one receipt photo. MPL-2.0
//
// Port of Bon.erkenne (Fasan-Karte/site/bon.js 3.19, PaddleOCR path). Steps:
// 1. find the receipt in the photo and rectify it (receipt_image.dart); turn by 90° if the text is sideways
// 2. read the cut-out, rotated by 180° if unreadable, else the whole photo (also re-cut from the text position)
// 2a. unfold with UVDoc (optional model), 2b. straighten from the text lines like a document scanner (scan.dart)
// 3. without a checked total: further passes on improved images (scan look, contrast, dark)
// 4. read every amount of the item block several times (votes), then the best pass wins
// The photo never leaves the device. Tesseract (fallback in the web app) is not part of the app.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:zxing2/qrcode.dart';

import 'image.dart';
import 'model.dart';
import 'paddle.dart';
import 'reader.dart';
import 'receipt_image.dart';
import 'scan.dart';
import 'text_util.dart';

/// Progress of the recognition: stage text, 0–1, optional preview (straightened image with the boxes found so far).
class RecognitionProgress {
  const RecognitionProgress(this.stage, this.progress, {this.preview, this.boxes, this.straight = false});

  final String stage;
  final double progress;
  final Uint8List? preview;

  /// Boxes normalised to 0–1 of the preview.
  final List<List<double>>? boxes;
  final bool straight;
}

class Recognition {
  Recognition({
    required this.result,
    required this.display,
    required this.original,
    required this.source,
    required this.tries,
    required this.qr,
    required this.log,
    required this.width,
    required this.height,
  });

  final ReadResult result;

  /// Shown image (straightened scan in document look) and the colour version.
  final Img display;
  final Img? original;
  final String source;
  final List<String> tries;
  final QrInfo? qr;

  /// Protocol of the steps (shared only on request; contains no image).
  final Map<String, Object?> log;
  final int width, height;
}

class _Pass {
  _Pass(this.g, this.r, this.canvas, this.read, this.name, this.corners, this.lines, this.straight);

  double g;
  ReadResult r;
  final Img canvas; // shown for this pass
  final Img read; // what was read
  final String name;
  final List<List<double>>? corners;
  final Lines lines;
  final bool straight;
  double gEnd = 0;
}

class Recognizer {
  Recognizer(this.ocr);

  final PaddleOcr ocr;
  final _sw = Stopwatch();
  late List<Map<String, Object?>> _steps, _errors;

  void _log(String type, [Map<String, Object?> d = const {}]) => _steps.add({'t': _sw.elapsedMilliseconds, 'typ': type, ...d});
  void _err(String where, Object e) => _errors.add({'t': _sw.elapsedMilliseconds, 'wo': where, 'text': '$e'});

  Recognition recognize(Uint8List bytes, {void Function(RecognitionProgress)? onProgress}) {
    _sw
      ..reset()
      ..start();
    _steps = [];
    _errors = [];
    void Function(double) stage(String text, double a, double b) =>
        (m) => onProgress?.call(RecognitionProgress(text, a + (b - a) * m.clamp(0.0, 1.0)));
    _log('motor', {'paddle': true, 'uvdoc': ocr.uvdoc != null});
    stage('Bon wird im Foto gesucht', 0.1, 0.14)(0);
    final photo = Img.decode(bytes);
    // 1. find the receipt and rectify
    ({Img canvas, Img raw, List<List<double>> corners})? cut;
    try {
      final f = ReceiptImage.find(photo);
      if (f != null) {
        var ec = f.corners;
        // add a margin: the found paper edge often lies inside (shadow, fold) and cut the line starts (4 % / 3 % outwards)
        final mx = ec.fold<double>(0, (a, p) => a + p[0]) / 4, my = ec.fold<double>(0, (a, p) => a + p[1]) / 4;
        ec = [
          for (final p in ec) [(mx + (p[0] - mx) * 1.08).clamp(0, photo.w - 1.0), (my + (p[1] - my) * 1.03).clamp(0, photo.h - 1.0)]
        ];
        var e = ReceiptImage.rectify(photo, ec);
        var sc = ReceiptImage.straighten(e.image);
        if (ocr.sideways(e.image)) {
          ec = [ec[3], ec[0], ec[1], ec[2]];
          e = ReceiptImage.rectify(photo, ec);
          sc = ReceiptImage.straighten(e.image);
        }
        cut = (canvas: sc, raw: e.image, corners: ec);
      }
    } catch (e) {
      cut = null;
      _err('ausschnitt', e);
    }
    _log('foto', {
      'breite': photo.w,
      'hoehe': photo.h,
      'ausschnitt': cut == null ? null : {'breite': cut.canvas.w, 'hoehe': cut.canvas.h}
    });
    var qr = _qrSearch(photo);
    if (qr == null && cut != null) qr = _qrTiles(cut.raw) ?? _qrSearch(cut.raw) ?? _qrTiles(cut.canvas);
    final tries = <String>[], all = <_Pass>[];
    _Pass? best;
    final scans = <Img, ScanResult>{};
    var readable = 0.0;
    double run(Img canvas, String name, List<List<double>>? corners, void Function(double) progress, {Img? display, bool? straightArg}) {
      final straight = straightArg ?? name != 'foto';
      final ts = _sw.elapsedMilliseconds;
      final words = ocr.words(canvas, progress: progress);
      var z = linesFrom(words, straight: straight);
      var r = readLines(z.lines, qr);
      var g = quality(r, words);
      final zk = linesByColumns(words) ?? const <Lines>[];
      var zname = '';
      // with a confirmed total a large offset still costs; a whole-line offset only if the total confirms it
      for (final z2 in zk) {
        final r2 = readLines(z2.lines, qr);
        final ok2 = r2.check.ok;
        final g2 = quality(r2, words) - (ok2 ? 300 : 400) * math.max(0, z2.columns!.offset.abs() - 0.6);
        if (g2 > g) {
          z = z2;
          r = r2;
          g = g2;
          zname = '+spalten(${_num(z2.columns!.offset)})';
        }
      }
      // amount column re-split and read – only if the reading does not check out yet
      if (!r.check.ok) {
        try {
          final w2 = _columnReread(canvas, words);
          if (w2 != null) {
            for (final z2 in [linesFrom(w2, straight: straight), ...(linesByColumns(w2) ?? const <Lines>[])]) {
              final r2 = readLines(z2.lines, qr);
              final vs = z2.columns?.offset ?? 0;
              final g2 = quality(r2, w2) - (r2.check.ok ? 300 : 400) * math.max(0, vs.abs() - 0.6) - 150;
              if (g2 > g) {
                z = z2;
                r = r2;
                g = g2;
                zname = '+spalte${z2.columns != null ? '(${_num(vs)})' : ''}';
              }
            }
          }
        } catch (e) {
          _err('spalte', e);
        }
      }
      final fullName = name + zname;
      g += displayBonus(fullName, straight);
      tries.add('$fullName:${jsRound(g)}');
      _log('lauf', {
        'name': fullName,
        'guete': jsRound(g),
        'ms': _sw.elapsedMilliseconds - ts,
        'breite': canvas.w,
        'hoehe': canvas.h,
        'woerter': words.length,
        'posten': r.items.length,
        'summe': r.sum,
        'total': r.total,
        'gesamtOk': r.check.ok,
        'zeilen': z.lines.map((x) => x.text).toList(),
      });
      final shown = display ?? canvas;
      final e = _Pass(g, r, shown, canvas, fullName, corners, z, straight);
      all.add(e);
      // preview for the progress screen: first image with the lines found, then the straightened scan
      if (onProgress != null && (all.length == 1 || fullName.startsWith('gerade'))) {
        try {
          final W0 = shown.w, H0 = shown.h, f = math.min(1.0, 640 / W0);
          final small = shown.resized(math.max(1, (W0 * f).round()), math.max(1, (H0 * f).round()));
          final sc = scans[shown];
          final look = sc != null ? documentLook(small, textHeight: jsRound(sc.textHeightOut * f)) : small;
          onProgress(RecognitionProgress(fullName.startsWith('gerade') ? 'Bon wird begradigt wie gescannt' : 'Zeilen gefunden', 0,
              preview: look.jpeg(80), boxes: [for (final x in words.take(400)) [x.box.x0 / W0, x.box.y0 / H0, x.box.x1 / W0, x.box.y1 / H0]], straight: sc != null));
        } catch (_) {/* preview is display only */}
      }
      if (best == null || g > best!.g) best = e;
      readable = words.isNotEmpty ? words.where((x) => x.conf > 80).length / words.length : 0;
      return g;
    }

    // 2. straight cut-out, rotated by 180° if unreadable, last the whole photo
    if (cut != null) {
      final g1 = run(cut.canvas, 'ausschnitt', cut.corners, stage('Bon wird gelesen', 0.14, 0.4));
      if (g1 < 5000 && readable < 0.5) run(cut.canvas.rotated180(), 'ausschnitt180', cut.corners, stage('Bon wird gedreht gelesen', 0.14, 0.4));
    }
    if (best == null || best!.g < 5000) {
      final fl = fitLongest(photo);
      run(fl, 'foto', null, stage('Ganzes Foto wird gelesen', 0.14, 0.3));
      // receipt from the text position, rectify and read again in full resolution
      final fp = all.last, ec = textQuad(fp.lines.lines, fl.w.toDouble(), fl.h.toDouble());
      if (ec != null) {
        final f = fl.w / photo.w;
        final ecO = [for (final p in ec) [p[0] / f, p[1] / f]];
        final e = ReceiptImage.rectify(photo, ecO);
        final sc = ReceiptImage.straighten(e.image);
        run(sc, 'begradigt', ecO, stage('Bon wird begradigt und neu gelesen', 0.3, 0.4));
      }
    }
    // 2a. unfold (UVDoc): whole photo first, then the best rectified pass
    if (ocr.uvdoc != null) {
      try {
        final ef = _unfold(fitLongest(photo), photo);
        if (ef != null) run(ef, 'entfaltet-foto', null, stage('Blatt wird erkannt und entfaltet', 0.3, 0.33), straightArg: true);
      } catch (e) {
        _err('uvdoc-foto', e);
      }
      final b = best!;
      if (b.straight && !b.name.startsWith('entfaltet')) {
        try {
          final ef = _unfold(b.read, b.read);
          if (ef != null) run(ef, 'entfaltet', b.corners, stage('Knicke und Wölbung werden entfaltet', 0.33, 0.37), straightArg: true);
        } catch (e) {
          _err('uvdoc', e);
        }
      }
    }
    // 2b. straighten like a document scanner from the best pass on the photo itself (not the UVDoc image)
    final bases = stableSorted<_Pass>(all.where((e) => !e.name.startsWith('entfaltet')), (a, b) => numAsc(b.g, a.g));
    final basis = bases.isNotEmpty ? bases.first : best!;
    try {
      final ts = _sw.elapsedMilliseconds;
      final s1 = straighten(basis.canvas, basis.lines.lines, smooth: 0.05);
      _log('gerade', {'stufe': 1, 'quelle': basis.name, 'ms': _sw.elapsedMilliseconds - ts, 'ok': s1 != null, 'grund': s1 == null ? scanLastError : null, ...?s1?.stats});
      if (s1 != null) {
        scans[s1.image] = s1;
        run(s1.image, 'gerade', null, stage('Bon wird begradigt wie gescannt', 0.36, 0.42), straightArg: true);
        final e1 = all.last;
        final s2 = straighten(s1.image, e1.lines.lines, smooth: 0.05);
        _log('gerade', {'stufe': 2, 'ok': s2 != null, 'grund': s2 == null ? scanLastError : null, ...?s2?.stats});
        if (s2 != null) {
          scans[s2.image] = s2;
          run(s2.image, 'gerade2', null, stage('Feinere Begradigung', 0.42, 0.46), straightArg: true);
        }
      }
    } catch (e) {
      _err('gerade', e);
    }
    // 3. total not confirmed yet: improved images
    if (!best!.r.check.ok) {
      final src = best!.canvas, straight = best!.straight, corners = best!.corners;
      run(improve(src, 'scan'), 'scan', corners, stage('Bon wird wie gescannt aufbereitet und neu gelesen', 0.4, 0.46), display: src, straightArg: straight);
      if (!best!.r.check.ok) run(improve(src, 'kontrast'), 'kontrast', corners, stage('Bild wird verbessert und neu gelesen', 0.46, 0.55), display: src, straightArg: straight);
      if (!best!.r.check.ok) run(improve(src, 'dunkel'), 'dunkel', corners, stage('Blasser Druck wird verstärkt gelesen', 0.55, 0.64), display: src, straightArg: straight);
    }
    // 4. read every amount of the item block several times; on the first (original) pass and on the best
    final cands = <_Pass>[all.first];
    if (!identical(best, all.first)) cands.add(best!);
    var end = best!;
    for (var ki = 0; ki < cands.length; ki++) {
      final pass = cands[ki];
      var r = pass.r;
      final fort = stage(cands.length > 1 ? 'Beträge werden mehrfach geprüft (${ki + 1}/${cands.length})' : 'Beträge werden mehrfach geprüft',
          0.64 + (0.34 * ki) / cands.length, 0.64 + (0.34 * (ki + 1)) / cands.length);
      _rereadAmounts(pass, fort);
      final r2 = readLines(pass.lines.lines, qr);
      if (quality(r2, const []) >= quality(r, const [])) r = r2;
      final g2 = quality(r, const []) + displayBonus(pass.name, pass.straight);
      if (ki == 0 || g2 > end.gEnd) {
        end = _Pass(pass.g, r, pass.canvas, pass.read, pass.name, pass.corners, pass.lines, pass.straight)..gEnd = g2;
      }
    }
    stage('Fertig', 0.98, 1)(1);
    var r = end.r;
    var canvas = end.canvas;
    var name = end.name;
    // shown image = straightened scan; otherwise straighten the winner now and map all boxes with the same mapping
    var scan = scans[end.canvas] ?? scans[end.read];
    if (scan == null) {
      try {
        final s3 = straighten(end.canvas, end.lines.lines, smooth: 0.05);
        _log('gerade', {'stufe': 'anzeige', 'quelle': name, 'ok': s3 != null, 'grund': s3 == null ? scanLastError : null, ...?s3?.stats});
        if (s3 != null) {
          for (final z in r.lines) {
            z.box = s3.boxToScan(z.box);
          }
          for (final p in r.items) {
            if (p.frame != null) p.frame = s3.boxToScan(p.frame!);
            for (final x in p.extras) {
              if (x.frame != null) x.frame = s3.boxToScan(x.frame!);
            }
          }
          canvas = s3.image;
          scan = s3;
          name = '$name→gerade';
        }
      } catch (e) {
        _err('gerade-anzeige', e);
      }
    }
    Img display = canvas;
    try {
      display = scan != null ? documentLook(scan.image, textHeight: scan.textHeightOut, paper: scan.paper) : scanLook(canvas, strong: true);
    } catch (e) {
      display = canvas;
      _err('scanbild', e);
    }
    for (final p in r.items) {
      final b = p.frame ?? (p.line >= 0 && p.line < r.lines.length ? r.lines[p.line].box : null);
      p.snippet = snippet(display, b);
    }
    // Menu parts without a price right below an item („1 M Agridoce“ under „1 MG Veggie Nug 5.75“) belong to that item
    // (Karte 3.13: Menü-Bestandteile); a separate 0 € item only confuses the assignment.
    for (var i = r.items.length - 1; i > 0; i--) {
      final p = r.items[i], prev = r.items[i - 1];
      if (p.amount == 0 && p.extras.isEmpty && p.line == prev.line + 1 && p.name.trim().isNotEmpty) {
        prev.name = '${prev.name} (mit ${p.name.replaceFirst(RegExp(r'^\s*\d+\s+'), '').trim()})';
        r.items.removeAt(i);
      }
    }
    // winner with a contradiction in a line: never "checked", even if the total adds up
    if (r.check.ok && contradictions(r) > 0) r.check = Check(ok: false, source: r.check.source, corrected: r.check.corrected, targets: r.check.targets, contradiction: true);
    _log('ergebnis', {
      'gewinner': name,
      'posten': [for (final p in r.items) {'t': p.name, 'b': p.amount, 'menge': p.qty, 'sicher': p.sure, 'zeile': p.line}],
      'summe': r.sum,
      'total': r.total,
      'gesamtOk': r.check.ok,
      'zeilen': [for (final x in r.lines) '${x.type}|${x.text}'],
    });
    _sw.stop();
    return Recognition(
      result: r,
      display: display,
      original: identical(display, canvas) ? null : canvas,
      source: name,
      tries: tries,
      qr: qr,
      log: {'version': 'split-0.1 (bon.js 3.19)', 'dauer': _sw.elapsedMilliseconds, 'schritte': _steps, 'fehler': _errors, 'versuche': tries},
      width: canvas.w,
      height: canvas.h,
    );
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Re-reads each amount of the item block (own box; tall merged boxes at line height; pieces "2," | "59") with
  /// the original and with darker / higher-contrast images [Nachlesen in erkenne].
  void _rereadAmounts(_Pass pass, void Function(double) progress) {
    final v = pass.canvas, z = pass.lines.lines, r = pass.r;
    final group = [for (var i = 0; i < r.lines.length; i++) if (r.lines[i].block || r.lines[i].type == 'summe') i];
    final amountRe = RegExp(r'\d[.,]\s?\d{2}(?!\d)');
    Word? amountWord(Line zl) {
      final m = zl.words.where((x) => amountRe.hasMatch(x.text)).toList();
      return m.isNotEmpty ? m.last : null;
    }

    final edges = stableSorted<double>([for (final i in group) if (i < z.length && amountWord(z[i]) != null) amountWord(z[i])!.box.x1], numAsc);
    final colR = edges.isNotEmpty ? edges[edges.length >> 1] : v.w * 0.95;
    final digit = RegExp(r'\d'), letters3 = RegExp(r'[a-z]{3,}', caseSensitive: false);
    final digits = [
      for (final i in group)
        if (i < z.length)
          for (final x in z[i].words)
            if (digit.hasMatch(x.text) && !letters3.hasMatch(x.text) && x.box.x0 > v.w * 0.45) x
    ];
    double? pct(List<double> a, double q) {
      final s = stableSorted<double>(a, numAsc);
      return s.isEmpty ? null : s[math.min(s.length - 1, (s.length * q).floor())];
    }

    final spX0 = pct(digits.map((x) => x.box.x0).toList(), 0.15);
    final dark = improve(v, 'dunkel'), contrast = improve(v, 'kontrast');
    double med2(List<double> a) => stableSorted<double>(a, numAsc)[a.length >> 1];
    var n = 0;
    for (final i in group) {
      if (i >= z.length) continue;
      final zl = z[i];
      final x = r.lines[i];
      final bw = amountWord(zl);
      Box? k;
      var merged = false;
      final names = zl.words.where((y) => spX0 == null || y.box.x1 < spX0 - 2).toList();
      final pieces = bw == null && spX0 != null ? zl.words.where((y) => digit.hasMatch(y.text) && y.box.x0 >= spX0 - 2 && !letters3.hasMatch(y.text)).toList() : <Word>[];
      if (bw == null && pieces.isNotEmpty) {
        final y0b = med2(pieces.map((y) => y.box.y0).toList()), y1b = med2(pieces.map((y) => y.box.y1).toList()), hb = y1b - y0b;
        k = Box(math.max(0, math.min(minOf(pieces.map((y) => y.box.x0)) - 1.6 * hb, spX0! - 0.5 * hb)), y0b,
            math.min(v.w.toDouble(), maxOf(pieces.map((y) => y.box.x1)) + 0.3 * hb), y1b);
      } else if (bw != null && names.isNotEmpty) {
        final y0 = med2(names.map((y) => y.box.y0).toList()), y1 = med2(names.map((y) => y.box.y1).toList()), hz = y1 - y0, hb = bw.box.h;
        k = bw.box;
        // only a clearly too tall amount box (merged with the neighbour line) is cut to line height
        if (hb > 1.35 * hz) {
          final m = bw.box.cy, mn = (y0 + y1) / 2, c = math.max(bw.box.y0 + hz / 2, math.min(bw.box.y1 - hz / 2, mn));
          k = Box(bw.box.x0, c - hz / 2, bw.box.x1, c + hz / 2);
          merged = (m - c).abs() > 0.2 * hz;
        }
      } else if (bw != null) {
        final rest = zl.words.where((y) => !identical(y, bw)).toList();
        k = bw.box;
        if (rest.isNotEmpty) {
          final y0 = med2(rest.map((y) => y.box.y0).toList()), y1 = med2(rest.map((y) => y.box.y1).toList());
          if (bw.box.h > 1.3 * (y1 - y0)) {
            k = Box(bw.box.x0, y0, bw.box.x1, y1);
            merged = true;
          }
        }
      } else if (x.type == 'unklar') {
        final hz = zl.box.h;
        k = Box(math.max(0, colR - hz * 4.5), zl.box.y0, math.min(v.w.toDouble(), colR + hz * 0.3), zl.box.y1);
      }
      if (k != null) {
        var more = [
          ...ocr.multiRead(v, k),
          ...ocr.multiRead(dark, k, variants: const [(0.15, 0, false), (0.35, 0, false)]),
          ...ocr.multiRead(contrast, k, variants: const [(0.15, 0, false), (0.35, 0, false)]),
        ];
        if (merged) more = [...more, ...more]; // readings at line height count double against the merged box
        zl.readings = more;
      }
      progress(++n / math.max(1, group.length));
    }
  }

  /// Amount column as a strip: slope from the line profile, split at the gaps, each line read [spalteNeu].
  List<Word>? _columnReread(Img c, List<Word> words) {
    final w = withoutCrumbs(words);
    final isB = RegExp(r'\d[.,]\s?\d{2}(?!\d)'), l4 = RegExp(r'[a-z]{4,}', caseSensitive: false), l3 = RegExp(r'[a-z]{3,}', caseSensitive: false);
    final digit = RegExp(r'\d'), l2 = RegExp(r'[a-z]{2,}', caseSensitive: false);
    bool istB(String t) => isB.hasMatch(t) && !l4.hasMatch(t);
    final bet = w.where((x) => istB(x.text)).toList();
    if (bet.length < 3) return null;
    double med(Iterable<double> a) => stableSorted<double>(a, numAsc)[a.length >> 1];
    final h = med(w.map((x) => x.box.h));
    final edge = stableSorted<double>(bet.map((x) => x.box.x1), numAsc)[(bet.length * 0.7).floor()];
    final col = w.where((x) => x.box.x1 > edge - 2.5 * h && x.box.x1 < edge + 2 * h && digit.hasMatch(x.text) && !l3.hasMatch(x.text)).toList();
    if (col.length < 3) return null;
    final width = med(bet.map((x) => x.box.w));
    final X0 = math.max(0, (math.max(minOf(col.map((x) => x.box.x0)), edge - 1.6 * width) - 0.4 * h).round()), X1 = math.min(c.w, (edge + 1.2 * h).round());
    final Y0 = math.max(0, (minOf(col.map((x) => x.box.y0)) - h).round()), Y1 = math.min(c.h, (maxOf(col.map((x) => x.box.y1)) + h).round());
    final SW = X1 - X0, SH = Y1 - Y0;
    if (SW < 2 * h || SH < 3 * h) return null;
    // grey and Otsu threshold in the strip
    final strip = c.crop(X0, Y0, SW, SH);
    final gray = Uint8List(SW * SH), hist = Float64List(256);
    for (var i = 0; i < gray.length; i++) {
      final v = (strip.rgba[i * 4] * 3 + strip.rgba[i * 4 + 1] * 6 + strip.rgba[i * 4 + 2]) ~/ 10;
      gray[i] = v;
      hist[v]++;
    }
    var thr = 128;
    {
      double sum = 0;
      for (var i = 0; i < 256; i++) {
        sum += i * hist[i];
      }
      double wB = 0, sB = 0, bestV = -1;
      for (var t = 0; t < 256; t++) {
        wB += hist[t];
        if (wB == 0) continue;
        final wF = gray.length - wB;
        if (wF == 0) break;
        sB += t * hist[t];
        final d = sB / wB - (sum - sB) / wF, v = wB * wF * d * d;
        if (v > bestV) {
          bestV = v;
          thr = t;
        }
      }
    }
    final darkPx = <int>[];
    for (var y = 0; y < SH; y++) {
      for (var x = 0; x < SW; x += 2) {
        if (gray[y * SW + x] < thr) darkPx.addAll([x, y]);
      }
    }
    if (darkPx.length < 40) return null;
    // slope: the angle with the sharpest line profile
    var angle = 0.0;
    double bestS = -1;
    for (var a = -6.0; a <= 6.001; a += 0.25) {
      final t = math.tan(a * math.pi / 180), pr = Float64List(SH + SW);
      for (var i = 0; i < darkPx.length; i += 2) {
        final yy = jsRound(darkPx[i + 1] - (darkPx[i] - SW / 2) * t + SW / 2);
        if (yy >= 0 && yy < pr.length) pr[yy]++;
      }
      double s2 = 0;
      for (final v in pr) {
        s2 += v * v;
      }
      if (s2 > bestS) {
        bestS = s2;
        angle = a;
      }
    }
    // strip without foreign words (names reaching into it): those areas become white; then rotate back by the slope
    final S = strip.copy();
    final colSet = col.toSet();
    for (final x in w) {
      if (!colSet.contains(x) && l2.hasMatch(x.text) && x.box.x1 > X0 && x.box.x0 < X1 && x.box.y1 > Y0 && x.box.y0 < Y1) {
        for (var yy = math.max(0, (x.box.y0 - Y0).floor()); yy < math.min(SH, (x.box.y1 - Y0).ceil()); yy++) {
          for (var xx = math.max(0, (x.box.x0 - X0).floor()); xx < math.min(SW, (x.box.x1 - X0).ceil()); xx++) {
            final o = (yy * SW + xx) * 4;
            S.rgba[o] = S.rgba[o + 1] = S.rgba[o + 2] = 255;
          }
        }
      }
    }
    final cos = math.cos(angle * math.pi / 180), sin = math.sin(angle * math.pi / 180);
    final R = Img(SW, SH);
    for (var y = 0; y < SH; y++) {
      for (var x = 0; x < SW; x++) {
        // inverse of a rotation by −angle around the centre: source = rot(+angle)(dest − centre) + centre
        final dx = x + 0.5 - SW / 2, dy = y + 0.5 - SH / 2;
        final sx = dx * cos - dy * sin + SW / 2 - 0.5, sy = dx * sin + dy * cos + SH / 2 - 0.5;
        if (sx < 0 || sy < 0 || sx > SW - 1 || sy > SH - 1) continue;
        final o = (y * SW + x) * 4;
        for (var ch = 0; ch < 3; ch++) {
          R.rgba[o + ch] = S.sample(sx, sy, ch).round();
        }
      }
    }
    final prof = Float64List(SH), lx = Int32List(SH)..fillRange(0, SH, SW), rx = Int32List(SH)..fillRange(0, SH, -1);
    for (var y = 0; y < SH; y++) {
      for (var x = 0; x < SW; x++) {
        final o = (y * SW + x) * 4;
        if ((R.rgba[o] * 3 + R.rgba[o + 1] * 6 + R.rgba[o + 2]) / 10 < thr) {
          prof[y]++;
          if (x < lx[y]) lx[y] = x;
          if (x > rx[y]) rx[y] = x;
        }
      }
    }
    final gl = Float64List(SH);
    for (var i = 0; i < SH; i++) {
      gl[i] = (prof[math.max(0, i - 1)] + prof[i] + prof[math.min(SH - 1, i + 1)]) / 3;
    }
    final limit = math.max(1.5, 0.06 * maxOf(gl));
    final runs = <(int, int)>[];
    for (var y = 0, a = -1; y <= SH; y++) {
      final on = y < SH && gl[y] > limit;
      if (on && a < 0) a = y;
      if (!on && a >= 0) {
        runs.add((a, y));
        a = -1;
      }
    }
    final single = [for (final (a, b) in runs) if (b - a > 0.55 * h && b - a < 1.45 * h) (b - a).toDouble()];
    final hz = single.length >= 2 ? med(single) : h;
    final rows = <(int, int)>[];
    for (final (a, b) in runs) {
      final k = math.max(1, jsRound((b - a) / hz));
      if (k == 1) {
        if (b - a >= 0.45 * h) rows.add((a, b));
        continue;
      }
      var start = a;
      for (var j = 1; j < k; j++) {
        final want = a + ((b - a) * j) / k, rr = 0.3 * hz;
        var m = jsRound(want);
        var mv = double.infinity;
        for (var y = jsRound(want - rr); y <= want + rr; y++) {
          if (y > start && y < b && gl[y] < mv) {
            mv = gl[y];
            m = y;
          }
        }
        rows.add((start, m));
        start = m;
      }
      rows.add((start, b));
    }
    if (rows.length < 3 || rows.length > 80) return null;
    final neu = <Word>[];
    final lead = RegExp(r'^[^\d-]+');
    for (final (a, b) in rows) {
      var l = SW, rr = -1;
      for (var y = a; y < b; y++) {
        if (lx[y] < l) l = lx[y];
        if (rx[y] > rr) rr = rx[y];
      }
      if (rr - l < 0.6 * h) continue;
      final k = Box(math.max(0, l - 0.3 * h), math.max(0, a - 0.12 * h), math.min(SW.toDouble(), rr + 0.3 * h), math.min(SH.toDouble(), b + 0.12 * h));
      List<Reading> readings;
      try {
        readings = ocr.multiRead(R, k, variants: const [(0.12, 0, false), (0.3, 0, false), (0.2, 0, true)]);
      } catch (_) {
        continue;
      }
      readings = [for (final x in readings) Reading(x.text.replaceFirst(lead, '').trim(), x.conf)].where((x) => x.text.isNotEmpty).toList();
      final withB = readings.where((x) => istB(x.text)).toList();
      final pool = stableSorted<Reading>(withB.isNotEmpty ? withB : readings, (p, q) => numAsc(q.conf, p.conf));
      final pick = pool.isNotEmpty ? pool.first : null;
      if (pick == null || !digit.hasMatch(pick.text)) continue;
      // centre back into the image (rotation around the strip centre)
      final mx = (k.x0 + k.x1) / 2 - SW / 2, my = (a + b) / 2 - SH / 2;
      final ox = mx * cos - my * sin + SW / 2 + X0, oy = mx * sin + my * cos + SH / 2 + Y0, hw = k.w / 2, hh = (b - a) / 2;
      neu.add(Word(text: pick.text, conf: pick.conf, box: Box(ox - hw, oy - hh, ox + hw, oy + hh), fromColumn: true, alts: readings.map((x) => x.text).toList()));
    }
    if (neu.where((x) => istB(x.text)).length < 3) return null;
    bool inStrip(Word x) =>
        x.box.x0 >= X0 - 0.3 * h &&
        x.box.x1 <= X1 + 0.5 * h &&
        x.box.cy >= Y0 &&
        x.box.cy <= Y1 &&
        (digit.hasMatch(x.text) || x.text.trim().length <= 2) &&
        !l3.hasMatch(x.text);
    _log('spalte', {'winkel': angle, 'zeilen': rows.length, 'gelesen': neu.length});
    return [...words.where((x) => !inStrip(x)), ...neu];
  }

  /// UVDoc grid → resampled flat sheet; output size from the grid line lengths, read width ≥ 1300 px [entfalten].
  Img? _unfold(Img c, Img source, [double targetWidth = 1300]) {
    final res = ocr.uvGrid(c);
    if (res == null) return null;
    final (grid, dims) = res;
    final gh = dims[2], gw = dims[3], n = gh * gw, QW = source.w, QH = source.h;
    List<double> px(int k) => [((grid[k] + 1) / 2) * (QW - 1), ((grid[n + k] + 1) / 2) * (QH - 1)];
    double lw = 0, lh = 0;
    for (var j = 0; j < gh; j++) {
      for (var i = 0; i + 1 < gw; i++) {
        final a = px(j * gw + i), b = px(j * gw + i + 1);
        lw += math.sqrt(math.pow(b[0] - a[0], 2) + math.pow(b[1] - a[1], 2));
      }
    }
    for (var i = 0; i < gw; i++) {
      for (var j = 0; j + 1 < gh; j++) {
        final a = px(j * gw + i), b = px((j + 1) * gw + i);
        lh += math.sqrt(math.pow(b[0] - a[0], 2) + math.pow(b[1] - a[1], 2));
      }
    }
    lw /= gh;
    lh /= gw;
    final f = math.min(math.max(1.0, targetWidth / lw), 4500 / math.max(lw, lh));
    final OW = math.max(32, (lw * f).round()), OH = math.max(32, (lh * f).round());
    final out = Img(OW, OH), o = out.rgba, src = source.rgba;
    for (var y = 0; y < OH; y++) {
      final fy = (y / (OH - 1)) * (gh - 1), j = math.min(gh - 2, fy.floor()), v = fy - j;
      for (var x = 0; x < OW; x++) {
        final fx = (x / (OW - 1)) * (gw - 1), i = math.min(gw - 2, fx.floor()), u = fx - i, k0 = j * gw + i, k1 = k0 + gw;
        final gx = (grid[k0] * (1 - u) + grid[k0 + 1] * u) * (1 - v) + (grid[k1] * (1 - u) + grid[k1 + 1] * u) * v;
        final gy = (grid[n + k0] * (1 - u) + grid[n + k0 + 1] * u) * (1 - v) + (grid[n + k1] * (1 - u) + grid[n + k1 + 1] * u) * v;
        final X = (((gx + 1) / 2) * (QW - 1)).clamp(0.0, QW - 1.001), Y = (((gy + 1) / 2) * (QH - 1)).clamp(0.0, QH - 1.001);
        final xi = X.floor(), yi = Y.floor(), a = X - xi, b = Y - yi, p0 = (yi * QW + xi) * 4, p1 = p0 + QW * 4, q = (y * OW + x) * 4;
        for (var ch = 0; ch < 3; ch++) {
          o[q + ch] = ((src[p0 + ch] * (1 - a) + src[p0 + 4 + ch] * a) * (1 - b) + (src[p1 + ch] * (1 - a) + src[p1 + 4 + ch] * a) * b).round();
        }
      }
    }
    _log('uvdoc', {'aus': '$OW×$OH'});
    return out;
  }

  // ---- QR (Portugal: ATCUD invoice code) ----

  QrInfo? _qrDecode(Img g) {
    final px = Int32List(g.w * g.h);
    for (var i = 0, j = 0; i < px.length; i++, j += 4) {
      px[i] = (g.rgba[j] << 16) | (g.rgba[j + 1] << 8) | g.rgba[j + 2];
    }
    try {
      final hints = DecodeHints()..put(DecodeHintType.tryHarder);
      final r = QRCodeReader().decode(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(g.w, g.h, px))), hints: hints);
      return parseInvoiceQr(r.text);
    } catch (_) {
      return null;
    }
  }

  /// Whole photo at three sizes [qrSuchen].
  QrInfo? _qrSearch(Img img) {
    for (final max in const [1600, 2400, 1000]) {
      final f = math.min(1.0, max / math.max(img.w, img.h));
      final c = f < 1 ? img.resized((img.w * f).round(), (img.h * f).round()) : img;
      final q = _qrDecode(c);
      if (q != null) return q;
    }
    return null;
  }

  /// Tall cut-out: tiles at several scales, full resolution [qrKacheln].
  QrInfo? _qrTiles(Img c) {
    for (final sk in const [0.41, 0.35, 0.3, 0.5, 0.25, 0.6, 0.7, 1.0]) {
      final k = c.resized(math.max(1, (c.w * sk).round()), math.max(1, (c.h * sk).round()));
      if (k.h <= 2200) {
        final q = _qrDecode(k);
        if (q != null) return q;
      }
      final fh = math.min(k.h, 900);
      for (var y = 0; y < k.h; y += 300) {
        final h = math.min(fh, k.h - y);
        final q = _qrDecode(k.crop(0, y, k.w, h));
        if (q != null) return q;
        if (y + h >= k.h) break;
      }
    }
    return null;
  }
}

/// Light balance: pixel / local mean (box blur via integral image) against shadows [lichtAusgleich].
Float32List lightBalance(Float32List y, int w, int h) {
  final r = math.max(8, (math.min(w, h) / 30).round());
  final I = Float64List((w + 1) * (h + 1));
  for (var j = 0; j < h; j++) {
    double zs = 0;
    for (var i = 0; i < w; i++) {
      zs += y[j * w + i];
      I[(j + 1) * (w + 1) + i + 1] = I[j * (w + 1) + i + 1] + zs;
    }
  }
  final out = Float32List(w * h);
  for (var j = 0; j < h; j++) {
    final a = math.max(0, j - r), b = math.min(h, j + r + 1);
    for (var i = 0; i < w; i++) {
      final l = math.max(0, i - r), q = math.min(w, i + r + 1);
      final m = (I[b * (w + 1) + q] - I[a * (w + 1) + q] - I[b * (w + 1) + l] + I[a * (w + 1) + l]) / ((b - a) * (q - l));
      out[j * w + i] = math.min(255, (255 * y[j * w + i]) / math.max(1, m * 1.02));
    }
  }
  return out;
}

/// "Scanned" look: background from a max/mean filter on a 1/6 copy, divided out [scanBild].
Img scanLook(Img c, {bool strong = false}) {
  final w = c.w, h = c.h, y = c.gray(), n = w * h;
  final sw = math.max(8, (w / 6).round()), sh = math.max(8, (h / 6).round());
  final k = c.resized(sw, sh), m = sw * sh;
  var b = Float32List(m);
  for (var i = 0; i < m; i++) {
    b[i] = 0.299 * k.rgba[i * 4] + 0.587 * k.rgba[i * 4 + 1] + 0.114 * k.rgba[i * 4 + 2];
  }
  final r = math.max(2, (math.min(sw, sh) / 40).round());
  Float32List pass(Float32List src, bool max, bool horiz) {
    final o = Float32List(m), L = horiz ? sw : sh, Q = horiz ? sh : sw;
    for (var q = 0; q < Q; q++) {
      for (var l = 0; l < L; l++) {
        double a = 0;
        var z = 0;
        for (var t = math.max(0, l - r); t <= math.min(L - 1, l + r); t++) {
          final v = src[horiz ? q * sw + t : t * sw + q];
          if (max) {
            if (v > a) a = v;
          } else {
            a += v;
            z++;
          }
        }
        o[horiz ? q * sw + l : l * sw + q] = max ? a : a / z;
      }
    }
    return o;
  }

  b = pass(pass(pass(pass(b, true, true), true, false), false, true), false, false);
  final bgSmall = Img.fromGray(b, sw, sh), bg = bgSmall.resized(w, h);
  final out = Img(w, h);
  for (var i = 0; i < n; i++) {
    final v = (255 * y[i]) / math.max(24, bg.rgba[i * 4]);
    double x;
    if (strong) {
      final t = ((v - 85) / (205 - 85)).clamp(0.0, 1.0);
      x = 255 * math.pow(t, 0.85).toDouble();
    } else {
      x = (((v - 40) * 255) / 200).clamp(0.0, 255.0);
    }
    final q = x.round();
    out.rgba[i * 4] = out.rgba[i * 4 + 1] = out.rgba[i * 4 + 2] = q;
  }
  return out;
}

/// Improved images for further passes: 'scan', 'scanstark', 'dunkel', 'kontrast' [verbessern].
Img improve(Img c, String kind) {
  if (kind == 'scan') return scanLook(c);
  if (kind == 'scanstark') return scanLook(c, strong: true);
  final w = c.w, h = c.h, y = c.gray(), n = w * h;
  var v = Float32List(n);
  if (kind == 'dunkel') {
    for (var i = 0; i < n; i++) {
      v[i] = 255 * math.pow(y[i] / 255, 1.8).toDouble();
    }
  } else {
    final flat = lightBalance(y, w, h);
    for (var i = 0; i < n; i++) {
      v[i] = 0.5 * y[i] + 0.5 * flat[i];
    }
    final s2 = Float32List(n);
    for (var j = 1; j < h - 1; j++) {
      for (var i = 1; i < w - 1; i++) {
        final k = j * w + i, m = (v[k - 1] + v[k + 1] + v[k - w] + v[k + w] + v[k]) / 5;
        s2[k] = v[k] + 0.7 * (v[k] - m);
      }
    }
    v = s2;
  }
  return Img.fromGray(v, w, h);
}

/// Picture of the item's line in the shown image (JPEG, ≤ 56 px high) [schnipsel].
Uint8List? snippet(Img c, Box? r) {
  if (r == null) return null;
  final h0 = r.h, h = h0 * 0.76, pad = (h0 * 0.04).round();
  final x0 = math.max(0, (r.x0 - pad).round()), y0 = math.max(0, (r.y0 + h0 * 0.12 - pad).round());
  final bw = math.min(c.w - x0, (r.w + 2 * pad).round()), bh = math.min(c.h - y0, (h + 2 * pad).round());
  if (bw < 8 || bh < 6) return null;
  final f = math.min(1.0, 56 / bh);
  return c.region(x0.toDouble(), y0.toDouble(), bw.toDouble(), bh.toDouble(), math.max(1, (bw * f).round()), math.max(1, (bh * f).round())).jpeg(80);
}
