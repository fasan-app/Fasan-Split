// SPDX-License-Identifier: MPL-2.0
// Plus menu (Nutzer 09.11. 18:44): cash payment in a group (with subject), group entries and the „Ohne Gruppe“ note under „Alle Gruppen“.
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/add_bill.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester, {String? group, List<String> people = const [], bool groupMenu = false}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    const tilt = MethodChannel('app.fasan.ui/tilt');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, null));
    final store = BillStore.memory([]);
    final queue = ScanQueue(store, recognize: (_) => const Stream.empty());
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(
      store: store,
      ui: ui,
      home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => addBillSheet(c, queue, group: group, people: people, groupMenu: groupMenu), child: const Text('plus'))))),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('plus'));
    await tester.pumpAndSettle();
  }

  testWidgets('in a group with two people: payment tile, no group entries', (tester) async {
    await open(tester, group: 'Reise', people: ['Anna', 'Ben']);
    expect(find.byKey(const ValueKey('plus-payment')), findsOneWidget);
    expect(find.text('Zahlung (Bargeld)'), findsOneWidget);
    expect(find.text('Gruppe'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('plus-payment')));
    await tester.pumpAndSettle();
    expect(find.text('Betreff (optional)'), findsOneWidget, reason: 'der Dialog fragt den Betreff');
  });

  testWidgets('without a group: note and group entries, no payment', (tester) async {
    await open(tester, groupMenu: true);
    expect(find.byKey(const ValueKey('plus-payment')), findsNothing);
    expect(find.textContaining('Ohne Gruppe'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Gruppe beitreten'), 100, scrollable: find.byType(Scrollable).last);
    expect(find.text('Gruppe'), findsOneWidget);
  });

  testWidgets('a group with one person has no payment tile', (tester) async {
    await open(tester, group: 'Reise', people: ['Anna']);
    expect(find.byKey(const ValueKey('plus-payment')), findsNothing);
  });
}
