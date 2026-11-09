// Fasan Split – helpers that reproduce JavaScript semantics used by the web reader (bon.js). MPL-2.0
//
// The receipt reader was ported from Fasan-Karte/site/bon.js (3.19). Where JS and Dart differ, these helpers keep the
// JS behaviour so that the Dart port gives the same results as the web app on the shared regression tests:
// - Math.round rounds .5 towards +∞ (Dart's round() rounds away from zero) → [jsRound]
// - parseFloat reads a numeric prefix and returns NaN otherwise → [jsParseFloat]
// - Array.prototype.sort is stable (ES2019); Dart's List.sort is not guaranteed to be → [stableSort]
// - String.prototype.slice clamps and accepts negative indices → [jsSlice]
// - normalize('NFD') + removing U+0300–U+036F → [stripAccents] (table generated from Unicode data)
// Regular expressions: the Dart VM uses V8's irregexp, so JS patterns behave the same (\b and \w are ASCII in both).
import 'accents.g.dart';

/// JS Math.round. Non-finite values give 0 (JS would give NaN; callers check finiteness where it matters).
int jsRound(num x) => x.isFinite ? (x + 0.5).floor() : 0;

final _floatPrefix = RegExp(r'^\s*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)');

/// JS parseFloat: numeric prefix or NaN.
double jsParseFloat(String s) {
  final m = _floatPrefix.firstMatch(s);
  if (m == null) return double.nan;
  return double.parse(m.group(1)!);
}

/// JS `+s` for simple integer strings (used on regex groups of digits).
int jsInt(String s) => int.tryParse(s.trim()) ?? 0;

String jsSlice(String s, int start, [int? end]) {
  final n = s.length;
  int norm(int i) => i < 0 ? (n + i).clamp(0, n) : i.clamp(0, n);
  final a = norm(start), b = end == null ? n : norm(end);
  return b <= a ? '' : s.substring(a, b);
}

/// NFD + strip combining marks (JS: t.normalize('NFD').replace(/[̀-ͯ]/g, '')).
String stripAccents(String t) {
  final b = StringBuffer();
  for (final r in t.runes) {
    if (r >= 0x300 && r <= 0x36F) continue; // already decomposed input
    final f = accentFold[r];
    if (f != null) {
      b.write(f);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// bon.js ohneAkz: without accents, lower case.
String foldLower(String t) => stripAccents(t).toLowerCase();

/// Stable sort in place (merge sort), like JS Array.prototype.sort with a comparator.
void stableSort<T>(List<T> list, int Function(T a, T b) cmp) {
  if (list.length < 2) return;
  final tmp = List<T>.of(list);
  _mergeSort(list, tmp, 0, list.length, cmp);
}

void _mergeSort<T>(List<T> a, List<T> tmp, int lo, int hi, int Function(T, T) cmp) {
  if (hi - lo < 2) return;
  if (hi - lo <= 12) {
    for (var i = lo + 1; i < hi; i++) {
      final x = a[i];
      var j = i - 1;
      while (j >= lo && cmp(a[j], x) > 0) {
        a[j + 1] = a[j];
        j--;
      }
      a[j + 1] = x;
    }
    return;
  }
  final mid = (lo + hi) >> 1;
  _mergeSort(a, tmp, lo, mid, cmp);
  _mergeSort(a, tmp, mid, hi, cmp);
  if (cmp(a[mid - 1], a[mid]) <= 0) return;
  for (var i = lo; i < hi; i++) {
    tmp[i] = a[i];
  }
  var i = lo, j = mid, k = lo;
  while (i < mid && j < hi) {
    a[k++] = cmp(tmp[j], tmp[i]) < 0 ? tmp[j++] : tmp[i++];
  }
  while (i < mid) {
    a[k++] = tmp[i++];
  }
  while (j < hi) {
    a[k++] = tmp[j++];
  }
}

List<T> stableSorted<T>(Iterable<T> it, int Function(T a, T b) cmp) {
  final l = List<T>.of(it);
  stableSort(l, cmp);
  return l;
}

/// Comparator for numbers ascending (JS `(a, b) => a - b`).
int numAsc(num a, num b) => a < b ? -1 : (a > b ? 1 : 0);

/// JS `arr.sort((a,b)=>a-b)[arr.length >> 1]` – upper median of a copy; 0 for empty when [orZero].
double medianOf(Iterable<num> v, {double empty = 0}) {
  final l = stableSorted<num>(v, numAsc);
  return l.isEmpty ? empty : l[l.length >> 1].toDouble();
}

/// JS Math.min(...a) / Math.max(...a) (±Infinity for empty lists).
double minOf(Iterable<num> v) => v.fold<double>(double.infinity, (a, x) => x < a ? x.toDouble() : a);
double maxOf(Iterable<num> v) => v.fold<double>(double.negativeInfinity, (a, x) => x > a ? x.toDouble() : a);

/// JS `+x.toFixed(n)`.
double toFixed(double x, int n) {
  final s = x.toStringAsFixed(n);
  return double.parse(s);
}

/// Count of regex matches (JS `(s.match(/…/g) || []).length`).
int countMatches(RegExp re, String s) => re.allMatches(s).length;

/// JS `/re/.test(s)` for non-global regexes.
extension RegExpTest on RegExp {
  bool test(String s) => hasMatch(s);
}
