// Fasan Split – what was this item? Port of Fasan-Karte/site/speisen.js (MPL-2.0).
// Own dictionary (DE, EN, PT, ES, FR, IT, NL), no network, no AI. Fuzzy match against reading errors: words from 5 letters
// may differ by 1 character, from 8 letters by 2. Multi-word terms first. Unknown stays unknown.
import 'speisen_list.g.dart';
import 'text_util.dart';

class FoodMatch {
  const FoodMatch(this.symbol, this.name, this.term);

  final String symbol; // [s]
  final String name; // [n]
  final String term; // [grund]
}

class _Entry {
  _Entry(this.s, this.n, this.w, this.order) : parts = w.split(' ');

  final String s, n, w;
  final List<String> parts;
  final int order;
}

class Speisen {
  Speisen._();

  static const _extras = [
    ['koffeinfrei', 'descafeinado,descaf,decaf,deca,decaffeinato,koffeinfrei,sans cafeine,descafeinado,entkoffeiniert,cafeinevrij'],
    ['doppelt', 'duplo,doble,double,doppio,doppelt,dubbel,grande'],
    ['groß', 'grande,large,gross,big,xl,caneca,maxi'],
    ['klein', 'pequeno,small,klein,petit,piccolo,mini,curto'],
    ['vegetarisch', 'vegetariano,vegetarian,vegetarisch,veggie,vegetarien'],
    ['vegan', 'vegan,vegano,vegane,vegetal'],
    ['ohne Zucker', 'zero,sem acucar,sugar free,sin azucar,light,diet,ohne zucker'],
    ['mit Eis', 'com gelo,with ice,con hielo,mit eis,on the rocks'],
  ];

  static final _nonWord = RegExp(r'[^a-z0-9ß ]+');
  static final _unit = RegExp(r'\b\d+([.,]\d+)?\s*(cl|ml|l|lt|g|kg|gr|oz|un|uni|x)\b');
  static final _num = RegExp(r'\b\d+\b');
  static final _ws = RegExp(r'\s+');

  static String norm(String? t) => foldLower(t ?? '')
      .replaceAll(_nonWord, ' ')
      .replaceAll(_unit, ' ')
      .replaceAll(_num, ' ')
      .replaceAll(_ws, ' ')
      .trim();

  static final List<_Entry> _entries = () {
    final out = <_Entry>[];
    for (final z in speisenList.trim().split('\n')) {
      final f = z.split('|');
      if (f.length < 3 || f[2].isEmpty) continue;
      for (final b in f[2].split(',')) {
        final w = norm(b);
        if (w.isNotEmpty) out.add(_Entry(f[0], f[1], w, out.length));
      }
    }
    // more words first, then list order (drinks and dishes before ingredients)
    stableSort<_Entry>(out, (a, b) => b.parts.length != a.parts.length ? b.parts.length - a.parts.length : a.order - b.order);
    return out;
  }();

  static final List<(String, List<String>)> _extraTerms = [
    for (final e in _extras) (e[0], e[1].split(',').map(norm).where((x) => x.isNotEmpty).toList()),
  ];

  static int _distance(String a, String b, int max) {
    if ((a.length - b.length).abs() > max) return max + 1;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      var min = i;
      for (var j = 1; j <= b.length; j++) {
        final v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
        cur[j] = v;
        if (v < min) min = v;
      }
      if (min > max) return max + 1;
      prev = cur;
    }
    return prev[b.length];
  }

  static int _allowed(String w) => w.length >= 8 ? 2 : (w.length >= 5 ? 1 : 0);

  static bool _same(String a, String b) {
    if (a == b) return true;
    if ((a.length < b.length ? a.length : b.length) < 5) return false;
    final m = _allowed(a) < _allowed(b) ? _allowed(a) : _allowed(b);
    return _distance(a, b, m) <= m;
  }

  static int _find(List<String> words, List<String> parts, bool exact) {
    for (var i = 0; i + parts.length <= words.length; i++) {
      var ok = true;
      for (var k = 0; k < parts.length && ok; k++) {
        ok = exact ? words[i + k] == parts[k] : _same(words[i + k], parts[k]);
      }
      if (ok) return i;
    }
    return -1;
  }

  static final _umlautHint = RegExp(r'ae|oe|ue', caseSensitive: false);

  /// Match or null. [kind]: receipt kind id from the reader ('supermarkt': "Kaffee 500 g" is a pack).
  static FoodMatch? recognise(String? text, [String? kind]) {
    final r = _recognise1(text ?? '', kind);
    if (r != null || !_umlautHint.hasMatch(text ?? '')) return r;
    // tills without umlauts write KAESE, GRUENE: second try with ä/ö/ü (only if the first found nothing)
    final t = text!
        .replaceAll(RegExp('ae', caseSensitive: false), 'ä')
        .replaceAll(RegExp('oe', caseSensitive: false), 'ö')
        .replaceAll(RegExp('ue', caseSensitive: false), 'ü');
    return _recognise1(t, kind);
  }

  static final _pack = RegExp(r'\d\s*(g|kg|ml|cl|l|lt)\b', caseSensitive: false);

  static FoodMatch? _recognise1(String text, String? kind) {
    final words = norm(text).split(' ').where((x) => x.isNotEmpty).toList();
    if (words.isEmpty) return null;
    _Entry? hit;
    for (final exact in [true, false]) {
      for (final e in _entries) {
        if (_find(words, e.parts, exact) >= 0) {
          hit = e;
          break;
        }
      }
      if (hit != null) break;
    }
    final extras = <String>[];
    for (final (n, ws) in _extraTerms) {
      // speisen.js calls finde() without `genau` here → fuzzy
      if (ws.any((w) => _find(words, w.split(' '), false) >= 0) && !(hit != null && hit.n.toLowerCase().contains(n.toLowerCase()))) {
        extras.add(n);
      }
    }
    if (hit == null) return null;
    final uniq = <String>[];
    for (final z in extras) {
      if (!uniq.contains(z)) uniq.add(z);
    }
    final n = hit.n + (extras.isNotEmpty ? ', ${uniq.take(2).join(', ')}' : '');
    final pack = kind == 'supermarkt' && _pack.hasMatch(text) && !n.contains('Pfand') ? ', Packung' : '';
    return FoodMatch(hit.s, n + pack, hit.w);
  }
}
