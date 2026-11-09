// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the tip line under the main menu (Nutzer 07.11.): one short help sentence per start of the app. In the browser one
// start = one page load: the choice is kept in a static, so it does not change with a click, a page switch or a rebuild.
// Switched off in the settings („Tipps zeigen“). Texts: l10n/tips_<code>.dart, one per id in [tipIds]. MPL-2.0
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../l10n/tr.dart';
import 'scope.dart';
import 'tutorial.dart';
import 'shape_tokens.dart';

/// Ids of all tips; text key `tip.<id>`. A new tip = a new id here and its text in every `tips_<code>.dart` (test: tips_test).
const tipIds = <String>[
  'plus', 'swipe', 'drag', 'invite', 'everyone', 'lock', 'give', 'colors', 'people', 'autosave', 'history', 'balance', 'backup', 'local', 'perf', 'tutorial', 'off',
];

class TipLine extends StatefulWidget {
  const TipLine({super.key});

  /// Tip of this start (null = not chosen yet) and whether it was closed; per process, so once per start of the app or page load.
  static int? _current;
  static bool _closed = false;

  @visibleForTesting
  static void resetForTest() {
    _current = null;
    _closed = false;
  }

  @override
  State<TipLine> createState() => _TipLineState();
}

class _TipLineState extends State<TipLine> {
  @override
  void initState() {
    super.initState();
    if (TipLine._current == null) {
      final store = StoreScope.read(context);
      final i = store.tipNext % tipIds.length;
      TipLine._current = i;
      // after the first frame: writing the settings notifies listeners, which is not allowed while building
      scheduleMicrotask(() => store.tipNext = i + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final l = FasanLook.of(context);
    final lang = S.of(context).de ? 'de' : 'en';
    final show = store.showTips && !TipLine._closed && TipLine._current != null;
    final text = show ? trLang(lang, 'tip.${tipIds[TipLine._current!]}') : '';
    return FasanReveal(
      show: show,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s),
        child: Material(
          color: Color.alphaBlend(l.accent.withValues(alpha: 0.08), l.surface),
          borderRadius: BorderRadius.circular(l.rInner),
          child: InkWell(
            borderRadius: BorderRadius.circular(l.rInner),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TutorialScreen())),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.m, FasanSpace.xs, 0, FasanSpace.xs),
              child: Row(children: [
                Icon(Icons.lightbulb_outline_rounded, color: l.accent, size: 20),
                const SizedBox(width: FasanSpace.s),
                Expanded(child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
                IconButton(
                  tooltip: trLang(lang, 'tip.close'),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => TipLine._closed = true),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
