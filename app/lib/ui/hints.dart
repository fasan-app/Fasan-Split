// SPDX-License-Identifier: MPL-2.0
// Fasan Split – hints at the place where the next step is (Nutzer 03.11.: „nicht selbst erklärend“). MPL-2.0
//
// Rules: short sentences, one hint at a time, each can be closed with one tap and never comes back by itself; the
// settings can show them all again. A pulsing ring marks the control to use next (motion follows „Animationen entfernen“).
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import 'package:fasan_core/bill.dart';

import '../l10n.dart';
import '../l10n/tr.dart';
import 'scope.dart';

/// Inline hint card with an icon, up to two sentences and „Verstanden“. Shows only while [id] is not dismissed.
class HintCard extends StatelessWidget {
  const HintCard({super.key, required this.id, required this.text, this.icon = Icons.lightbulb_outline_rounded});

  final String id;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final l = FasanLook.of(context);
    final t = S.of(context);
    final show = !store.hintDone(id);
    return FasanReveal(
      show: show,
      child: Padding(
        padding: const EdgeInsets.only(bottom: FasanSpace.m),
        child: Container(
          padding: const EdgeInsets.fromLTRB(FasanSpace.m, FasanSpace.m, FasanSpace.s, FasanSpace.s),
          decoration: BoxDecoration(
            color: Color.alphaBlend(l.accent.withValues(alpha: 0.10), l.surface),
            borderRadius: BorderRadius.circular(l.radius * 0.7),
            border: Border.all(color: l.accent.withValues(alpha: 0.35)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: l.accent)),
            const SizedBox(width: FasanSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: Theme.of(context).textTheme.bodyMedium),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      FasanHaptics.of(context).tap();
                      store.hintDismiss(id);
                    },
                    child: Text(t.hintOk),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A ring that breathes around [child] while [active]: „use this next“. Still ring without motion.
class PulseRing extends StatefulWidget {
  const PulseRing({super.key, required this.child, required this.active, this.radius = 18});

  final Widget child;
  final bool active;
  final double radius;

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final move = FasanMotion.of(context).enabled;
    if (widget.active && move) {
      if (!_c.isAnimating && !_done) {
        _done = true; // breathes three times, then stays a still ring: an endless animation repainted the start page all the time (Nutzer 08.11.)
        _c.repeat(count: 3);
      }
    } else {
      _c.stop();
    }
  }

  @override
  void didUpdateWidget(PulseRing old) {
    super.didUpdateWidget(old);
    didChangeDependencies();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final l = FasanLook.of(context);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = _c.isAnimating ? Curves.easeOut.transform(_c.value) : 0.5;
        return DecoratedBox(
          position: DecorationPosition.background,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius + 10 * v),
            boxShadow: [BoxShadow(color: l.accent.withValues(alpha: 0.55 * (1 - v)), spreadRadius: 4 + 16 * v, blurRadius: 4)],
          ),
          child: child,
        );
      },
    );
  }
}

/// Banner on a locked bill (Nutzer 07.11.): who holds the padlock and what that means for me. Nothing if the bill is open.
class LockBanner extends StatelessWidget {
  const LockBanner({super.key, required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final lock = bill.lockBy;
    if (lock == null) return const SizedBox.shrink();
    final c = CollabScope.of(context), l = FasanLook.of(context);
    final other = c.lockedAgainstMe(bill, lock);
    final who = c.lockerName(bill, lock);
    return Padding(
      padding: const EdgeInsets.only(bottom: FasanSpace.m),
      child: Container(
        padding: const EdgeInsets.all(FasanSpace.m),
        decoration: BoxDecoration(
          color: Color.alphaBlend(l.accent.withValues(alpha: 0.10), l.surface),
          borderRadius: BorderRadius.circular(l.radius * 0.7),
          border: Border.all(color: l.accent.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_rounded, color: l.accent),
          const SizedBox(width: FasanSpace.m),
          Expanded(child: Text(context.tr(other ? 'lock.bannerOther' : 'lock.bannerMine', [who]), style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      ),
    );
  }
}
