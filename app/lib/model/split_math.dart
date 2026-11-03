// Fasan Split – exact money arithmetic. MPL-2.0
//
// Rules (Beschluss 03.11.): money is integer cents, shares are integer thousandths, NO floating point in any sum.
// Every split is computed twice with two independent methods; the app only trusts a result if both agree on the total
// and differ by at most one cent per person. Leftover cents rotate between people from item to item („reihum gerecht“),
// so nobody pays the extra cent every time. The same inputs give the same result on every device.

/// Shares are stored as doubles in the model (1 = one equal part, 0.5 = half a part). They are converted to integer
/// thousandths here, once, so all later steps are exact.
const int shareUnit = 1000;

int shareThousandths(double w) => (w * shareUnit).round();

class SplitMath {
  const SplitMath._();

  /// Method A – largest remainder with integers. [rotate] (the item's index) decides who gets leftover cents when
  /// remainders are equal, so ties move on from item to item.
  static Map<int, int> split(int amount, Map<int, double> shares, {int rotate = 0}) {
    final w = _weights(shares);
    if (w.isEmpty) return {};
    return _splitInts(amount, w, rotate: rotate);
  }

  /// Method B – cumulative rounding (a different algorithm on purpose, used only as a cross-check).
  /// Person k gets round(a·W_k / S) − round(a·W_{k−1} / S); the parts always add up to the amount.
  static Map<int, int> splitCumulative(int amount, Map<int, double> shares) {
    final w = _weights(shares);
    if (w.isEmpty) return {};
    final neg = amount < 0, a = amount.abs();
    final keys = w.keys.toList()..sort();
    final sum = w.values.fold<int>(0, (x, y) => x + y);
    int roundDiv(int num) => (2 * num + sum) ~/ (2 * sum); // round half up, integers only
    var acc = 0, prev = 0;
    final out = <int, int>{};
    for (final k in keys) {
      acc += w[k]!;
      final cum = roundDiv(a * acc);
      out[k] = cum - prev;
      prev = cum;
    }
    return neg ? {for (final e in out.entries) e.key: -e.value} : out;
  }

  /// True if two splits of the same amount are consistent: equal totals, each person at most one cent apart.
  static bool agree(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) return false;
    var sa = 0, sb = 0;
    for (final k in a.keys) {
      final x = a[k], y = b[k];
      if (y == null) return false;
      if ((x! - y).abs() > 1) return false;
      sa += x;
      sb += y;
    }
    return sa == sb;
  }

  /// Spreads [diff] cents (tip, unread line) over people in proportion to their cents. Integers only.
  static Map<int, int> spread(int diff, Map<int, int> basis, {int rotate = 0}) {
    final w = {for (final e in basis.entries) if (e.value > 0) e.key: e.value.toDouble()};
    if (w.isEmpty || diff == 0) return {};
    // basis cents are exact ints; scale them to thousandths so `split` can reuse the same path
    return _splitInts(diff, {for (final e in w.entries) e.key: e.value.toInt()}, rotate: rotate);
  }

  static Map<int, int> _splitInts(int amount, Map<int, int> weights, {int rotate = 0}) {
    final neg = amount < 0, a = amount.abs();
    final keys = weights.keys.toList()..sort();
    final sum = weights.values.fold<int>(0, (x, y) => x + y);
    final out = <int, int>{}, rem = <int, int>{};
    for (final k in keys) {
      final num = a * weights[k]!;
      out[k] = num ~/ sum;
      rem[k] = num % sum;
    }
    var rest = a - out.values.fold<int>(0, (x, y) => x + y);
    final n = keys.length;
    int slot(int k) => ((keys.indexOf(k) - rotate) % n + n) % n;
    final order = [...keys]..sort((p, q) {
        final c = rem[q]!.compareTo(rem[p]!);
        return c != 0 ? c : slot(p).compareTo(slot(q));
      });
    for (var i = 0; rest > 0; i = (i + 1) % n) {
      out[order[i]] = out[order[i]]! + 1;
      rest--;
    }
    return neg ? {for (final e in out.entries) e.key: -e.value} : out;
  }

  static Map<int, int> _weights(Map<int, double> shares) {
    final w = <int, int>{};
    for (final e in shares.entries) {
      final t = shareThousandths(e.value);
      if (t > 0) w[e.key] = t;
    }
    return w;
  }

  /// Pieces of an item one person gets, as an exact fraction (numerator, denominator) – for display: 3 pieces for 2
  /// people is 3/2, shown as „1,5“.
  static (int, int) pieces(int qty, Map<int, double> shares, int person) {
    final w = _weights(shares);
    final mine = w[person];
    if (mine == null) return (0, 1);
    final sum = w.values.fold<int>(0, (x, y) => x + y);
    final n = qty * mine, d = sum;
    final g = n.gcd(d);
    return (n ~/ g, d ~/ g);
  }
}

/// One finding of the audit; shown to the user and blocks „Fertig“ when [blocking].
class AuditIssue {
  const AuditIssue(this.code, this.detail, {this.blocking = true});
  final String code; // 'sum', 'method', 'range'
  final String detail;
  final bool blocking;
  @override
  String toString() => '$code: $detail';
}
