// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the guide (Einstellungen → Anleitung, and a tap on the tip line): the steps from the first receipt to settling up
// (Nutzer 07.11.). Texts: l10n/tutorial_<code>.dart per id in [tutorialIds]. Every change of the operation updates them (CLAUDE.md). MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../l10n/tr.dart';

/// Steps of the guide in order; keys `tutorial.<id>.title` / `.body`. A new function gets its step here and its texts in every language.
const tutorialIds = <String>['idea', 'scan', 'check', 'assign', 'paid', 'group', 'invite', 'together', 'history', 'settle', 'settings'];

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = S.of(context).de ? 'de' : 'en';
    final tt = Theme.of(context).textTheme;
    final l = FasanLook.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(trLang(lang, 'tutorial.title'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, FasanSpace.xl + MediaQuery.paddingOf(context).bottom),
        children: [
          Padding(padding: const EdgeInsets.only(bottom: FasanSpace.m), child: Text(trLang(lang, 'tutorial.intro'), style: tt.bodyLarge)),
          for (final (i, id) in tutorialIds.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: FasanSpace.m),
              child: Container(
                padding: const EdgeInsets.all(FasanSpace.m),
                decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.7)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(radius: 16, backgroundColor: l.accent, foregroundColor: Colors.white, child: Text('${i + 1}')),
                  const SizedBox(width: FasanSpace.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(trLang(lang, 'tutorial.$id.title'), style: tt.titleMedium),
                      const SizedBox(height: FasanSpace.xs),
                      Text(trLang(lang, 'tutorial.$id.body'), style: tt.bodyMedium),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
