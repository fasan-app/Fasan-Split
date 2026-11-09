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
import 'shape_tokens.dart';
import 'bill_screen.dart' show ItemTile, ReviewScreen;

/// Opens a bill the way the tile does: finished bills show the result, unfinished ones continue where the user left.
void openBill(BuildContext context, Bill bill, {int? focusItem}) {
  CollabScope.read(context).billSeen(bill.id);
  markBillOrigin(context);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => focusItem != null
      ? (bill.done ? ReviewScreen(bill: bill, focusItem: focusItem) : ResumeFlow(bill: bill, focusItem: focusItem))
      : (bill.done ? ResultScreen(bill: bill) : ResumeFlow(bill: bill))));
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
    final r = l.rCard;
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
/// True when [b] passes the status buttons: some item with a chosen state ([fills] empty = no filter), and, when [noPayer] is on,
/// only bills nobody paid yet (Nutzer 09.11.: the numbers are filters).
bool billMatches(Bill b, Set<ItemFill> fills, bool noPayer) {
  if (noPayer && !(!b.isTransfer && b.its.isNotEmpty && b.payer == null && !b.multiPay)) return false;
  if (fills.isEmpty) return true;
  return b.its.any((i) => fills.contains(i.fill));
}

/// The row under the frame: three state buttons (done, in progress, open) with their counts, the „no payer“ button and a „?“.
/// Every button is a switch (Nutzer 09.11.): filled and coloured = on, outlined = off; the counts always show the whole scope, so
/// they stay put while filtering. Symbols and numbers only, so no text shifts the row in another language; the explanation sits
/// behind the „?“ (docs/KONZEPT-STARTBILDSCHIRM.md).
class GroupCountsLine extends StatelessWidget {
  const GroupCountsLine({super.key, required this.bills, required this.fills, required this.noPayer, required this.onFills, required this.onNoPayer});

  final List<Bill> bills;
  final Set<ItemFill> fills;
  final bool noPayer;
  final ValueChanged<Set<ItemFill>> onFills;
  final ValueChanged<bool> onNoPayer;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context);
    final lang = t.de ? 'de' : 'en';
    final c = itemCounts(bills);
    final np = billsWithoutPayer(bills);
    Widget chip(String key, IconData icon, Color color, int n, bool on, VoidCallback onTap, String label) => Padding(
          padding: const EdgeInsets.only(right: FasanSpace.s),
          child: StateChip(key: ValueKey('chip-$key'), icon: icon, color: color, count: n, on: on, onTap: onTap, label: label),
        );
    void toggle(ItemFill f) => onFills(fills.contains(f) ? ({...fills}..remove(f)) : {...fills, f});
    return SizedBox(
      height: 48,
      child: Row(children: [
        chip('done', fillIcon(ItemFill.complete), fillColor(context, ItemFill.complete), c.done, fills.contains(ItemFill.complete), () => toggle(ItemFill.complete), trLang(lang, 'grp.fDone')),
        chip('partial', fillIcon(ItemFill.partial), fillColor(context, ItemFill.partial), c.partial, fills.contains(ItemFill.partial), () => toggle(ItemFill.partial), trLang(lang, 'grp.fPartial')),
        chip('open', fillIcon(ItemFill.open), fillColor(context, ItemFill.open), c.open, fills.contains(ItemFill.open), () => toggle(ItemFill.open), trLang(lang, 'grp.fOpen')),
        const Spacer(),
        if (np > 0) chip('nopayer', Icons.account_balance_wallet_outlined, l.accent, np, noPayer, () => onNoPayer(!noPayer), trLang(lang, 'grp.fNoPayer')),
        HelpButton(title: trLang(lang, 'grp.helpTitle'), body: trLang(lang, 'grp.helpBody')),
      ]),
    );
  }
}

/// A state button: pill with symbol and number. On = filled in its colour with a visible edge, off = hairline edge.
class StateChip extends StatelessWidget {
  const StateChip({super.key, required this.icon, required this.color, required this.count, required this.on, required this.onTap, required this.label});

