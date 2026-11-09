// Fasan Split – receipt reader: words → lines → items, total, check. MPL-2.0
//
// Port of Fasan-Karte/site/bon.js 3.19 (functions named in brackets). Behaviour is kept 1:1 so that the shared regression
// tests (fasan-diagnose/tests: einheit, e2e, sroie) measure the same thing for web and app. Comments of the original are
// kept in short form; the reasons and test cases behind each rule are in bon.js.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'model.dart';
import 'package:fasan_core/speisen.dart';
import 'package:fasan_core/text_util.dart';

// ---------------------------------------------------------------------------------------------------------------------
// Lines from words

/// Drops crumbs: tiny, unsure, almost letterless boxes [ohneKrumen].
List<Word> withoutCrumbs(List<Word> words) {
  final w = words.where((x) => x.text.trim().isNotEmpty && x.conf > 15).toList();
  final mh = medianOf(w.map((x) => x.box.h));
  final nonAlnum = RegExp(r'[^A-Za-z0-9]');
  return w.where((x) => !(x.conf < 60 && x.text.replaceAll(nonAlnum, '').length <= 3 && x.box.h < 0.6 * mh)).toList();
}

/// A hairline box: the detector sometimes boxes a dotted rule or glare as „text“ 8 px high next to lines of 55 px („easo“, „ua“,
/// „roozao“ on a Bäckerei Probe photo, 05.11.). It is not text – but it must not be dropped for good: in scans (SROIE 016) such
/// boxes hold the garbled start of a real line. Callers that mask or merge treat it as noise.
bool isHairline(Word x, double medianHeight) => medianHeight > 0 && x.box.h < 0.2 * medianHeight;

/// Groups words into lines; tolerant to slanted lines using the local tilt of long boxes [zeilenAus].
Lines linesFrom(List<Word> words, {bool straight = false}) {
  final w = withoutCrumbs(words);
  for (final x in w) {
    x.cy = (x.box.y0 + x.box.y1) / 2;
    // height without the share the tilt adds to the box (else neighbour lines get caught)
    x.hh = math.max(4, x.box.h - (x.tilt != null ? x.tilt!.abs() * x.box.w : 0)).toDouble();
  }
  stableSort<Word>(w, (a, b) => numAsc(a.box.x0, b.box.x0));
  final long = w.where((x) => x.tilt != null && x.box.w > 6 * x.hh).toList();
  double med(List<double> v) {
    stableSort<double>(v, numAsc);
    return v.isEmpty ? 0 : v[v.length >> 1];
  }

  final all = med(long.map((q) => q.tilt!).toList());
  final limit = straight ? 0.02 : 1.0;
  double tiltAt(double y, double h) {
    final v = long.where((q) => (q.cy - y).abs() < 5 * h).map((q) => q.tilt!).toList();
    final n = v.isNotEmpty ? med(v) : all;
    return math.max(-limit, math.min(limit, n));
  }

  final lines = <Line>[];
  for (final x in w) {
    Line? best;
    var bestD = double.infinity;
    for (final z in lines) {
      final last = z.words.last;
      if (last.box.x1 > x.box.x0 + x.hh) continue; // overlaps horizontally: other line
      final n = tiltAt(last.cy, last.hh), dx = x.box.cx - last.box.cx;
      final d = (last.cy + n * dx - x.cy).abs();
      if (d < 0.55 * math.max(x.hh, last.hh) && d < bestD) {
        best = z;
        bestD = d;
      }
    }
    if (best != null) {
      best.words.add(x);
    } else {
      lines.add(Line([x]));
    }
  }
  for (final z in lines) {
    finishLine(z);
  }
  stableSort<Line>(lines, (a, b) => numAsc(a.box.y0 + a.box.y1, b.box.y0 + b.box.y1));
  return Lines(lines);
}

final _endsSep = RegExp(r'[.,]$');
final _startsDigit = RegExp(r'^\d');

/// Box, confidence and characters of a line; glues amounts split at the comma ("1," | "11 B") [zeileFertig].
Line finishLine(Line z) {
  stableSort<Word>(z.words, (a, b) => numAsc(a.box.x0, b.box.x0));
  z.box = Box(minOf(z.words.map((x) => x.box.x0)), minOf(z.words.map((x) => x.box.y0)), maxOf(z.words.map((x) => x.box.x1)),
      maxOf(z.words.map((x) => x.box.y1)));
  z.conf = minOf(z.words.map((x) => x.conf));
  final zz = <Glyph>[];
  Word? prev;
  for (final x in z.words) {
    final own = (x.glyphs != null && x.glyphs!.isNotEmpty)
        ? x.glyphs!.where((q) => q.ch.isNotEmpty).toList()
        : [for (final r in x.text.runes) Glyph(String.fromCharCode(r), x.conf / 100)];
    var s = 0, e = own.length;
    while (s < e && own[s].ch == ' ') {
      s++;
    }
    while (e > s && own[e - 1].ch == ' ') {
      e--;
    }
    final part = own.sublist(s, e), hz = math.max(4, x.box.h);
    final glue = prev != null && _endsSep.hasMatch(prev.text.trim()) && _startsDigit.hasMatch(x.text.trim()) && x.box.x0 - prev.box.x1 < hz * 0.9;
    if (zz.isNotEmpty && !glue) zz.add(const Glyph(' ', 1));
    zz.addAll(part);
    prev = x;
  }
  z.glyphs = zz;
  z.text = zz.map((q) => q.ch).join();
  return z;
}

/// Receipt corners from the position of the text lines (when the paper edge is not visible) [textViereck].
List<List<double>>? textQuad(List<Line> lines, double W, double H) {
  var z = lines.where((q) => q.words.isNotEmpty && q.box.w > 2 * q.box.h).toList();
  if (z.length < 6) return null;
  final h = medianOf(z.map((q) => q.box.h));
  double cy(Line q) => (q.box.y0 + q.box.y1) / 2;
  stableSort<Line>(z, (a, b) => numAsc(cy(a), cy(b)));
  final groups = <List<Line>>[
    [z[0]]
  ];
  for (var i = 1; i < z.length; i++) {
    if (cy(z[i]) - cy(z[i - 1]) > 5 * h) groups.add([]);
    groups.last.add(z[i]);
  }
  stableSort<List<Line>>(groups, (a, b) => b.length - a.length);
  z = groups[0];
  if (z.length < 6) return null;
  ({double a, double b}) fit(List<List<double>> pk) {
    var p = pk;
    for (var it = 0; it < 3; it++) {
      final n = p.length;
      final sy = p.fold<double>(0, (s, q) => s + q[1]) / n, sx = p.fold<double>(0, (s, q) => s + q[0]) / n;
      var num = 0.0, den = 0.0;
      for (final q in p) {
        num += (q[1] - sy) * (q[0] - sx);
        den += (q[1] - sy) * (q[1] - sy);
      }
      final b = den != 0 ? num / den : 0.0, a = sx - b * sy;
      final res = p.map((q) => (q[0] - (a + b * q[1])).abs()).toList();
      final m2 = medianOf(res) * 2.5 + 1;
      if (it == 2 || p.length < 5) return (a: a, b: b);
      final keep = <List<double>>[];
      for (var k = 0; k < p.length; k++) {
        if (res[k] <= m2) keep.add(p[k]);
      }
      p = keep;
    }
    return (a: 0.0, b: 0.0);
  }

  final x0s = z.map((q) => q.box.x0).toList(), x1s = z.map((q) => q.box.x1).toList();
  final q30 = stableSorted<double>(x0s, numAsc)[(z.length * 0.4).floor()];
  final q70 = stableSorted<double>(x1s, numAsc)[(z.length * 0.6).floor()];
  final li = fit(z.where((q) => q.box.x0 <= q30).map((q) => [q.box.x0 - 1.2 * h, cy(q)]).toList());
  final re = fit(z.where((q) => q.box.x1 >= q70).map((q) => [q.box.x1 + 1.2 * h, cy(q)]).toList());
  double tilt(List<Line> rows) {
    final v = <double>[
      for (final q in rows)
        for (final x in q.words)
          if (x.tilt != null && x.box.w > 4 * h) x.tilt!
    ];
    final m = medianOf(v);
    return m.isNaN ? 0 : m;
  }

  final k4 = math.max(2, (z.length / 4).floor());
  final top = z.sublist(0, k4), bottom = z.sublist(z.length - k4);
  final xc = medianOf(z.map((q) => (q.box.x0 + q.box.x1) / 2));
  final yO = minOf(top.map((q) => q.box.y0)) - 1.5 * h, yU = maxOf(bottom.map((q) => q.box.y1)) + 1.5 * h;
  final sO = tilt(top), sU = tilt(bottom);
  List<double> cut(({double a, double b}) g, double y0, double sl) {
    final x = (g.a + g.b * y0 - g.b * sl * xc) / (1 - g.b * sl);
    return [math.max(0, math.min(W, x)), math.max(0, math.min(H, y0 + sl * (x - xc)))];
  }

  final corners = [cut(li, yO, sO), cut(re, yO, sO), cut(re, yU, sU), cut(li, yU, sU)];
  final width = math.sqrt(math.pow(corners[1][0] - corners[0][0], 2) + math.pow(corners[1][1] - corners[0][1], 2));
  return width > 10 * h ? corners : null;
}

// ---------------------------------------------------------------------------------------------------------------------
// Column matching: names left, amounts right, paired in order with the best constant offset [zeilenSpalten]

final _isAmountRe = RegExp(r'-?\d+[.,]\s?\d{2}(?!\d)');
final _euro = RegExp(r'euro?', caseSensitive: false);
final _letters4 = RegExp(r'[a-z]{4,}', caseSensitive: false);

bool _isAmountWord(String t) => _isAmountRe.hasMatch(t) && !_letters4.hasMatch(t.replaceAll(_euro, ''));

/// Up to four pairings, one per whole-line offset (−2 … +2); null if there is no amount column.
List<Lines>? linesByColumns(List<Word> words) {
  final w = withoutCrumbs(words);
  final amounts = w.where((x) => _isAmountWord(x.text)).toList();
  if (amounts.length < 3) return null;
  final h = medianOf(w.map((x) => x.box.h));
  final edges = stableSorted<double>(amounts.map((x) => x.box.x1), numAsc);
  final edge = edges[(edges.length * 0.7).floor()];
  final keep = RegExp(r'[^A-Za-z0-9*€]');
  final right = w.where((x) => (_isAmountWord(x.text) && (x.box.x1 - edge).abs() < 3 * h) || (x.box.x0 > edge - 0.6 * h && x.text.replaceAll(keep, '').length <= 3)).toList();
  if (right.where((x) => _isAmountWord(x.text)).length < 3) return null;
  final rightSet = right.toSet();
  final left = w.where((x) => !rightSet.contains(x)).toList();
  final L = linesFrom(left, straight: true).lines, R = linesFrom(right, straight: true).lines;
  if (L.isEmpty || R.isEmpty) return null;
  double cy(Line z) => (z.box.y0 + z.box.y1) / 2;
  final ly = L.map(cy).toList();
  final gaps = <double>[];
  for (var i = 1; i < ly.length; i++) {
    final d = ly[i] - ly[i - 1];
    if (d > h * 0.4) gaps.add(d);
  }
  stableSort<double>(gaps, numAsc);
  final pitch = gaps.isNotEmpty ? gaps[gaps.length >> 1] : h * 1.3;
  Lines build(_Alignment best) {
    final out = <Line>[];
    final takenR = <int>{};
    for (final z in L) {
      z.taken = false;
    }
    for (final (i, j) in best.pairs) {
      out.add(finishLine(Line([...L[i].words, ...R[j].words])));
      takenR.add(j);
      L[i].taken = true;
    }
    for (final z in L) {
      if (!z.taken) out.add(z);
    }
    for (var j = 0; j < R.length; j++) {
      if (!takenR.contains(j)) out.add(R[j]);
    }
    stableSort<Line>(out, (a, b) => numAsc(cy(a), cy(b)));
    return Lines(out, ColumnInfo(toFixed(best.off / pitch, 2), best.pairs.length, pitch));
  }

  final per = <int, _Alignment>{};
  for (var o = -2.4; o <= 2.4001; o += 0.05) {
    final a = _alignRows(L, R, o * pitch, pitch), k = jsRound(o);
    if (!per.containsKey(k) || a.cost < per[k]!.cost) per[k] = a;
  }
  final sorted = stableSorted<_Alignment>(per.values, (a, b) => numAsc(a.cost, b.cost));
  final out = sorted.take(4).map(build).toList();
  // A curved, folded or crumpled receipt shifts the amount column part of the way down: top in line, from a fold on one line off
  // (Woolworths/Coles, Weltkorpus 06.11.). One more candidate with two offsets and a break between two name rows: forward costs
  // of the prefix at one offset plus backward costs of the rest at the other, minimised over the break (Needleman–Wunsch
  // prefix/suffix split, as in Hirschberg's algorithm).
  final grid = [for (var o = -20; o <= 20; o++) o / 10];
  final fw = [for (final o in grid) _alignTable(L, R, o * pitch, pitch, false)];
  final bw = [for (final o in grid) _alignTable(L, R, o * pitch, pitch, true)];
  ({double cost, int a, int b, int i})? split;
  for (var a = 0; a < grid.length; a++) {
    for (var b = 0; b < grid.length; b++) {
      if ((grid[a] - grid[b]).abs() < 0.45) continue;
      final F = fw[a], B = bw[b];
      for (var i = 1; i < L.length; i++) {
        for (var j = 0; j <= R.length; j++) {
          final c = F[i][j] + B[i][j];
          if (split == null || c < split.cost) split = (cost: c, a: a, b: b, i: i);
        }
      }
    }
  }
  if (split != null && sorted.isNotEmpty && split.cost < sorted.first.cost - 0.3) {
    final s0 = split;
    final offs = [for (var i = 0; i < L.length; i++) (i < s0.i ? grid[s0.a] : grid[s0.b]) * pitch];
    final x = _alignRows(L, R, 0, pitch, offs: offs);
    out.add(build(_Alignment(x.cost, x.pairs, (grid[s0.a].abs() > grid[s0.b].abs() ? grid[s0.a] : grid[s0.b]) * pitch)));
  }
  return out;
}

class _Alignment {
  _Alignment(this.cost, this.pairs, this.off);

  final double cost;
  final List<(int, int)> pairs;
  final double off;
}

final _latinLetter = RegExp(r'[A-Za-zÀ-ÿ]');

