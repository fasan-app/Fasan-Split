// Fasan Split – a single line of text that is too long: it fades out at the edge instead of being cut hard, scrolls slowly and
// smoothly sideways to show the rest, and springs back (Nutzer 05.11.). Researched rules (docs/recherche/2026-11-05-ein-bildschirm-bon.md):
// moving text needs control and must not run on „Animationen entfernen“ (WCAG 2.2.2: > 5 s needs a pause). So: one short pass per
// appearance (under 5 s), again every ~10 s only while it is on screen, never with reduced motion; the full text stays in the
// semantics. It handles no gestures: taps and swipes go to the row around it. MPL-2.0
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText(this.text, {super.key, this.style, this.autoPlay = true, this.textAlign = TextAlign.start, this.width});

  final String text;

  /// A fixed width (for chips and other places that ask for intrinsic sizes, which a LayoutBuilder cannot answer).
  final double? width;
  final TextStyle? style;

  /// Play by itself (after a short wait, then now and then). Off: never (a parent can call it for a replay).
  final bool autoPlay;
  final TextAlign textAlign;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  // the offset in px the text is shifted left; unbounded so the spring may overshoot to the other side a little
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  Timer? _timer;
  bool _playing = false;
  double _overflow = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _schedule({Duration wait = const Duration(milliseconds: 1400)}) {
    _timer?.cancel();
    if (!widget.autoPlay) return;
    _timer = Timer(wait, () {
      if (mounted) _play();
    });
  }

  Future<void> _play() async {
    if (_playing || !mounted || _overflow <= 0 || !FasanMotion.of(context).enabled) return;
    _playing = true;
    final over = _overflow;
    try {
      // slow and smooth: ~34 px per second, at least 1 s, at most 3.4 s
      final ms = (over / 34 * 1000).clamp(1000, 3400).round();
      await _c.animateTo(over, duration: Duration(milliseconds: ms), curve: Curves.easeInOutCubic);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      // back with a spring: a little overshoot, then rest
      await _c.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 140, damping: 11), _c.value, 0, 0));
    } finally {
      _playing = false;
      if (mounted) _schedule(wait: const Duration(seconds: 10));
    }
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _timer?.cancel();
      _c.value = 0;
      _playing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.width;
    if (fixed != null) return SizedBox(width: fixed, child: _body(context, fixed));
    return LayoutBuilder(builder: (context, box) => _body(context, box.maxWidth));
  }

  Widget _body(BuildContext context, double avail) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    {
      final tp = TextPainter(text: TextSpan(text: widget.text, style: style), maxLines: 1, textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
      final fullWidth = tp.width;
      if (!avail.isFinite || fullWidth <= avail + 0.5) {
        _overflow = 0;
        _timer?.cancel();
        return Text(widget.text, style: widget.style, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, textAlign: widget.textAlign);
      }
      _overflow = fullWidth - avail;
      if (_timer == null && !_playing) _schedule();
      final fade = (avail * 0.22).clamp(10.0, 28.0);
      // No gestures of its own: a tap or a swipe on a long name belongs to the row around it (open, assign, swipe actions).
      return Semantics(
        label: widget.text,
        excludeSemantics: true,
        // a fixed height: an OverflowBox is as big as it may be, and in a list the height is unbounded
        child: SizedBox(
          height: tp.height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final o = _c.value;
                // fade at the right while there is more to see, at the left once it has moved
                final right = ((_overflow - o) / fade).clamp(0.0, 1.0), left = (o / fade).clamp(0.0, 1.0);
                return ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => LinearGradient(
                    colors: [Colors.black.withValues(alpha: 1 - left), Colors.black, Colors.black, Colors.black.withValues(alpha: 1 - right)],
                    stops: [0, (fade / r.width).clamp(0.0, 0.4), (1 - fade / r.width).clamp(0.6, 1.0), 1],
                  ).createShader(r),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: Transform.translate(offset: Offset(-o, 0), child: child),
                  ),
                );
              },
              child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false, overflow: TextOverflow.visible),
            ),
          ),
        ),
      );
    }
  }
}

/// A [MarqueeText] with a fixed width for places that ask for intrinsic sizes (chips): as wide as the text, at most [maxWidth].
class MarqueeLabel extends StatelessWidget {
  const MarqueeLabel(this.text, {super.key, this.style, this.maxWidth = 170});

  final String text;
  final TextStyle? style;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final st = style ?? DefaultTextStyle.of(context).style;
    final tp = TextPainter(text: TextSpan(text: text, style: st), maxLines: 1, textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
    return MarqueeText(text, style: style, width: (tp.width + 1).clamp(0, maxWidth).toDouble());
  }
}
