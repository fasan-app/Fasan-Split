// SPDX-License-Identifier: MPL-2.0
// Fasan Split – guides the eye to one element (Nutzer 09.11. 18:44): when a search hit, a notification or the bell leads
// to an item, the item is scrolled into the middle of the screen and its frame pulses ONCE. Apple's guidance: motion explains
// a change and does not decorate (HIG „Motion“); with „Animationen entfernen“ the element is only marked, without movement.
// Cost: one controller on one element for under a second, nothing runs afterwards. MPL-2.0
import 'dart:math' as math;

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import 'shape_tokens.dart';

class PulseOnFocus extends StatefulWidget {
  const PulseOnFocus({super.key, required this.active, required this.child});

  /// True for the element the person is led to. Read once when the element first appears.
  final bool active;
  final Widget child;

  @override
  State<PulseOnFocus> createState() => _PulseOnFocusState();
}

class _PulseOnFocusState extends State<PulseOnFocus> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.active) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) return;
    final m = FasanMotion.of(context);
    // into the middle of the screen; the scrollable of the screen does the work (nothing to do when there is none)
    if (Scrollable.maybeOf(context) != null) {
      await Scrollable.ensureVisible(context, alignment: 0.5, duration: m.enabled ? m.medium : Duration.zero, curve: FasanCurves.medium);
    }
    if (!mounted) return;
    final c = _c = AnimationController(vsync: this, duration: m.enabled ? const Duration(milliseconds: 900) : const Duration(milliseconds: 1400));
    setState(() {});
    await c.forward();
    if (!mounted) return;
    _c = null;
    c.dispose();
    setState(() {});
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final l = FasanLook.of(context), m = FasanMotion.of(context);
    return Stack(children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: c,
            builder: (_, _) {
              // two soft beats with movement; a steady mark without
              final a = m.enabled ? math.pow(math.sin(c.value * math.pi * 2).abs(), 2).toDouble() * (1 - c.value) : 1 - c.value;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(l.rInner),
                  border: Border.all(color: l.accent.withValues(alpha: a.clamp(0.0, 1.0)), width: 3),
                  color: l.accent.withValues(alpha: (a * 0.12).clamp(0.0, 1.0)),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}