/// Cost table of [_alignRows] at one offset: forward (prefixes) or backward (suffixes); [i][j] = cost of the first/remaining i, j rows.
List<List<double>> _alignTable(List<Line> L, List<Line> R, double off, double pitch, bool backward) {
  final n = L.length, m = R.length;
  double cy(Line z) => (z.box.y0 + z.box.y1) / 2;
  const gapL = 0.45, gapR = 0.6;
  final noName = [for (final z in L) countMatches(_latinLetter, z.text) < 2 ? 0.5 : (isHeaderLine(z.text) ? 2.0 : 0.0)];
  final ry = R.map(cy).toList(), lyy = L.map(cy).toList();
  double pair(int i, int j) {
    final d = (ry[j] - lyy[i] - off).abs() / pitch;
    return d < 0.6 ? d * d * 2 + noName[i] : double.infinity;
  }

  final D = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  if (!backward) {
    for (var i = 1; i <= n; i++) {
      D[i][0] = i * gapL;
    }
    for (var j = 1; j <= m; j++) {
      D[0][j] = j * gapR;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        D[i][j] = math.min(D[i - 1][j - 1] + pair(i - 1, j - 1), math.min(D[i - 1][j] + gapL, D[i][j - 1] + gapR));
      }
    }
  } else {
    for (var i = n - 1; i >= 0; i--) {
      D[i][m] = (n - i) * gapL;
    }
    for (var j = m - 1; j >= 0; j--) {
      D[n][j] = (m - j) * gapR;
    }
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        D[i][j] = math.min(D[i + 1][j + 1] + pair(i, j), math.min(D[i + 1][j] + gapL, D[i][j + 1] + gapR));
      }
    }
  }
  return D;
}

/// Sequence alignment (Needleman–Wunsch) of name rows and amount rows with a fixed offset [reihenAbgleich].
_Alignment _alignRows(List<Line> L, List<Line> R, double off, double pitch, {List<double>? offs}) {
  final n = L.length, m = R.length;
  double cy(Line z) => (z.box.y0 + z.box.y1) / 2;
  const gapL = 0.45, gapR = 0.6;
  final D = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  final W = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    D[i][0] = i * gapL;
    W[i][0] = 1;
  }
  for (var j = 1; j <= m; j++) {
    D[0][j] = j * gapR;
    W[0][j] = 2;
  }
  final noName = [for (final z in L) countMatches(_latinLetter, z.text) < 2 ? 0.5 : (isHeaderLine(z.text) ? 2.0 : 0.0)];
  final ry = R.map(cy).toList(), lyy = L.map(cy).toList();
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final d = (ry[j - 1] - lyy[i - 1] - (offs != null ? offs[i - 1] : off)).abs() / pitch;
      final pair = d < 0.6 ? D[i - 1][j - 1] + d * d * 2 + noName[i - 1] : double.infinity;
      final a = D[i - 1][j] + gapL, b = D[i][j - 1] + gapR;
      if (pair <= a && pair <= b) {
        D[i][j] = pair;
        W[i][j] = 0;
      } else if (a <= b) {
        D[i][j] = a;
        W[i][j] = 1;
      } else {
        D[i][j] = b;
        W[i][j] = 2;
      }
    }
  }
  final pairs = <(int, int)>[];
  var i = n, j = m;
  while (i > 0 || j > 0) {
    final w = W[i][j];
    if (w == 0) {
      pairs.add((i - 1, j - 1));
      i--;
      j--;
    } else if (w == 1) {
      i--;
    } else {
      j--;
    }
  }
  return _Alignment(D[n][m], pairs.reversed.toList(), off);
}

// ---------------------------------------------------------------------------------------------------------------------
// Amounts and words

final _priceRe = RegExp(r'(-?\d{1,3}(?:[.\s]\d{3})*[,.]\d{2})(?!\d)');

/// Letter confusions between digits [zahl].
String fixDigits(String t) => t
    .replaceAllMapped(RegExp(r'(\d)[oO](?=\d)'), (m) => '${m[1]}0')
    .replaceAllMapped(RegExp(r'(\d)[lI|](?=\d)'), (m) => '${m[1]}1');

/// "1.234,50" → 123450 [cent].
int cent(String s) {
  final neg = s.startsWith('-');
  final v = jsRound(jsParseFloat(s.replaceAll(RegExp(r'[-\s.](?=\d{3}\b)'), '').replaceFirst(RegExp(r'^-'), '').replaceFirst(',', '.')) * 100);
  return neg ? -v : v;
}

final _unitsLetters = RegExp(r'\b(x|kg|eur|un|uni|l|cl|ml|g)\b', caseSensitive: false);
final _letterAZ = RegExp(r'[a-zà-ÿ]', caseSensitive: false);
int _letters(String t) => countMatches(_letterAZ, t.replaceAll(_unitsLetters, '')); // [buchstaben]

/// Keyword families in many languages [W].
abstract final class Kw {
  static final summe = RegExp(r'\b(total|totaal|totale|totalt|gesamt|gesamtbetrag|gesamtsumme|summe|endsumme|endbetrag|zu zahlen|zahlbetrag|importe|a pagar|montant|net a payer|te betalen|suma|razem|celkem|osszesen|yhteensa|att betala|i alt|ukupno|toplam|kokku|amount due|balance due)\b');
  static final zwischen = RegExp(r'\b(sub[- ]?total|subtotale|subtotaal|sous-?total|zwischensumme|zw\.? ?summe)\b');
  static const steuerSrc = r'\b(mwst|mw\.?st|ust|vat|gst|sst|hst|pst|tax|taxes|sales tax|iva|tva|btw|moms|mva|alv|dph|pdv|kdv|steuer|netto|brutto|incid|incidencia|incidencias|imponible|imponibile|imposta|taxa iva|base|tributavel|ht|sem iva|net)\b';
  static final steuer = RegExp(steuerSrc);
  static final service = RegExp(r'\b(service|serv|svc|bedienung|trinkgeld|tip|tips|gratuity|servizio|pourboire|fooi|propina)\b');
  static final anzahl = RegExp(r'\b(total\s*(qty|quantity|items?|pcs|points|pts)|items?\s*\(?s?\)?\.?\s*:|qty\s*\(?s?\)?\.?\s*:|item count|iten count|no\.? of items|anzahl artikel|artikelanzahl|anz\.? artikel)');
  static const inklSteuerSrc = r'\b(incl|inkl|inclusive?|inclusiv\s+e|including|inc)\b\.?\s*(of\s*)?(gst|vat|tax|mwst|iva|tva|sst|ust)\b|\binclu\S{0,5}(\s+\S)?\s+(of\s*)?(gst|vat|tax|sst)\b|\b(net|nett)\s+total\b';
  static final inklSteuer = RegExp(inklSteuerSrc);
  static final steuerTabelle = RegExp(r'\b(gst|tax|vat|mwst|iva|tva|sst|ust)\s*(summary|susmary|summ?ary|analysis|breakdown|code)\b|steuer\s*(ubersicht|aufstellung)|resumo (do )?iva|riepilogo iva|desglose iva');
  static final zahlung = RegExp(r'\b(bar|gegeben|kartenzahlung|karte|ec|ec-cash|girocard|kreditkarte|visa|mastercard|maestro|amex|vpay|paypal|apple pay|google pay|cash|card|tendered|entregue|valor entregue|pago|pagamento|efectivo|tarjeta|especes|carte|cb|contanti|carta|bancomat|pin|contant|kaart|pinnen|multibanco|mb way|dinheiro|numerario|cartao|kontaktlos|contactless|bezahlt|paid)\b');
  static final rueck = RegExp(r'\b(ruckgeld|wechselgeld|change|cambio|vuelto|rendu|resto|troco|wisselgeld)\b');
  static final rabatt = RegExp(r'\b(rabatt|nachlass|coupon|gutschein|discount|desconto|descuento|sconto|remise|reduction|korting|preisvorteil|sofortrabatt|ersparnis|sie sparen|you save|reduziert|mhd|aktion|promo|promocao|oferta)\b|\d ?% ?off\b');
  static final leergut = RegExp(r'\b(leergut|leergutbon|pfandbon|pfandruckgabe|pfand-?ruckgabe|pfandgutschrift|bottle return|statiegeld retour|retorno de vasilhame|devolucao de tara)\b');
  static final storno = RegExp(r'\b(storno|storniert|stornierung|void|voided|anulad[oa]|anulacao|anulacion|annullat[oa]|annulation|annule|cancelled|canceled|cancelado|ruckbuchung|correcao)\b');
  static final kaution = RegExp(r'\b(kaution|caucao|fianza|cauzione|security deposit|damage deposit|deposito de garantia|deposito caucao)\b');
  static final vorab = RegExp(r'\b(vorautorisierung|vorautorisiert|pre-?auth\w*|pre-?autoriza\w*|blockiert|blockierung|reserviert|reservierung des betrags|hold|retencao|retid[oa]|cativo|cativa|bloqueado)\b');
  static final anzahlung = RegExp(r'\b(anzahlung|vorauszahlung|vorauskasse|bereits bezahlt|bereits gezahlt|advance payment|advance deposit|prepaid|pre-?payment|deposit paid|sinal|adiantamento|pagamento antecipado|acconto|anticipo|arrhes|acompte)\b');
  static final ortstaxe = RegExp(r'\b(kurtaxe|ortstaxe|kurbeitrag|gastetaxe|city tax|tourist tax|tourism tax|taxa turistica|taxa municipal turistica|tassa di soggiorno|taxe de sejour|tasa turistica|toeristenbelasting)\b');
  static final rundung = RegExp(r'\b(rundung|gerundet|rounding|arredondamento|redondeo|arrotondamento|arrondi|afronding|pyoristys|avrundning|oresavrundning)\b');
  static final nein = RegExp(r'\b(uid|ust-?idnr|ust-?id|vat no|capital|social|registo|registro|contrib|contribuinte|conservatoria|matricula|e-?mail|iban|bic|swift|handelsregister|hrb|amtsgericht|geschaftsfuhrer|sede|datum|date|data|fecha|uhrzeit|hora|heure|ora|tisch|table|mesa|tavolo|kasse|kassierer|beleg|bon-?nr|receipt|recibo|ricevuta|tel|telefon|phone|fax|www|http|ust-?id|st\.?-?nr|steuer-?nr|steuernummer|nif|nipc|siret|cif|atcud|fatura|factura|rechnung|invoice|original|kopie|copy|operador|bediener|kellner|cashier|danke|thank|thanks|merci|grazie|gracias|obrigad[oa]|vielen|willkommen|welcome|gmbh|lda|srl|ltd|inc|ohg|tse|signatur|seriennummer|transaktion|terminal|trace|beleg-?nr|autorisierung|kartennummer)\b');
  // global in bon.js: used with match() (count) and replace() (all)
  static final kopf = RegExp(r'\b(qt|qtd|qty|qte|quant|amt|disc|quantidade|menge|anz|anzahl|descri[cç]?[aã]?o|descricao|descripcion|description|bezeichnung|artikel|artigo|article|articulo|produkt|produto|p\.?\s?unit|p\.?\s?u|preco|preis|price|prix|precio|prezzo|valor|betrag|amount|montant|importe|importo|tx|vat|mwst|einzel)\b');
  static final einzel = RegExp(r'\b(pre[cç]o|preis|price|prix|precio|prezzo|prijs|je|a|à|@|ea|each|stuckpreis|einzelpreis|ep)\b\s*[:;.]?\s*$');
}

bool isHeaderLine(String? t) => Kw.nein.hasMatch(foldLower(t ?? '')); // [istKopfzeile]

/// Edit distance ≤ 1 [abst1].
bool _dist1(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0, j = 0, f = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++f > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return f + (a.length - i) + (b.length - j) <= 1;
}

final _word4 = RegExp(r'[a-z]{4,}');

/// Total word with one reading error ("SLMMe", "T0TAL") [summeUnscharf].
bool _fuzzyTotal(String n) {
  final w = _word4.allMatches(n.replaceAll('0', 'o')).map((m) => m[0]!).toList();
  return w.isNotEmpty &&
      w.length <= 3 &&
      w.any((x) => const ['summe', 'total', 'gesamt', 'totale', 'totaal', 'gesamtsumme'].any((k) => _dist1(x, k))) &&
      !Kw.steuer.hasMatch(n) &&
      !Kw.zahlung.hasMatch(n);
}

// „1.000ea @ $ 4.99/ea“ (Colonial, Australien; Weltkorpus 06.11.): „ea/each/pce/kpl“ are units like „kg“, else „1.000ea“ became the name
final _qtyWordStart = RegExp(r'^\W*(?:qty|quantity|anz|menge|qtd|cant)\b', caseSensitive: false);
final _qtyBeforePrice = RegExp(r'\s(\d{1,2})\s+(?:[$€£]\s?)?$');
// quantity and unit price read as one grouped amount: „2 140.00“ → 2 × 140.00 (only used when it gives the line total)
final _pctOff = RegExp(r'\d ?% ?off\b');
final _qtySpaceUnit = RegExp(r'^(\d{1,2}) (\d{3}[.,]\d{2})$');
final _totalForItems = RegExp(r'\btotal\s+(?:for|of)\s+\d{1,3}\s+items?\b');
final _qtyFront = RegExp(r'^\s*(\d{1,3}(?:[.,]\d{1,3})?)\s*(?:x|×|\*|stk\.?|st\.?|pcs\.?|pc\.?|pce|un\.?|uni|und\.?|pz\.?|kg|l|ea|each|kpl|items?|item\(s\))?\s*[x×*]?\s+', caseSensitive: false);

/// Decimal separator of this receipt [dezimal].
/// '0' = a receipt in a currency without minor units (Indonesia „60.000“, Korea „12,000“, Hungary, Japan with grouping): at least
/// three grouped whole numbers and at most one amount with two decimals (CORD 06.11.). Amounts then count whole units ×100, so the
/// app keeps one unit („hundredths“) and only the display drops the decimals.
String decimalSep(List<Line> lines) {
  var k = 0, p = 0, g = 0;
  final rk = RegExp(r'\d,\d{2}(?!\d)'), rp = RegExp(r'\d\.\d{2}(?!\d)');
  for (final z in lines) {
    k += countMatches(rk, z.text);
    p += countMatches(rp, z.text);
    g += countMatches(_wholeRe, z.text);
  }
  if (g >= 3 && k + p <= 1) return '0';
  return p > k ? '.' : ',';
}

// grouped whole number: 1.000, 60.000, 1.250.000, 12,000 (not followed by more digits or a decimal part)
final _wholeRe = RegExp(r"(?<![\d.,])(-\s?)?(\d{1,3}(?:[.,]\d{3})+)(?![\d]|[.,]\d)");

// („-$1.00“ / „-£0.85“: the minus can stand before the currency sign, Coles/Tesco 06.11.)
final _amountsRe = RegExp(r"(^|[^\d.,])(-\s?(?:[$€£]\s?)?)?((?:\d{1,3}(?:[.,' ]\d{3})+|\d+)[.,] ?\d{2})(?!\d|[.,]\d)(\s?-(?![\d]))?");
final _pctAfter = RegExp(r'^\s*%');
final _sepSpace = RegExp(r'([.,]) (\d{2})$');
final _groupSep = RegExp(r"[.,' ]");
final _sepChar = RegExp(r'[.,]');
final _digit = RegExp(r'\d');

