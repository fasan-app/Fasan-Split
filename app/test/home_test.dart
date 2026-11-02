// Übersicht: Mehrfachauswahl, Gruppen, Status, Wischen, Löschen mit Rückgängig und die Warteschlange für mehrere Fotos.
import 'dart:async';

import 'package:fasan_split/main.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/recognition_service.dart';
import 'package:fasan_split/state/scan_queue.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Bill _bill(String id, String name, {bool done = false, String? group, String read = BillRead.ok}) => Bill(
      id: id,
      created: DateTime(2026, 11, 2),
      purpose: name,
      total: 1000,
      items: [BillItem(name: 'Posten', amount: 1000)],
      done: done,
      group: group,
      read: read,
    );

ScanResultData _result(String shop) => ScanResultData(
      items: [BillItem(name: 'Café', amount: 250), BillItem(name: 'Pastel', amount: 120)],
      total: 370,
      checked: true,
      contradiction: false,
      display: Uint8List(0),
      width: 100,
      height: 200,
      shop: shop,
      kind: 'Café',
      advance: 0,
      log: '{}',
      lines: const [],
    );

void main() {
  Future<void> app(WidgetTester tester, BillStore store, ScanQueue queue) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // the test environment starts in English; the texts below are German
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    const tilt = MethodChannel('app.fasan.ui/tilt');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, null));
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ui, home: HomeScreen(queue: queue)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  ScanQueue idle(BillStore s) => ScanQueue(s, recognize: (_) => const Stream.empty());

  group('Übersicht', () {
    testWidgets('auswählen, gruppieren: Kopfzeile der Gruppe mit Anzahl', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück'), _bill('b', 'Abendessen'), _bill('c', 'Taxi', done: true)]);
      await app(tester, store, idle(store));
      await tester.tap(find.byTooltip('Auswählen'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Frühstück'));
      await tester.tap(find.text('Abendessen'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('2 ausgewählt'), findsOneWidget);
      await tester.tap(find.byTooltip('Gruppe'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'Lissabon');
      await tester.tap(find.text('OK'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.groups, ['Lissabon']);
      expect(store.inGroup('Lissabon').map((b) => b.id).toSet(), {'a', 'b'});
      expect(find.text('Lissabon'), findsOneWidget);
      expect(find.text('2 · 20,00 €'), findsOneWidget);
      expect(store.inGroup(null).map((b) => b.id), ['c']);
    });

    testWidgets('Wischen nach rechts setzt Fertig und wieder Offen', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück')]);
      await app(tester, store, idle(store));
      await tester.drag(find.byKey(const ValueKey('bill-a')), const Offset(500, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.bills.single.done, isTrue);
      await tester.drag(find.byKey(const ValueKey('bill-a')), const Offset(500, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.bills.single.done, isFalse);
    });

    testWidgets('Wischen nach links löscht mit Rückgängig', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück'), _bill('b', 'Taxi')]);
      await app(tester, store, idle(store));
      await tester.drag(find.byKey(const ValueKey('bill-a')), const Offset(-600, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Bon gelöscht'), findsOneWidget);
      expect(store.drafts.map((b) => b.id), ['b'], reason: 'sofort ausgeblendet');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Rückgängig'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.drafts.map((b) => b.id).toSet(), {'a', 'b'});
    });

    testWidgets('Ohne Rückgängig wird nach der Meldung endgültig gelöscht', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück'), _bill('b', 'Taxi')]);
      await app(tester, store, idle(store));
      await tester.drag(find.byKey(const ValueKey('bill-b')), const Offset(-600, 0));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Bon gelöscht'), findsOneWidget);
      expect(store.bills.length, 2, reason: 'noch nicht endgültig');
      for (var i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(store.bills.map((b) => b.id), ['a']);
    });

    testWidgets('Foto in der Warteschlange: wartet, wird gelesen, ohne Öffnen; fehlgeschlagen bietet „Nochmal lesen“', (tester) async {
      final store = BillStore.memory([_bill('q1', '', read: BillRead.queued), _bill('q2', '', read: BillRead.reading), _bill('f1', '', read: BillRead.failed)]);
      await app(tester, store, idle(store));
      expect(find.text('Wartet auf das Lesen'), findsOneWidget);
      expect(find.text('Wird gelesen'), findsOneWidget);
      expect(find.text('Lesen unterbrochen oder fehlgeschlagen'), findsOneWidget);
      expect(find.text('Nochmal lesen'), findsOneWidget);
    });
  });

  group('Warteschlange', () {
    test('mehrere Fotos werden nacheinander gelesen und füllen ihre Platzhalter', () async {
      final store = BillStore.memory();
      var n = 0;
      final q = ScanQueue(store, recognize: (_) async* {
        final shop = ['Café Um', 'Padaria Dois'][n++];
        yield ScanProgress('Bon wird gelesen', 0.5);
        yield ScanDone(_result(shop));
      });
      await q.add([Uint8List(3), Uint8List(3)], group: 'Reise');
      // alle Platzhalter sind sofort da
      expect(store.bills.length, 2);
      expect(store.bills.every((b) => b.group == 'Reise'), isTrue);
      while (q.open > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.bills.every((b) => b.read == BillRead.ok), isTrue);
      expect(store.bills.map((b) => b.purpose).toSet(), {'Café Um', 'Padaria Dois'});
      expect(store.bills.every((b) => b.its.length == 2 && b.total == 370 && b.group == 'Reise'), isTrue);
    });

    test('Lesefehler: Bon bleibt, Status „fehlgeschlagen“, der nächste wird trotzdem gelesen', () async {
      final store = BillStore.memory();
      var n = 0;
      final q = ScanQueue(store, recognize: (_) async* {
        if (n++ == 0) {
          yield ScanError('kaputt');
        } else {
          yield ScanDone(_result('Gut'));
        }
      });
      await q.add([Uint8List(3), Uint8List(3)]);
      while (q.open > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.bills.map((b) => b.read), [BillRead.failed, BillRead.ok]);
      // nochmal lesen
      await q.retry(store.bills.first, Uint8List(3));
      while (q.open > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.bills.first.read, BillRead.ok);
    });

    test('während des Lesens gelöscht: kommt nicht zurück', () async {
      final store = BillStore.memory();
      final gate = Completer<void>();
      final q = ScanQueue(store, recognize: (_) async* {
        await gate.future;
        yield ScanDone(_result('Weg'));
      });
      await q.add([Uint8List(3)]);
      store.remove(store.bills.single);
      gate.complete();
      while (q.open > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.bills, isEmpty);
    });
  });

  test('Beim Start: wartende oder unterbrochene Fotos gelten als fehlgeschlagen, Gruppe bleibt erhalten', () async {
    SharedPreferences.setMockInitialValues({
      'bills.v1': '[${_bill('a', '', read: BillRead.reading, group: 'X').toJson().entries.map((e) => '"${e.key}":${_enc(e.value)}').join(',').replaceFirst(RegExp('^'), '{')}}]',
    });
    final s = await BillStore.load();
    expect(s.bills.single.read, BillRead.failed);
    expect(s.bills.single.group, 'X');
  });
}

String _enc(Object? v) => switch (v) {
      null => 'null',
      String s => '"${s.replaceAll('"', r'\"')}"',
      List l => '[${l.map(_enc).join(',')}]',
      Map m => '{${m.entries.map((e) => '"${e.key}":${_enc(e.value)}').join(',')}}',
      _ => '$v',
    };
