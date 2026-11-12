// SPDX-License-Identifier: MPL-2.0
// Fasan Split – how a balance comes about (Nutzer 07.11.: „im Profil sehen, wie sich das Saldo ergibt, alle Positiven und Negativen
// als Rechnung auf einen Blick“; „die Umrechnung, wer wem wie viel schuldet, auch in der Gruppe für alle zum Nachvollziehen“).
// Two screens over the same data as the balances themselves (settle.dart), so the lines always add up to the number shown. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_core/settle.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../l10n/tr.dart' show trLang;
import 'balance_state_ui.dart' show gapReasons;
import 'common.dart';
import 'shape_tokens.dart';
import 'history.dart' show HistoryScreen;
import 'groups.dart' show groupNaming;
import 'my_balance.dart' show myNames, myPerson;
import 'scope.dart';

String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

/// My balance as a calculation: every receipt with what it adds (+) or takes (−), grouped, summing to the number of „Mein Stand“.
class MyBreakdownScreen extends StatelessWidget {
  const MyBreakdownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    String tr(String k, [List<Object> a = const []]) => trLang(de ? 'de' : 'en', k, a);
    final store = StoreScope.of(context);
    CollabScope.of(context);
    final isMe = myNames(context);
    final sign = signOf(context);
    final bills = store.bills.where((b) => b.trashedAt == null).toList();
    Color c(int v) => v > 0 ? Colors.green.shade600 : (v < 0 ? Colors.red.shade600 : l.textMuted);
    int sum(Map<String, int> m) => m.values.fold(0, (a, x) => a + x);

    // per bill: confirmed lines, provisional lines
    final rows = <({Bill bill, Map<String, int> sure, Map<String, int> soft})>[];
    for (final b in bills) {
      final sure = myDebts([b], isMe, isMePerson: myPerson(context)), soft = myProvisional([b], isMe, isMePerson: myPerson(context));
      if (sum(sure) + sum(soft) != 0 || sure.isNotEmpty || soft.isNotEmpty) rows.add((bill: b, sure: sure, soft: soft));
    }
    rows.sort((a, b) => (b.bill.receiptDate ?? b.bill.created).compareTo(a.bill.receiptDate ?? a.bill.created));
    final groups = <String?>[...store.allGroups, null];
    final total = rows.fold(0, (a, r) => a + sum(r.sure) + sum(r.soft));

    Widget billRow(({Bill bill, Map<String, int> sure, Map<String, int> soft}) r) {
      final mine = sum(r.sure) + sum(r.soft);
      final soft = r.soft.isNotEmpty && r.sure.isEmpty;
      final lines = <String>[
        for (final e in r.sure.entries) tr(e.value > 0 ? 'my_balance.owesYou' : 'my_balance.youOwe2', [e.key]),
        for (final e in r.soft.entries) e.key.isEmpty ? tr('my_balance.provisionalOpenPayer') : tr(e.value > 0 ? 'my_balance.provisionalGets' : 'my_balance.provisionalOwes', [e.key]),
      ];
      return Opacity(
        opacity: soft ? 0.65 : 1,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${r.bill.purpose.isEmpty ? tr('bill.title') : r.bill.purpose} · ${_day(r.bill.receiptDate ?? r.bill.created)}${soft ? ' · ${tr('breakdown.provisional')}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
          trailing: Text('${money(mine, de: de, sign: true)} $sign', style: tt.titleMedium!.copyWith(color: c(mine))),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('breakdown.myTitle')), actions: [
        IconButton(
          key: const ValueKey('balance-history-icon'),
          tooltip: tr('history.openBalance'),
          icon: const Icon(Icons.history_rounded),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen.all(initialTab: 1))),
        ),
      ]),
      body: rows.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(FasanSpace.xl), child: Text(tr('breakdown.nothing'), textAlign: TextAlign.center, style: tt.bodyMedium!.copyWith(color: l.textMuted))))
          : ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
              // the visible twin of the history icon: every change of the balance, with cause and undo (Nutzer 12.11.)
              InkWell(
                key: const ValueKey('balance-history'),
                borderRadius: BorderRadius.circular(l.rInner),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen.all(initialTab: 1))),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: l.minTap),
                  child: Row(children: [
                    Icon(Icons.history_rounded, color: l.accent),
                    const SizedBox(width: FasanSpace.m),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(tr('history.openBalance'), style: tt.titleSmall),
                      Text(tr('history.openBalanceSub'), style: tt.bodySmall!.copyWith(color: l.textMuted)),
                    ])),
                    Icon(Icons.chevron_right_rounded, color: l.textMuted),
                  ]),
                ),
              ),
              for (final g in groups)
                if (rows.any((r) => r.bill.group == g)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: FasanSpace.m),
                    child: Row(children: [
                      Expanded(child: FasanLabel(g ?? tr('my_balance.noGroup'))),
                      Builder(builder: (_) {
                        final sub = rows.where((r) => r.bill.group == g).fold(0, (a, r) => a + sum(r.sure) + sum(r.soft));
                        return Text('${money(sub, de: de, sign: true)} $sign', style: tt.labelLarge!.copyWith(color: c(sub)));
                      }),
                    ]),
                  ),
                  for (final r in rows.where((r) => r.bill.group == g)) billRow(r),
                ],
              const Divider(height: FasanSpace.xl),
              Row(children: [
                Expanded(child: Text(tr('breakdown.sum'), style: tt.titleMedium)),
                Text('${money(total, de: de, sign: true)} $sign', style: tt.titleLarge!.copyWith(color: c(total), fontWeight: FontWeight.w700)),
              ]),
            ]),
    );
  }
}