/// Amounts of a line with their position; "1,00-" and "-1,00" are negative; "19,00 %" is no amount [betraege].
List<Amount> amountsIn(String t, [String dec = ',']) {
  final out = <Amount>[];
  if (dec == '0') {
    for (final m in _wholeRe.allMatches(t)) {
      final neg = m[1] != null && m[1]!.isNotEmpty;
      final start = m.start + (m[1]?.length ?? 0), end = start + m[2]!.length;
      if (_pctAfter.hasMatch(jsSlice(t, end))) continue;
      final v = int.parse(m[2]!.replaceAll(_groupSep, '')) * 100;
      out.add(Amount(neg ? -v : v, start, end, neg));
    }
    return out;
  }
  for (final m in _amountsRe.allMatches(t)) {
    final g1 = m[1] ?? '', g2 = m[2], g3 = m[3]!, g4 = m[4];
    final start = m.start + g1.length + (g2 != null ? g2.length : 0), end = start + g3.length;
    if (_pctAfter.hasMatch(jsSlice(t, end))) continue;
    final raw = g3.replaceFirstMapped(_sepSpace, (x) => '${x[1]}${x[2]}');
    final d = raw.length - 3;
    final head = raw.substring(0, d), whole = head.replaceAll(_groupSep, '');
    if (_sepChar.hasMatch(head) && head.replaceAll(_digit, '').split('').any((c) => c == raw[d])) continue; // 1.234.56: unclear
    final v = jsRound(jsParseFloat('$whole.${raw.substring(d + 1)}') * 100);
    final neg = (g2 != null && g2.isNotEmpty) || (g4 != null && g4.isNotEmpty);
    out.add(Amount(neg ? -v : v, start, end, neg));
  }
  // An item line whose decimal point was not printed or read: „MAYB MASC 5 24“ (Target, faint dot; Weltkorpus b3-013 07.11.). Only at
  // the end of a line with a name and no other amount; the total check decides whether it holds (a wrong guess cannot be „checked“).
  if (out.isEmpty) {
    final s = _spaceDecimal.firstMatch(t);
    if (s != null) {
      final v = jsInt(s[1]!) * 100 + jsInt(s[2]!);
      final a0 = s.start + 1; // after the space before the digits
      if (v > 0) out.add(Amount(v, a0, a0 + s[1]!.length + 1 + s[2]!.length, false));
    }
  }
  return out;
}

final _spaceDecimal = RegExp(r'(?<=[A-Za-zÀ-ÿ]{3}[^\d]*)\s(\d{1,3}) (\d{2})\s*(?:[A-Z]{1,2}|\*)?\s*$');

/// Other readings of an amount from second-best digits (only unsure digits, one change each) [alternativen].
List<Vote> alternatives(Line z, Amount b) {
  final out = <Vote>[];
  if (z.glyphs.isEmpty) return out;
  // whole-unit amount („60.000“): the two-decimal arithmetic below does not apply
  if (RegExp(r'[.,]\d{3}$').hasMatch(jsSlice(z.text, b.start, b.end))) return out;
  for (var i = b.start; i < b.end; i++) {
    if (i >= z.glyphs.length) break;
    final q = z.glyphs[i];
    if (!_digit.hasMatch(q.ch) || q.p > 0.97 || q.alt == null || !_digit.hasMatch(q.alt!) || q.p2 < 0.01) continue;
    final t = jsSlice(z.text, b.start, i) + q.alt! + jsSlice(z.text, i + 1, b.end);
    final f = jsParseFloat('${jsSlice(t, 0, t.length - 3).replaceAll(_groupSep, '')}.${jsSlice(t, -2)}') * 100;
    if (!f.isFinite) continue;
    final v = jsRound(f);
    final k = 1 + math.max(0, math.log(q.p / math.max(q.p2, 1e-4)) / math.ln10) / 2;
    out.add(Vote(b.neg ? -v : v, k, 0, 'Ziffer unsicher'));
  }
  return out;
}

final _unitsWord = RegExp(r'\b(x|kg|eur|euro|usd|chf|gbp|un|uni|stk|st|pcs|l|cl|ml|g|items?|qty|ea|each)\b');
final _az = RegExp(r'[a-z]');
int lettersIn(String t) => countMatches(_az, foldLower(t).replaceAll(_unitsWord, '')); // [buchst]

// „Uni“ as OCR reads it: Uni, Un1, Unl, Unt, Unf, Unj, Uní, Um, Jni (protocols 02.11.: „Unf CANECA“, „í Cesta de pao“ –
// \b treats „í“ as non-word, so „Un“ was cut and „í“ stayed). Ends only where no letter follows.
// A smudge or fold in front of the unit column is read as one or two stray characters („2 P Uni PIZZA PEPPERONI“, Nutzer
// 02.11.: „P Pizza Peperoni“ wurde erkannt); they are dropped only when a unit word follows.
final _n2 = RegExp(r'^\s*(?:[^\s\d]{1,2}\s+(?=(?:u[nm][il1tfjíìĩ|!]?|jni)(?![A-Za-zÀ-ÿ])))?(u[nm][il1tfjíìĩ|!]?|jni|und|unid|unidade|uds?|stk|pcs|pc)(?![A-Za-zÀ-ÿ])\.?\s*', caseSensitive: false);
final _n3 = RegExp(r'\b\d{1,2}\s*%');
// a tax rate at the end of the name with „%“ read as „x“ (Café Beispiel 06.11.: „Croissant c/ N 13x“)
final _n3x = RegExp(r'\s+(?:4|5|6|7|8|9|10|12|13|16|19|20|21|22|23|24|25)\s*[xX]\s*$');
// the VAT column glued to the name end with a misread „%“ or a stray letter: „TULIPA 238“, „QUEIJOS P P13“ (Restaurant Beispiel 06.11.)
// two lower-case consonants at the end are a smudge read as letters („Cafe Duplo nm“, Bäckerei Probe 06.11.), except units
final _n3s = RegExp(r'\s+(?!(?:cl|ml|kg|gr|lt|st|pz|pk|cx|dz)\b)[b-df-hj-np-tv-z]{2}\s*$');
// (a bare number stays: „Pizza 13“; only with a misread „%“ or a letter in front it is the VAT column)
final _n3v = RegExp(r'\s+(?:[A-Za-z](?:6|13|23)[%8xX]?|(?:6|13|23)[%8xX])\s*$');
// OCR doubles letters on thermal print („Croisssant“); three equal letters in a row do not occur in item names
final _tripleLetter = RegExp(r'([A-Za-zÀ-ÿ])\1{2,}');
final _n4 = RegExp(
    r'[€$£¥₩₹]|(?<![\p{L}])(euro|eur|usd|chf|gbp|jpy|fr\.|kr|zł|kč|rm|myr|sgd|thb|idr|php|vnd|aud|nzd|cad|hkd|cny|rmb|krw|inr|try|pln|czk|huf|sek|nok|dkk|brl|mxn|zar|aed)(?![\p{L}])',
    caseSensitive: false,
    unicode: true);
final _n5 = RegExp(r'\s+\d+[.,]\d[a-z]?\s*$', caseSensitive: false);
final _n6 = RegExp(r'\s+\d{3,5}\s?[A-D]\s*\*?\s*$');
final _n7 = RegExp(r'\s+\d{1,3}\s\d{2}\s*[A-D]?\s*\*?\s*$');
final _n8 = RegExp(r'\s+[A-Z0-9*]{1,2}\s*$');
final _n9 = RegExp(r'^[^\wÀ-ÿ]+|[^\wÀ-ÿ.)]+$');
final _ws = RegExp(r'\s+');

/// A name that probably contains a reading error: a stray single consonant in front („P PIZZA PEPPERONI“) or several junk
/// symbols. Such items are marked unsure at once, so the user checks them before they do harm (Nutzer 02.11.).
bool suspiciousName(String n) {
  final t = n.trim();
  final tokens = t.split(RegExp(r'\s+'));
  if (tokens.length >= 2 && RegExp(r'^[B-DF-HJ-NP-TV-XZ]$').hasMatch(tokens.first)) return true;
  return RegExp(r"[^\p{L}\d\s.,'&/()+\-–%*]", unicode: true).allMatches(t).length >= 2;
}

/// Other plausible readings of an item name (without the stray front character, no truncated last letter, readable case).
List<String> nameAlternatives(String n) {
  final t = n.trim();
  if (t.isEmpty) return const [];
  final out = <String>[];
  void add(String s) {
    final x = s.trim();
    if (x.isNotEmpty && x != t && !out.contains(x)) out.add(x);
  }
  final tokens = t.split(RegExp(r'\s+'));
  if (tokens.length >= 2 && tokens.first.length == 1) add(tokens.skip(1).join(' '));
  if (tokens.length >= 3 && tokens.last.length == 1) add(tokens.take(tokens.length - 1).join(' '));
  final base = out.isNotEmpty ? out.first : t;
  if (base == base.toUpperCase() && RegExp(r'[A-ZÀ-Þ]{3}').hasMatch(base)) {
    add(base.split(' ').map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(' '));
  }
  return out.take(3).toList();
}

/// Item name from the text left of the amount [nameAus].
// article number in front of the name: Aldi/Lidl „814998 Bio Spaghetti“ (5–8 digits), Woolworths UK „000001803 SPOCKLEY“, Target
// „052080250 CGIRL LIPSTK“ (9), EAN (13). Long numbers may carry one OCR slip („0520B0250“, Weltkorpus b3-013 07.11.).
final _articleNoRe = RegExp(r'^\s*([0-9OBIlSZ]{5,14})\s+(?=[A-Za-zÀ-ÿ])');
String _dropArticleNo(String t) {
  final m = _articleNoRe.firstMatch(t);
  if (m == null) return t;
  final g = m[1]!, letters = g.replaceAll(RegExp(r'\d'), '').length;
  final ok = letters == 0 || (letters == 1 && g.length >= 8);
  return ok ? t.substring(m.end) : t;
}

// Portuguese „c/ Nata“, „s/ Gelo“ (com/sem): part of the name, not a tax code (else „Croissant c/ N“ became „Croissant c“)
final _withWithout = RegExp(r'\s([cCsS])/\s*([A-Za-zÀ-ÿ]{1,14})\.?\s*$');

// A weight or count detail line without a name: „0.482 kg NET @ $4.50/kg“ (Woolworths), „0.375kg @ $ 5.99/kg“, „1.000Ea @$ 4.99/Ea“
// (Colonial), „2 @ $0.25 EACH“ (Coles). The article name is on the line above (Weltkorpus 06.11.: „NET“ became the name).
final _weightDetail = RegExp(
    r'^\W*\d{1,3}(?:[.,]\d{1,3})?\s*(?:kg|g|gr|lb|lbs|oz|ea|each|pcs?|stk|st)?\.?\s*(?:net|netto|nt|nett)?\s*[@©à]\s*(?:[$€£]|eur|aud|usd)?\s*(?:\d{1,4}[.,]\d{2}\s*(?:/\s*(?:kg|g|100\s?g|lb|ea|each|stk|st|pc|un)\.?|each|ea|per\s+kg)?)?\W*$',
    caseSensitive: false);

// „Korean Chicken Wings 1 item(s)“ (Australien, Weltkorpus 06.11.): the count after the name is no part of it
final _itemsTail = RegExp(r'\s+\d{1,3}\s*items?(?:\(s\))?(?=\W*$)', caseSensitive: false);

// „Qty 2 @ $0.25 each“ (Woolworths): only the quantity word is left before the price
final _qtyWordOnly = RegExp(r'^\W*(?:qty|quantity|anz|menge|qtd|cant)\W*$', caseSensitive: false);

String nameFrom(String t) {
  if (_weightDetail.hasMatch(t) || _qtyWordOnly.hasMatch(t)) return '';
  t = t.replaceFirst(_itemsTail, ' ');
  final ww = _withWithout.firstMatch(t.replaceAll(_n3, '').replaceFirst(_n3x, '').trimRight());
  if (ww != null) {
    final head = nameFrom(t.replaceAll(_n3, '').replaceFirst(_n3x, '').trimRight().substring(0, ww.start));
    if (head.isNotEmpty) return jsSlice('$head ${ww[1]!.toLowerCase()}/ ${ww[2]}', 0, 40);
  }
  final s = _dropArticleNo(t)
      .replaceFirst(_qtyFront, '')
      .replaceFirst(_n2, '')
      .replaceAll(_n3, '')
      .replaceFirst(_n3x, '')
      .replaceFirst(_n3v, '')
      .replaceFirst(_n3s, '')
      .replaceAllMapped(_tripleLetter, (m) => '${m[1]}${m[1]}')
      .replaceAll(_n4, '') // currency only as its own word (else KRAEUTERQUARK became AEUTERQUARK)
      .replaceFirst(_n5, '')
      .replaceFirst(_n6, '')
      .replaceFirst(_n7, '')
      .replaceFirst(_n8, '')
      .replaceAll(_n9, '')
      .replaceAll(_ws, ' ')
      .trim();
  // once more at the very end: currency signs and tax codes are gone only now („Cafe Duplo nm €“ → „Cafe Duplo nm“ → „Cafe Duplo“)
  final e = ' $s'.replaceFirst(_n3v, '').replaceFirst(_n3s, '').trim();
  return jsSlice(e.isEmpty ? s : e, 0, 40);
}

final _splitAmount = RegExp(r'^\s*(-?\d{1,3})\s?(\d{2})\s*[A-D*]?\s*\*?\s*$');

/// Votes from several readings of the same amount; share of votes → cost in matching [stimmen].
List<Vote> votes(int? first, List<Reading>? more, String dec) {
  final count = <int, double>{};
  void add(int v, double c) => count[v] = (count[v] ?? 0) + math.max(0.2, c / 100);
  if (first != null) add(first, 90);
  for (final m in more ?? const <Reading>[]) {
    final a = amountsIn(m.text, dec);
    int? v = a.isNotEmpty ? a.last.v : null;
    if (v == null) {
      final x = _splitAmount.firstMatch(m.text);
      if (x != null) {
        final n = jsInt(x[1]!);
        final sign = n == 0 ? 1 : n.sign;
        v = jsRound(n * 100 + sign * jsInt(x[2]!));
      }
    }
    if (v != null) add(v, m.conf * (a.isNotEmpty ? 1 : 0.7));
  }
  var total = count.values.fold<double>(0, (a, x) => a + x);
  if (total == 0) total = 1;
  final entries = stableSorted<MapEntry<int, double>>(count.entries, (a, b) => numAsc(b.value, a.value));
  return [for (final e in entries) Vote(e.key, toFixed(0.7 * (1 - e.value / total), 3), e.value / total, e.key == first ? null : 'nachgelesen')];
}

// ---------------------------------------------------------------------------------------------------------------------
// Extras: Pfand, Rabatt and extras belong to an item above or below

