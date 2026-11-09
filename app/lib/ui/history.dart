// SPDX-License-Identifier: MPL-2.0
// Fasan Split – history (Nutzer 07.11.: „einen Verlauf sehen, im Profil, in der Gruppe, in den Bons“; „was genau geändert wurde“;
// „einen Kosten-Verlauf im Saldo, global und per Gruppe“). One screen, three scopes: a bill (changes), a group (changes and
// costs), everything (profile: changes and costs). MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../collab/bill_changes.dart';
import '../collab/group.dart' show BillSnapshot;
import '../collab/ledger.dart';
import '../l10n.dart';
import '../l10n/tr.dart' show trLang;
import 'common.dart';
import 'scope.dart';

class HistoryScreen extends StatelessWidget {
  /// Changes of one bill only.
  const HistoryScreen.bill({super.key, required String this.billId, this.billTitle}) : groupTag = null, groupName = null;

  /// One group: its changes and its costs.
  const HistoryScreen.group({super.key, required String this.groupTag, required String this.groupName}) : billId = null, billTitle = null;

  /// Everything: all groups.
  const HistoryScreen.all({super.key}) : billId = null, billTitle = null, groupTag = null, groupName = null;

  final String? billId, billTitle, groupTag, groupName;

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de;
    final c = CollabScope.of(context);
    final changes = billId != null ? c.changesOfBill(billId!) : groupTag != null ? c.changesOfGroup(groupTag!) : c.changeLog;
    final entries = billId != null ? const <LedgerEntry>[] : [for (final e in c.ledger.entries) if (groupName == null || e.group == groupName) e];
    String tr(String k, [List<Object> a = const []]) => trLang(de ? 'de' : 'en', k, a);
    final title = billId != null && billTitle?.isNotEmpty == true ? billTitle! : tr('history.title');
    final changesList = _ChangesList(changes: changes, showBill: billId == null, showGroup: groupTag == null && billId == null);
    if (billId != null) {
      final bill = StoreScope.of(context).bills.where((b) => b.id == billId).firstOrNull;
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: [
          if (bill != null && bill.group != null)
            IconButton(tooltip: tr('history.restore'), icon: const Icon(Icons.settings_backup_restore_rounded), onPressed: () => _restoreDialog(context, bill)),
        ]),
        body: changesList,
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(groupName == null ? title : '$title · $groupName'),
          bottom: TabBar(tabs: [Tab(text: tr('history.tabChanges')), Tab(text: tr('history.tabCosts'))]),
        ),
        body: TabBarView(children: [changesList, _CostList(entries: entries, perGroup: groupName != null)]),
      ),
    );
  }
}

String _when(BuildContext context, DateTime d) {
  final de = S.of(context).de, n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(d.hour)}:${two(d.minute)}';
  if (d.year == n.year && d.month == n.month && d.day == n.day) return trLang(de ? 'de' : 'en', 'history.today', [hm]);
  final y = n.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return trLang(de ? 'de' : 'en', 'history.yesterday', [hm]);
  return '${two(d.day)}.${two(d.month)}. $hm';
}

Widget _empty(BuildContext context, String key) {
  final l = FasanLook.of(context);
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(FasanSpace.xl),
      child: Text(trLang(S.of(context).de ? 'de' : 'en', key), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: l.textMuted)),
    ),
  );
}

class _ChangesList extends StatelessWidget {
  const _ChangesList({required this.changes, required this.showBill, required this.showGroup});
  final List<ChangeRecord> changes;
  final bool showBill, showGroup;

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final c = CollabScope.of(context);
    if (changes.isEmpty) {
      return _empty(context, 'history.emptyChanges');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom),
      itemCount: changes.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: l.hairline),
      itemBuilder: (_, i) {
        final r = changes[i];
        final mine = r.whoKey == c.identity?.pub;
        final who = mine ? trLang(de ? 'de' : 'en', 'history.you') : r.who;
        final where = [if (showBill) r.title, if (showGroup) c.groups[r.group]?.localName].whereType<String>().join(' · ');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: FasanSpace.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(where.isEmpty ? who : '$who · $where', style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text([_when(context, r.at), if (r.app != null) r.app!].join(' · '), style: tt.bodySmall!.copyWith(color: l.textMuted)),
            ]),
            const SizedBox(height: 2),
            for (final line in r.lines) Padding(padding: const EdgeInsets.only(top: 1), child: Text('• ${line.text(de)}', style: tt.bodyMedium)),
          ]),
        );
      },
    );
  }
}

