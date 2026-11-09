// SPDX-License-Identifier: MPL-2.0
// Fasan Split – „changed by others“ marks (Nutzer 08.11.): a small counter on the thumbnail of a bill in the list (the orange dot beside
// the name took room from the name), and a banner in the bill that lists what changed since the last opening and by whom.
// The counter pulses three times the first time it shows in a session, then stands still: a never-ending animation would
// keep the screen drawing 60 frames a second for nothing (on a browser without WebGL every frame is drawn by the processor).
// It follows „Animationen entfernen“ (FasanMotion). MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../l10n/tr.dart' show trLang;
import 'history.dart';
import 'scope.dart';

/// Counter (or a plain dot when only the mark is known) at the upper right corner of a thumbnail.
class ChangeBadge extends StatefulWidget {
  const ChangeBadge({super.key, required this.id, required this.count});

  final String id;
  final int count;

  /// Bills whose badge already pulsed in this session (memory only).
  static final Set<String> _pulsed = {};

  @override
  State<ChangeBadge> createState() => _ChangeBadgeState();
}

class _ChangeBadgeState extends State<ChangeBadge> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || ChangeBadge._pulsed.contains(widget.id)) return;
    final m = FasanMotion.of(context);
    ChangeBadge._pulsed.add(widget.id);
    if (!m.enabled) return;
    // three beats, then it stops and the controller is released
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true, count: 6)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
          if (mounted) setState(() {});
        }
      });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final n = widget.count;
    final badge = Container(
      constraints: BoxConstraints(minWidth: n > 0 ? 18 : 12, minHeight: n > 0 ? 18 : 12),
      padding: EdgeInsets.symmetric(horizontal: n > 9 ? 4 : 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: l.accent, shape: n > 9 ? BoxShape.rectangle : BoxShape.circle, borderRadius: n > 9 ? BorderRadius.circular(9) : null, border: Border.all(color: l.surface, width: 1.5)),
      child: n > 0 ? Text(n > 99 ? '99+' : '$n', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1)) : null,
    );
    final c = _c;
    if (c == null || !c.isAnimating) return badge;
    // only this small layer repaints while it pulses
    return RepaintBoundary(child: ScaleTransition(scale: Tween(begin: 1.0, end: 1.25).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)), child: badge));
  }
}

/// What changed since I opened the bill last, and by whom; tap = the full history of the bill. Nothing if nothing is new.
class UnseenChangesBanner extends StatelessWidget {
  const UnseenChangesBanner({super.key, required this.billId});

  final String billId;

  @override
  Widget build(BuildContext context) {
    final c = CollabScope.of(context);
    final recs = c.unseenChanges(billId);
    if (recs.isEmpty) return const SizedBox.shrink();
    final de = S.of(context).de;
    String tr(String k, [List<Object> a = const []]) => trLang(de ? 'de' : 'en', k, a);
    final l = FasanLook.of(context);
    final lines = <(String, String)>[
      for (final r in recs) for (final x in r.lines) (r.who, de ? x.de : x.en),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: FasanSpace.s, bottom: FasanSpace.s),
      child: Material(
        color: Color.alphaBlend(l.accent.withValues(alpha: 0.10), l.surface),
        borderRadius: BorderRadius.circular(l.radius * 0.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(l.radius * 0.5),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HistoryScreen.bill(billId: billId, billTitle: recs.first.title))),
          child: Padding(
            padding: const EdgeInsets.all(FasanSpace.m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('changes.since'), style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final (who, text) in lines.take(5)) Text('$who: $text', style: Theme.of(context).textTheme.bodyMedium),
              if (lines.length > 5) Text(tr('changes.more', ['${lines.length - 5}']), style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }
}
