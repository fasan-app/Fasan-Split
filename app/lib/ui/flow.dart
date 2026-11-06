// Fasan Split – the bill flow: 1 total and purpose, 2 who was there, 3 assign, 4 who paid + result. MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../l10n/tr.dart';
import '../l10n_bill.dart';
import '../main.dart';
import '../app/scan_queue.dart';
import '../state/images.dart';
import '../model/bill.dart';
import 'category_ui.dart';
import 'currency_ui.dart';
import 'collab_ui.dart';
import 'bill_notes.dart';
import 'my_balance.dart' show myNames;
import 'pay_ui.dart';
import 'payers.dart';
import 'common.dart';
import 'diagnose.dart';

// The bill screen (total, people, who paid, items) lives in bill_screen.dart; ReviewScreen is its name here for the old imports.
import 'bill_screen.dart' show ReviewScreen;
import 'marquee_text.dart';
export 'bill_screen.dart' show ReviewScreen;

/// „Bon neu lesen“: after asking, the newest recognition reads the original photo again (ScanQueue.reread).
Future<void> rereadFlow(BuildContext context, Bill bill) async {
  final t = S.of(context), q = ScanQueue.current, path = bill.originalPath;
  if (q == null || path == null) return;
  final ok = await confirmDialog(
    context,
    t.de ? 'Bon neu lesen' : 'Read receipt again',
    t.de
        ? 'Die Posten werden mit der neuesten Erkennung neu gelesen. Die Zuordnung der Posten geht dabei verloren. Personen, Zahler, Gruppe, Kategorie und Name bleiben.'
        : 'The items are read again with the newest recognition. The assignment of the items is lost; people, payer, group, category and name stay.',
    t.de ? 'Neu lesen' : 'Read again',
  );
  if (!ok || !context.mounted) return;
  final bytes = await readImage(path);
  if (bytes == null || !context.mounted) return;
  await q.reread(bill, bytes);
  if (context.mounted) closeBillFlow(context);
}

/// Adds [name] to the bill with the first free colour; false if the name is there already.
bool addPersonTo(Bill b, String name) {
  final n = name.trim();
  if (n.isEmpty || b.ps.any((p) => p.name.toLowerCase() == n.toLowerCase())) return false;
  final used = b.ps.map((p) => p.color).toSet();
  var c = 0;
  while (used.contains(c) && c < 64) {
    c++;
  }
  b.ps.add(Person(n, c));
  return true;
}

