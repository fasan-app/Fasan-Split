// SPDX-License-Identifier: MPL-2.0
// Sheets must not overflow on a small or sideways screen (found 07.11.: the choice sheet of the plus overflowed by 21 px at 393 dp
// height, App and Browser alike). Opens every plain choice sheet in the phone size sideways, with the real fonts.
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/perf/perf_governor.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fonts.dart';

void main() {
  testWidgets('Auswahlblatt des Plus läuft im Querformat nicht über', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory([])
      ..onboarded = true
      ..me = 'Lena';
    final ctl = SplitController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ctl, home: const HomeScreen()));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byIcon(Icons.add_rounded));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.byType(ListTile), findsNWidgets(6)); // Kamera, Galerie / Datei, Ohne Bon + live, nur hier, beitreten (Alle Gruppen)
    expect(tester.takeException(), isNull);
  });
}
