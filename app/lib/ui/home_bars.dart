// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the bars of the start page: navigation, selection bar, drop dock while dragging, drag feedback. Split out of
// home.dart (13.11., Umbau, behaviour unchanged). MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import '../l10n.dart';
import 'package:fasan_core/bill.dart';
import '../state/images.dart';
import 'shape_tokens.dart';

/// Which list of bills a page shows.
enum BillList { open, archive, trash }

/// The three main places (Rechnungen, Gruppen, Freunde) as a glass bar at the bottom: icon and label, colour for the active
/// one (no check marks; Nutzer 02.11.). Material 3: a navigation bar holds three to five destinations.
class HomeNavBar extends StatelessWidget {
  const HomeNavBar({super.key, required this.selected, required this.onSelect, this.onDropGroup, this.badges = const [0, 0, 0]});

  /// Unread messages per tab (Nutzer 04.11.: indicators for new messages).
  final List<int> badges;

  final int selected;
  final ValueChanged<int> onSelect;

  /// While bills are dragged: the Gruppen tab takes them.
  final void Function(List<Bill>)? onDropGroup;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context);
    final items = [
      (Icons.receipt_long_outlined, Icons.receipt_long_rounded, t.billsTab),
      (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, t.groupsTab),
      (Icons.people_outline_rounded, Icons.people_rounded, t.friendsTab),
    ];
    return Padding(
      // same side margin as the cards above (Nutzer 04.11.: surfaces of different width)
      padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s + MediaQuery.paddingOf(context).bottom),
      // fixed height: the glass fills the space it is given, and the Scaffold gives its bottom bar all the height there is
      child: SizedBox(
        height: l.minTap + 24, // slimmer (Nutzer 09.11.), still symbol and word
        child: FasanGlass(
        padding: const EdgeInsets.all(4),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                selected: i == selected,
                button: true,
                label: items[i].$3,
                child: DragTarget<List<Bill>>(
                  onWillAcceptWithDetails: (_) => i == 1 && onDropGroup != null,
                  onAcceptWithDetails: (d) => onDropGroup?.call(d.data),
                  builder: (context, cand, _) => InkWell(
                  borderRadius: BorderRadius.circular(l.rCard),
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: FasanMotion.of(context).short,
                    curve: FasanCurves.short,
                    constraints: BoxConstraints(minHeight: l.minTap),
                    decoration: BoxDecoration(
                        color: cand.isNotEmpty
                            ? l.accent.withValues(alpha: 0.3)
                            : i == selected || (i == 1 && onDropGroup != null)
                                ? l.accent.withValues(alpha: 0.14)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(l.rCard)),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Badge(
                        isLabelVisible: badges[i] > 0,
                        label: Text(badges[i] > 99 ? '99+' : '${badges[i]}'),
                        child: Icon(i == selected ? items[i].$2 : items[i].$1, color: i == selected ? l.accent : l.textMuted, size: 24),
                      ),
                      const SizedBox(height: 2),
                      Text(items[i].$3, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: i == selected ? l.accent : l.textMuted, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500)),
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

/// What follows the finger while bills are dragged: a small stack of the receipts with their number (Nutzer 04.11.:
/// the full-width card covered where it would land).
class HomeDragFeedback extends StatelessWidget {
  const HomeDragFeedback({super.key, required this.bills});

  final List<Bill> bills;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final shown = bills.take(3).toList();
    Widget card(Bill b) => Container(
          width: 56,
          height: 72,
          decoration: BoxDecoration(
            color: l.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: l.accent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          clipBehavior: Clip.antiAlias,
          child: imageExists(b.imagePath)
              ? Image(image: ResizeImage(imageProvider(b.imagePath!), width: 120), fit: BoxFit.cover, gaplessPlayback: true)
              : Icon(Icons.receipt_long_rounded, color: l.textMuted),
        );
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 88,
        height: 96,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(left: 6.0 * i, top: 4.0 * i, child: Transform.rotate(angle: (i - 1) * 0.06, child: card(shown[i]))),
          if (bills.length > 1)
            Positioned(
              right: 0,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: l.accent, borderRadius: BorderRadius.circular(12)),
                child: Text('${bills.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// While bills are dragged the bottom bar becomes the drop targets (Nutzer 04.11.: „beim Verschieben auf den darunter
/// liegenden Papierkorb muss er deutlich animiert zeigen, dass beim Loslassen gelöscht wird – systemweit die Regel“).
/// The target under the finger grows, takes its colour and says what happens on release.
/// Bottom bar of the selection mode: same size as the navigation bar, one clear action „Schicken (N)“ (Nutzer 12.11.).
class HomeSelectBar extends StatelessWidget {
  const HomeSelectBar({super.key, required this.count, required this.onSend});

  final int count;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), lang = S.of(context).de ? 'de' : 'en';
    return Padding(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s + MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: l.minTap + 24,
        child: Center(
          child: FasanButton(key: const ValueKey('select-send'), label: trLang(lang, 'select.send', ['$count']), onPressed: onSend),
        ),
      ),
    );
  }
}

class HomeDropDock extends StatelessWidget {
  const HomeDropDock({super.key, required this.from, required this.onList, required this.onGroup});

  final BillList from;
  final void Function(List<Bill>, BillList) onList;
  final void Function(List<Bill>) onGroup;

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, l = FasanLook.of(context);
    final targets = <(IconData, String, String, Color, void Function(List<Bill>))>[
      if (from != BillList.open) (Icons.inbox_rounded, trLang(de ? 'de' : 'en', 'home.open'), trLang(de ? 'de' : 'en', 'home.releaseOpenAgain'), l.accent, (b) => onList(b, BillList.open)),
      (Icons.folder_rounded, trLang(de ? 'de' : 'en', 'home.group'), trLang(de ? 'de' : 'en', 'home.releaseChooseAGroup'), l.accent, onGroup),
      if (from != BillList.archive) (Icons.task_alt_rounded, trLang(de ? 'de' : 'en', 'home.settle'), trLang(de ? 'de' : 'en', 'home.releasePaidToThe'), Colors.green.shade600, (b) => onList(b, BillList.archive)),
      if (from != BillList.trash) (Icons.delete_rounded, trLang(de ? 'de' : 'en', 'home.trash'), trLang(de ? 'de' : 'en', 'home.releaseToTheTrash'), Colors.red.shade600, (b) => onList(b, BillList.trash)),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s + MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: l.minTap + 24, // as high as the navigation bar: the bottom does not jump when dragging starts (Nutzer 12.11.)
        child: Row(children: [
          for (final (icon, label, action, color, drop) in targets)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: DragTarget<List<Bill>>(
                  onWillAcceptWithDetails: (_) {
                    FasanHaptics.of(context).tap(); // entering a target is felt
                    return true;
                  },
                  onAcceptWithDetails: (d) => drop(d.data),
                  builder: (context, cand, _) {
                    final over = cand.isNotEmpty;
                    final motion = FasanMotion.of(context);
                    return AnimatedScale(
                      duration: motion.short,
                      curve: Curves.easeOutBack,
                      scale: over ? 1.08 : 1,
                      child: AnimatedContainer(
                        duration: motion.short,
                        curve: FasanCurves.short,
                        decoration: BoxDecoration(
                          color: over ? color : color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(l.rCard),
                          border: Border.all(color: color.withValues(alpha: over ? 1 : 0.5), width: 1.5),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedScale(duration: motion.short, scale: over ? 1.25 : 1, child: Icon(icon, color: over ? Colors.white : color, size: 22)),
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(over ? action : label,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall!.copyWith(color: over ? Colors.white : color, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