final _pfandRe = RegExp(r'^\W*(pfand|einweg|mehrweg|einwegpfand|mehrwegpfand|flaschenpfand|dosenpfand|deposit|bottle deposit|crv|depot|statiegeld|pant|vasilhame|tara|dpg)(?![a-z])');
final _drinkRe = RegExp(r'\b(cola|coke|pepsi|fanta|sprite|limo\w*|lemon\w*|koffein|energy|red ?bull|monster|iso\w*|saft|nektar|juice|smoothie|wasser|water|sprudel|mineral\w*|bier|beer|pils\w*|radler|weizen|helles|lager|wein|wine|sekt|prosecco|tee|tea|eistee|mate|schorle|spezi|drink|getranke?|sumo|agua|cerveja|vinho|refrigerante)\b|\b\d[.,]?\d{0,2}\s?(l|ltr|ml|cl)\b|\b(pet|dose|flasche|fl\.|can|btl)\b');
final _billDiscount = RegExp(r'\b(coupon|gutschein|bon-?rabatt|einkauf|gesamteinkauf|mitarbeiter|treue|payback|lidl plus|app-?rabatt|bonus|punkte|club|member|mitglied|warenkorb|einkaufswert)\b');
final _drinkSym = RegExp('☕|🫖|🥛|💧|🥤|🧃|🍺|🍻|🍷|🥂|🍸|🍹|🥃|🧉', unicode: true);
final _fruitSym = RegExp('🍎|🍏|🍊|🍋|🍓|🫐|🍇|🍑|🥭|🍍|🍒|🍌|🥥|🍉|🍐|🥝', unicode: true);

/// 1 drink, −1 surely no drink, 0 unknown [getraenk].
int drinkScore(String? t) {
  final n = foldLower(t ?? '');
  if (_drinkRe.hasMatch(n)) return 1;
  final r = Speisen.recognise(t ?? '');
  if (r != null) return _drinkSym.hasMatch(r.symbol) ? 1 : (_fruitSym.hasMatch(r.symbol) ? 0 : -1);
  return 0;
}

final _nonWordSplit = RegExp(r'\W+');
int _sameWords(String? a, String? b) {
  final A = foldLower(a ?? '').split(_nonWordSplit).where((x) => x.length > 2).toSet();
  return foldLower(b ?? '').split(_nonWordSplit).where((x) => x.length > 2 && A.contains(x)).length;
}

/// Storno lines cancel an item above with the same negative amount [stornoPaare].
void _cancelPairs(List<Item> items, List<_Info> info) {
  for (var k = items.length - 1; k >= 0; k--) {
    final s = items[k];
    if (s.kind2 != 'storno' || s.dropped) continue;
    var best = -1, bs = -1;
    for (var j = k - 1; j >= 0; j--) {
      final q = items[j];
      if (q.kind2 != null || q.cancelled || q.amount != -s.amount) continue;
      final sim = _sameWords(q.name, s.name);
      if (sim > bs) {
        bs = sim;
        best = j;
      }
    }
    if (best < 0) continue;
    final q = items[best];
    q.cancelled = s.cancelled = true;
    info[q.line].type = info[s.line].type = 'storno';
  }
  items.removeWhere((p) => p.cancelled);
}

final _extraStart = RegExp(r'^\s*(\+|extra\b|zusatz\b|mit\b|add\b|com\b|con\b|avec\b|plus\b|suppl\w*)', caseSensitive: false);
final _pctRe = RegExp(r'(\d{1,2}(?:[.,]\d)?)\s*%');
final _leadNonWord = RegExp(r'^\W+');

/// Weighs each extra line between the item above and below (≤ 2 lines away) [zusaetzeZuordnen].
void _attachExtras(List<Item> items, List<_Info> info) {
  bool isPfand(Item p) => p.amount > 0 && p.amount <= 1500 && _pfandRe.hasMatch(foldLower(p.name)) && p.kind2 == null;
  // a negative rounding/tax line after the subtotal is never a discount on the last article (Woolworths 06.11.: „Rounding -$0.01“
  // became a discount on the paper bag, 25 → 24)
  bool isDiscount(Item p) =>
      p.amount < 0 && p.surcharge == null && (p.kind2 == null || p.kind2 == 'rabatt') && !_billDiscount.hasMatch(foldLower(info[p.line].line.text));
  bool article(Item? p) => p != null && p.surcharge == null && p.kind2 == null && !isPfand(p) && p.amount > 0;
  bool isExtra(Item p) => p.amount > 0 && p.kind2 == null && _extraStart.hasMatch(info[p.line].line.text);
  final extras = items.where((p) => isPfand(p) || isDiscount(p) || isExtra(p)).toList();
  for (final z in extras) {
    final k = items.indexOf(z);
    final kind = isPfand(z) ? 'pfand' : (isDiscount(z) ? 'rabatt' : 'extra');
    int lastLine(Item p) {
      final idx = items.indexOf(p);
      var m = p.line;
      for (final r in info) {
        if (r.type == 'teil' && r.item == idx && r.i > m) m = r.i;
      }
      // lines already attached (deposit after deposit): „SPRITE ZERO 3 @ 2.50“ with three „DEPOSIT 0.48“ below (Target, Weltkorpus
      // b3-013 07.11.) – the third was 3 lines away from the article and stayed a loose item; the chain counts from the last one
      for (final x in p.extras) {
        if (x.line > m) m = x.line;
      }
      return m;
    }

    Item? above;
    for (var j = k - 1; j >= 0; j--) {
      if (article(items[j])) {
        above = items[j];
        break;
      }
    }
    Item? below;
    for (var j = k + 1; j < items.length; j++) {
      if (article(items[j])) {
        below = items[j];
        break;
      }
    }
    final cands = <_ExtraCand>[];
    if (above != null && z.line - lastLine(above) <= 2) cands.add(_ExtraCand(above, true, z.line - lastLine(above)));
    if (below != null && below.line - z.line <= 2 && kind != 'extra') cands.add(_ExtraCand(below, false, below.line - z.line));
    for (final c in cands) {
      var s = c.above ? 1.0 : 0.3;
      s += c.dist == 1 ? 0.4 : -0.2;
      if (z.taxCode != null && c.p.taxCode != null) s += z.taxCode == c.p.taxCode ? 1.5 : -2;
      if (kind == 'pfand') {
        final g = drinkScore(c.p.name);
        s += g > 0 ? 1.2 : (g < 0 ? -1 : 0);
        if (c.p.extras.any((x) => x.kind == 'pfand') && !(c.p.qty > 1)) s -= 0.8;
        final q25 = z.amount / 25;
        final n = z.qty > 1 ? z.qty : ((q25).round() == q25 && q25 > 1 && q25 <= 24 ? q25 : 1);
        if (n > 1 && c.p.qty == n) s += 0.8;
      } else if (kind == 'extra') {
        s += 1;
      } else {
        s += _sameWords(c.p.name, info[z.line].line.text) > 0 ? 2 : 0;
        s += z.amount.abs() < c.p.amount ? 0.5 : -3;
        final pc = _pctRe.firstMatch(info[z.line].line.text);
        if (pc != null) {
          final want = jsRound((c.p.amount * jsParseFloat(pc[1]!.replaceFirst(',', '.'))) / 100);
          s += (want - z.amount.abs()).abs() <= 1 ? 2.5 : -0.5;
        }
      }
      c.s = toFixed(s, 2);
    }
    stableSort<_ExtraCand>(cands, (a, b) => numAsc(b.s, a.s));
    final pick = cands.isNotEmpty && cands[0].s >= 0.8 ? cands[0] : null;
    final alt = [for (final c in cands) if (c != pick) (c.p.line, c.s)];
    if (pick == null) {
      z.extraCands = [for (final c in cands) (c.p.line, c.s)];
      z.extraKind = kind;
      continue;
    }
    final q = pick.p;
    q.extras.add(Extra(
      kind: kind,
      amount: z.amount,
      line: z.line,
      name: kind == 'pfand' ? 'Pfand' : (kind == 'extra' ? z.name.replaceFirst(_leadNonWord, '') : (z.nameUncertain ? 'Rabatt' : z.name)),
      alt: alt,
      score: pick.s,
      sure: alt.isEmpty || pick.s - alt[0].$2 >= 1.5,
      frame: z.frame,
    ));
    q.amount += z.amount;
    if (q.unit != null && q.unit != 0) q.unit = null; // unit price no longer matches the amount incl. Pfand/Rabatt
    q.certainty = math.min(q.certainty ?? 100, z.certainty ?? 100);
    q.frame = q.frame != null && z.frame != null ? q.frame!.union(z.frame!) : q.frame;
    q.suggestions = [];
    info[z.line].type = kind;
    z.merged = true;
  }
  items.removeWhere((p) => p.merged);
  for (var i = 0; i < items.length; i++) {
    final p = items[i];
    info[p.line].item = i;
    for (final x in p.extras) {
      info[x.line].item = i;
    }
  }
}

class _ExtraCand {
  _ExtraCand(this.p, this.above, this.dist);

  final Item p;
  final bool above;
  final int dist;
  double s = 0;
}

/// Working record per line [info in liesAllgemein].
class _Info {
  _Info(this.i, this.line, this.n, this.amounts);

  final int i;
  final Line line; // [z]
  final String n;
  final List<Amount> amounts; // [bt]
  Amount? last; // [letzter]
  String kind = 'sonst'; // [art]
  num? qty; // [menge]
  num? unit; // [einzel]
  String name = '';
  String? taxCode; // [stb]
  int letters = 0; // [bu]
  int? rate; // [satz]
  bool unitOnly = false; // [nurEinzel]
  String? type; // [typ]
  int? item; // [zu]
  bool part = false; // [bestandteil]
  _QtyRef? qtyFor, qtyFrom; // [mengeFuer, mengeVon]
  bool totalWithoutWord = false;
}

class _QtyRef {
  _QtyRef(this.qty, this.unit, this.line);

  final num? qty;
  final num? unit;
  final int line;
}

/// The printed sign of a rounding line says nothing reliable: Colonial (Australien) prints „Rounding 0.02“ for −2 Cent and „−0.01“
/// for +1 Cent, Coles „-$0.02“ for −2 Cent (Weltkorpus 06.11.). Both signs are offered; the total decides.
/// Only for amounts below one unit: a shifted amount column can put the subtotal into the rounding row („Rounding $49.05“,
/// Woolworths 06.11.), and its flipped sign then made a wrong total „check out“.
List<Cand> _roundingSign(_Info r) =>
    r.kind == 'rundung' && r.last != null && r.last!.v != 0 && r.last!.v.abs() < 100 ? [Cand(-r.last!.v, 0.1, 'Vorzeichen')] : const [];

class _Surcharge {
  _Surcharge(this.name, this.kind, this.line, this.cands);

  final String name, kind;
  final int line;
  final List<Cand> cands;
}

class _Target {
  _Target(this.v, this.k, this.source, this.line);

  final int v;
  double k;
  final String source;
  final int line;
}

final _currencyOnly = RegExp(r'^\W*(eur|euro|€|usd|chf|gbp)\W*$');
final _qtyPattern = RegExp(r'\d\s*[x×*]\s*\d');
final _pctStart = RegExp(r'^\W*\d{1,2}([.,]\d+)?\s*%');
final _abc3 = RegExp(r'[a-z]{3,}');
final _brutto = RegExp(r'\bbrutto\b');
final _totalWords = RegExp(r'\b(total|sales|amount|betrag|summe)\b');
final _nonWordOnly = RegExp(r'^\W*$');
final _letterStart = RegExp(r'^\s*[A-Za-zÀ-ÿ]');
final _qtyInGap = RegExp(r'(?:^|\s)(\d{1,3})(?=\s|$)');
final _qtyLead = RegExp(r'^\s*(\d{1,2})\s*(?:x|×|stk\.?|st\.?|pcs\.?|un\.?|uni|und\.?|pz\.?)?\s+[A-Za-zÀ-ÿ]', caseSensitive: false);
final _lateTail = RegExp(r'(\s+(\d{1,3}|[A-D]))+\s*$');
final _rateRe = RegExp(r'\b(\d{1,2})\s*%');
final _taxCodeRe = RegExp(r'^\s*([A-D1-4])(?![A-Za-z0-9])');
final _taxCodeLate = RegExp(r'\d[.,]\s?\d{2}\s*([A-D])(?![A-Za-z0-9])');
final _bullet = RegExp(r'^\s*[-+*•>·]');
final _priceWord = RegExp(r'pre[cç]o|preis|price|prix|precio', caseSensitive: false);
final _leadDash = RegExp(r'^[-–•*>\s]+');
final _totalish = RegExp(r'\b(total|summe|gesamt)');
final _roundish = RegExp(r'\b(round|rundung|arrondi|afronding)');
// the tax word that names a tax item found between a net and a grand total (Kw.steuer without net/base words)
final _taxName = RegExp(r'\b(mwst|ust|vat|gst|sst|hst|iva|tva|btw|moms|mva|alv|dph|pdv|kdv|tax|steuer|imposta)\b');

