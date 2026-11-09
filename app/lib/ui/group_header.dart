// SPDX-License-Identifier: MPL-2.0
// Fasan Split – group header (count · price · people) with a progress frame, and the flat item list of a group. MPL-2.0
//
// Nutzer 08.11. 04:09/04:16 + Beschluss 08.11. 21:06: the group gets a framed header. Left: number of bills. Middle: the total price,
// tappable (opens the settlement view). Right: person symbol + count, tappable (opens the members). The frame is split by item state
// (done green | in progress amber | open red, left to right, width by count). Colour is never the only signal: the line under the
// header names the three counts with their icons (Regelwerk 1.8, Prüfliste W10).
// Performance (docs/recherche/2026-11-09-reale-und-gefuehlte-leistung.md §4): the frame is painted once from three numbers, the item
// list is lazy (SliverList), rows have no shadow or blur.
import 'dart:math' as math;

import 'package:fasan_core/bill.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../l10n/tr.dart';
import 'common.dart';
import 'flow.dart' show ResultScreen;
import 'resume.dart' show ResumeFlow;
import 'scope.dart';

/// Opens a bill the way the tile does: finished bills show the result, unfinished ones continue where the user left.
void openBill(BuildContext context, Bill bill) {
  CollabScope.read(context).billSeen(bill.id);
  markBillOrigin(context);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => bill.done ? ResultScreen(bill: bill) : ResumeFlow(bill: bill)));
}

/// Counts of items by state over [bills] (settlement payments are no spending and have no items to track).
({int done, int partial, int open}) itemCounts(Iterable<Bill> bills) {
  var d = 0, p = 0, o = 0;
  for (final b in bills) {
    if (b.isTransfer) continue;
    for (final it in b.its) {
      switch (it.fill) {
        case ItemFill.complete:
          d++;
        case ItemFill.partial:
          p++;
        case ItemFill.open:
          o++;
      }
    }
  }
  return (done: d, partial: p, open: o);
}

/// Bills without a payer (a finished-looking bill nobody paid yet): „nicht eingetragene Bezahlung“ (Nutzer 08.11. 21:15, Lesart a).
int billsWithoutPayer(Iterable<Bill> bills) => bills.where((b) => !b.isTransfer && b.its.isNotEmpty && b.payer == null && !b.multiPay).length;

class GroupHeader extends StatelessWidget {
  const GroupHeader({super.key, required this.bills, required this.people, required this.onPrice, required this.onPeople});

