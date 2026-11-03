// Fasan Split – the bill flow: 1 total and purpose, 2 who was there, 3 assign, 4 who paid + result. MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../main.dart';
import '../model/bill.dart';
import '../recognition_service.dart';
import 'assign.dart';
import 'common.dart';
import 'when_where.dart';
import 'diagnose.dart';

// ---------------------------------------------------------------------------------------------------------------------
// 1. total and purpose

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.bill, this.scan});

  final Bill bill;
  final ScanResultData? scan;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final _purpose = TextEditingController(text: widget.bill.purpose);
  late final _total = TextEditingController(text: widget.bill.total == null ? '' : money(widget.bill.total!));

  Bill get b => widget.bill;
  int _pulse = 0;
  bool _wasOk = false;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    final diff = b.difference;
    // The total matches the items: one ring pulse around the total and a light haptic (attention rules: once).
    final ok = b.total != null && diff == 0 && b.its.isNotEmpty;
    if (ok && !_wasOk) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _pulse++);
        FasanHaptics.of(context).confirm();
      });
    }
    _wasOk = ok;
    final status = b.checked && diff == 0
        ? _Status(icon: Icons.verified_outlined, text: t.checked, color: l.accent)
        : (diff != 0 && b.total != null
            ? _Status(icon: Icons.error_outline, text: t.diff('${money(diff.abs(), de: t.de)} €'), color: Theme.of(context).colorScheme.error)
            : (widget.scan?.contradiction == true ? _Status(icon: Icons.help_outline, text: t.contradiction, color: Theme.of(context).colorScheme.error) : null));
    return StepScaffold(
      title: t.totalAndPurpose,
      step: 1,
      bill: b,
      action: t.next,
      onAction: b.its.isEmpty && b.total == null
          ? null
          : () {
              b.purpose = _purpose.text.trim();
              StoreScope.read(context).upsert(b);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => PeopleScreen(bill: b)));
            },
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context)),
        children: [
          // compact head: the items are the main thing, purpose/total/date/place take two rows (Nutzer 02.11.)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _purpose,
                decoration: InputDecoration(labelText: t.purpose, hintText: t.purposeHint),
                textInputAction: TextInputAction.next,
                // saved while typing: leaving without „Weiter“ or a finishing scan must not lose the name
                onChanged: (v) {
                  b.purpose = v.trim();
                  StoreScope.read(context).upsert(b);
                },
              ),
            ),
            const SizedBox(width: FasanSpace.s),
            Expanded(
              flex: 2,
              child: FasanGlow(pulse: _pulse, strength: 0, radius: 6, child: TextField(
                controller: _total,
                textAlign: TextAlign.end,
                decoration: InputDecoration(labelText: t.total, suffixText: '€'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: tt.titleLarge,
                onChanged: (v) => setState(() {
                  b.total = parseMoney(v);
                  b.checked = false;
                }),
              )),
            ),
          ]),
          const SizedBox(height: FasanSpace.s),
          WhenWhere(bill: b, compact: true, onChanged: () => setState(() {})),
          if (status != null) ...[const SizedBox(height: FasanSpace.xs), status],
          const SizedBox(height: FasanSpace.l),
          Row(children: [
            FasanLabel('${t.items} · ${b.its.length}'),
            const Spacer(),
            Money(b.itemSum, style: tt.bodyMedium),
          ]),
          const SizedBox(height: FasanSpace.s),
          for (var i = 0; i < b.its.length; i++) _ItemRow(item: b.its[i], onTap: () => _edit(i)),
          const SizedBox(height: FasanSpace.s),
          Align(
            alignment: Alignment.centerLeft,
            child: FasanButton(label: t.addItem, icon: Icons.add, kind: FasanButtonKind.quiet, onPressed: _add),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(int i) async {
    final it = b.its[i];
    var deleted = false;
    final changed = await editItem(context, it, onDelete: () => deleted = true);
    if (!changed) return;
    setState(() {
      if (deleted) b.its.removeAt(i);
      b.checked = false;
    });
  }

  Future<void> _add() async {
    final it = BillItem(name: S.of(context).de ? 'Posten' : 'Item', amount: 0);
    if (await editItem(context, it)) setState(() => b.its.add(it));
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    // one small line, not a big box (space belongs to the items)
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: l.radius * 0.2, vertical: 4),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: FasanSpace.s),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final BillItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final unsure = !item.sure || (item.certainty != null && item.certainty! < 60);
    // Each item is one card: name, amount and its line picture share one region, with clear gaps between items
    // (Common Region; 0.2 showed the picture between two names and it was unclear which it belonged to).
    return Padding(
      padding: const EdgeInsets.only(bottom: FasanSpace.s),
      child: Material(
        color: l.surfaceAlt,
        borderRadius: BorderRadius.circular(l.radius * 0.5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(l.radius * 0.5),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FasanSpace.m, 10, FasanSpace.m, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ItemTitle(item)),
                if (unsure)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: Tooltip(message: t.unsure, child: Icon(Icons.help_outline, size: 18, color: Theme.of(context).colorScheme.error)),
                  ),
                Money(item.amount),
              ]),
              if (item.note != null) Text(item.note!, style: tt.bodySmall),
              if (item.snippet != null) Padding(padding: const EdgeInsets.only(top: 6), child: Snippet(item.snippet, height: 24)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// 2. who was there

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.bill});

  final Bill bill;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _name = TextEditingController();
  Bill get b => widget.bill;

  void _add(String n) {
    final name = n.trim();
    if (name.isEmpty || b.ps.any((p) => p.name.toLowerCase() == name.toLowerCase())) return;
    final used = b.ps.map((p) => p.color).toSet();
    var c = 0;
    while (used.contains(c) && c < 64) {
      c++;
    }
    setState(() => b.ps.add(Person(name, c)));
    _name.clear();
    FasanHaptics.of(context).tap();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final recent = StoreScope.of(context).recentNames.where((n) => !b.ps.any((p) => p.name == n)).toList();
    return StepScaffold(
      title: t.whoWasThere,
      step: 2,
      bill: b,
      action: b.ps.length < 2 ? t.needPeople : t.next,
      onAction: b.ps.length < 2
          ? null
          : () {
              StoreScope.read(context).upsert(b);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => AssignScreen(bill: b)));
            },
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context)),
        children: [
          Row(children: [
            Expanded(child: TextField(controller: _name, decoration: InputDecoration(labelText: t.addPerson), textCapitalization: TextCapitalization.words, onSubmitted: _add)),
            const SizedBox(width: FasanSpace.s),
            FasanButton(label: t.add, onPressed: () => _add(_name.text)),
          ]),
          const SizedBox(height: FasanSpace.l),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < b.ps.length; i++)
              InputChip(
                avatar: FasanAvatar(name: b.ps[i].name, index: b.ps[i].color, size: 28),
                label: Text(b.ps[i].name),
                onDeleted: () => setState(() {
                  b.ps.removeAt(i);
                  for (final it in b.its) {
                    it.shares = {for (final e in it.shares.entries) if (e.key != i) (e.key > i ? e.key - 1 : e.key): e.value};
                  }
                  if (b.payer == i) b.payer = null;
                }),
              ),
          ]),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: FasanSpace.xl),
            FasanLabel(t.recent),
            const SizedBox(height: FasanSpace.s),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final n in recent) ActionChip(label: Text(n), onPressed: () => _add(n))]),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// 4. who paid + result

