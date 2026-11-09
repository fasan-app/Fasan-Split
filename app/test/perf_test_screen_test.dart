// SPDX-License-Identifier: MPL-2.0
// Leistungstest im Menü (Nutzer 08.11.): läuft allein durch, liefert je Phase Messwerte und einen Bericht ohne Namen. MPL-2.0
import 'package:fasan_split/main.dart';
import 'package:fasan_split/perf/perf_governor.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/perf_test.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Leistungstest läuft durch und zeigt alle zehn Phasen und ein Urteil', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory();
    await tester.pumpWidget(SplitApp(store: store, ui: SplitController(settings: const FasanSettings(reduceMotion: true)), home: const PerfTestScreen()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Test starten'), findsOneWidget);
    await tester.tap(find.text('Test starten'));
    // about 35 s of test time: advance the clock in frames
    for (var i = 0; i < 16000 && find.text('Noch einmal').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Noch einmal'), findsOneWidget, reason: 'Test wurde fertig');
    for (final n in ['Leerlauf', 'Rechnungsliste scrollen', 'Leere Zeilen scrollen (Gegenprobe)', 'Nur Schatten scrollen (Gegenprobe)', 'Liste ohne Vorschaubilder (Gegenprobe)', 'Posten scrollen', 'Alle Posten der Gruppe (500) scrollen', 'Gruppen-Nachrichten prüfen beim Scrollen', 'Fenster öffnen und schließen', 'Ruhe (30 Sekunden)']) {
      expect(find.text(n), findsOneWidget, reason: n);
    }
    expect(find.textContaining('Median'), findsNWidgets(10));
    expect(find.textContaining('Gesamturteil'), findsOneWidget);
  });
}
