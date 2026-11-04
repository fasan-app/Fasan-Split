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

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüßàáâãçéêíóôõú]'), '');

/// The names other passes read for the same item (same position, same amount) vote; a winner name that fewer passes
/// share than another one is replaced. [others] are the item lists of the other passes (already cleaned).
void voteNames(List<Item> items, List<List<Item>> others) {
  for (var i = 0; i < items.length; i++) {
    final p = items[i];
    final votes = <String, (int, String)>{};
    void add(String n) {
      final k = _norm(n);
      if (k.length < 2) return;
      final old = votes[k];
      votes[k] = (old == null ? 1 : old.$1 + 1, old?.$2 ?? n.trim());
    }

    add(p.name);
    for (final o in others) {
      // same amount near the same place (a pass can have one item more or less above)
      for (final j in [i, i - 1, i + 1]) {
        if (j >= 0 && j < o.length && o[j].amount == p.amount) {
          add(o[j].name);
          break;
        }
      }
    }
    if (votes.length < 2) continue;
    final mine = votes[_norm(p.name)]?.$1 ?? 0;
    final best = votes.values.reduce((a, b) => b.$1 > a.$1 ? b : a);
    if (best.$1 >= 2 && best.$1 > mine) p.name = best.$2;
  }
}