/// Reader for receipts of all countries (Latin script) [liesAllgemein].
ReadResult readGeneral(List<Line> lines, QrInfo? qr, ReceiptKind? kind) {
  final dec = decimalSep(lines);
  final info = <_Info>[];
  for (var i = 0; i < lines.length; i++) {
    final z = lines[i];
    final n = foldLower(z.text), bt = amountsIn(z.text, dec);
    if (bt.isEmpty && z.readings != null && z.readings!.isNotEmpty) {
      final st = votes(null, z.readings, dec);
      if (st.isNotEmpty && st[0].share >= 0.4) bt.add(Amount(st[0].v, z.text.length, z.text.length, st[0].v < 0, late: true));
    }
    double? qtyFront;
    if (bt.length >= 2 &&
        _nonWordOnly.hasMatch(jsSlice(z.text, 0, bt[0].start)) &&
        _letterStart.hasMatch(jsSlice(z.text, bt[0].end)) &&
        bt[0].v > 0 &&
        bt[0].v <= 9900) {
      qtyFront = bt[0].v / 100;
      bt.removeAt(0);
    }
    final r = _Info(i, z, n, bt);
    r.last = bt.isNotEmpty ? bt.last : null;
    final kopfCount = countMatches(Kw.kopf, n);
    var art = 'sonst';
    if ((bt.isEmpty && (kopfCount >= 2 || _currencyOnly.hasMatch(n))) || kopfCount >= 3) {
      art = 'kopf';
    } else if (_totalForItems.hasMatch(n)) {
      // Coles (Australien): „Total for 19 items: $57.10“ is the total, not an item count (Weltkorpus 06.11.)
      art = 'summe';
    } else if (Kw.anzahl.hasMatch(n)) {
      art = 'nein';
    } else if (Kw.zwischen.hasMatch(n)) {
      art = 'zwischen';
    } else if ((Kw.summe.hasMatch(n) &&
            !Kw.steuer.hasMatch(n.replaceAll(Kw.inklSteuer, ' ').replaceFirst(Kw.summe, '').replaceFirst(_brutto, ''))) ||
        (Kw.inklSteuer.hasMatch(n) && _totalWords.hasMatch(n)) ||
        (bt.isNotEmpty && _fuzzyTotal(n))) {
      art = 'summe';
    } else if (Kw.rueck.hasMatch(n)) {
      art = 'rueck';
    } else if (Kw.vorab.hasMatch(n)) {
      art = 'vorab';
    } else if (Kw.anzahlung.hasMatch(n)) {
      art = 'anzahlung';
    } else if (Kw.zahlung.hasMatch(n) && !_qtyPattern.hasMatch(n)) {
      art = 'zahlung';
    } else if (Kw.rundung.hasMatch(n)) {
      art = 'rundung';
    } else if (Kw.leergut.hasMatch(n)) {
      art = 'leergut';
    } else if (Kw.storno.hasMatch(n)) {
      art = 'storno';
    } else if (Kw.kaution.hasMatch(n)) {
      art = 'kaution';
    } else if (Kw.ortstaxe.hasMatch(n)) {
      art = 'sonst'; // city tax is an item, not VAT
    } else if (Kw.service.hasMatch(n)) {
      art = 'service';
    } else if (_pctOff.hasMatch(n)) {
      // „50% Off Today -2.50“ under each article (Woolworths UK, Weltkorpus b1-087 07.11.): a line starting with a percentage is a
      // tax line, except „n % off“ – that is a discount and belongs to the article above
      art = 'rabatt';
    } else if ((Kw.steuer.hasMatch(n) || _pctStart.hasMatch(n)) && !_weightDetail.hasMatch(jsSlice(z.text, 0, bt.isNotEmpty ? bt.last.start : z.text.length))) {
      // („0.482 kg NET @ $4.50/kg 2.17“ is a weighed article, „NET“ there is no net-of-tax line)
      art = 'steuer';
    } else if (Kw.rabatt.hasMatch(n)) {
      art = 'rabatt';
    } else if (Kw.nein.hasMatch(n)) {
      art = 'nein';
    }
    if (art == 'steuer' &&
        bt.isEmpty &&
        countMatches(_abc3, n.replaceAll(Kw.steuer, ' ').replaceAll(Kw.kopf, ' ')) >= 2 &&
        !Kw.steuerTabelle.hasMatch(n)) {
      art = 'sonst';
    }
    r.kind = art;
    // quantity × unit price: "2 x 4,90", "3 X 0,79 2,37", "0,512 kg x 2,99 €/kg"
    num? menge;
    num? einzel;
    final d = dec == '0' ? r'[.,]' : RegExp.escape(dec);
    var mx = RegExp(
            '(\\d{1,3}(?:[.,]\\d{1,3})?)\\s*(?:stk\\.?|st\\.?|kg|pcs|un\\.?|uni|l|ltr|lt|liter|litros|lts|gal|n[aä]chte?|noites|nights|n\\.|tage|dias|days|pers\\.?|personen|pax|ea|each)?\\s*[x×*@]\\s*(?:[\$€£]\\s?)?(\\d+$d ?\\d{2,3})(?!\\d)',
            caseSensitive: false)
        .firstMatch(z.text);
    // A mid-line „13x 8,00“ after a name is often the tax rate with a misread „%“ (Café Beispiel, Beispielstadt 06.11.: „2Uni Croissant
    // c/ N 13x 8,00“ became 13 croissants). When the line already starts with its own quantity and the x-price is the last
    // amount of the line (no separate line total), the leading quantity wins.
    final lead = qtyFront ?? (() {
      final m = _qtyLead.firstMatch(z.text);
      return m == null ? null : jsInt(m[1]!).toDouble();
    })();
    // Generally: when the x-price IS the only/last amount of a line that also carries a name before it, „N x price“ would claim a
    // total N × price that is printed nowhere (Karte 3.18: „Menge × Preis passt zu keinem Betrag“ is a contradiction). Then N is not
    // a quantity (tax rate, size „33 x“ …); the leading quantity of the line counts, else 1. Lines that are only „2 x 0,79“ (name on
    // the line above) keep their quantity.
    if (mx != null && r.last != null && mx.end >= r.last!.end - 1 && _letterAZ.hasMatch(jsSlice(z.text, 0, mx.start)) &&
        (lead == null || jsParseFloat(mx[1]!.replaceFirst(',', '.')) != lead)) {
      mx = null;
    }
    final mx2 = mx == null ? RegExp('(\\d+$d ?\\d{2,3})\\s*(?:€|eur)?\\s*[x×*]\\s*(\\d{1,3})(?![.,]\\d)\\b', caseSensitive: false).firstMatch(z.text) : null;
    if (mx != null) {
      menge = jsParseFloat(mx[1]!.replaceFirst(',', '.'));
      var e = dec == '0' ? (int.tryParse(mx[2]!.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) * 100.0 : jsParseFloat(mx[2]!.replaceFirst(' ', '').replaceFirst(dec, '.')) * 100;
      if ((e - jsRound(e)).abs() < 1e-6) {
        einzel = jsRound(e);
      } else {
        einzel = e;
      }
    } else if (mx2 != null) {
      menge = jsInt(mx2[2]!);
      einzel = dec == '0' ? (int.tryParse(mx2[1]!.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) * 100 : jsRound(jsParseFloat(mx2[1]!.replaceFirst(' ', '').replaceFirst(dec, '.')) * 100);
    } else if (qtyFront != null && qtyFront != 0) {
      menge = qtyFront;
      if (bt.length >= 2) einzel = bt[bt.length - 2].v;
    } else if (bt.length >= 2 && r.last!.v > 0) {
      final e0 = bt[bt.length - 2], gap = jsSlice(z.text, e0.end, r.last!.start);
      for (final t in _qtyInGap.allMatches(gap)) {
        final q = jsInt(t[0]!);
        if (q >= 1 && (e0.v * q - r.last!.v).abs() <= 1) {
          menge = q;
          einzel = e0.v;
          break;
        }
      }
      // quantity column before the unit price: „EDE MICRO 3 KESKIKO 2 3,50 7,00“ (Finnland, Määrä/A-hinta/Summa; Weltkorpus
      // 06.11.). Only when quantity × unit price gives the line total exactly.
      // „RED BULL 2 140.00 280.00“ (India, Qty/Rate/Amount; Weltkorpus b2-001 07.11.): the amount pattern allows a space as thousands
      // separator, so „2 140.00“ was read as 2 140.00 and the quantity was lost. When quantity × the rest gives the line total exactly,
      // the space separates the quantity column, not thousands.
      if (menge == null) {
        final sp = _qtySpaceUnit.firstMatch(jsSlice(z.text, e0.start, e0.end));
        if (sp != null) {
          final q = jsInt(sp[1]!);
          final u = jsRound(jsParseFloat(sp[2]!.replaceFirst(',', '.')) * 100);
          if (q >= 2 && u > 0 && (u * q - r.last!.v).abs() <= 1) {
            menge = q;
            einzel = u;
            e0.v = e0.neg ? -u : u;
          }
        }
      }
      if (menge == null) {
        final qb = _qtyBeforePrice.firstMatch(jsSlice(z.text, 0, e0.start));
        final q = qb != null ? jsInt(qb[1]!) : 0;
        if (q >= 2 && e0.v > 0 && (e0.v * q - r.last!.v).abs() <= 1) {
          menge = q;
          einzel = e0.v;
        } else if (_qtyWordStart.hasMatch(z.text) && e0.v > 0 && r.last!.v % e0.v == 0 && r.last!.v ~/ e0.v >= 2 && r.last!.v ~/ e0.v <= 50) {
          // „Qty 2@ $2.00 each 4.00“ with „@“ read as „0“ („Qty 20 $2.00“, Woolworths 06.11.): total ÷ unit price is the quantity
          menge = r.last!.v ~/ e0.v;
          einzel = e0.v;
        }
      }
    } else {
      final mv = _qtyLead.firstMatch(z.text);
      // A leading number is a quantity only if the line amount splits into whole cents per piece: „94 MAYB MASC 5.24“ (rest of a cut
      // article number, Target, Weltkorpus b3-013 07.11.) became 94 pieces at 5.5745 each
      final q = mv != null ? jsInt(mv[1]!) : 0;
      if (q > 0 && (q == 1 || r.last == null || r.last!.v % q == 0)) menge = q;
    }
    r.qty = menge;
    r.unit = einzel;
    final mxi = mx != null ? mx.start : (mx2 != null ? mx2.start : 1 << 30);
    var name = r.last != null ? nameFrom(jsSlice(z.text, 0, math.min(mxi, bt[0].start))) : nameFrom(z.text);
    if (r.last != null && r.last!.late) name = name.replaceFirst(_lateTail, '');
    r.name = name;
    final satz = _rateRe.firstMatch(z.text)?[1];
    String? stb = r.last != null && !r.last!.late ? _taxCodeRe.firstMatch(jsSlice(z.text, r.last!.end))?.group(1) : null;
    if (r.last != null && r.last!.late && z.readings != null) {
      final zz = <String, int>{};
      for (final m in z.readings!) {
        final x = _taxCodeLate.firstMatch(m.text);
        if (x != null) zz[x[1]!] = (zz[x[1]!] ?? 0) + 1;
      }
      final top = stableSorted<MapEntry<String, int>>(zz.entries, (p2, q2) => q2.value - p2.value);
      if (top.isNotEmpty && top[0].value >= 2) stb = top[0].key;
    }
    r.taxCode = stb;
    r.letters = lettersIn(name);
    r.rate = satz != null ? jsInt(satz) : null;
    r.unitOnly = Kw.einzel.hasMatch(foldLower(jsSlice(z.text, 0, bt.isNotEmpty ? bt[0].start : z.text.length)));
    info.add(r);
  }
  // tax table after a total: its "Total" lines are tax totals
  {
    final s0 = info.indexWhere((r) => r.kind == 'summe' || _totalish.hasMatch(r.n));
    if (s0 >= 0) {
      var t0 = -1;
      for (var i = s0 + 1; i < info.length; i++) {
        if (Kw.steuerTabelle.hasMatch(info[i].n)) {
          t0 = i;
          break;
        }
      }
      if (t0 > 0) {
        for (var i = t0; i < info.length; i++) {
          if (info[i].kind == 'summe') info[i].kind = 'steuer';
        }
      }
    }
  }
  // end of the item block: first total line with an amount (or the next line carries it)
  var end = -1;
  for (var i = 0; i < info.length; i++) {
    final r = info[i];
    if (r.kind == 'summe' && (r.last != null || (i + 1 < info.length && info[i + 1].last != null && info[i + 1].letters < 3))) {
      end = i;
      break;
    }
  }
  if (end < 0) end = info.length;
  // no total word: the first line whose amount equals the sum of all amounts above (≥ 2 items) is the total
  // Only on receipts without any total word: when „TOTAL DUE“ is printed but its amount sits on another line (Cutler & Co, Weltkorpus
  // b3-143: business card text merged into the rows), the first coincidence „4.00 + 5.00 = 9.00“ became the total and 2 of 7 items
  // were reported as checked. A printed total word outranks arithmetic coincidence (06.11., Sitzung B).
  if (end == info.length && !(qr != null && qr.total != 0) && !info.any((r) => r.kind == 'summe')) {
    var sum = 0, n = 0;
    for (var i = 0; i < info.length; i++) {
      final r = info[i];
      if (r.last == null || const ['kopf', 'nein', 'steuer', 'zahlung', 'rueck'].contains(r.kind)) continue;
      if (n >= 2 && r.last!.v == sum && sum > 0) {
        r.kind = 'summe';
        r.totalWithoutWord = true;
        end = i;
        break;
      }
      sum += r.last!.v;
      n++;
    }
  }
  var headLine = -1;
  for (var i = 0; i < info.length; i++) {
    if (i < end && info[i].kind == 'kopf') {
      headLine = i;
      break;
    }
  }
  final withSub = info.asMap().entries.any((e) => e.key < end && e.value.kind == 'zwischen');
  {
    var seen = false;
    for (var i = headLine + 1; i < end; i++) {
      final r = info[i];
      if (r.last != null && r.kind == 'sonst') seen = true;
      if (seen && ((r.kind == 'steuer' && (r.last == null || !withSub)) || (r.kind == 'zwischen' && !withSub))) {
        end = i;
        break;
      }
    }
  }
  final items = <Item>[];
  final surcharges = <_Surcharge>[];
  // indentation: lines clearly right of the usual start belong to the item above
  final starts = stableSorted<double>([
    for (final r in info)
      if (r.i > headLine && r.i < end && r.last != null) r.line.box.x0
  ], numAsc);
  final hs = stableSorted<double>(info.map((r) => r.line.box.h), numAsc);
  final hBlock = hs.isNotEmpty && hs[0] != 0 ? hs[0] : 20.0;
  final indent = starts.length >= 3 ? starts[starts.length >> 1] + 1.2 * hBlock : null;
  int lastUsed(Item p) {
    final idx = items.indexOf(p);
    var m = p.line;
    for (final r in info) {
      if (r.type == 'teil' && r.item == idx && r.i > m) m = r.i;
    }
    return m;
  }

  for (var i = headLine + 1; i < end; i++) {
    final r = info[i];
    if (r.last == null || r.kind == 'nein' || r.kind == 'zwischen' || r.kind == 'vorab' || r.kind == 'anzahlung' || (r.kind == 'steuer' && !withSub)) {
      final prev = items.isNotEmpty ? items.last : null;
      if (r.last == null &&
          r.kind == 'sonst' &&
          prev != null &&
          i - lastUsed(prev) <= 3 &&
          (_bullet.hasMatch(r.line.text) || (indent != null && r.line.box.x0 > indent))) {
        r.type = 'teil';
        r.item = items.length - 1;
        r.part = true;
        continue;
      }
      if (r.last == null &&
          r.kind == 'sonst' &&
          r.letters >= 3 &&
          !r.unitOnly &&
          !_priceWord.hasMatch(r.n) &&
          (items.isNotEmpty || headLine >= 0)) {
        r.type = 'unklar';
      }
      continue;
    }
    if ((r.kind == 'steuer' && withSub) || r.kind == 'service' || r.kind == 'rundung') {
      surcharges.add(_Surcharge(
        r.kind == 'service' ? (r.name.isNotEmpty ? r.name : 'Service') : (r.kind == 'rundung' ? 'Rundung' : (r.name.isNotEmpty ? r.name : 'Steuer')),
        r.kind,
        i,
        [Cand(r.last!.v, 0), for (final a in alternatives(r.line, r.last!)) Cand(a.v, a.k, a.why), ..._roundingSign(r)],
      ));
      continue;
    }
    // unit price / quantity line without name: belongs to the item above or below
    final prev = items.isNotEmpty ? items.last : null;
    final qtyLine = r.unitOnly || (r.letters < 2 && r.unit != null && r.unit != 0 && r.amounts.length == 1);
    if (qtyLine) {
      final num? e0 = r.unitOnly ? r.last!.v : r.unit;
      final total0 = r.qty != null && r.qty != 0 && e0 != null && e0 != 0 ? jsRound(r.qty! * e0) : null;
      final above = prev != null && prev.line == i - 1 ? prev : null;
      final nx = i + 1 < info.length ? info[i + 1] : null;
      final below = nx != null && nx.last != null && nx.letters >= 2 && !const ['nein', 'summe', 'zwischen', 'steuer'].contains(nx.kind) ? nx : null;
      bool fits(int b) => total0 != null && (b.abs() - total0).abs() <= 1;
      if (below != null && !(above != null && fits(above.amount)) && (fits(below.last!.v) || above == null)) {
        r.type = 'teil';
        r.qtyFor = _QtyRef(r.qty, e0, i);
        below.qtyFrom = r.qtyFor;
        continue;
      }
    }
    if (prev != null && prev.line == i - 1 && qtyLine) {
      final num? e = r.unitOnly ? r.last!.v : r.unit;
      prev.unit = e;
      if (r.unit != null && r.unit != 0 && r.qty != null && r.qty != 0) prev.qty = r.qty!;
      if (e != null && e != 0 && prev.amount % e == 0 && prev.amount / e >= 1 && prev.amount / e <= 50) {
        prev.qty = prev.amount / e;
        prev.qtySure = true;
      } else if (e != null && e != 0) {
        final m = prev.qtyRead != 0 ? prev.qtyRead : math.max(1, jsRound(prev.amount / e));
        if (m * e != prev.amount && m <= 50) prev.cands.add(Cand(jsRound(m * e), prev.qtyRead != 0 ? 0.4 : 0.6, 'Menge × Preis'));
      }
      r.type = 'teil';
      r.item = items.length - 1;
      continue;
    }
    var name = r.name;
    var nameLine = -1;
    // name one line higher
    if (r.letters < 2) {
      for (var k = i - 1; k >= math.max(0, i - 2); k--) {
        final o = info[k];
        if (o.last != null || o.kind != 'sonst' || (o.type != null && o.type != 'unklar')) break;
        if (o.letters >= 3) {
          name = o.name;
          nameLine = k;
          break;
        }
      }
    }
    // name one line lower (Malaysia: "item no. qty price amount", name below)
    if (r.letters < 2 && nameLine < 0) {
      final o = i + 1 < info.length ? info[i + 1] : null;
      if (o != null && o.last == null && o.kind == 'sonst' && o.type == null && o.letters >= 3) {
        name = o.name.replaceFirst(_leadDash, '');
        nameLine = i + 1;
      }
    }
    var v = r.last!.v;
    final st = votes(r.last!.late ? null : v, r.line.readings, dec);
    if (st.isNotEmpty && st[0].v != v && st[0].share > 0.5) v = st[0].v;
    if (r.kind == 'rabatt' && v > 0) v = -v;
    final cands = [Cand(v, 0)];
    for (final a in [...st, ...alternatives(r.line, r.last!)]) {
      final w = r.kind == 'rabatt' && a.v > 0 ? -a.v : a.v;
      if (!cands.any((x) => x.v == w)) cands.add(Cand(w, math.max(0.15, a.k), a.why ?? 'Ziffer unsicher'));
    }
    if (r.kind == 'storno' || r.kind == 'leergut') v = -v.abs();
    if (r.unit != null && r.unit != 0 && r.qty != null && r.qty != 0) {
      final mv = jsRound(r.qty! * r.unit!);
      if (mv != v && mv.abs() < 1e6) cands.add(Cand(mv, 0.6, 'Menge × Preis'));
    }
    if (r.qtyFrom != null && (r.qty == null || r.qty == 0)) {
      r.qty = r.qtyFrom!.qty;
      r.unit = r.qtyFrom!.unit;
      info[r.qtyFrom!.line].item = items.length;
      final prod = (r.qty ?? double.nan) * (r.unit ?? double.nan);
      final mv = jsRound(prod);
      if (prod.isFinite && mv != v && mv.abs() < 1e6) cands.add(Cand(mv, 0.6, 'Menge × Preis'));
    }
    if (nameLine >= 0) {
      info[nameLine].type = 'teil';
      info[nameLine].item = items.length;
    }
    r.type = 'posten';
    r.item = items.length;
    final readable = lettersIn(name) >= 2;
    final gastro = kind != null && const ['restaurant', 'cafe', 'bar'].contains(kind.id), shop = kind != null && kind.id == 'supermarkt';
    cands.add(Cand(0, readable ? 99 : (gastro ? 1.5 : (shop ? 0.9 : 1.2)), 'weg'));
    final q = r.qty;
    final qtyOk = q != null && q >= 1 && q == q.roundToDouble();
    final it = Item(
      name: readable ? name : (r.kind == 'leergut' ? 'Leergut' : (v < 0 ? 'Rabatt' : 'Posten')),
      amount: v,
      qty: qtyOk ? q : 1,
      line: i,
      conf: r.line.conf,
      frame: r.line.box,
      cands: cands,
    )
      ..qtyRead = qtyOk && q > 1 ? q : 0
      ..unit = r.unit
      ..rate = r.rate
      ..taxCode = r.taxCode
      ..nameLine = nameLine
      ..nameUncertain = !readable && r.kind != 'leergut'
      ..kind2 = const ['rabatt', 'leergut', 'storno', 'kaution'].contains(r.kind) ? r.kind : null
      ..deposit = r.kind == 'kaution'
      ..votes = [for (final x in st) (x.v, toFixed(x.share, 3))]
      ..readCount = r.line.readings != null ? r.line.readings!.length + 1 : 1;
    items.add(it);
  }
  // total candidates: total line(s), card payment, given − change, QR
  final targets = <_Target>[];
  void target(int v, double k, String source, [int line = -1]) {
    if (qr != null && qr.total != 0 && source != 'qr') return;
    if (v > 0 && !targets.any((z) => z.v == v && z.k <= k)) targets.add(_Target(v, k, source, line));
  }

  if (qr != null && qr.total != 0) target(qr.total, 0, 'qr');
  var totalLine = -1;
  int? totalRead;
  var advance = 0;
  for (var i = end; i < info.length; i++) {
    final r = info[i];
    if (r.last != null && (r.kind == 'service' || r.kind == 'rundung')) {
      surcharges.add(_Surcharge(r.kind == 'rundung' ? 'Rundung' : (r.name.isNotEmpty ? r.name : 'Trinkgeld'), r.kind == 'rundung' ? 'rundung' : 'trinkgeld', i, [Cand(r.last!.v, 0), ..._roundingSign(r)]));
      r.type = 'zuschlag';
      continue;
    }
    if (r.last != null && r.kind == 'anzahlung') {
      advance += r.last!.v.abs();
      r.type = 'anzahlung';
      continue;
    }
    if (r.kind == 'summe' && r.last == null && i + 1 < info.length && info[i + 1].last != null) {
      final q = info[i + 1];
      target(q.last!.v, 0.3, 'summe', i + 1);
      if (totalLine < 0) {
        totalLine = i;
        totalRead = q.last!.v;
      }
      r.type = 'summe';
      continue;
    }
    if (r.last == null) continue;
    if (r.kind == 'summe') {
      if (totalLine < 0) {
        totalLine = i;
        totalRead = r.last!.v;
      }
      target(r.last!.v, 0, 'summe', i);
      for (final a in [...votes(r.last!.v, r.line.readings, dec).skip(1), ...alternatives(r.line, r.last!)]) {
        target(a.v, math.max(0.2, a.k), 'summe', i);
      }
      r.type = 'summe';
    }
  }
  // without total word: amounts after the block at least as large as every item are candidates
  if (!targets.any((z) => z.source == 'summe' || z.source == 'qr')) {
    var tab = -1;
    for (var i = end; i < info.length; i++) {
      if (Kw.steuerTabelle.hasMatch(info[i].n)) {
        tab = i;
        break;
      }
    }
    final until = tab >= 0 ? tab : info.length;
    final maxP = items.fold<int>(0, (a, p) => math.max(a, p.amount.abs()));
    final after = [
      for (var i = end; i < until; i++)
        if (info[i].last != null && info[i].last!.v > 0 && info[i].last!.v >= maxP && !const ['steuer', 'rueck', 'nein', 'rabatt'].contains(info[i].kind)) i
    ];
    final cnt = <int, int>{};
    for (final i in after) {
      cnt[info[i].last!.v] = (cnt[info[i].last!.v] ?? 0) + 1;
    }
    for (final i in after) {
      final rep = cnt[info[i].last!.v]! >= 2;
      if (rep || items.length >= 2) target(info[i].last!.v, rep ? 0.5 : 1.0, rep ? 'wiederholt' : 'betrag', i);
    }
  }
  {
    final sz = targets.where((z) => z.source == 'summe').toList();
    final max = sz.isNotEmpty ? sz.map((z) => z.v).reduce(math.max) : 0;
    for (final z in sz) {
      if (z.v < max) z.k += 0.8;
    }
  }
  final given = [for (var i = end; i < info.length; i++) if (info[i].kind == 'zahlung' && info[i].last != null) info[i].last!.v];
  final change = [for (var i = end; i < info.length; i++) if (info[i].kind == 'rueck' && info[i].last != null) info[i].last!.v.abs()];
  for (final g in given) {
    target(g, 0.4, 'zahlung', end);
    for (final q in change) {
      if (g - q > 0) target(g - q, 0.4, 'zahlung');
    }
  }
  // amounts larger than every total cannot be items: dropping is almost free
  final maxTarget = targets.isNotEmpty ? targets.map((z) => z.v).reduce(math.max).toDouble() : double.infinity;
  for (final p in items) {
    if (p.amount.abs() > maxTarget) {
      for (final c in p.cands) {
        if (c.why == 'weg') {
          c.k = 0.1;
          break;
        }
      }
    }
  }
  final solution = items.isNotEmpty ? _match(items, surcharges, targets) : null;
  int? total;
  var ok = false;
  if (solution != null) {
    for (var i = 0; i < items.length; i++) {
      final p = items[i];
      final c = p.cands[solution.pick[i]];
      if (c.why == 'weg') {
        p.dropped = true;
        continue;
      }
      if (c.v != p.amount) p.repair = c.why ?? 'aus der Summe';
      p.amount = c.v;
      p.sure = true;
    }
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i].dropped) {
        info[items[i].line].type = 'sonst';
        items.removeAt(i);
      }
    }
    for (var i = 0; i < items.length; i++) {
      info[items[i].line].item = i;
      if (items[i].nameLine >= 0) info[items[i].nameLine].item = i;
    }
    for (var i = 0; i < solution.extra.length; i++) {
      final w = solution.extra[i];
      if (w >= 0) {
        final z = surcharges[i];
        items.add(Item(name: z.name, amount: z.cands[w].v, line: z.line, conf: 100)
          ..surcharge = z.kind
          ..sure = true);
        info[z.line].type = 'zuschlag';
      }
    }
    total = solution.target.v;
    ok = true;
    // The total word is printed but its amount could not be read („Total Que 51.“, faint print 06.11.): another source (cash
    // given, a large amount) cannot vouch for the items then – it matched a cash line „0.20“ and reported 0.20 as checked.
    final unreadTotal = info.any((r) => r.kind == 'summe' && r.last == null && !(r.i + 1 < info.length && info[r.i + 1].last != null) && !Kw.inklSteuer.hasMatch(r.n));
    if (unreadTotal && solution.target.source != 'summe' && solution.target.source != 'qr') ok = false;
    // tax/rounding after a (net) total: the larger read total is the grand total if net + these lines give it
    final extra = <int>[];
    for (var i = end; i < info.length && extra.length < 6; i++) {
      final r2 = info[i];
      if (r2.last != null &&
          (r2.kind == 'steuer' || r2.kind == 'rundung' || r2.kind == 'service') &&
          r2.last!.v.abs() < total &&
          (r2.type == null || (r2.type == 'zuschlag' && !items.any((p) => p.surcharge != null && p.line == i)))) {
        extra.add(i);
      }
    }
    final zl0 = solution.target.line;
    final later = [
      for (var i = math.max(zl0, end - 1) + 1; i < info.length; i++)
        if (info[i].last != null && info[i].last!.v > 0) info[i].last!.v
    ];
    final others = <int>{for (final z in targets) if (z.v != total && z.line > zl0 && z.source != 'betrag') z.v};
    var roundLine = -1;
    for (var i = end; i < info.length; i++) {
      if (info[i].kind == 'rundung' || _roundish.hasMatch(info[i].n)) {
        roundLine = i;
        break;
      }
    }
    ({int sum, List<int> part, int round})? pickE;
    for (var m = 0; m < 1 << extra.length; m++) {
      var sum = total;
      final part = <int>[];
      for (var k = 0; k < extra.length; k++) {
        if (m & (1 << k) != 0) {
          final r2 = info[extra[k]];
          if (r2.kind == 'rundung' && r2.last!.v == 0) continue;
          sum += r2.last!.v;
          part.add(extra[k]);
        }
      }
      int? target2 = others.contains(sum) && m != 0 ? sum : null;
      var round = 0;
      if (target2 == null && roundLine >= 0) {
        final c = stableSorted<int>([...others, ...later].where((x) => x % 5 == 0 && x != sum && (x - sum).abs() <= 4), (a, b) => (a - sum).abs() - (b - sum).abs());
        if (c.isNotEmpty) {
          target2 = c[0];
          round = c[0] - sum;
        }
      }
      // Rounding to whole units that is not printed (India „Grand Total 3128.00“ after net 2620.00 + taxes 508.47, Czechia; Weltkorpus
      // b2-001 06.11.): only towards a printed total line, only with at least one tax line used, only to a whole unit and by less than
      // half a unit – the tax lines must already explain the rest exactly.
      if (target2 == null && m != 0) {
        final c = stableSorted<int>(others.where((x) => x % 100 == 0 && x != sum && (x - sum).abs() <= 50), (a, b) => (a - sum).abs() - (b - sum).abs());
        if (c.isNotEmpty) {
          target2 = c[0];
          round = c[0] - sum;
        }
      }
      if (target2 == null) continue;
      final w = (sum: target2, part: part, round: round);
      int cnt(({int sum, List<int> part, int round}) x) => x.part.length + (x.round != 0 ? 1 : 0);
      if (pickE == null || w.sum > pickE.sum || (w.sum == pickE.sum && cnt(w) < cnt(pickE))) pickE = w;
    }
    if (pickE != null) {
      for (final i in pickE.part) {
        final r2 = info[i];
        items.add(Item(
          name: r2.kind == 'rundung' ? 'Rundung' : (r2.name.isNotEmpty ? r2.name : (r2.kind == 'service' ? 'Service' : 'Steuer')),
          amount: r2.last!.v,
          line: i,
          conf: 100,
        )
          ..surcharge = r2.kind == 'rundung' ? 'rundung' : r2.kind
          ..sure = true);
        r2.type = 'zuschlag';
      }
      if (pickE.round != 0) {
        // unprinted rounding: anchored to the printed total it leads to (a line index is needed for the snippet)
        final sumAt = info.indexWhere((r) => r.i > zl0 && r.kind == 'summe' && r.last?.v == pickE!.sum);
        items.add(Item(name: 'Rundung', amount: pickE.round, line: roundLine >= 0 ? roundLine : math.max(sumAt, zl0), conf: 100)
          ..surcharge = 'rundung'
          ..sure = true);
      }
      total = pickE.sum;
    } else {
      // A larger printed total further down that the tax lines do not explain: the matched total was a net or sub total („T. Importe
      // 9.81 … Total 10.50“, Weltkorpus b1-092 06.11.; b2-001 before the rounding rule). The items cannot vouch for what is to be paid.
      // If the exact difference is printed in the tax block between both totals (IVA 0.69 in the tax table), it is the tax item;
      // otherwise the larger total is shown and the receipt is not checked. At most 40 % above (tax/service), so a total printed again
      // in another currency is never taken.
      final t1 = total;
      final grand = info.indexWhere((r) => r.i > zl0 && r.kind == 'summe' && r.last != null && r.last!.v > t1 && r.last!.v * 10 <= t1 * 14);
      if (grand >= 0) {
        final d = info[grand].last!.v - t1;
        final taxAt = [for (var i = zl0 + 1; i < grand; i++) if (info[i].kind == 'steuer') i];
        var bridge = -1;
        if (taxAt.isNotEmpty) {
          for (var i = zl0 + 1; i < grand && bridge < 0; i++) {
            if (info[i].kind != 'summe' && info[i].amounts.any((a) => a.v == d)) bridge = i;
          }
        }
        if (bridge >= 0) {
          final word = taxAt.map((i) => _taxName.firstMatch(info[i].n)?[0]).whereType<String>().firstOrNull;
          items.add(Item(name: word == null ? 'Steuer' : (word.length <= 4 ? word.toUpperCase() : word), amount: d, line: bridge, conf: 100)
            ..surcharge = 'steuer'
            ..sure = true);
          info[bridge].type = 'zuschlag';
        } else {
          ok = false;
        }
        total = info[grand].last!.v;
      }
    }
  } else {
    // A „total“ of zero or less next to items that add up to a positive amount is a misread (a rounding line „-0.02“ or „0.00“
    // that slipped into the total's row when the amount column is shifted by one line, SROIE 008/020/034) – better unknown than
    // wrong. Real refunds have negative items too and keep their negative total.
    final itemSum = items.fold<int>(0, (a, p) => a + p.amount);
    final read = totalRead != null && totalRead <= 0 && itemSum > 0 ? null : totalRead;
    total = qr != null && qr.total != 0 ? qr.total : (read ?? (given.isNotEmpty ? given[0] - (change.isNotEmpty ? change[0] : 0) : null));
    for (final p in items) {
      p.sure = false;
      if (p.cands.length > 2) p.suggestions = p.cands.where((c) => c.why != 'weg' && c.v != p.amount).take(3).map((c) => c.v).toList();
    }
  }
  // an item whose name could not be read is not „sure“ (the screen shows a question mark and the receipt snippet): the sum may
  // check out and the name still be missing (05.11.: three „Posten“ marked sure)
  for (final p in items) {
    if (p.nameUncertain && !p.missing) p.sure = false;
  }
  // reading certainty per item: share of readings that gave exactly this amount (sign ignored)
  for (final p in items) {
    if (p.surcharge != null) continue;
    final share = p.votes.where((x) => x.$1.abs() == p.amount.abs()).fold<double>(0, (a, x) => a + x.$2);
    p.certainty = p.readCount > 1 ? jsRound(math.min(1, share == 0 ? 0.1 : share) * 100) : jsRound(math.min(95, (p.conf == 0 ? 80 : p.conf) * 0.95));
    final sugg = <int>[];
    for (final x in p.votes) {
      if (x.$1.abs() != p.amount.abs() && !sugg.contains(x.$1.abs())) sugg.add(x.$1.abs());
    }
    for (final c in p.cands) {
      if (c.why != 'weg' && c.v > 0 && c.v != p.amount.abs() && !sugg.contains(c.v)) sugg.add(c.v);
    }
    p.suggestions = sugg.take(4).toList();
  }
  // A storno line can be torn in two (de-discount 06.11.: „Storno os Paprika“ without amount, „cYanmaGtaYelow -1,79“ with a misread
  // name): a negative item without its own kind right next to a storno line that has no amount is that line's amount.
  for (final p in items) {
    if (p.amount >= 0 || p.kind2 != null || p.line < 0) continue;
    for (final j in [p.line - 1, p.line + 1]) {
      if (j >= 0 && j < info.length && info[j].kind == 'storno' && info[j].amounts.isEmpty) {
        p.kind2 = 'storno';
        break;
      }
    }
  }
  _cancelPairs(items, info);
  _attachExtras(items, info);
  for (final p in items) {
    if (p.surcharge == null && p.qty > 1 && (p.unit == null || p.unit == 0) && p.amount > 0 && p.amount % p.qty == 0) p.unit = p.amount / p.qty;
  }
  final sum = items.fold<int>(0, (a, p) => a + p.amount);
  return ReadResult(
    lines: [
      for (final r in info)
        LineOut(
          text: r.line.text,
          box: r.line.box,
          conf: r.line.conf,
          type: r.type ?? r.kind,
          item: r.item,
          block: r.i > headLine && r.i < end,
        )
    ],
    items: items,
    total: total,
    totalLine: totalLine,
    sum: sum,
    dec: dec,
    advance: advance,
    check: Check(ok: ok && sum == total, source: solution?.target.source, corrected: items.where((p) => p.repair != null).length, targets: targets.length),
  );
}

