// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Klarheit (Nutzer 07.11.): plus inside a group, „Später weiter“ instead of the confusing „Speichern“, hints. MPL-2.0
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/bill_screen.dart';
import 'package:fasan_split/ui/groups.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Plus in der Gruppe: neuer Bon ohne Foto landet in der Gruppe; „Später weiter“ statt „Speichern“', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory()..onboarded = true;
    store.addGroup('Beispielstadt');
    final q = ScanQueue(store, recognize: (_) => const Stream.empty());
    final ctl = FasanController(settings: FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ctl, home: GroupScreen(name: 'Beispielstadt', queue: q)));
    await tester.pump(const Duration(milliseconds: 100));
    // the hints say how it works and that everyone can enter for everyone
    expect(find.textContaining('rechnet alles automatisch'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ohne Bon'));
    await tester.pumpAndSettle();
    final review = tester.widget<ReviewScreen>(find.byType(ReviewScreen));
    expect(review.bill.group, 'Beispielstadt', reason: 'in der Gruppe gestartet = in der Gruppe');
    expect(find.text('Später weiter'), findsOneWidget);
    expect(find.text('Speichern'), findsNothing, reason: 'es wird immer sofort gespeichert; der Knopf schließt nur');
  });
}
