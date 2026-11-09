// SPDX-License-Identifier: MPL-2.0
// "Was ist neu" in the update sheet: plain-language news per language, no commit lines, link to the public repo.
import 'dart:io';

import 'package:fasan_split/flows/update.dart';
import 'package:fasan_split/l10n/languages.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/update_ui.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _body = '''Testversion aus abc1234.

<!--news:de-->
## 0.1.74
- Neu A.
## 0.1.73
- Neu B.
- Neu C.
## 0.1.70
- Alt D.
<!--/news:de-->

<!--news:en-->
## 0.1.74
- New A.
## 0.1.73
- New B.
- New C.
## 0.1.70
- Old D.
<!--/news:en-->

- abc1234 Commit-Zeile die niemand sehen soll
''';

/// (heading, item count) per section of a news file.
List<(String, int)> _shape(String md) {
  final out = <(String, int)>[];
  for (final l in md.split('\n')) {
    if (l.startsWith('## ')) out.add((l.trim(), 0));
    if (l.startsWith('- ') && out.isNotEmpty) out[out.length - 1] = (out.last.$1, out.last.$2 + 1);
  }
  return out;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Jede App-Sprache hat eine News-Datei mit denselben Abschnitten und gleich vielen Zeilen', () {
    final ref = _shape(File('../news/de.md').readAsStringSync());
    expect(ref, isNotEmpty);
    for (final l in appLanguages) {
      final f = File('../news/${l.code}.md');
      expect(f.existsSync(), isTrue, reason: 'news/${l.code}.md fehlt');
      expect(_shape(f.readAsStringSync()), ref, reason: 'news/${l.code}.md weicht von de.md ab');
    }
  });

  test('Nur Abschnitte neuer als der eigene Build, neueste zuerst, Sprache getrennt, Ausweichen auf Englisch', () {
    expect(Updates.newsSince(_body, 'de', 72), ['Neu A.', 'Neu B.', 'Neu C.']);
    expect(Updates.newsSince(_body, 'en', 73), ['New A.']);
    expect(Updates.newsSince(_body, 'de', 74), isEmpty);
    expect(Updates.newsSince(_body, 'de', null), hasLength(4));
    expect(Updates.newsSince(_body, 'fr', 72), ['New A.', 'New B.', 'New C.'], reason: 'unbekannte Sprache → Englisch');
    expect(Updates.newsSince(_body, 'de', 0, max: 2), ['Neu A.', 'Neu B.']);
    expect(Updates.newsSince('nur Commits\n- abc1234 x', 'de', 0), isEmpty, reason: 'Commit-Zeilen werden nie angezeigt');
  });

  for (final lang in ['de', 'en']) {
    testWidgets('Update-Fenster ($lang): Neuigkeiten in Sprache, keine Commit-Zeile, Link zum Repo', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final store = BillStore.memory()
        ..onboarded = true
        ..language = lang;
      await tester.pumpWidget(SplitApp(
        store: store,
        ui: FasanController(settings: const FasanSettings(reduceMotion: true)),
        home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showUpdateSheet(c, const UpdateInfo(run: 74, name: 'Fasan Split 0.1.74 (Test)', url: 'https://x', sha256: null, size: 84000000, body: _body, ownRun: 72)), child: const Text('open')))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(lang == 'de' ? '• Neu A.' : '• New A.'), findsOneWidget);
      expect(find.text(lang == 'de' ? '• Neu C.' : '• New C.'), findsOneWidget);
      expect(find.textContaining('Old'), findsNothing);
      expect(find.textContaining('Alt D'), findsNothing);
      expect(find.textContaining('Commit-Zeile'), findsNothing);
      expect(find.byKey(const ValueKey('update-repo-link')), findsOneWidget);
      expect(find.text(lang == 'de' ? 'Alle Details und die Roadmap ansehen' : 'See all details and the roadmap'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Update-Fenster ohne eigenen News-Abschnitt (Build nach der letzten Meldung): nie leer, sagt es in einem Satz', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory()
      ..onboarded = true
      ..language = 'de';
    await tester.pumpWidget(SplitApp(
      store: store,
      ui: FasanController(settings: const FasanSettings(reduceMotion: true)),
      home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showUpdateSheet(c, const UpdateInfo(run: 80, name: 'Fasan Split 0.1.80 (Test)', url: 'https://x', sha256: null, size: 84000000, body: _body, ownRun: 79)), child: const Text('open')))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Kleine Verbesserungen und Fehlerkorrekturen.'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-repo-link')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
