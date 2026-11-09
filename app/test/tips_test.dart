// SPDX-License-Identifier: MPL-2.0
// Fasan Split – tip line and guide (Nutzer 07.11.): every language has the same keys, one tip per start, off in the settings. MPL-2.0
import 'package:fasan_split/l10n/languages.dart';
import 'package:fasan_split/l10n/tr.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_split/ui/tips.dart';
import 'package:fasan_split/ui/tutorial.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:fasan_split/ui/my_balance.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> keysOf(AppLanguage l, String prefix) => {for (final k in l.strings.keys) if (k.startsWith(prefix)) k};

void main() {
  test('Jede Sprache hat alle Tipps und alle Anleitungsschritte (neue Funktion ohne Eintrag = nicht fertig)', () {
    final wantTips = {for (final id in tipIds) 'tip.$id'};
    final wantGuide = {
      'tutorial.title', 'tutorial.intro',
      for (final id in tutorialIds) ...['tutorial.$id.title', 'tutorial.$id.body'],
    };
    for (final l in appLanguages) {
      for (final k in [...wantTips, ...wantGuide]) {
        expect((l.strings[k] ?? '').trim(), isNotEmpty, reason: '${l.code}: $k fehlt');
      }
      // no text without an id: every tip.* / tutorial.* key of the language is used
      final tipKeys = keysOf(l, 'tip.')..removeAll(wantTips);
      expect(tipKeys.where((k) => !const {'tip.setTitle', 'tip.setSub', 'tip.open', 'tip.close'}.contains(k)), isEmpty, reason: '${l.code}: Tipp ohne Id');
      final guideKeys = keysOf(l, 'tutorial.')..removeAll(wantGuide);
      expect(guideKeys, isEmpty, reason: '${l.code}: Anleitungstext ohne Schritt');
    }
    expect(tipIds.toSet().length, tipIds.length);
  });

  testWidgets('Tipp: einer je Start, bleibt beim Wechseln gleich, in den Einstellungen abschaltbar; Anleitung öffnet', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    TipLine.resetForTest();
    final store = BillStore.memory()..onboarded = true;
    final ctl = FasanController(settings: FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ctl, home: const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    // the tip line is off on the start page for now (Nutzer 09.11.: it costs too much room); the setting stays
    expect(find.text(trLang('de', 'tip.${tipIds[0]}')), findsNothing);
    expect(find.byTooltip('Tipp schließen'), findsNothing);
    // settings: the switch turns the tips off; the guide opens with all steps
    await tester.tap(find.byType(MyBalanceBadge)); // settings live in the profile, top right (Nutzer 09.11.)
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-6'))); // Aussehen und Hinweise: a page of its own (Nutzer 09.11.)
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tipps zeigen'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Tipps zeigen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Tipps zeigen'));
    await tester.pump();
    expect(store.showTips, isFalse);
    await tester.tap(find.text('Anleitung'));
    await tester.pumpAndSettle();
    expect(find.byType(TutorialScreen), findsOneWidget);
    expect(find.text('Bon scannen'), findsOneWidget);
  });
}
