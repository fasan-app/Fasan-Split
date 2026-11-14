// SPDX-License-Identifier: MPL-2.0
// Fasan Split – which currency a receipt is in (Roadmap 2, 14.11.: „Währung aus dem Bon erkennen“). Counts unambiguous signs and ISO
// codes in the read lines; ambiguous ones (a bare „$“, „kr“) count only next to an amount and never alone decide between currencies
// that share them. The result is a suggestion: the app asks before it changes a bill (a wrong currency without a rate would count
// 1:1). Pure Dart, no I/O. MPL-2.0

/// ISO code and the patterns that point to it (word boundaries; amounts like „12,50 CHF“ or „CHF 12.50“).
const Map<String, List<String>> _signs = {
  'EUR': [r'€', r'\bEUR\b', r'\bEURO\b'],
  'CHF': [r'\bCHF\b', r'\bSFR\b', r'\bFr\.\s?\d'],
  'GBP': [r'£', r'\bGBP\b'],
  'USD': [r'\bUSD\b', r'\bUS\$', r'(?<![A-Z])\$\s?\d'], // a bare „$“ before an amount: USD is by far the most common reading
  'CZK': [r'(?<![A-Za-z])Kč(?![A-Za-z])', r'\bKc\b', r'\bCZK\b'],
  'PLN': [r'(?<![A-Za-z])zł(?![A-Za-z])', r'\bPLN\b'],
  'HUF': [r'\bHUF\b', r'\d\s?Ft\b'],
  'DKK': [r'\bDKK\b'],
  'SEK': [r'\bSEK\b'],
  'NOK': [r'\bNOK\b'],
  'TRY': [r'₺', r'\bTRY\b', r'\bTL\b'],
};

final Map<String, List<RegExp>> _compiled = {
  for (final e in _signs.entries) e.key: [for (final p in e.value) RegExp(p, caseSensitive: e.key == 'HUF' || e.key == 'TRY' ? true : false)],
};

/// The currency of the receipt [lines], or null when nothing points to one clearly. A currency needs at least two hits and must
/// have more hits than every other one (a single „EUR“ in a footer of a Swiss receipt must not win).
String? guessCurrency(List<String> lines) {
  final hits = <String, int>{};
  for (final l in lines) {
    for (final e in _compiled.entries) {
      for (final r in e.value) {
        final n = r.allMatches(l).length;
        if (n > 0) hits[e.key] = (hits[e.key] ?? 0) + n;
      }
    }
  }
  if (hits.isEmpty) return null;
  final best = hits.entries.reduce((a, b) => a.value >= b.value ? a : b);
  if (best.value < 2) return null;
  if (hits.entries.any((e) => e.key != best.key && e.value >= best.value)) return null;
  return best.key;
}