/// One group, for everyone: each finished receipt with who owes whom, the balance per person, and the transfers that settle it.
class GroupBreakdownScreen extends StatelessWidget {
  const GroupBreakdownScreen({super.key, required this.name, this.person});
  final String name;

  /// Only this person (key as of `groupNaming`): their bills, their balance, their transfers (Nutzer 12.11.: tap on a balance).
  final String? person;

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    String tr(String k, [List<Object> a = const []]) => trLang(de ? 'de' : 'en', k, a);
    final store = StoreScope.of(context);
    CollabScope.of(context);
    final sign = signOf(context);
    final (:keyOf, :label) = groupNaming(context, name);
    final bills = store.inGroup(name, done: true);
    final who = person;
    final allMoves = billMoves(bills, key: keyOf);
    final moves = who == null
        ? allMoves
        : [
            for (final bm in allMoves)
              if (bm.moves.any((m) => m.$1 == who || m.$2 == who)) BillMoves(bm.bill, [for (final m in bm.moves) if (m.$1 == who || m.$2 == who) m])
          ];
    final fullBal = balances(bills, key: keyOf)..removeWhere((_, v) => v == 0);
    final bal = who == null ? fullBal : {for (final e in fullBal.entries) if (e.key == who) e.key: e.value};
    final plan = settle(fullBal).where((p) => who == null || p.$1 == who || p.$2 == who).toList();
    final gap = who == null ? null : store.groupGaps(name, key: keyOf)[who];
    // why the balance of this person is uncertain, in words (never colour alone)
    final gapLine = gap != null && gap.uncertain
        ? Padding(
            key: const ValueKey('breakdown-uncertain'),
            padding: const EdgeInsets.only(bottom: FasanSpace.m),
            child: Row(children: [
              Icon(Icons.help_outline_rounded, size: 18, color: l.textMuted),
              const SizedBox(width: FasanSpace.s),
              Expanded(child: Text('${tr('balance.uncertain')}: ${gapReasons(gap, de ? 'de' : 'en').join(' · ')}', style: tt.bodyMedium!.copyWith(color: l.textMuted))),
            ]),
          )
        : null;
    Color c(int v) => v > 0 ? Colors.green.shade600 : (v < 0 ? Colors.red.shade600 : l.textMuted);
    String m(int v) => '${money(v, de: de)} $sign';
    return Scaffold(
      appBar: AppBar(title: Text(who == null ? tr('breakdown.groupTitle') : tr('breakdown.personTitle', [label(who)]))),
      body: moves.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(FasanSpace.xl), child: Column(mainAxisSize: MainAxisSize.min, children: [?gapLine, Text(who == null ? tr('breakdown.nothing') : tr('breakdown.personNothing', [label(who)]), textAlign: TextAlign.center, style: tt.bodyMedium!.copyWith(color: l.textMuted))])))
          : ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
              ?gapLine,
              FasanLabel(tr('breakdown.bills')),
              for (final bm in moves)
                Padding(
                  padding: const EdgeInsets.only(bottom: FasanSpace.m),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${bm.bill.purpose.isEmpty ? tr('bill.title') : bm.bill.purpose} · ${_day(bm.bill.receiptDate ?? bm.bill.created)}', style: tt.titleSmall),
                    if (bm.bill.payer != null && bm.bill.payer! < bm.bill.ps.length && !bm.bill.multiPay)
                      Text(tr('breakdown.paidBy', [label(keyOf(bm.bill.ps[bm.bill.payer!].name))]), style: tt.bodySmall!.copyWith(color: l.textMuted)),
                    for (final (f, t, cents) in bm.moves)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          Expanded(child: Text(tr('breakdown.owesTo', [label(f), label(t)]), style: tt.bodyMedium)),
                          Text(m(cents), style: tt.bodyMedium),
                        ]),
                      ),
                  ]),
                ),
              const Divider(height: FasanSpace.xl),
              FasanLabel(tr('breakdown.perPerson')),
              if (bal.isEmpty) Text(tr('breakdown.even'), style: tt.bodyMedium),
              for (final e in (bal.entries.toList()..sort((a, b) => a.value.compareTo(b.value))))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: FasanAvatar(name: label(e.key), index: e.key.hashCode % 8, size: 28),
                  title: Text(label(e.key)),
                  trailing: Text('${money(e.value, de: de, sign: true)} $sign', style: tt.titleSmall!.copyWith(color: c(e.value))),
                ),
              if (plan.isNotEmpty) ...[
                const SizedBox(height: FasanSpace.m),
                FasanLabel(tr('breakdown.settle')),
                for (final (f, t, cents) in plan)
                  ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(tr('breakdown.settleLine', [label(f), label(t)])), trailing: Text(m(cents), style: tt.titleSmall)),
              ],
            ]),
    );
  }
}
