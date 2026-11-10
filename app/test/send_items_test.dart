// SPDX-License-Identifier: MPL-2.0
// Send items (Nutzer 09.11. 19:04): a chat message carries the bill and only the chosen positions; old messages without positions stay whole bills.
import 'package:fasan_split/collab/notes.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/send_items.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  rowLookTests();
  test('Nachricht mit Posten: Positionen bleiben erhalten, sortiert wie gesendet', () {
    final d = LwwDoc('aa');
    Notes.send(d, 'p1', '2 Posten aus „Abendessen“', bill: 'b1', items: [3, 1]);
    Notes.send(d, 'p1', 'ganzer Bon', bill: 'b2');
    final m = Notes.messages(d);
    expect(m[0].bill, 'b1');
    expect(m[0].items, [3, 1]);
    expect(m[1].bill, 'b2');
    expect(m[1].items, isEmpty, reason: 'ohne Positionen = ganzer Bon (alte Nachrichten)');
  });

  test('Fremde oder kaputte Positionen werden ignoriert', () {
    final d = LwwDoc('aa');
    final id = Notes.send(d, 'p1', 'x', bill: 'b1', items: [0]);
    d.set('c/$id', {'f': 'p1', 'x': 'x', 't': 1, 'b': 'b1', 'i': [0, 'zwei', null, 2]});
    expect(Notes.messages(d).single.items, [0, 2]);
  });

  testWidgets('Bon ohne geteilte Gruppe: Hinweis statt Auswahl', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    const tilt = MethodChannel('app.fasan.ui/tilt');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, null));
    final bill = Bill(id: 'a', created: DateTime(2026, 11, 2), purpose: 'Abendessen', total: 1000, items: [BillItem(name: 'Pizza', amount: 1000)], group: 'WG');
    await tester.pumpWidget(SplitApp(
      store: BillStore.memory([bill]),
      ui: FasanController(settings: const FasanSettings(reduceMotion: true)),
      home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => sendItemsFlow(c, bill), child: const Text('senden'))))),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('senden'));
    await tester.pumpAndSettle();
    expect(find.text('Posten lassen sich nur in einer geteilten Gruppe schicken.'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-go')), findsNothing);
  });
}

// Row look (Nutzer 09.11. Foto): no duplicate subtitle, initials of overlapping avatars stay readable.
void rowLookTests() {
  test('Untertitel nur wenn der Bon-Name vom Klarnamen abweicht', () {
    BillItem.plainNames = true;
    expect(BillItem(name: 'Pizza', amount: 100).subtitle, isNull, reason: 'gleicher Name, kein doppelter Text');
    expect(BillItem(name: 'Apfelschorle 0,4', amount: 100).subtitle, isNotNull);
  });
}