class _Solution {
  _Solution(this.pick, this.extra, this.target, this.k);

  final List<int> pick, extra;
  final _Target target;
  final double k;
}

class _Dp {
  _Dp(this.k, this.prev, this.w);

  final double k;
  final int prev;
  final int w;
}

/// Fewest changes so that the items (plus optional tax/service) give one of the totals; DP over cent sums,
/// at most cost 3 [abgleich].
_Solution? _match(List<Item> items, List<_Surcharge> extras, List<_Target> targets) {
  if (targets.isEmpty) return null;
  const maxK = 3.0;
  final layers = <Map<int, _Dp>>[];
  var dp = <int, _Dp>{0: _Dp(0, 0, 0)};
  void step(List<({int v, double k, int w})> options) {
    final next = <int, _Dp>{};
    dp.forEach((s, e) {
      for (final o in options) {
        final ns = s + o.v, nk = e.k + o.k;
        if (nk > maxK) continue;
        final old = next[ns];
        if (old == null || nk < old.k) next[ns] = _Dp(nk, s, o.w);
      }
    });
    if (next.length > 40000) {
      final sorted = stableSorted<MapEntry<int, _Dp>>(next.entries, (a, b) => numAsc(a.value.k, b.value.k)).take(40000);
      dp = {for (final e in sorted) e.key: e.value};
    } else {
      dp = next;
    }
    layers.add(dp);
  }

  for (final p in items) {
    step([for (var w = 0; w < p.cands.length; w++) (v: p.cands[w].v, k: p.cands[w].k, w: w)]);
  }
  for (final z in extras) {
    step([(v: 0, k: 0.0, w: -1), for (var w = 0; w < z.cands.length; w++) (v: z.cands[w].v, k: z.cands[w].k + 0.05, w: w)]);
  }
  ({double k, _Target t})? best;
  for (final z in targets) {
    final e = dp[z.v];
    if (e != null && (best == null || e.k + z.k < best.k)) best = (k: e.k + z.k, t: z);
  }
  if (best == null) return null;
  final pick = <int>[], extra = <int>[];
  var s = best.t.v;
  for (var i = layers.length - 1; i >= 0; i--) {
    final e = layers[i][s]!;
    if (i >= items.length) {
      extra.insert(0, e.w);
    } else {
      pick.insert(0, e.w);
    }
    s = e.prev;
  }
  return _Solution(pick, extra, best.t, best.k);
}

