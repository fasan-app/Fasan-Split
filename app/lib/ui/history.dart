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
import '../collab/service.dart' show UndoResult;
import '../l10n.dart';
import '../l10n/tr.dart' show trLang;
import 'bill_screen.dart' show ReviewScreen;
import 'common.dart';
import 'resume.dart' show ResumeFlow;
import 'scope.dart';

/// The app tag of an old APK build (0.1.N with N up to [kLastOldApk]) that wrote within the last 14 days, or null. Builds up to 0.1.85
/// lack the fixes against writing stale bills back (STAND 12.11.); the history showed entries of 0.1.83 repeating (Nutzer 12.11.).
/// Web builds carry „web“ plus short hash, so they never match. Cause: [Likely], not proven.
const kLastOldApk = 85;
String? staleAppOf(List<ChangeRecord> changes, {DateTime? now}) {
  final t = (now ?? DateTime.now()).subtract(const Duration(days: 14));
  final re = RegExp(r'^0\.1\.(\d+)$');
  for (final r in changes) {
    final m = r.app == null ? null : re.firstMatch(r.app!);
    if (m != null && r.at.isAfter(t) && int.parse(m.group(1)!) <= kLastOldApk) return r.app;
  }
  return null;
}

class HistoryScreen extends StatelessWidget {
  /// Changes of one bill only.
  const HistoryScreen.bill({super.key, required String this.billId, this.billTitle}) : groupTag = null, groupName = null, initialTab = 0;

  /// One group: its changes and its costs.
  const HistoryScreen.group({super.key, required String this.groupTag, required String this.groupName, this.initialTab = 0}) : billId = null, billTitle = null;

  /// Everything: all groups.
  const HistoryScreen.all({super.key, this.initialTab = 0}) : billId = null, billTitle = null, groupTag = null, groupName = null;

  final String? billId, billTitle, groupTag, groupName;

  /// 0 = Änderungen, 1 = Saldo (the balance history; the balance pages open it directly).
  final int initialTab;

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
      initialIndex: initialTab,
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

/// Opens a bill, at an item when [itemUid] is given. Everything in the histories is a link (Nutzer 11.11., 12.11.).
void openBillAt(BuildContext context, String billId, [String? itemUid]) {
  final bill = StoreScope.read(context).bills.where((b) => b.id == billId).firstOrNull;
  if (bill == null) return;
  final at = itemUid == null ? -1 : bill.its.indexWhere((x) => x.uid == itemUid);
  final focus = at < 0 ? null : at;
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => bill.done ? ReviewScreen(bill: bill, focusItem: focus) : ResumeFlow(bill: bill, focusItem: focus)));
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
    // the same change repeated one after another (somebody toggles a person on and off) is one line with a count
    final rows = <(ChangeRecord, int)>[];
    for (final r in changes) {
      final last = rows.isEmpty ? null : rows.last;
      if (last != null && last.$1.whoKey == r.whoKey && last.$1.billId == r.billId && last.$1.at.difference(r.at).abs() < const Duration(minutes: 30) && _sameText(last.$1, r)) {
        rows[rows.length - 1] = (last.$1, last.$2 + 1);
      } else {
        rows.add((r, 1));
      }
    }
    final oldApp = staleAppOf(changes);
    final lead = oldApp == null ? 0 : 1;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom),
      itemCount: rows.length + lead,
      separatorBuilder: (_, _) => Divider(height: 1, color: l.hairline),
      itemBuilder: (_, i) {
        if (lead == 1 && i == 0) {
          return Padding(
            key: const Key('old-app-warning'),
            padding: const EdgeInsets.symmetric(vertical: FasanSpace.s),
            child: Text(trLang(de ? 'de' : 'en', 'history.oldApp', [oldApp!]), style: tt.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.error)),
          );
        }
        final (r, times) = rows[i - lead];
        final mine = r.whoKey == c.identity?.pub;
        final who = mine ? trLang(de ? 'de' : 'en', 'history.you') : r.who;
        final where = [if (showBill) r.title, if (showGroup) c.groups[r.group]?.localName].whereType<String>().join(' · ');
        // everything is a link (Nutzer 11.11.): the entry opens the bill, a line about an item opens it at that item
        void open(String? itemUid) => openBillAt(context, r.billId, itemUid);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: FasanSpace.xs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: () => open(null),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: FasanSpace.xs),
                child: Row(children: [
                  Expanded(child: Text(where.isEmpty ? who : '$who · $where', style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(_when(context, r.at), style: tt.bodySmall!.copyWith(color: l.textMuted)),
                ]),
              ),
            ),
            for (final line in r.lines)
              InkWell(
                onTap: () => open(line.item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text('• ${line.text(de)}${times > 1 ? '  ×$times' : ''}', style: tt.bodyMedium)),
                    Icon(Icons.chevron_right_rounded, size: 18, color: l.textMuted),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

bool _sameText(ChangeRecord a, ChangeRecord b) => a.lines.length == b.lines.length && [for (var i = 0; i < a.lines.length; i++) a.lines[i].de == b.lines[i].de].every((x) => x);

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
        return InkWell(
          key: ValueKey('ledger-$i'),
          onTap: () => showLedgerSheet(context, e, perGroup: perGroup),
          child: Padding(
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
            Padding(padding: const EdgeInsets.only(top: 4), child: Icon(Icons.chevron_right_rounded, size: 20, color: l.textMuted)),
          ]),
        ));
      },
    );
  }
}

