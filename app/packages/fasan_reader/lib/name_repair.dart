// Fasan Split – item names after reading (Nutzer 04.11., Ferreiras LX: „Caneca 23 e“, „z Coca cola“, a garbled
// „nrezaenrzzeu“ where four other passes read „Coca cola zero“). Pure Dart, runs on the winner of the passes:
// 1. VAT column and currency sign in the name: when most names end with „<code> e“ (the € printed as e, the code being
//    the VAT %), both are cut from every name.
// 2. Quantity letters: on a receipt whose names start after a read quantity, a leading „z“/„Z“ is a 2, „l“/„I“/„|“ a 1.
// 3. Majority of the passes: for each item, the names other passes read for the same position and amount vote; a name
//    most of them do not share gives way to the one most of them read. Amounts are never touched. MPL-2.0
import 'model.dart';

final _taxE = RegExp(r'\s+\S{1,3}\s+[eE€]$');
final _code = RegExp(r'\s+(\d{1,2}|\S)$');

/// Names with the VAT code and „e“ (for €) at the end lose them, when most names of the receipt look like that.
void cleanColumns(List<Item> items) {
  if (items.length < 3) return;
  final withE = items.where((p) => _taxE.hasMatch(p.name.trim())).length;
  if (withE * 10 < items.length * 6) return; // fewer than 60 %: a real name, leave it
  for (final p in items) {
    var n = p.name.trim();
    if (n.endsWith(' e') || n.endsWith(' E') || n.endsWith(' €')) n = n.substring(0, n.length - 2).trimRight();
    final m = _code.firstMatch(n);
    if (m != null && n.length - m.group(0)!.length >= 3) n = n.substring(0, m.start).trimRight();
    p.name = n;
  }
}

/// „z Coca cola“ with quantity 1 → „Coca cola“ with quantity 2, when the receipt prints quantities in front.
void fixQuantityLetters(List<Item> items) {
  if (items.length < 3) return;
  final readQty = items.where((p) => p.qtyRead > 0).length;
  if (readQty * 2 < items.length) return;
  for (final p in items) {
    final m = RegExp(r'^([zZlI|])\s+(\S.*)$').firstMatch(p.name.trim());
    if (m == null || p.qtyRead > 0) continue;
    final q = m.group(1) == 'z' || m.group(1) == 'Z' ? 2 : 1;
    p.name = m.group(2)!;
    if (q != p.qty) {
      p.qty = q;
      p.unit = p.amount / q;
    }
  }
}

/// Digits the reading put into the middle or end of a word: „G1n Tonico Mart1“ is „Gin Tonico Marti“, „Soc1al“ is „Social“ (1 → i,
/// 0 → o, 5 → s). Only in a word of at least three characters that has two letters or more and exactly one digit; real names with
/// digits („7UP“, „H2O“, „B12“, „Coca 33“) have a digit that is not 0, 1 or 5, or stand alone, or have more than one.
final _digitWord = RegExp(r'\b(?=[A-Za-zÀ-ÿ0-9]{3,}\b)(?=(?:[A-Za-zÀ-ÿ]*\d){1}[A-Za-zÀ-ÿ]*\b)[A-Za-zÀ-ÿ]*[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ]*[015][A-Za-zÀ-ÿ]*[A-Za-zÀ-ÿ]*\b|\b[A-Za-zÀ-ÿ]{2,}[015]\b|\b[A-Za-zÀ-ÿ]+[015][A-Za-zÀ-ÿ]+\b');
String fixDigitsInWord(String name) => name.replaceAllMapped(_digitWord, (m) {
      final w = m[0]!;
      final digits = RegExp(r'\d').allMatches(w).length;
      final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(w).length;
      if (digits != 1 || letters < 2 || w.length < 3) return w;
      final lower = w == w.toLowerCase();
      return w.replaceAllMapped(RegExp(r'[015]'), (d) => switch (d[0]) { '1' => lower ? 'i' : 'i', '0' => 'o', _ => 's' });
    });

/// [fixDigitsInWord] on every name of a reading.
void fixDigitLetters(List<Item> items) {
  for (final p in items) {
    final n = fixDigitsInWord(p.name);
    if (n != p.name) p.name = n;
  }
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüßàáâãçéêíóôõú]'), '');

/// Core of a name for voting: without short leftovers at the start or end (≤ 3 characters: „Jn“, „í“, „nm“, „P13“) and without
/// digit-only tokens next to them („238“ = „23%“ of the VAT column). „TULIPA“ and „TULIPA 238“ are the same vote (Da Sé 06.11.).
String nameCore(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  bool debris(String t) => _norm(t).length <= 3 || RegExp(r'^\d+[%x8]?$').hasMatch(t);
  while (w.length > 1 && debris(w.first)) {
    w.removeAt(0);
  }
  while (w.length > 1 && debris(w.last)) {
    w.removeLast();
  }
  return _norm(w.join(' '));
}

