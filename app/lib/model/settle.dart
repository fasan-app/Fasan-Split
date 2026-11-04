// Fasan Split – balances over several bills and who pays whom to settle them. MPL-2.0
//
// Balance per person in cents: positive = gets money, negative = owes money. Built from Bill.transfers(), so refunds
// (Bill.refund) already point the right way. Only finished bills with a payer count; open bills could still change.
import 'bill.dart';

/// Net balance per person over [bills]. The key is the name (bills are separate, indices differ per bill), or what
/// [key] makes of it: in a live group every name linked to one member becomes that member (GroupPeople).
Map<String, int> balances(Iterable<Bill> bills, {String Function(String name)? key}) {
  final k = key ?? (String n) => n;
  final out = <String, int>{};
  for (final b in bills) {
    if (!b.done || b.payer == null) continue;
    for (final (from, to, c) in b.transfers()) {
      if (from >= b.ps.length || to >= b.ps.length) continue;
      out.update(k(b.ps[from].name), (x) => x - c, ifAbsent: () => -c);
      out.update(k(b.ps[to].name), (x) => x + c, ifAbsent: () => c);
    }
  }
  return out;
}

/// Few transfers that settle [bal]: the biggest debtor pays the biggest creditor, repeated. At most n-1 transfers.
/// Ties are broken by name so the result is the same on every phone.
List<(String from, String to, int cents)> settle(Map<String, int> bal) {
  int byAmount(MapEntry<String, int> a, MapEntry<String, int> b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key);
  final cred = [for (final e in bal.entries) if (e.value > 0) MapEntry(e.key, e.value)]..sort(byAmount);
  final debt = [for (final e in bal.entries) if (e.value < 0) MapEntry(e.key, -e.value)]..sort(byAmount);
  final out = <(String, String, int)>[];
  var i = 0, j = 0;
  var c = cred.isEmpty ? 0 : cred[0].value, d = debt.isEmpty ? 0 : debt[0].value;
  while (i < cred.length && j < debt.length) {
    final x = c < d ? c : d;
    if (x > 0) out.add((debt[j].key, cred[i].key, x));
    c -= x;
    d -= x;
    if (c == 0 && ++i < cred.length) c = cred[i].value;
    if (d == 0 && ++j < debt.length) d = debt[j].value;
  }
  return out;
}

/// What [me] gets (+) or owes (−) to each other person over [bills], from the transfers of each bill. [isMe] decides
/// which names are me (own name, names linked to my member key in live groups).
Map<String, int> myDebts(Iterable<Bill> bills, bool Function(String name) isMe) {
  final out = <String, int>{};
  for (final b in bills) {
    if (!b.done || b.payer == null) continue;
    for (final (from, to, c) in b.transfers()) {
      if (from >= b.ps.length || to >= b.ps.length) continue;
      final f = b.ps[from].name, t = b.ps[to].name;
      if (isMe(f) && !isMe(t)) out.update(t, (x) => x - c, ifAbsent: () => -c);
      if (isMe(t) && !isMe(f)) out.update(f, (x) => x + c, ifAbsent: () => c);
    }
  }
  out.removeWhere((_, v) => v == 0);
  return out;
}

/// Who should pay the next bill in a group: the one with the lowest balance (owes most); null when all are even.
String? nextPayer(Map<String, int> balance) {
  if (balance.isEmpty) return null;
  final e = balance.entries.reduce((a, b) => b.value < a.value || b.value == a.value && b.key.compareTo(a.key) < 0 ? b : a);
  return e.value < 0 ? e.key : null;
}
