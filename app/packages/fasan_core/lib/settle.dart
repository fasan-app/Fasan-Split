// Fasan Split – balances over several bills and who pays whom to settle them. MPL-2.0
//
// Balance per person in cents: positive = gets money, negative = owes money. Built from Bill.transfers(), so refunds
// (Bill.refund) already point the right way. Only finished bills with a payer count; open bills could still change.
// Settled bills (Bill.settled, paid back) do not count any more.
import 'bill.dart';

/// Net balance per person over [bills]. The key is the name (bills are separate, indices differ per bill), or what
/// [key] makes of it: in a live group every name linked to one member becomes that member (GroupPeople).
Map<String, int> balances(Iterable<Bill> bills, {String Function(String name)? key}) {
  final k = key ?? (String n) => n;
  final out = <String, int>{};
  for (final b in bills) {
    if (!b.done || b.settled || b.payer == null) continue;
    for (final (from, to, c) in b.transfers()) {
      if (from >= b.ps.length || to >= b.ps.length) continue;
      final h = b.toHome(c); // other currency → home currency with the bill's rate
      out.update(k(b.ps[from].name), (x) => x - h, ifAbsent: () => -h);
      out.update(k(b.ps[to].name), (x) => x + h, ifAbsent: () => h);
    }
  }
  return out;
}

/// The fewest transfers that settle [bal] (Kosten 2, Beschluss 06.11.: exakt, nicht gierig). The minimum is n − k, where k is the largest
/// number of groups of people whose balances add up to zero (each group settles inside with size − 1 transfers). Found exactly by dynamic
/// programming over the subsets (2^n · n steps) for up to [exactLimit] people with a non-zero balance; above that the greedy way.
/// Deterministic: people sorted by name, ties to the lowest index – the same result on every phone.
const exactLimit = 16;

List<(String from, String to, int cents)> settle(Map<String, int> bal) {
  final people = [for (final e in bal.entries) if (e.value != 0) e.key]..sort();
  final m = people.length;
  if (m <= 2 || m > exactLimit) return _greedy(bal);
  final v = [for (final p in people) bal[p]!];
  final full = (1 << m) - 1;
  final sum = List<int>.filled(full + 1, 0), best = List<int>.filled(full + 1, 0);
  for (var mask = 1; mask <= full; mask++) {
    final low = mask & -mask;
    sum[mask] = sum[mask ^ low] + v[low.bitLength - 1];
    var b = 0;
    for (var i = 0; i < m; i++) {
      if (mask & (1 << i) != 0 && best[mask ^ (1 << i)] > b) b = best[mask ^ (1 << i)];
    }
    best[mask] = b + (sum[mask] == 0 ? 1 : 0);
  }
  // walk back: the removed people, read backwards, form the zero groups one after the other
  final order = <int>[];
  var mask = full;
  while (mask != 0) {
    final want = best[mask] - (sum[mask] == 0 ? 1 : 0);
    var pick = -1;
    for (var i = 0; i < m && pick < 0; i++) {
      if (mask & (1 << i) != 0 && best[mask ^ (1 << i)] == want) pick = i;
    }
    order.add(pick);
    mask ^= 1 << pick;
  }
  final out = <(String, String, int)>[];
  var group = <String, int>{}, acc = 0;
  for (final i in order.reversed) {
    group[people[i]] = v[i];
    acc += v[i];
    if (acc == 0) {
      out.addAll(_greedy(group));
      group = {};
    }
  }
  return out;
}

/// The biggest debtor pays the biggest creditor, repeated. At most n-1 transfers; ties broken by name.
List<(String from, String to, int cents)> _greedy(Map<String, int> bal) {
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
    if (!b.done || b.settled || b.payer == null) continue;
    for (final (from, to, c) in b.transfers()) {
      if (from >= b.ps.length || to >= b.ps.length) continue;
      final f = b.ps[from].name, t = b.ps[to].name;
      final h = b.toHome(c);
      if (isMe(f) && !isMe(t)) out.update(t, (x) => x - h, ifAbsent: () => -h);
      if (isMe(t) && !isMe(f)) out.update(f, (x) => x + h, ifAbsent: () => h);
    }
  }
  out.removeWhere((_, v) => v == 0);
  return out;
}