class _CostList extends StatelessWidget {
  const _CostList({required this.entries, required this.perGroup});
  final List<LedgerEntry> entries;
  final bool perGroup;

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    if (entries.isEmpty) {
      return _empty(context, 'history.emptyCosts');
    }
    Color col(int v) => v > 0 ? Colors.green.shade600 : (v < 0 ? Colors.red.shade600 : l.textMuted);
    final sign = signOf(context);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom),
      itemCount: entries.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: l.hairline),
      itemBuilder: (_, i) {
        final e = entries[i];
        final after = perGroup ? e.groupTotal : e.total;
        final why = de ? e.whyDe : (e.whyEn ?? e.whyDe);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: FasanSpace.s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 96, child: Text('${money(e.delta, de: de, sign: true)} $sign', style: tt.titleSmall!.copyWith(color: col(e.delta), fontWeight: FontWeight.w700))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text([e.title, if (!perGroup && e.group != null) e.group!].join(' · '), style: tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (why != null) Text(why, style: tt.bodySmall!.copyWith(color: l.textMuted)),
                Text('${trLang(de ? 'de' : 'en', 'history.balanceAfter')}: ${money(after, de: de, sign: true)} $sign · ${_when(context, e.at)}', style: tt.bodySmall!.copyWith(color: l.textMuted)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Lists the last state each member published for [bill] and brings the chosen one back (Nutzer 08.11.: Kassenzettel zerschossen).
Future<void> _restoreDialog(BuildContext context, Bill bill) {
  final c = CollabScope.read(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => RestoreDialog(
      bill: bill,
      snapshots: c.snapshotsOfBill(bill),
      who: (s) => c.snapshotWho(bill, s),
      onRestore: (s) => c.restoreSnapshot(bill, s),
    ),
  );
}

/// The dialog itself (public so the screenshot test can show it with made-up snapshots).
class RestoreDialog extends StatelessWidget {
  const RestoreDialog({super.key, required this.bill, required this.snapshots, required this.who, required this.onRestore});
  final Bill bill;
  final Future<List<BillSnapshot>> snapshots;
  final String Function(BillSnapshot) who;
  final void Function(BillSnapshot) onRestore;

  @override
  Widget build(BuildContext ctx) {
    final de = S.of(ctx).de;
    String tr(String k, [List<Object> a = const []]) => trLang(de ? 'de' : 'en', k, a);
    return AlertDialog(
      title: Text(tr('history.restore')),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<List<BillSnapshot>>(
          future: snapshots,
          builder: (ctx, snap) {
            if (!snap.hasData) return Row(children: [const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 12), Expanded(child: Text(tr('history.restoreLoading')))]);
            final list = snap.data!;
            if (list.isEmpty) return Text(tr('history.restoreNone'));
            return ListView(shrinkWrap: true, children: [
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('history.restoreHint'))),
              for (final s in list)
                Builder(builder: (_) {
                  final b = s.bill(bill.id);
                  return ListTile(
                    minVerticalPadding: 12,
                    title: Text('${who(s)} · ${_when(ctx, s.at)}'),
                    subtitle: Text(tr('history.restoreSummary', ['${b.items?.length ?? 0}', money(b.effectiveTotal, de: de), [for (final i in (b.items ?? const <BillItem>[]).take(3)) '${i.qty > 1 ? '${i.qty} × ' : ''}${i.name}'].join(', ')])),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (c2) => AlertDialog(
                          content: Text(tr('history.restoreConfirm', [who(s), _when(ctx, s.at)])),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c2, false), child: Text(tr('s.cancel'))),
                            FilledButton(onPressed: () => Navigator.pop(c2, true), child: Text(tr('history.restoreDo'))),
                          ],
                        ),
                      );
                      if (ok == true) {
                        onRestore(s);
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
                  );
                }),
            ]);
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('s.close')))],
    );
  }
}
