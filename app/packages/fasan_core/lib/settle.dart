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

/// What makes a person's balance uncertain (Nutzer 12.11.: „ungewiss, weil z. B. der Zahler fehlt“). [openBills]: bills with the
/// person that are not finished yet (they are not in the balance); [noPayer]: finished bills with the person but without a payer
/// (they cannot be counted). Both are only counted for bills that are not settled and no settlement payment.
class BalanceGap {
  const BalanceGap({this.openBills = 0, this.noPayer = 0});
  final int openBills, noPayer;
  bool get uncertain => openBills + noPayer > 0;
}

/// The gaps per person (same [key] as [balances]); people without a gap are not in the map.
Map<String, BalanceGap> balanceGaps(Iterable<Bill> bills, {String Function(String name)? key}) {
  final k = key ?? (String n) => n;
  final open = <String, int>{}, nopay = <String, int>{};
  for (final b in bills) {
    if (b.settled || b.isTransfer) continue;
    final gapMap = !b.done ? open : (b.payer == null ? nopay : null);
    if (gapMap == null) continue;
    for (final n in {for (final p in b.ps) k(p.name)}) {
      gapMap.update(n, (x) => x + 1, ifAbsent: () => 1);
    }
  }
  return {for (final n in {...open.keys, ...nopay.keys}) n: BalanceGap(openBills: open[n] ?? 0, noPayer: nopay[n] ?? 0)};
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
///
/// [isMePerson] (Nutzer 11.11.: „Bons dürfen nicht nur mit Namen verknüpft sein“) decides by the person's stable uid first;
/// when it is null the name predicate [isMe] is used alone.
Map<String, int> myDebts(Iterable<Bill> bills, bool Function(String name) isMe, {bool Function(Person)? isMePerson}) {
  bool me(int i, Bill b) => isMePerson?.call(b.ps[i]) ?? isMe(b.ps[i].name);
  final out = <String, int>{};
  for (final b in bills) {
    if (!b.done || b.settled || b.payer == null) continue;
    for (final (from, to, c) in b.transfers()) {
      if (from >= b.ps.length || to >= b.ps.length) continue;
      final f = b.ps[from].name, t = b.ps[to].name;
      final h = b.toHome(c);
      final mf = me(from, b), mt = me(to, b);
      if (mf && !mt) out.update(t, (x) => x - h, ifAbsent: () => -h);
      if (mt && !mf) out.update(f, (x) => x + h, ifAbsent: () => h);
    }
  }
  out.removeWhere((_, v) => v == 0);
  return out;
}


/// Provisional balance of me over bills that are not finished yet (Nutzer 06.11./07.11.: „sobald Posten vergeben sind“).
/// Only what is assigned counts (no tip/difference spread, open items are not guessed). Key = the other person's name,
/// or '' when nobody is known to have paid yet (then it is only what I owe, recipient open). The sum is added to the
/// confirmed balance for display, but never to settlement suggestions ([balances], [settle]) – those stay confirmed only.
Map<String, int> myProvisional(Iterable<Bill> bills, bool Function(String name) isMe, {bool Function(Person)? isMePerson}) {
  bool me(int i, Bill b) => isMePerson?.call(b.ps[i]) ?? isMe(b.ps[i].name);
  final out = <String, int>{};
  void add(String k, int v) => out.update(k, (x) => x + v, ifAbsent: () => v);
  for (final b in bills) {
    if (b.done || b.settled || b.trashedAt != null || b.multiPay || b.ps.length < 2) continue;
    final parts = b.perPerson(withDifference: false);
    final mine = [for (var i = 0; i < b.ps.length; i++) if (me(i, b)) i];
    if (mine.isEmpty) continue;
    final sign = b.refund ? -1 : 1;
    final p = b.payer;
    if (p != null && p < b.ps.length) {
      if (mine.contains(p)) {
        // I paid: everybody else owes me what is assigned to them so far
        for (final e in parts.entries) {
          if (e.key == p || e.key >= b.ps.length || me(e.key, b) || e.value == 0) continue;
          add(b.ps[e.key].name, sign * b.toHome(e.value));
        }
      } else {
        final c = mine.fold<int>(0, (a, i) => a + (parts[i] ?? 0));
        if (c != 0) add(b.ps[p].name, -sign * b.toHome(c));
      }
    } else {
      final c = mine.fold<int>(0, (a, i) => a + (parts[i] ?? 0));
      if (c != 0) add('', -sign * b.toHome(c));
    }
  }
  out.removeWhere((_, v) => v == 0);
  return out;
}

/// What one finished bill moves between people: the lines behind the balance (Nutzer 07.11.: „sehen, wie sich der Saldo ergibt“,
/// „wer wem wie viel schuldet, auch in der Gruppe für alle nachvollziehbar“). Same bills, same names and same conversion as [balances],
/// so the lines add up to exactly that balance.
class BillMoves {
  const BillMoves(this.bill, this.moves);
  final Bill bill;

  /// (from, to, cents in home currency): [from] owes [to].
  final List<(String from, String to, int cents)> moves;
}

List<BillMoves> billMoves(Iterable<Bill> bills, {String Function(String name)? key}) {
  final k = key ?? (String n) => n;
  final out = <BillMoves>[];
  for (final b in bills) {
    if (!b.done || b.settled || b.payer == null) continue;
    final m = <(String, String, int)>[];
    for (final (from, to, c) in b.transfers()) {
      if (from >= b.ps.length || to >= b.ps.length) continue;
      final h = b.toHome(c);
      if (h != 0) m.add((k(b.ps[from].name), k(b.ps[to].name), h));
    }
    if (m.isNotEmpty) out.add(BillMoves(b, m));
  }
  return out;
}