/// The detail of one booking of the balance history (Nutzer 12.11.: „klickbar, nachvollziehbar, rückgängig machbar“): how much,
/// before and after, what changed and who did it (with the device), open the bill, take the change back.
Future<void> showLedgerSheet(BuildContext context, LedgerEntry e, {required bool perGroup}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => LedgerSheet(entry: e, perGroup: perGroup, parent: context),
  );
}

class LedgerSheet extends StatelessWidget {
  const LedgerSheet({super.key, required this.entry, required this.perGroup, required this.parent});

  final LedgerEntry entry;
  final bool perGroup;
  final BuildContext parent;

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final c = CollabScope.of(context);
    String tr(String k, [List<Object> a = const []]) => trLang(de ? 'de' : 'en', k, a);
    final sign = signOf(context);
    final e = entry;
    final after = perGroup ? e.groupTotal : e.total, before = after - e.delta;
    // the record behind it: same bill, same time and author
    final rec = e.recAt == null ? null : c.changeLog.where((r) => r.billId == e.billId && r.at.millisecondsSinceEpoch == e.recAt && r.whoKey == e.recBy).firstOrNull;
    final mine = rec != null && rec.whoKey == c.identity?.pub;
    final who = rec == null ? null : (mine ? tr('history.you') : rec.who);
    final bill = StoreScope.of(context).bills.where((b) => b.id == e.billId).firstOrNull;
    final col = e.delta > 0 ? Colors.green.shade600 : (e.delta < 0 ? Colors.red.shade600 : l.textMuted);
    Future<void> undo() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('ledger.undo')),
          content: Text(tr('ledger.undoAsk', [who ?? ''])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.of(ctx).cancel)),
            TextButton(key: const ValueKey('ledger-undo-yes'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ledger.undo'))),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final r = CollabScope.read(context).undoChange(rec!);
      Navigator.pop(context);
      if (parent.mounted) {
        ScaffoldMessenger.of(parent).showSnackBar(SnackBar(content: Text(tr(r == UndoResult.done ? 'ledger.undoDone' : r == UndoResult.partly ? 'ledger.undoPartly' : 'ledger.undoNothing'))));
      }
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.xl),
        children: [
          Text('${money(e.delta, de: de, sign: true)} $sign', style: tt.headlineSmall!.copyWith(color: col, fontWeight: FontWeight.w800)),
          const SizedBox(height: FasanSpace.xs),
          Text([e.title, if (!perGroup && e.group != null) e.group!].join(' · '), style: tt.titleMedium),
          const SizedBox(height: FasanSpace.s),
          Text('${tr('ledger.before')}: ${money(before, de: de, sign: true)} $sign  →  ${tr('history.balanceAfter')}: ${money(after, de: de, sign: true)} $sign', style: tt.bodyMedium),
          Text(_when(context, e.at), style: tt.bodySmall!.copyWith(color: l.textMuted)),
          const SizedBox(height: FasanSpace.m),
          if (rec == null)
            Text(de ? (e.whyDe ?? tr('ledger.noRecord')) : (e.whyEn ?? e.whyDe ?? tr('ledger.noRecord')), style: tt.bodyMedium)
          else ...[
            FasanLabel(tr('ledger.what')),
            Text('$who · ${_when(context, rec.at)}${rec.app == null ? '' : ' · ${tr('ledger.device')} ${rec.app}'}', style: tt.bodySmall!.copyWith(color: l.textMuted)),
            const SizedBox(height: FasanSpace.xs),
            for (final line in rec.lines)
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  openBillAt(parent, e.billId, line.item);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text('• ${line.text(de)}', style: tt.bodyMedium)),
                    Icon(Icons.chevron_right_rounded, size: 20, color: l.textMuted),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: FasanSpace.m),
          if (bill != null)
            FasanButton(
              key: const ValueKey('ledger-open'),
              label: tr('ledger.open'),
              kind: FasanButtonKind.quiet,
              onPressed: () {
                Navigator.pop(context);
                openBillAt(parent, e.billId);
              },
            ),
          if (rec != null && rec.undo.isNotEmpty) ...[
            const SizedBox(height: FasanSpace.s),
            FasanButton(key: const ValueKey('ledger-undo'), label: tr('ledger.undo'), onPressed: undo),
          ] else if (rec != null)
            Padding(padding: const EdgeInsets.only(top: FasanSpace.s), child: Text(tr('ledger.noUndo'), style: tt.bodySmall!.copyWith(color: l.textMuted))),
        ],
      ),
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