class PayScreen extends StatefulWidget {
  const PayScreen({super.key, required this.bill});

  final Bill bill;

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  Bill get b => widget.bill;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return StepScaffold(
      title: t.whoPaid,
      step: 4,
      bill: b,
      action: t.done,
      onAction: b.payer == null
          ? null
          : () {
              // The numbers are checked twice (Beschluss 03.11.): a mismatch stops here, nothing is saved as finished.
              if (b.audit().isNotEmpty) {
                FasanHaptics.of(context).warn();
                showNote(context, t.splitCheckBad, duration: const Duration(seconds: 6));
                return;
              }
              b.done = true;
              StoreScope.read(context).upsert(b);
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => ResultScreen(bill: b)), (r) => r.isFirst);
            },
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context)),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < b.ps.length; i++)
              FasanPersonChip(name: b.ps[i].name, index: b.ps[i].color, selected: b.payer == i, onTap: () => setState(() => b.payer = i)),
          ]),
          if (b.advance > 0) ...[
            const SizedBox(height: FasanSpace.l),
            Text('${t.advance}: ${money(b.advance, de: t.de)} €', style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: FasanSpace.xl),
          if (b.payer != null) ResultBody(bill: b),
        ],
      ),
    );
  }
}

/// Per person, transfers, unassigned items.
class ResultBody extends StatelessWidget {
  const ResultBody({super.key, required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    final pp = bill.perPerson();
    final open = bill.its.where((p) => !p.assigned).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FasanLabel(t.result),
      const SizedBox(height: FasanSpace.s),
      for (var i = 0; i < bill.ps.length; i++)
        Container(
          constraints: BoxConstraints(minHeight: l.minTap),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: l.hairline))),
          child: Row(children: [
            FasanAvatar(name: bill.ps[i].name, index: bill.ps[i].color, size: 32),
            const SizedBox(width: FasanSpace.m),
            Expanded(child: Text(t.perPerson(bill.ps[i].name), style: tt.bodyLarge)),
            Money(pp[i] ?? 0),
          ]),
        ),
      if (bill.difference != 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${t.differenceSpread}: ${money(bill.difference, de: t.de, sign: true)} €', style: tt.bodySmall)),
      const SizedBox(height: FasanSpace.l),
      for (final (from, to, c) in bill.transfers())
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            FasanAvatar(name: bill.ps[from].name, index: bill.ps[from].color, size: 26),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded, size: 18, color: l.textMuted),
            const SizedBox(width: 6),
            FasanAvatar(name: bill.ps[to].name, index: bill.ps[to].color, size: 26),
            const SizedBox(width: FasanSpace.m),
            Expanded(child: Text(t.owes(bill.ps[from].name, bill.ps[to].name, '${money(c, de: t.de)} €'), style: tt.bodyMedium)),
          ]),
        ),
      const SizedBox(height: FasanSpace.m),
      _AuditLine(bill: bill),
      if (open.isNotEmpty) ...[
        const SizedBox(height: FasanSpace.l),
        Text('${t.notAssigned}: ${open.map((p) => p.title).join(', ')}', style: tt.bodySmall!.copyWith(color: Theme.of(context).colorScheme.error)),
      ],
    ]);
  }
}

