// SPDX-License-Identifier: MPL-2.0
// Fasan Split – „Meintest du …?“ for the search (Nutzer 09.11. 18:44). Pure and local: nothing leaves the phone, the words
// come from the bills the person already has. Distance: optimal string alignment (Levenshtein plus swapped neighbours, the
// typical slip on a phone keyboard).
import 'dart:math' as math;

/// Edit distance with insert, delete, replace and swap of two neighbours.
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = math.min(math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) v = math.min(v, d[i - 2][j - 2] + 1);
      d[i][j] = v;
    }
  }
  return d[a.length][b.length];
}

List<String> _words(String s) => s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.length >= 3).toList();

/// The query with every misspelt word replaced by the closest known word, or null when nothing is to correct (every word is
/// known, or a word has no neighbour within reach). [vocabulary] is any text: bill names, people, items.
String? didYouMean(String query, Iterable<String> vocabulary) {
  final known = <String, int>{};
  for (final v in vocabulary) {
    for (final w in _words(v)) {
      known[w] = (known[w] ?? 0) + 1;
    }
  }
  if (known.isEmpty) return null;
  final parts = query.trim().toLowerCase().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  var changed = false;
  final out = <String>[];
  for (final p in parts) {
    // a word that is the start of a known word is not a typo: the person is still typing
    if (p.length < 3 || known.keys.any((k) => k.startsWith(p))) {
      out.add(p);
      continue;
    }
    final reach = p.length <= 4 ? 1 : 2;
    String? best;
    var bestD = reach + 1;
    for (final e in known.entries) {
      if ((e.key.length - p.length).abs() > reach) continue;
      final dist = editDistance(p, e.key);
      if (dist < bestD || (dist == bestD && best != null && (known[e.key]! > known[best]!))) {
        bestD = dist;
        best = e.key;
      }
    }
    if (best == null) {
      out.add(p);
    } else {
      out.add(best);
      changed = true;
    }
  }
  return changed ? out.join(' ') : null;
}