  final IconData icon;
  final Color color;
  final int count;
  final bool on;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      toggled: on,
      label: '$label: $count',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(
            child: AnimatedContainer(
              duration: FasanMotion.of(context).short,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: on ? color.withValues(alpha: 0.22) : Colors.transparent,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: on ? color : l.hairline, width: on ? 2 : 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text('$count', style: tt.labelLarge!.copyWith(fontWeight: on ? FontWeight.w800 : FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The „?“ next to a title or a row: opens a sheet with the explanation (Nutzer 09.11.: short titles, long text on request).
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    return IconButton(
      tooltip: title,
      icon: Icon(Icons.help_outline_rounded, size: 20, color: l.textMuted),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.l),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: FasanSpace.s),
              Text(body, style: Theme.of(ctx).textTheme.bodyMedium),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One item as in the bill: name, amount, state icon and who shares it. Same frame colours as the bill list (fillSide).
/// [onTap] normally opens the bill the item belongs to.
class GroupItemRow extends StatelessWidget {
  const GroupItemRow({super.key, required this.bill, required this.item, this.onTap, this.onLongPress});

  final Bill bill;
  final BillItem item;
  final VoidCallback? onTap, onLongPress;

  /// The same tile as in the bill, with the receipt snippet (Nutzer 09.11. 18:44), so an item looks the same wherever it is.
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ItemTile(bill: bill, item: item, active: null, showSnippet: true, onTap: onTap ?? () {}, onLongPress: onLongPress ?? onTap ?? () {}),
      );
}

/// The line „rest to the total“ under the items of a bill in the flat list (service, tip, an unread line).
class GroupRestRow extends StatelessWidget {
  const GroupRestRow({super.key, required this.bill, this.onTap});

  final Bill bill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), r = BorderRadius.circular(l.rInner);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: l.minTap),
          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: 8),
          decoration: BoxDecoration(borderRadius: r, border: Border.all(color: l.hairline)),
          child: Row(children: [
            Icon(Icons.percent_rounded, size: 18, color: l.textMuted),
            const SizedBox(width: FasanSpace.s),
            Expanded(child: Text(trLang(S.of(context).de ? 'de' : 'en', 'grp.rest'), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: FasanSpace.m),
            Money(bill.difference),
          ]),
        ),
      ),
    );
  }
}

/// Marks the line „rest to the receipt total“ (service, tip, an unread line) in the flat list: not an item, but money that is split
/// like the items, so it must show (Nutzer 09.11. 18:44: „Service … müssen erscheinen“). Compare by identity.
final BillItem kDifferenceRow = BillItem(name: '', amount: 0);

/// Entries of the flat list: a bill heading ([item] null) followed by its visible items.
/// [fills] (the status buttons) wins over [onlyOpen]: with „erledigt“ switched on, the items that are done must show even when
/// „Nur offene Posten“ is on (Nutzer 09.11. 18:44: the button showed nothing). [itemMatch] narrows the items to the search.
List<(Bill, BillItem?)> flattenItems(Iterable<Bill> bills, {required bool onlyOpen, Set<ItemFill> fills = const {}, bool Function(Bill, BillItem)? itemMatch}) {
  final out = <(Bill, BillItem?)>[];
  for (final b in bills) {
    if (b.isTransfer) continue;
    final its = b.its
        .where((i) => fills.isNotEmpty ? fills.contains(i.fill) : (!onlyOpen || i.fill != ItemFill.complete))
        .where((i) => itemMatch == null || itemMatch(b, i))
        .toList();
    // the rest to the total shows only in the plain list: not under a status button or a search, not with „Nur offene“
    final rest = fills.isEmpty && itemMatch == null && !onlyOpen && b.difference != 0 && b.its.isNotEmpty;
    if (its.isEmpty && !rest) continue;
    out.add((b, null));
    for (final i in its) {
      out.add((b, i));
    }
    if (rest) out.add((b, kDifferenceRow));
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
