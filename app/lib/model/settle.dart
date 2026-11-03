// Fasan Split – balances over several bills and who pays whom to settle them. MPL-2.0
//
// Balance per person in cents: positive = gets money, negative = owes money. Built from Bill.transfers(), so refunds
// (Bill.refund) already point the right way. Only finished bills with a payer count; open bills could still change.
import 'bill.dart';

/// Net balance per person name over [bills]. Names are the key because bills are separate (indices differ per bill).
Map<String, int> balances(Iterable<Bill> bills) {
  final out = <String, int>{};
  for (final b in bills) {
    if (!b.done || b.payer == null) continue;
    for (final (from, to, c) in b.transfers()) {
      if (from >= b.ps.length || to >= b.ps.length) continue;
      out.update(b.ps[from].name, (x) => x - c, ifAbsent: () => -c);
      out.update(b.ps[to].name, (x) => x + c, ifAbsent: () => c);
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