/// „Rechenprüfung“: every number is computed twice; a mismatch is shown loudly. The expandable part shows how each
/// person's amount is made up (item by item, in cents).
class _AuditLine extends StatelessWidget {
  const _AuditLine({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final issues = bill.audit();
    final ok = issues.isEmpty;
    final pp = bill.perPerson();
    final total = pp.values.fold<int>(0, (a, x) => a + x);
    final color = ok ? FasanLook.of(context).textMuted : Theme.of(context).colorScheme.error;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        leading: Icon(ok ? Icons.verified_outlined : Icons.error_outline_rounded, color: color),
        title: Text(ok ? '${t.splitCheck}: ${money(total, de: t.de)} €' : t.splitCheckBad, style: tt.bodyMedium!.copyWith(color: color)),
        children: [
          for (var p = 0; p < bill.ps.length; p++) ...[
            Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(bill.ps[p].name, style: tt.labelLarge))),
            for (var n = 0; n < bill.its.length; n++)
              if (Bill.split(bill.its[n].amount, bill.its[n].shares, rotate: n)[p] case final c? when c != 0)
                Row(children: [
                  Expanded(child: Text(bill.its[n].title, style: tt.bodySmall, overflow: TextOverflow.ellipsis)),
                  Text('${money(c, de: t.de)} €', style: tt.bodySmall),
                ]),
          ],
          if (!ok)
            for (final i in issues) Text(i.toString(), style: tt.bodySmall!.copyWith(color: color)),
        ],
      ),
    );
  }
}

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.bill});

  final Bill bill;

  String _text(S t) {
    final b = StringBuffer('${bill.purpose.isEmpty ? t.appName : bill.purpose}: ${money(bill.effectiveTotal, de: t.de)} €\n');
    final pp = bill.perPerson();
    for (var i = 0; i < bill.ps.length; i++) {
      b.writeln('${bill.ps[i].name}: ${money(pp[i] ?? 0, de: t.de)} €');
    }
    for (final (from, to, c) in bill.transfers()) {
      b.writeln(t.owes(bill.ps[from].name, bill.ps[to].name, '${money(c, de: t.de)} €'));
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(bill.purpose.isEmpty ? t.appName : bill.purpose),
        actions: [
          IconButton(
            tooltip: t.edit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(bill: bill))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'log') shareRecognitionLog(context, bill);
              if (v == 'del') {
                store.remove(bill);
                Navigator.of(context).maybePop();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'log', child: Text(t.shareLog)),
              PopupMenuItem(value: 'del', child: Text(t.deleteBill)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.xxxl),
        children: [
          Money(bill.effectiveTotal, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: FasanSpace.l),
          if (bill.payer != null) ResultBody(bill: bill) else Text(t.whoPaid),
          const SizedBox(height: FasanSpace.xl),
          FasanButton(label: t.shareText, icon: Icons.ios_share_rounded, expand: true, onPressed: () => SharePlus.instance.share(ShareParams(text: _text(t)))),
          const SizedBox(height: FasanSpace.s),
          FasanButton(
            label: t.exportCsv,
            icon: Icons.table_view_outlined,
            kind: FasanButtonKind.secondary,
            expand: true,
            onPressed: () => SharePlus.instance.share(ShareParams(files: [
              XFile.fromData(Uint8List.fromList(utf8.encode(billCsv(bill, de: t.de))), mimeType: 'text/csv', name: 'fasan-split.csv'),
            ])),
          ),
        ],
      ),
    );
  }
}