/// Removes person [i]; shares and payer move with the indices.
void removePersonFrom(Bill b, int i) => b.removePerson(i);

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

  // Step 4 is the summary (Nutzer 04.11.: the old „Wer hat bezahlt?“ screen asked again what step 3 already knew and
  // raised question marks). Who paid stays changeable in one small row; the result is the main thing; „Eintragen“ puts
  // the bill under Offen, it counts in the balances, and goes to the archive once it is settled.
  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    return StepScaffold(
      title: t.de ? 'Übersicht' : 'Summary',
      step: 4,
      bill: b,
      action: t.de ? 'Eintragen' : 'Save',
      onAction: b.payer == null || b.paidGap != 0
          ? null
          : () {
              // The numbers are checked twice (Beschluss 03.11.): a mismatch stops here, nothing is saved as finished.
              if (b.audit().isNotEmpty) {
                FasanHaptics.of(context).warn();
                showNote(context, t.splitCheckBad, duration: const Duration(seconds: 6));
                return;
              }
              b.done = true;
              if (b.transfers().isEmpty) b.settled = true; // nobody owes anything: nothing to settle
              StoreScope.read(context).upsert(b);
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => ResultScreen(bill: b)), isBillOrigin);
            },
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context)),
        children: [
          // who paid: the same sheet as in the bill screen (one way to do it)
          Row(children: [
            Text('${context.tr('bill.paidBy')}:', style: tt.labelLarge!.copyWith(color: l.textMuted)),
            const SizedBox(width: FasanSpace.s),
            ActionChip(
              key: const ValueKey('payer'),
              avatar: Icon(Icons.payments_outlined, size: 18, color: b.payer == null ? l.accent : null),
              label: Text(b.payer == null ? context.tr('bill.paidByNone') : payersSummary(context, b)),
              onPressed: () => showPayersSheet(context, b, changed: () => setState(() {})),
            ),
          ]),
          if (b.advance > 0) ...[
            const SizedBox(height: FasanSpace.m),
            Text('${t.advance}: ${money(b.advance, de: t.de)} ${billSign(context, b)}', style: tt.bodyMedium),
          ],
          const SizedBox(height: FasanSpace.l),
          if (b.payer != null) ...[
            ResultBody(bill: b),
            const SizedBox(height: FasanSpace.m),
            Text(
              t.de
                  ? 'Nach „Eintragen“ steht der Bon unter Offen und zählt im Saldo. Ins Archiv kommt er, wenn alles bezahlt ist.'
                  : 'After “Save” the receipt is under Open and counts in the balances. It goes to the archive once everything is paid.',
              style: tt.bodySmall!.copyWith(color: l.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Marks a bill as refund (money came back): the payer passes the others' share on. Shown in Review and Result.
class RefundNote extends StatelessWidget {
  const RefundNote({super.key});

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Row(children: [
      Icon(Icons.undo_rounded, size: 18, color: FasanLook.of(context).accent),
      const SizedBox(width: FasanSpace.s),
      Expanded(child: Text('${t.refundBadge}. ${t.refundHint}', style: Theme.of(context).textTheme.bodySmall)),
    ]);
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
      if (bill.difference != 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${t.differenceSpread}: ${money(bill.difference, de: t.de, sign: true)} ${billSign(context, bill)}', style: tt.bodySmall)),
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
            Expanded(child: Text(t.owes(bill.ps[from].name, bill.ps[to].name, '${money(c, de: t.de)} ${billSign(context, bill)}'), style: tt.bodyMedium)),
            // I owe: pay right here (Nutzer 04.11.; pay_ui.dart)
            if (myNames(context)(bill.ps[from].name) && !bill.settled)
              TextButton(
                onPressed: () {
                  final live = bill.group == null ? null : CollabScope.read(context).groupByLocalName(bill.group!);
                  payFlow(context, name: bill.ps[to].name, pub: live?.session.memberOfPerson(bill.ps[to].name), cents: c, currency: bill.currency ?? StoreScope.read(context).homeCurrency, purpose: bill.purpose);
                },
                child: Text(t.de ? 'Bezahlen' : 'Pay'),
              ),
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
        title: Text(ok ? '${t.splitCheck}: ${money(total, de: t.de)} ${billSign(context, bill)}' : t.splitCheckBad, style: tt.bodyMedium!.copyWith(color: color)),
        children: [
          for (var p = 0; p < bill.ps.length; p++) ...[
            Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(bill.ps[p].name, style: tt.labelLarge))),
            for (var n = 0; n < bill.its.length; n++)
              if (bill.partsOf(n)[p] case final c? when c != 0)
                Row(children: [
                  Expanded(child: MarqueeText(bill.its[n].title, style: tt.bodySmall)),
                  Text('${money(c, de: t.de)} ${billSign(context, bill)}', style: tt.bodySmall),
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

  String _text(S t, String cur) {
    final b = StringBuffer('${bill.purpose.isEmpty ? t.appName : bill.purpose}: ${money(bill.effectiveTotal, de: t.de)} $cur${bill.refund ? ' (${t.refundBadge})' : ''}\n');
    final pp = bill.perPerson();
    for (var i = 0; i < bill.ps.length; i++) {
      b.writeln('${bill.ps[i].name}: ${money(pp[i] ?? 0, de: t.de)} $cur');
    }
    for (final (from, to, c) in bill.transfers()) {
      b.writeln(t.owes(bill.ps[from].name, bill.ps[to].name, '${money(c, de: t.de)} $cur'));
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final store = StoreScope.of(context);
    return CurrencyScope(code: bill.currency ?? store.homeCurrency, child: Scaffold(
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
              if (v == 'reread') rereadFlow(context, bill);
              if (v == 'del') {
                store.remove(bill);
                Navigator.of(context).maybePop();
              }
            },
            itemBuilder: (_) => [
              if (imageExists(bill.originalPath)) PopupMenuItem(value: 'reread', child: Text(t.de ? 'Bon neu lesen' : 'Read receipt again')),
              PopupMenuItem(value: 'log', child: Text(t.shareLog)),
              PopupMenuItem(value: 'del', child: Text(t.deleteBill)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.xxxl),
        children: [
          PinnedNotes(bill: bill),
          Money(bill.effectiveTotal, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: FasanSpace.s),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [CategoryChip(bill: bill), CurrencyChip(bill: bill)]),
          ),
          if (bill.refund) ...[const SizedBox(height: FasanSpace.s), const RefundNote()],
          const SizedBox(height: FasanSpace.l),
          if (bill.payer != null) ResultBody(bill: bill) else Text(t.whoPaid),
          const SizedBox(height: FasanSpace.l),
          BillNotes(bill: bill),
          const SizedBox(height: FasanSpace.xl),
          // Nutzer 04.11.: the archive is for bills that are paid back; this is where one says so
          if (bill.done && bill.payer != null && bill.transfers().isNotEmpty) ...[
            FasanButton(
              label: bill.settled ? (t.de ? 'Wieder offen (nicht bezahlt)' : 'Open again (not paid)') : (t.de ? 'Alles bezahlt – ausgleichen' : 'All paid – settle'),
              icon: bill.settled ? Icons.undo_rounded : Icons.task_alt_rounded,
              kind: bill.settled ? FasanButtonKind.secondary : FasanButtonKind.primary,
              expand: true,
              onPressed: () {
                final settled = !bill.settled;
                store.setSettled([bill], settled);
                showNote(context, settled ? t.archivedN(1) : t.reopenedN(1));
                if (settled) Navigator.of(context).maybePop();
              },
            ),
            const SizedBox(height: FasanSpace.s),
          ],
          FasanButton(label: t.shareText, icon: Icons.ios_share_rounded, kind: FasanButtonKind.secondary, expand: true, onPressed: () => SharePlus.instance.share(ShareParams(text: _text(t, billSign(context, bill))))),
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
    ));
  }
}