// ---------------------------------------------------------------------------------------------------------------------
// Receipt kind [bonArt]

final List<(String, String, RegExp)> _kinds = [
  ('restaurant', 'Restaurant', RegExp(r'\b(mesa|tisch|table|tavolo|couvert|coperto|servico|servizio|bedienung|kellner|garcom|empregado|gorjeta|trinkgeld|gratuity|restaurante|restaurant|ristorante|trattoria|tasca|taberna|marisqueira|churrasqueira|pizzeria|brasserie|bistro|osteria|gasthaus|gaststatte)\b')),
  ('cafe', 'Café', RegExp(r'\b(cafe|caffe|cafetaria|pastelaria|confeitaria|padaria|bakery|backerei|baeckerei|konditorei|patisserie|boulangerie|coffee|gelataria|eiscafe|pasticceria)\b')),
  ('bar', 'Bar', RegExp(r'\b(bar|pub|cervejaria|kneipe|cocktail|lounge|taverna|biergarten)\b')),
  ('supermarkt', 'Einkauf', RegExp(r'\b(supermercado|supermarket|supermarche|supermarkt|markt|mercado|rewe|edeka|lidl|aldi|pingo doce|continente|carrefour|minipreco|auchan|spar|netto|penny|kaufland|mercadona|coop|migros|tesco|sainsbury|intermarche|pfand|leergut|eur kg|kg x|stk|cartao continente|poupanca|artikel)\b')),
  ('tanken', 'Tanken', RegExp(r'\b(diesel|gasoleo|gasolina|benzin|super e10|e10|sp95|sp98|litros|liter|ltr|zapfsaule|bomba|galp|repsol|shell|aral|esso|cepsa|adblue)\b')),
  ('apotheke', 'Apotheke', RegExp(r'\b(farmacia|apotheke|pharmacy|pharmacie|parafarmacia|drogerie|dm-drogerie|rossmann)\b')),
  ('fahrt', 'Fahrt', RegExp(r'\b(bilhete|fahrkarte|comboios|carris|metropolitano|uber|bolt|taxi|portagem|maut|estacionamento|parking|parkhaus)\b')),
  ('unterkunft', 'Unterkunft', RegExp(r'\b(hotel|hostel|alojamento|pousada|check-?in|noites|nights|ubernachtung|city tax|taxa turistica|kurtaxe)\b')),
  ('eintritt', 'Eintritt', RegExp(r'\b(museu|museum|museo|bilheteira|admission|eintritt|ingresso|monumento|palacio|castelo)\b')),
];
final _kgRe = RegExp(r'\d[.,]\d{2,3}\s*kg');
final _notFood = RegExp('Pfand|Service|Tanken|Fahrt|Eintritt');
final _notShop = RegExp(r'\d{4}|tel|nif|www|@|rua |str\.|avenida|street', caseSensitive: false);

ReceiptKind receiptKind(List<Line> lines) {
  final head = lines.take(math.max(6, (lines.length * 0.35).ceil())).map((z) => foldLower(z.text)).join(' \n ');
  final all = lines.map((z) => foldLower(z.text)).join(' \n ');
  final points = [
    for (final (id, name, re) in _kinds)
      (id: id, name: name, p: (countMatches(re, all) + countMatches(re, head) + (id == 'supermarkt' ? math.min(4, countMatches(_kgRe, all)) : 0)).toDouble())
  ];
  var food = 0;
  for (final z in lines) {
    final k = Speisen.recognise(z.text);
    if (k != null && !_notFood.hasMatch(k.name)) food++;
  }
  points[0] = (id: points[0].id, name: points[0].name, p: points[0].p + food * 0.3);
  points[1] = (id: points[1].id, name: points[1].name, p: points[1].p + food * 0.3);
  stableSort(points, (a, b) => numAsc(b.p, a.p));
  final best = points[0];
  final shopLine = lines.take(5).where((z) => lettersIn(z.text) >= 5 && !_notShop.hasMatch(z.text)).firstOrNull;
  final shop = jsSlice(shopLine?.text ?? '', 0, 40);
  return best.p >= 2
      ? ReceiptKind(best.id, best.name, best.p >= 4 && best.p >= points[1].p * 2, shop)
      : ReceiptKind('unbekannt', '', false, shop);
}

/// General reader, then the Portuguese tax-class reader if the first does not check out [lies].
ReadResult readLines(List<Line> lines, QrInfo? qr) {
  final kind = receiptKind(lines);
  final a = readGeneral(lines, qr, kind)..kind = kind;
  if (a.check.ok) return a;
  ReadResult? pt;
  try {
    pt = readPortugal(lines, qr);
  } catch (_) {
    pt = null;
  }
  if (pt != null) {
    pt.kind = kind;
    pt.lines = [
      for (var i = 0; i < pt.lines.length; i++)
        LineOut(
          text: pt.lines[i].text,
          box: pt.lines[i].box,
          conf: pt.lines[i].conf,
          type: pt.lines[i].type == 'posten' ? 'posten' : (i < a.lines.length ? a.lines[i].type : pt.lines[i].type),
          item: pt.lines[i].item,
          block: i < a.lines.length ? a.lines[i].block : false,
        )
    ];
    for (final p in pt.items) {
      p.certainty ??= p.repair != null || p.missing ? 30 : jsRound(math.min(95, (p.conf == 0 ? 80 : p.conf) * 0.95));
    }
  }
  if (pt != null && pt.check.ok) return pt;
  return a.items.length >= (pt?.items.length ?? 0) ? a : pt!;
}

// ---------------------------------------------------------------------------------------------------------------------
// Portuguese receipts with tax classes in the QR code [liesPT]

const _rates = [0, 4, 5, 6, 8, 9, 12, 13, 16, 22, 23];

int _lev(String a, String b) {
  final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0)..[0] = i);
  for (var j = 1; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      d[i][j] = math.min(math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
  }
  return d[a.length][b.length];
}

List<int> _rateCands(String digits, List<int> possible) {
  if (_rates.contains(jsInt(digits)) && digits.length <= 2) return [jsInt(digits)];
  return possible.where((x) => _lev('$x', digits) <= 1).toList();
}

class _Pt {
  _Pt({required this.name, required this.b, required this.qty, required this.vat, this.rateCands, required this.line, required this.conf, required this.nameUncertain, this.frame});

  String name;
  int? b;
  int qty;
  int? unit;
  int? vat;
  List<int>? rateCands;
  final int line;
  final double conf;
  String? rep;
  final bool nameUncertain;
  final Box? frame;
  List<int> kand = [];
  int? read;
  bool sure = false;
  bool missing = false;
}

const _kopfPtSrc = r"(?:^|[^A-Za-zÀ-ÿ])(Uni|Un|Kg|Lt)(?=[^a-z]|[a-z]?[A-Z])[\s'’|:.,;_-]*";
final _pt1 = RegExp('$_kopfPtSrc(.+?)\\s+(\\d{1,3})\\s*[%gx]\\s*(.*)\$', caseSensitive: false);
final _pt2 = RegExp('$_kopfPtSrc(.+?)\\s+(0|4|5|6|8|9|12|13|16|22|23)[48]?\\s+(-?\\d[\\d.,]*)\\s*\$', caseSensitive: false);
final _ptQty = RegExp(r'(\d{1,3})\s*[^\d\w]*$');
final _ptD = RegExp(r'^d(?=[A-Z])');
final _ptLead = RegExp(r'^[^\wÀ-ÿ]+');
final _ptTail = RegExp(r'[^\wÀ-ÿ.)]+$');
final _ptNr = RegExp(r'^(.*?)\b(\d{1,2})\s*%\s*(-?\d+[,.]\d{2})\s*$');
final _ptNot = RegExp(r'[pf]re[cçg]o|total|incid', caseSensitive: false);
final _ptQ = RegExp(r'^\W*(\d{1,3})\b');
final _ptNm1 = RegExp(r'^\W*\d{1,3}\b');
final _ptNm2 = RegExp(r'[^\wÀ-ÿ]+');
final _ptPe = RegExp(r'[pf]r[eé][cçg]o\s*[:;.]?\s*(\d+[,.]\d{2})', caseSensitive: false);
final _ptTa = RegExp(r'^\W*(\d{1,2})\s*%\s+(\d+[,.]\d{2})\s+(\d+[,.]\d{2})\s*$');