  final List<Bill> bills;
  final int people;
  final VoidCallback onPrice;
  final VoidCallback onPeople;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final lang = t.de ? 'de' : 'en';
    final spend = bills.where((b) => !b.isTransfer).toList();
    final sum = spend.fold<int>(0, (a, b) => a + b.effectiveTotal);
    final c = itemCounts(bills);
    final r = l.radius * 0.7;
    final tap = math.max(l.minTap, 48.0);
    return Semantics(
      container: true,
      label: trLang(lang, 'grp.progressLabel', ['${c.done}', '${c.partial}', '${c.open}']),
      child: CustomPaint(
        foregroundPainter: _FramePainter(
          radius: r,
          done: c.done,
          partial: c.partial,
          open: c.open,
          colors: (fillColor(context, ItemFill.complete), fillColor(context, ItemFill.partial), fillColor(context, ItemFill.open)),
          idle: l.hairline,
        ),
        child: Container(
          constraints: BoxConstraints(minHeight: tap + 8),
          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.xs),
          decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(r)),
          child: Row(children: [
            Expanded(child: Text(t.billsCount(spend.length), style: tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Semantics(
              button: true,
              label: trLang(lang, 'grp.settlementTip'),
              child: InkWell(
                borderRadius: BorderRadius.circular(r),
                onTap: onPrice,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: tap, minWidth: tap),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: FasanSpace.s),
                      child: Text('${money(sum, de: t.de)} ${signOf(context)}', style: tt.titleMedium!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  button: true,
                  label: trLang(lang, 'grp.peopleTip'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(r),
                    onTap: onPeople,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: tap, minWidth: tap),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.group_outlined, color: l.accent),
                        const SizedBox(width: 4),
                        Text('$people', style: tt.titleMedium),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Paints the rounded frame in three coloured stretches (done | in progress | open) clockwise from the upper left; plain hairline
/// when there are no items. Static: repainted only when a count changes.
class _FramePainter extends CustomPainter {
  _FramePainter({required this.radius, required this.done, required this.partial, required this.open, required this.colors, required this.idle});

  final double radius;
  final int done, partial, open;
  final (Color, Color, Color) colors;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(1);
    final path = Path()..addRRect(rect);
    final total = done + partial + open;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.butt;
    if (total == 0) {
      canvas.drawPath(path, p..color = idle);
      return;
    }
    final m = path.computeMetrics().first;
    var from = 0.0;
    void seg(int n, Color c) {
      if (n == 0) return;
      final len = m.length * n / total;
      canvas.drawPath(m.extractPath(from, from + len), p..color = c);
      from += len;
    }

    seg(done, colors.$1);
    seg(partial, colors.$2);
    seg(open, colors.$3);
  }

  @override
  bool shouldRepaint(_FramePainter o) => o.done != done || o.partial != partial || o.open != open || o.radius != radius || o.idle != idle || o.colors != colors;
}

/// One line under the header with the three counts and their icons, plus what is missing (shown only when something is).
class GroupCountsLine extends StatelessWidget {
  const GroupCountsLine({super.key, required this.bills, required this.onOpenItems});

  final List<Bill> bills;
  final VoidCallback onOpenItems;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final lang = t.de ? 'de' : 'en';
    final c = itemCounts(bills);
    final noPayer = billsWithoutPayer(bills);
    Widget chip(ItemFill f, int n) => Padding(
          padding: const EdgeInsets.only(right: FasanSpace.m),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(fillIcon(f), size: 16, color: fillColor(context, f)),
            const SizedBox(width: 4),
            Text('$n', style: tt.labelLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    final missing = [
      if (c.open + c.partial > 0) trLang(lang, 'grp.openItems', ['${c.open + c.partial}']),
      if (noPayer > 0) trLang(lang, 'grp.noPayer', ['$noPayer']),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: FasanSpace.s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [chip(ItemFill.complete, c.done), chip(ItemFill.partial, c.partial), chip(ItemFill.open, c.open)]),
        if (missing.isNotEmpty)
          InkWell(
            onTap: onOpenItems,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FasanSpace.xs),
              child: Text(missing.join(' · '), style: tt.bodySmall!.copyWith(color: l.textMuted)),
            ),
          ),
      ]),
    );
  }
}

/// One item as in the bill: name, amount, state icon and who shares it. Same frame colours as the bill list (fillSide).
/// [onTap] normally opens the bill the item belongs to.
class GroupItemRow extends StatelessWidget {
  const GroupItemRow({super.key, required this.bill, required this.item, this.onTap});

  final Bill bill;
  final BillItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final r = BorderRadius.circular(l.radius * 0.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: l.minTap),
          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: 8),
          decoration: BoxDecoration(borderRadius: r, border: Border.fromBorderSide(fillSide(context, item.fill))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: ItemTitle(item, maxLines: 1)), const SizedBox(width: FasanSpace.m), Money(item.amount)]),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [Icon(fillIcon(item.fill), size: 16, color: fillColor(context, item.fill)), const SizedBox(width: 6), ShareAvatars(bill: bill, item: item)]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Entries of the flat list: a bill heading ([item] null) followed by its visible items.
List<(Bill, BillItem?)> flattenItems(Iterable<Bill> bills, {required bool onlyOpen}) {
  final out = <(Bill, BillItem?)>[];
  for (final b in bills) {
    if (b.isTransfer) continue;
    final its = onlyOpen ? b.its.where((i) => i.fill != ItemFill.complete).toList() : b.its;
    if (its.isEmpty) continue;
    out.add((b, null));
    for (final i in its) {
      out.add((b, i));
    }
  }
  return out;
}

/// Heading of one bill in the flat item list (fixed height so the list can be built lazily).
class GroupBillHeading extends StatelessWidget {
  const GroupBillHeading({super.key, required this.bill, this.onTap});

  final Bill bill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = bill.receiptDate ?? bill.created;
    final day = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${bill.purpose.isEmpty ? S.of(context).newBill : bill.purpose} · $day', maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleSmall),
          ),
        ),
      ),
    );
  }
}
