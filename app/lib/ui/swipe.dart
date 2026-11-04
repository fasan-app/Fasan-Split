// Fasan Split – swipe a card to act on it (archive, trash, restore). The background lies under the card as one rounded
// surface (Dismissible clips its own background straight at the card edge, which looked square next to the rounded
// card, Nutzer 04.11.). Icon and label fade and grow in with the swipe distance instead of appearing at once. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

/// One side of a swipe: what it does, in which colour.
class SwipeSide {
  const SwipeSide(this.icon, this.label, this.color);

  final IconData icon;
  final String label;
  final Color color;
}

class SwipeActions extends StatefulWidget {
  const SwipeActions({super.key, required this.id, required this.child, this.start, this.end, required this.onDismissed, this.confirmDismiss, this.enabled = true});

  /// Stable id of the item (the Dismissible's key).
  final String id;
  final Widget child;

  /// Swipe to the right ([start]) and to the left ([end]); null = not possible.
  final SwipeSide? start, end;
  final void Function(DismissDirection) onDismissed;
  final ConfirmDismissCallback? confirmDismiss;
  final bool enabled;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions> {
  final _p = ValueNotifier<(DismissDirection, double)>((DismissDirection.none, 0));

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final r = BorderRadius.circular(l.radius * 0.7); // same as BillTile
    final dir = !widget.enabled
        ? DismissDirection.none
        : widget.start != null && widget.end != null
            ? DismissDirection.horizontal
            : widget.start != null
                ? DismissDirection.startToEnd
                : widget.end != null
                    ? DismissDirection.endToStart
                    : DismissDirection.none;
    return Stack(children: [
      Positioned.fill(
        child: ValueListenableBuilder<(DismissDirection, double)>(
          valueListenable: _p,
          builder: (context, v, _) {
            final (d, p) = v;
            final side = d == DismissDirection.startToEnd ? widget.start : (d == DismissDirection.endToStart ? widget.end : null);
            if (side == null || p <= 0) return const SizedBox.shrink();
            final k = Curves.easeOutCubic.transform(((p - 0.04) / 0.3).clamp(0.0, 1.0));
            final ground = Curves.easeOut.transform((p / 0.15).clamp(0.0, 1.0));
            return DecoratedBox(
              decoration: BoxDecoration(color: side.color.withValues(alpha: 0.18 * ground), borderRadius: r),
              child: Align(
                alignment: d == DismissDirection.startToEnd ? Alignment.centerLeft : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
                  child: Opacity(
                    opacity: k,
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * k,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(side.icon, color: side.color),
                        const SizedBox(width: 8),
                        Text(side.label, style: TextStyle(color: side.color, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      Dismissible(
        key: ValueKey('swipe-${widget.id}'),
        direction: dir,
        onUpdate: (u) => _p.value = (u.direction, u.progress),
        confirmDismiss: widget.confirmDismiss,
        onDismissed: widget.onDismissed,
        child: widget.child,
      ),
    ]);
  }
}
