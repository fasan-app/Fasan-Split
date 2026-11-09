// SPDX-License-Identifier: MPL-2.0
// Fasan Split – cost history of „Mein Stand“ (Nutzer 07.11.: „einen Kosten-Verlauf im Saldo, wenn etwas hinzu kommt oder geht,
// global und per Gruppe“). Per bill the app remembers what it adds to my balance (confirmed + provisional); when that changes,
// the difference is booked with the reason (who changed what, from the change log). MPL-2.0
import 'dart:convert';

import 'package:fasan_core/bill.dart';
import 'package:fasan_core/settle.dart';

/// One booking: [delta] cents on my balance because of [title].
class LedgerEntry {
  const LedgerEntry({required this.at, required this.billId, required this.title, required this.group, required this.delta, required this.total, required this.groupTotal, this.whyDe, this.whyEn});

  final DateTime at;
  final String billId, title;
  final String? group; // group name of the bill (null = no group)
  final int delta; // + I get more / owe less, − the other way
  final int total; // my balance after the booking, all groups
  final int groupTotal; // my balance in [group] after the booking
  final String? whyDe, whyEn;

  Map<String, Object?> toJson() => {'t': at.millisecondsSinceEpoch, 'b': billId, 'n': title, if (group != null) 'g': group, 'd': delta, 'a': total, 'ga': groupTotal, if (whyDe != null) 'x': whyDe, if (whyEn != null) 'y': whyEn};

  static LedgerEntry? fromJson(Object? j) {
    try {
      final m = (j as Map).cast<String, Object?>();
      return LedgerEntry(
        at: DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()),
        billId: m['b'] as String,
        title: m['n'] as String,
        group: m['g'] as String?,
        delta: (m['d'] as num).toInt(),
        total: (m['a'] as num).toInt(),
        groupTotal: (m['ga'] as num).toInt(),
        whyDe: m['x'] as String?,
        whyEn: m['y'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// What [b] adds to my balance now: confirmed transfers of a finished bill, or the assigned part of an open one.
int mineOf(Bill b, bool Function(String) isMe) {
  if (b.trashedAt != null) return 0;
  int sum(Map<String, int> m) => m.values.fold(0, (a, x) => a + x);
  return sum(myDebts([b], isMe)) + sum(myProvisional([b], isMe));
}

class BalanceLedger {
  BalanceLedger({this.seen, List<LedgerEntry>? entries, this.maxEntries = 500}) : entries = entries ?? [];

  final int maxEntries;

  /// Newest first.
  final List<LedgerEntry> entries;
  Map<String, int>? seen; // per bill: what it added to my balance at the last look; null = never looked (baseline)

  /// Looks at all [bills]; books every difference. Returns true if something was booked or the baseline was set.
  /// [why] gives the reason for a bill (German, English) or null.
  bool update(Iterable<Bill> bills, bool Function(String) isMe, {DateTime? now, (String, String)? Function(String billId, int before, int after)? why}) {
    final list = bills.toList();
    final cur = {for (final b in list) b.id: mineOf(b, isMe)};
    final last = seen;
    if (last == null) {
      seen = cur; // first look: what is there already is the starting point, not a booking
      return true;
    }
    final byId = {for (final b in list) b.id: b};
    var total = last.values.fold(0, (a, x) => a + x);
    final groupOf = <String, String?>{for (final b in list) b.id: b.group};
    final groupTotals = <String?, int>{};
    for (final e in last.entries) {
      groupTotals.update(groupOf[e.key], (x) => x + e.value, ifAbsent: () => e.value);
    }
    var changed = false;
    final at = now ?? DateTime.now();
    for (final id in {...cur.keys, ...last.keys}) {
      final before = last[id] ?? 0, after = cur[id] ?? 0;
      if (before == after) continue;
      final b = byId[id];
      final delta = after - before;
      total += delta;
      final g = groupOf[id];
      groupTotals.update(g, (x) => x + delta, ifAbsent: () => delta);
      final w = why?.call(id, before, after);
      final title = b == null ? (entries.where((e) => e.billId == id).firstOrNull?.title ?? 'Bon') : (b.purpose.isNotEmpty ? b.purpose : 'Bon');
      entries.insert(0, LedgerEntry(at: at, billId: id, title: title, group: g, delta: delta, total: total, groupTotal: groupTotals[g] ?? delta, whyDe: w?.$1, whyEn: w?.$2));
      changed = true;
    }
    seen = cur;
    if (entries.length > maxEntries) entries.removeRange(maxEntries, entries.length);
    return changed;
  }

  String encode() => jsonEncode({'last': seen, 'e': [for (final e in entries) e.toJson()]});

  static BalanceLedger decode(String? s) {
    try {
      final m = (jsonDecode(s ?? '{}') as Map).cast<String, Object?>();
      final last = (m['last'] as Map?)?.map((k, v) => MapEntry(k as String, (v as num).toInt()));
      return BalanceLedger(seen: last, entries: [for (final j in (m['e'] as List?) ?? const []) ?LedgerEntry.fromJson(j)]);
    } catch (_) {
      return BalanceLedger();
    }
  }
}