/// How much a name looks like words: share of tokens that have a vowel, no digits glued inside letters, and at most one switch
/// from lower to upper case („SpaghettiioTnsldanAstnen“, „nedtelwol“ from text shining through the paper score low).
double wordLikeness(String name) {
  final w = name.split(RegExp(r'\s+')).where((x) => RegExp(r'[A-Za-zÀ-ÿ]{2,}').hasMatch(x)).toList();
  if (w.isEmpty) return 0;
  var good = 0;
  for (final t in w) {
    final switches = RegExp(r'[a-zà-ÿ][A-ZÀ-Þ]').allMatches(t).length;
    final vowels = RegExp(r'[aeiouyäöüàáâãéêíóôõú]', caseSensitive: false).allMatches(t).length;
    final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(t).length;
    final ratio = letters == 0 ? 0 : vowels / letters;
    if (switches <= 1 && ratio >= 0.2 && ratio <= 0.75 && letters <= 18) good++;
  }
  return good / w.length;
}

/// The names other passes read for the same item (same position, same amount) vote; a winner name that fewer passes
/// share than another one is replaced. [others] are the item lists of the other passes (already cleaned).
/// Votes are grouped by [nameCore], so leftovers of neighbouring columns never outvote the clean name; the group's cleanest member
/// (fewest extra tokens) is taken. A winner that does not look like words gives way to any readable name. The quantity votes too:
/// when the winner read none (1) and two other passes agree on more, it is taken (Ferreiras 06.11.: „z 23 e 6.00“ = 2 Coca cola).
/// Names and amounts paired differently than in the winner: a name we also read comes with another amount more often than with ours
/// (an extra or missing item above only moves the index, not the pairing, and does not count).
bool _shifted(List<Item> items, List<Item> o) {
  final mine = <String, Set<int>>{};
  for (final p in items) {
    final n = nameCore(p.name);
    if (n.length >= 2) (mine[n] ??= {}).add(p.amount);
  }
  var same = 0, off = 0;
  for (final q in o) {
    final a = mine[nameCore(q.name)];
    if (a == null) continue;
    a.contains(q.amount) ? same++ : off++;
  }
  return off >= 2 && off > same;
}

void voteNames(List<Item> items, List<List<Item>> others) {
  // A pass whose names sit one row off against the winner (amount column shifted by a line: „Pork Sausages“ next to 4.99) pairs every
  // amount with its neighbour's name; several such passes outvoted the right reading (Weltkorpus b2-084, 07.11.). It may not vote:
  // more of its names match our item one row up or down than the same row.
  others = [for (final o in others) if (!_shifted(items, o)) o];
  for (var i = 0; i < items.length; i++) {
    final p = items[i];
    final groups = <String, List<String>>{};
    final qtys = <num, int>{};
    void add(String n) {
      final k = nameCore(n);
      if (k.length < 2) return;
      (groups[k] ??= []).add(n.trim());
    }

    add(p.name);
    for (final o in others) {
      // same amount near the same place (a pass can have one item more or less above)
      for (final j in [i, i - 1, i + 1]) {
        if (j >= 0 && j < o.length && o[j].amount == p.amount) {
          add(o[j].name);
          qtys[o[j].qty] = (qtys[o[j].qty] ?? 0) + 1;
          break;
        }
      }
    }
    if (p.qty == 1) {
      final more = qtys.entries.where((e) => e.key > 1 && e.value >= 2).toList()..sort((a, b) => b.value.compareTo(a.value));
      if (more.isNotEmpty && p.amount % more.first.key == 0) {
        p.qty = more.first.key;
        p.unit = p.amount / more.first.key;
      }
    }
    if (groups.isEmpty) continue;
    String cleanest(List<String> g) => g.reduce((a, b) => b.split(' ').length < a.split(' ').length || (b.split(' ').length == a.split(' ').length && b.length < a.length) ? b : a);
    final mineKey = nameCore(p.name);
    final mine = groups[mineKey]?.length ?? 0;
    final best = groups.entries.reduce((a, b) => b.value.length > a.value.length ? b : a);
    final readable = wordLikeness(p.name) > 0.5;
    // a winner that does not look like words: the most voted other group that does
    final legible = groups.entries.where((e) => e.key != mineKey && wordLikeness(cleanest(e.value)) >= 0.75).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    if (best.key != mineKey && best.value.length >= 2 && best.value.length > mine) {
      p.name = cleanest(best.value);
    } else if (!readable && legible.isNotEmpty) {
      p.name = cleanest(legible.first.value);
    } else if (groups[mineKey] != null && groups[mineKey]!.length > 1) {
      // same name, other passes read it with fewer leftovers: take the cleanest spelling of the own group
      final c = cleanest(groups[mineKey]!);
      if (c.split(' ').length < p.name.trim().split(RegExp(r'\s+')).length) p.name = c;
    }
  }
}