ReadResult? readPortugal(List<Line> lines, QrInfo? qr) {
  final items = <_Pt>[];
  final table = <TaxClass>[];
  final withGross = qr?.classes.where((k) => k.gross > 0).toList() ?? const <TaxClass>[];
  final possible = withGross.isNotEmpty ? withGross.map((k) => k.rate).toList() : [6, 13, 23];
  for (var i = 0; i < lines.length; i++) {
    final z = lines[i];
    final t = fixDigits(z.text);
    var m = _pt1.firstMatch(t);
    m ??= _pt2.firstMatch(t);
    final sk = m != null ? _rateCands(m[3]!, possible) : const <int>[];
    if (m != null && sk.isNotEmpty) {
      final vor = jsSlice(t, 0, m.start + (m[0]!.toLowerCase().startsWith(m[1]!.toLowerCase()) ? 0 : 1));
      final q = _ptQty.firstMatch(vor);
      final pr = _priceRe.allMatches(m[4]!).map((x) => cent(x[1]!)).toList();
      final name = m[2]!.replaceFirst(_ptD, '').replaceFirst(_ptLead, '').replaceFirst(_ptTail, '').replaceAll(_ws, ' ').trim();
      var qty = q != null ? jsInt(q[1]!) : 1;
      if (qty > 20) qty = 1;
      final readable = _letters(name) >= 3;
      items.add(_Pt(
        name: readable ? name : 'Posten (Name nicht lesbar)',
        b: pr.isNotEmpty ? pr.last : null,
        qty: qty,
        vat: sk[0],
        rateCands: sk,
        line: i,
        conf: z.conf,
        nameUncertain: !readable,
        frame: z.box,
      ));
      continue;
    }
    final nr = _ptNr.firstMatch(t);
    if (nr != null && _rates.contains(jsInt(nr[2]!)) && _digit.hasMatch(nr[1]!) && !_ptNot.hasMatch(t)) {
      final q = _ptQ.firstMatch(nr[1]!);
      final nm = nr[1]!.replaceFirst(_ptNm1, '').replaceAll(_ptNm2, ' ').trim();
      final readable = _letters(nm) >= 3;
      items.add(_Pt(
        name: readable ? nm : 'Posten (Name nicht lesbar)',
        b: cent(nr[3]!),
        qty: q != null && jsInt(q[1]!) <= 20 ? jsInt(q[1]!) : 1,
        vat: jsInt(nr[2]!),
        line: i,
        conf: z.conf,
        nameUncertain: !readable,
        frame: z.box,
      ));
      continue;
    }
    final pe = _ptPe.firstMatch(t);
    if (pe != null && items.isNotEmpty) {
      items.last.unit = cent(pe[1]!);
      continue;
    }
    final ta = _ptTa.firstMatch(t);
    if (ta != null && _rates.contains(jsInt(ta[1]!))) table.add(TaxClass(rate: jsInt(ta[1]!), gross: cent(ta[2]!) + cent(ta[3]!)));
  }
  if (items.length < 2) return null;
  for (final p in items) {
    p.kand = [];
    if (p.unit != null && p.unit != 0) {
      if (p.qty != 0 && p.unit! * p.qty > 0) p.kand.add(p.unit! * p.qty);
      if (p.b != null && p.b! % p.unit! == 0 && p.b! / p.unit! <= 20 && !p.kand.contains(p.b)) p.kand.add(p.b!);
    }
    if (p.b != null && !p.kand.contains(p.b)) p.kand.add(p.b!);
    p.read = p.b;
  }
  final fromQr = qr != null && qr.classes.isNotEmpty;
  final classes = [for (final k in (fromQr ? qr.classes : table)) TaxClass(rate: k.rate, gross: k.gross, base: k.base, vat: k.vat)];
  final source = fromQr ? 'qr' : (table.isNotEmpty ? 'tabelle' : null);
  ({int abw, List<int> pick, int rest, List<_Pt> fixed, List<_Pt> open})? solveClass(TaxClass k, List<_Pt> with_) {
    final fixed = with_.where((p) => p.kand.isNotEmpty).toList(), open = with_.where((p) => p.kand.isEmpty).toList();
    if (fixed.length > 14 || open.length > 1) return null;
    final n = fixed.length;
    final pick = List<int>.filled(n, 0);
    ({int abw, List<int> pick, int rest, List<_Pt> fixed, List<_Pt> open})? best;
    void rec(int i, int sum, int abw) {
      if (best != null && abw > best!.abw) return;
      if (i == n) {
        final rest = k.gross - sum;
        if (open.isEmpty ? rest == 0 : rest > 0) {
          if (best == null || abw < best!.abw) best = (abw: abw, pick: List.of(pick), rest: rest, fixed: fixed, open: open);
        }
        return;
      }
      for (var c = 0; c < fixed[i].kand.length; c++) {
        pick[i] = c;
        rec(i + 1, sum + fixed[i].kand[c], abw + (c != 0 ? 1 : 0));
      }
    }

    rec(0, 0, 0);
    return best;
  }

  // lines with several possible rates: try all assignments (≤ 600), take the first without error
  final unclear = items.where((p) => p.rateCands != null && p.rateCands!.length > 1).toList();
  var assignments = <List<int>>[[]];
  for (final p in unclear) {
    final next = <List<int>>[];
    for (final z in assignments) {
      for (final s2 in p.rateCands!) {
        next.add([...z, s2]);
      }
    }
    assignments = next.take(600).toList();
  }
  List<Object?>? chosen; // per class: solution, 'leer' or null
  if (classes.isNotEmpty) {
    for (final z in assignments) {
      for (var i = 0; i < unclear.length; i++) {
        unclear[i].vat = z[i];
      }
      final sols = <Object?>[
        for (final k in classes)
          () {
            final with_ = items.where((p) => p.vat == k.rate).toList();
            return with_.isNotEmpty ? solveClass(k, with_) : 'leer';
          }()
      ];
      final foreign = items.any((p) => !classes.any((k) => k.rate == p.vat));
      if (!foreign && sols.every((x) => x != null)) {
        chosen = sols;
        break;
      }
    }
    if (chosen == null) {
      for (final p in unclear) {
        p.vat = p.rateCands![0];
      }
    }
  }
  for (var ki = 0; ki < classes.length; ki++) {
    final k = classes[ki];
    final with_ = items.where((p) => p.vat == k.rate).toList();
    if (with_.isEmpty) {
      k.actual = 0;
      k.ok = k.gross == 0;
      continue;
    }
    final Object? sol = chosen != null ? chosen[ki] : solveClass(k, with_);
    if (sol != null && sol is! String) {
      final s = sol as ({int abw, List<int> pick, int rest, List<_Pt> fixed, List<_Pt> open});
      for (var i = 0; i < s.fixed.length; i++) {
        final p = s.fixed[i];
        final v = p.kand[s.pick[i]];
        if (v != p.read) p.rep = p.unit != null && p.unit != 0 && v == p.unit! * p.qty ? 'Menge × Preis' : 'aus der Steuer-Summe';
        p.b = v;
        p.sure = true;
      }
      if (s.open.isNotEmpty) {
        s.open[0].b = s.rest;
        s.open[0].rep = 'aus der Steuer-Summe';
        s.open[0].sure = true;
      }
      k.actual = k.gross;
      k.ok = true;
    } else {
      for (final p in with_) {
        if (p.kand.isNotEmpty) p.b = p.kand[0];
        p.sure = false;
      }
      var actual = with_.fold<int>(0, (a, p) => a + (p.b ?? 0));
      if (actual < k.gross) {
        items.add(_Pt(name: 'Nicht gelesen (${k.rate} %)', b: k.gross - actual, qty: 1, vat: k.rate, line: -1, conf: 0, nameUncertain: false)
          ..rep = 'fehlender Rest'
          ..missing = true);
        actual = k.gross;
      }
      k.actual = actual;
      k.ok = false;
    }
  }
  if (classes.isEmpty) {
    for (final p in items) {
      if (p.b == null && p.kand.isNotEmpty) {
        p.b = p.kand[0];
      } else if (p.kand.isNotEmpty && p.unit != null && p.unit != 0 && p.qty != 0) {
        p.b = p.kand[0];
      }
    }
  }
  final total = qr != null ? qr.total : (classes.isNotEmpty && classes.every((k) => k.ok) ? classes.fold<int>(0, (a, k) => a + k.gross) : null);
  final sum = items.fold<int>(0, (a, p) => a + (p.b ?? 0));
  final unreadable = items.where((p) => p.b == null).length;
  final out = [
    for (final p in items)
      Item(name: p.name, amount: p.b ?? 0, qty: p.qty, line: p.line, conf: p.conf, frame: p.frame)
        ..unit = p.unit
        ..vat = p.vat
        ..repair = p.rep
        ..nameUncertain = p.nameUncertain
        ..sure = p.sure
        ..missing = p.missing
  ];
  return ReadResult(
    lines: [
      for (var i = 0; i < lines.length; i++)
        LineOut(
          text: lines[i].text,
          box: lines[i].box,
          conf: lines[i].conf,
          type: out.any((p) => p.line == i) ? 'posten' : 'sonst',
          item: out.indexWhere((p) => p.line == i),
        )
    ],
    items: out,
    total: total,
    totalLine: -1,
    sum: sum,
    dec: ',',
    advance: 0,
    check: Check(
      ok: total != null && sum == total && !out.any((p) => p.missing || p.repair != null) && classes.every((k) => k.ok),
      source: source,
      classes: classes,
      unreadable: unreadable,
      repaired: out.where((p) => p.repair != null).length,
    ),
  );
}

// ---------------------------------------------------------------------------------------------------------------------
// Invoice QR code (AT specification v1.1): "A:…*B:…*…*O:total" [qrLesen]

final _qrStart = RegExp(r'^A:\d{9}\*');
final _qrAmount = RegExp(r'^\d+\.\d{2}$');

QrInfo? parseInvoiceQr(String? text) {
  if (text == null || !_qrStart.hasMatch(text)) return null;
  final f = <String, String>{};
  for (final part in text.split('*')) {
    final i = part.indexOf(':');
    if (i > 0) f[part.substring(0, i)] = part.substring(i + 1);
  }
  if (!_qrAmount.hasMatch(f['O'] ?? '')) return null;
  int? c(String k) => _qrAmount.hasMatch(f[k] ?? '') ? jsRound(double.parse(f[k]!) * 100) : null;
  // classes (Portaria 195/2020): I2 exempt; I3/I4 base/VAT reduced (6 %); I5/I6 intermediate (13 %); I7/I8 normal (23 %)
  final kl = <TaxClass>[];
  void klass(int rate, int? b, int? v) {
    if (b != null || v != null) kl.add(TaxClass(rate: rate, gross: (b ?? 0) + (v ?? 0), base: b, vat: v));
  }

  if (f['I1'] == 'PT' || f['I1'] == null) {
    klass(0, c('I2'), 0);
    klass(6, c('I3'), c('I4'));
    klass(13, c('I5'), c('I6'));
    klass(23, c('I7'), c('I8'));
  }
  return QrInfo(total: jsRound(double.parse(f['O']!) * 100), nif: f['A'], date: f['F'], doc: f['G'], tax: c('N'), classes: kl);
}

// ---------------------------------------------------------------------------------------------------------------------
// Scoring of a pass [guete, widersprueche, anzeigeBonus]

final _pfandWord = RegExp(r'pfand|deposit|statiegeld|vasilhame', caseSensitive: false);
final _leergutWord = RegExp(r'leergut|r[uü]ckgabe', caseSensitive: false);
final _qtyAtStart = RegExp(r'^\s*(\d{1,3})\s*(?:stk|st|pcs?|pz|un|x|×)\.?\s*(?:x|×|à|a|@)?\s*(\d+[.,]\s?\d{2})(?!\d)', caseSensitive: false);

/// Contradictions inside lines: "PFAND 0,25 EUR 0,39", "2 x 1,29" next to an item that is not 2,58 [widersprueche].
int contradictions(ReadResult r) {
  final zl = r.lines;
  var n = zl.where((z) => _pfandWord.hasMatch(z.text) && !_leergutWord.hasMatch(z.text)).where((z) {
    final bt = amountsIn(z.text, r.dec);
    return bt.length >= 2 && bt.first.v.abs() != bt.last.v.abs();
  }).length;
  for (var i = 0; i < zl.length; i++) {
    final m = _qtyAtStart.firstMatch(zl[i].text);
    if (m == null) continue;
    final want = jsRound(jsInt(m[1]!) * cent(m[2]!.replaceAll(RegExp(r'\s'), '')));
    final near = r.items.where((p) => p.line >= i - 2 && p.line <= i + 1 && p.line != i).toList();
    if (near.isNotEmpty && !near.any((p) => (p.amount.abs() - want).abs() <= 1)) n++;
  }
  final nameless = r.items.any((p) => p.nameUncertain && !p.missing), orphan = zl.any((z) => z.type == 'unklar');
  if (nameless && orphan) n++;
  return n;
}

/// Quality of a pass: checked total, consistent assignment, sure items [guete].
double quality(ReadResult r, List<Word> words) {
  // A pass that found no item at all must never win over one that found items (McDonald's 02.11.: the whole-photo pass
  // read all items and the total correctly but scored −384 after penalties; an empty pass with 10 garbage words won
  // with +45). Among empty passes the order stays as before.
  if (r.items.isEmpty) return -100000.0 + math.min(words.length, 400) * 0.1 + (r.total != null ? 10 : 0);
  final sure = r.items.where((p) => p.sure).length, good = words.where((x) => x.conf > 70).length;
  // unclear lines only count from the item block on: header lines above the first item (cashier id, „REG 30 date“,
  // column header, masked NIF) cannot be forgotten items. McDonald's 02.11.: four such lines zeroed a checked pass.
  final firstItem = r.lines.indexWhere((z) => z.type == 'posten');
  var orphans = 0;
  for (var i = firstItem < 0 ? 0 : firstItem; i < r.lines.length; i++) {
    if (r.lines[i].type == 'unklar') orphans++;
  }
  final nameless = r.items.where((p) => p.nameUncertain && !p.missing).length;
  final c = contradictions(r);
  final consistent = math.max(0, 1 - 0.3 * (nameless + orphans) - 0.5 * c);
  return (r.check.ok ? 10000 * consistent : 0) +
      (r.total != null && r.sum == r.total ? 5000 * consistent : 0) +
      sure * 100 +
      r.items.length * 20 +
      math.min(good, 400) * 0.1 -
      150 * (nameless + orphans) -
      400 * c;
}

/// Tie-break: which image the user should see (straightened scan first) [anzeigeBonus].
double displayBonus(String name, bool straight) {
  if (name.startsWith('gerade2')) return 110;
  if (name.startsWith('gerade')) return 100;
  // UVDoc images no longer win ties: on tall receipts its grid stretches and squashes the sheet (Nutzer 02.11.: der Scan war
  // schief und verformt, das Original gerader). The cut-out keeps the proportions; UVDoc has to be clearly better.
  if (name.startsWith('entfaltet')) return 0;
  return straight && name != 'foto' ? 30 : 0;
}
