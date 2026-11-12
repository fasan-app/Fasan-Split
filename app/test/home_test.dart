// SPDX-License-Identifier: MPL-2.0
// Übersicht: Mehrfachauswahl, Gruppen, Status, Wischen, Löschen mit Rückgängig und die Warteschlange für mehrere Fotos.
import 'dart:async';

import 'package:fasan_split/main.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/recognition/service.dart';
import 'package:fasan_split/flows/scan_queue.dart';
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
      items: [BillItem(name: 'Café', amount: 250), BillItem(name: 'Törtchen', amount: 120)],
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
    testWidgets('Notiz zum Bon aus der Liste: schreiben, anpinnen, steht sofort unter dem Titel der Kachel', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück')]);
      await app(tester, store, idle(store));
      await tester.tap(find.byKey(const ValueKey('more-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notiz zum Bon'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Karte war defekt, bar bezahlt');
      await tester.tap(find.byTooltip('Oben anpinnen'));
      await tester.pump();
      await tester.tap(find.byTooltip('Notiz speichern'));
      await tester.pumpAndSettle();
      expect(store.bills.single.notes.single.text, 'Karte war defekt, bar bezahlt');
      expect(store.bills.single.notes.single.pinned, isTrue);
      await tester.tapAt(const Offset(5, 5)); // closes the sheet
      await tester.pumpAndSettle();
      expect(find.text('Karte war defekt, bar bezahlt'), findsOneWidget, reason: 'angepinnte Notiz als Zeile unter dem Titel');
    });

    testWidgets('auswählen, gruppieren: Kopfzeile der Gruppe mit Anzahl', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück'), _bill('b', 'Abendessen'), _bill('c', 'Taxi', done: true)]);
      await app(tester, store, idle(store));
      await tester.tap(find.byKey(const ValueKey('more-menu'))); // select lives in the ⋮ menu (Nutzer 09.11.)
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auswählen'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Frühstück'));
      await tester.tap(find.text('Abendessen'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('2 ausgewählt'), findsOneWidget);
      await tester.tap(find.byTooltip('Gruppe'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'Beispielstadt');
      await tester.tap(find.text('OK'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.groups, ['Beispielstadt']);
      expect(store.inGroup('Beispielstadt').map((b) => b.id).toSet(), {'a', 'b'});
      expect(find.text('Beispielstadt'), findsWidgets, reason: 'Überschrift der Gruppe (und ggf. der Gruppenschalter)');
      expect(find.text('2 · 20,00 €'), findsOneWidget);
      expect(store.inGroup(null).map((b) => b.id), ['c']);
    });

    testWidgets('Langdruck wählt aus; Auswahl auf einen Bon ziehen sortiert sie davor', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück'), _bill('b', 'Abendessen'), _bill('c', 'Taxi')]);
      await app(tester, store, idle(store));
      await tester.longPress(find.text('Taxi'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('1 ausgewählt'), findsOneWidget);
      final before = store.inGroup(null, done: false).map((b) => b.purpose).toList();
      final top = before.first;
      expect(top, isNot('Taxi'));
      // drag the selected bill onto the first one: it goes right before it
      final g = await tester.startGesture(tester.getCenter(find.text('Taxi')));
      await tester.pump(const Duration(milliseconds: 400));
      await g.moveTo(tester.getCenter(find.text(top)));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.inGroup(null, done: false).first.purpose, 'Taxi');
    });

    testWidgets('Langdruck hebt sofort an: ohne Loslassen auf „Papierkorb“ ziehen', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück'), _bill('b', 'Taxi')]);
      await app(tester, store, idle(store));
      final g = await tester.startGesture(tester.getCenter(find.text('Taxi')));
      await tester.pump(const Duration(milliseconds: 400)); // lifted, selection started, no letting go
      await g.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 100));
      // while dragging: the app bar only says where to go, the targets sit below (Nutzer 04.11.)
      expect(find.text('Auf ein Ziel unten ziehen'), findsOneWidget);
      await g.moveTo(tester.getCenter(find.text('Papierkorb').last));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Loslassen: in den Papierkorb'), findsOneWidget, reason: 'das Ziel sagt, was passiert');
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.bills.firstWhere((b) => b.id == 'b').trashedAt, isNotNull);
      expect(store.bills.firstWhere((b) => b.id == 'a').trashedAt, isNull);
    });

    test('moveBefore: mehrere Bons vor ein Ziel, Reihenfolge bleibt, Gruppe des Ziels', () {
      final store = BillStore.memory([_bill('a', 'A'), _bill('b', 'B'), _bill('c', 'C'), _bill('d', 'D')..group = 'WG']);
      final list = store.inGroup(null, done: false);
      final target = list.first;
      final moved = list.sublist(1);
      store.moveBefore(moved, target);
      final after = store.inGroup(null, done: false);
      expect(after.last.id, target.id);
      expect(after.take(moved.length).map((b) => b.id), moved.map((b) => b.id));
      final wg = store.inGroup('WG', done: false).single;
      store.moveBefore([after.first], wg);
      expect(store.inGroup('WG', done: false).first.id, after.first.id);
      expect(store.inGroup('WG', done: false).length, 2);
    });

    testWidgets('Auswahlmodus bleibt auch ohne Auswahl und endet mit dem X', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück'), _bill('b', 'Abendessen')]);
      await app(tester, store, idle(store));
      await tester.tap(find.byKey(const ValueKey('more-menu'))); // select lives in the ⋮ menu (Nutzer 09.11.)
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auswählen'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Bons auswählen'), findsOneWidget);
      await tester.tap(find.text('Frühstück'));
      await tester.tap(find.text('Frühstück'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Bons auswählen'), findsOneWidget, reason: 'bleibt, auch wenn nichts mehr gewählt ist');
      await tester.tap(find.byTooltip('Abbrechen'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Bons auswählen'), findsNothing);
      expect(find.byKey(const ValueKey('more-menu')), findsOneWidget);
    });

    Future<void> rowMenu(WidgetTester tester, String id, String label) async {
      await tester.tap(find.byKey(ValueKey('more-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('⋮ der Zeile: eingetragener Bon wird ausgeglichen (Archiv), Rückgängig holt zurück', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück', done: true)]);
      await app(tester, store, idle(store));
      await rowMenu(tester, 'a', 'Ausgleichen (bezahlt)');
      expect(store.bills.single.settled, isTrue);
      expect(find.text('Ausgeglichen, im Archiv'), findsOneWidget);
      await tester.tap(find.text('Rückgängig'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.bills.single.settled, isFalse);
      expect(store.bills.single.done, isTrue, reason: 'bleibt eingetragen');
    });

    testWidgets('⋮ der Zeile: angefangener Bon kommt nicht ins Archiv, der Eintrag ist grau und nennt den Grund', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück')]);
      await app(tester, store, idle(store));
      await tester.tap(find.byKey(const ValueKey('more-a')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Erst eintragen'), findsOneWidget, reason: 'the reason stands in the entry, nothing is hidden');
      await tester.tap(find.text('Ausgleichen (bezahlt)'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(store.bills.single.settled, isFalse);
    });

    testWidgets('⋮ der Zeile: Papierkorb mit Rückgängig; der Bon bleibt gespeichert', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück'), _bill('b', 'Taxi')]);
      await app(tester, store, idle(store));
      await rowMenu(tester, 'a', 'Löschen');
      expect(find.text('Bon im Papierkorb'), findsOneWidget);
      expect(store.drafts.map((b) => b.id), ['b']);
      expect(store.trashed.map((b) => b.id), ['a']);
      expect(store.bills.length, 2, reason: 'nichts ist endgültig gelöscht');
      await tester.tap(find.text('Rückgängig'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.trashed, isEmpty);
      expect(store.drafts.map((b) => b.id).toSet(), {'a', 'b'});
    });

    testWidgets('Ein Wisch über eine Zeile führt zur Abrechnung und ändert den Bon nicht (kein Wisch-Menü mehr)', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück', done: true)]);
      await app(tester, store, idle(store));
      await tester.drag(find.text('Frühstück'), const Offset(-700, 0));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('view-menu')), findsNothing, reason: 'now on Abrechnung');
      expect(store.bills.single.settled, isFalse);
      expect(store.trashed, isEmpty);
    });

    testWidgets('Reiter: Archiv und Papierkorb zeigen ihre Bons, Wiederherstellen und Leeren', (tester) async {
      final done = _bill('d', 'Taxi', done: true)..settled = true;
      final gone = _bill('t', 'Kino')..trashedAt = DateTime.now().subtract(const Duration(days: 2));
      final store = BillStore.memory([_bill('a', 'Frühstück'), done, gone]);
      await app(tester, store, idle(store));
      expect(find.text('Frühstück'), findsOneWidget);
      expect(find.text('Taxi'), findsNothing);
      // Offen / Archiv / Papierkorb live in a pull-down of the context row (Nutzer 09.11.)
      await tester.tap(find.byKey(const ValueKey('view-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archiv'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Taxi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('view-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Papierkorb'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Kino'), findsOneWidget);
      expect(find.textContaining('noch 28 Tage'), findsOneWidget);
      await rowMenu(tester, 't', 'Wiederherstellen');
      expect(store.trashed, isEmpty);
      expect(store.bills.firstWhere((b) => b.id == 't').trashedAt, isNull);
    });

    testWidgets('Untere Leiste: Gruppen und Freunde haben eigene Bildschirme', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück', group: 'Urlaub')]);
      await app(tester, store, idle(store));
      await tester.tap(find.text('Abrechnung').last);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Urlaub'), findsOneWidget, reason: 'Karte der Abrechnung (der Gruppenschalter zeigt „Alle Gruppen“)');
      expect(find.textContaining('1 Bon · '), findsOneWidget, reason: 'Karte zeigt jetzt Bons und Mitgliederzahl (Nutzer 12.11.)');
      await tester.tap(find.text('Freunde').last);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Noch keine Freunde'), findsOneWidget);
    });

    testWidgets('Bon aus der Gruppe öffnen und schließen: man bleibt in der Gruppe (Nutzer 04.11.)', (tester) async {
      final store = BillStore.memory([_bill('a', 'Frühstück', group: 'Urlaub', done: true)..payer = 0]);
      await app(tester, store, idle(store));
      await tester.tap(find.text('Abrechnung').last);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Urlaub').last); // the card; the first one is the chip of the picker
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frühstück').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(find.text('Urlaub'), findsWidgets, reason: 'zurück in der Gruppe, nicht auf der Startseite');
      expect(find.byType(BackButton), findsOneWidget);
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

    test('Erste Angaben (Ort, Datum, Preis) stehen in der Übersicht, bevor der Bon fertig gelesen ist', () async {
      final store = BillStore.memory();
      final gate = Completer<void>();
      final q = ScanQueue(store, recognize: (_) async* {
        yield ScanPartial('RESTAURANT BEISPIEL', 'CRUZES DA SE 31A, 1100-192 BEISPIELSTADT', '2026-10-24T00:00:00.000', 8500);
        await gate.future;
        yield ScanDone(_result('RESTAURANT BEISPIEL'));
      });
      await q.add([Uint8List(3)]);
      while (store.bills.single.purpose.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final b = store.bills.single;
      expect(b.read, BillRead.reading);
      expect(b.purpose, 'Restaurant Beispiel');
      expect(b.total, 8500);
      expect(b.receiptDate, DateTime(2026, 10, 24));
      expect(b.placeAddress, startsWith('CRUZES'));
      expect(q.liveFor(b.id), isNotNull, reason: 'die Kachel spielt die Scan-Animation');
      gate.complete();
      // Wait for the result itself, not for the queue counter: under load (CI, 2 cores) the counter can reach 0 a moment
      // before the finished bill is written (seen 03.11.: 'reading' instead of 'ok').
      for (var i = 0; i < 500 && store.bills.single.read == BillRead.reading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.bills.single.read, BillRead.ok);
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

  group('Papierkorb, Archiv, Gruppen, Freunde (Speicher)', () {
    test('Frist 7 Tage, 30 Tage oder nur manuell', () {
      final now = DateTime(2026, 11, 2);
      Bill gone(String id, int days) => _bill(id, id)..trashedAt = now.subtract(Duration(days: days));
      List<String> run(int days) {
        final store = BillStore.memory([gone('a8', 8), gone('b5', 5), gone('c1', 1), gone('z90', 90)]);
        store.trashDays = days;
        store.purgeTrash(now: now);
        return store.bills.map((b) => b.id).toList()..sort();
      }

      expect(run(7), ['b5', 'c1']);
      expect(run(30), ['a8', 'b5', 'c1']);
      expect(run(0), ['a8', 'b5', 'c1', 'z90'], reason: 'nur manuell: nichts verschwindet von selbst');
    });

    test('Standard ist 30 Tage; Restzeit zählt herunter', () {
      final now = DateTime(2026, 11, 2);
      final store = BillStore.memory([_bill('a', 'a')..trashedAt = now.subtract(const Duration(days: 2))]);
      expect(store.trashDays, 30);
      expect(store.daysLeft(store.bills.single, now: now), 28);
      store.trashDays = 0;
      expect(store.daysLeft(store.bills.single, now: now), isNull);
    });

    test('Archiv = ausgeglichen, Papierkorb ist getrennt; Wiederherstellen bringt zurück', () {
      final store = BillStore.memory([_bill('o', 'offen'), _bill('d', 'fertig', done: true)..settled = true]);
      expect(store.drafts.map((b) => b.id), ['o']);
      expect(store.finished.map((b) => b.id), ['d']);
      store.trash([store.bills.first]);
      expect(store.drafts, isEmpty);
      expect(store.trashed.map((b) => b.id), ['o']);
      store.untrash(store.trashed);
      expect(store.drafts.map((b) => b.id), ['o']);
    });

    test('Gruppen ohne Bons, Gruppe löschen lässt die Bons bestehen, Freunde aus Bons und von Hand', () {
      final b = _bill('a', 'a', group: 'Urlaub')..people = [Person('Anna', 1), Person('Jo', 2)];
      final store = BillStore.memory([b]);
      store.addGroup('Leer');
      expect(store.allGroups, ['Leer', 'Urlaub']);
      expect(store.groups, ['Urlaub']);
      store.deleteGroup('Urlaub');
      expect(store.bills.single.group, isNull);
      store.addFriend('Mia');
      expect(store.friends.map((f) => f.name).toSet(), {'Anna', 'Jo', 'Mia'});
      store.forgetFriend('Jo');
      expect(store.friends.map((f) => f.name).toSet(), {'Anna', 'Mia'});
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
