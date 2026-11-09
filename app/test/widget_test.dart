// SPDX-License-Identifier: MPL-2.0
// Bedienablauf ohne Erkennung: Summe → Personen → Zuordnen (alle vier Varianten) → Bezahlt → Ergebnis.
import 'package:fasan_split/main.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/flow.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:fasan_split/ui/receipt_view.dart';

Bill demoBill() => Bill(id: 'demo', created: DateTime(2026, 11, 1), purpose: 'Abendessen', total: 4890, checked: true, items: [
      BillItem(name: 'Bacalhau', amount: 1850, boxes: const [NBox(0.05, 0.30, 0.95, 0.34)]),
      BillItem(name: 'Weißwein', amount: 2400, boxes: const [NBox(0.05, 0.35, 0.95, 0.39)]),
      BillItem(name: 'Törtchen', amount: 640, qty: 4, boxes: const [NBox(0.05, 0.40, 0.95, 0.44), NBox(0.05, 0.44, 0.6, 0.47)]),
    ]);

void main() {
  /// Adds a person through the picker sheet (type the name, take „New: name“).
  Future<void> addViaPicker(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('add-person')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Type a name'), name);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New: $name'));
    await tester.pumpAndSettle();
  }

  testWidgets('Ablauf: ein Bildschirm (Personen, Zuordnen, Zahler) bis zur Übersicht und zum Ergebnis', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory();
    final b = demoBill();
    // Korn und Bildstandwackeln laufen bei voller Akku-Stufe dauerhaft (FasanFilm-Ticker, 24 Hz), dann wird
    // pumpAndSettle nie fertig. Dieser Test prüft die Bedienung, darum mit „Animationen entfernen“.
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ui, home: ReviewScreen(bill: b)));
    await tester.pumpAndSettle();
    expect(find.text('Bacalhau'), findsOneWidget);
    // too early: nothing assigned, nobody paid – the button (it says „3 open“) tells what is missing instead of moving on
    await tester.tap(find.text('3 open'));
    await tester.pumpAndSettle();
    expect(find.byType(PayScreen), findsNothing);
    expect(find.textContaining('Add at least two people'), findsOneWidget);
    for (final n in ['Anna', 'Jo', 'Mia']) {
      await addViaPicker(tester, n);
    }
    expect(b.ps.map((p) => p.name), ['Anna', 'Jo', 'Mia']);
    // tap a person, then the items they had
    await tester.tap(find.byKey(const ValueKey('person-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bacalhau'));
    await tester.pumpAndSettle();
    expect(b.its[0].shares, {0: 1});
    await tester.tap(find.text('Bacalhau'));
    await tester.pumpAndSettle();
    expect(b.its[0].shares, isEmpty, reason: 'a second tap takes it back');
    await tester.tap(find.byKey(const ValueKey('person-0'))); // person no longer active
    await tester.pumpAndSettle();
    // the rest: split everything evenly from the menu
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split everything evenly'));
    await tester.pumpAndSettle();
    expect(b.unassigned, 0);
    // still no payer
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(PayScreen), findsNothing);
    expect(find.text('Choose who paid.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('payer')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FasanPersonChip, 'Jo'));
    await tester.pumpAndSettle();
    expect(b.payer, 1);
    await tester.tap(find.text('Done').last); // close the sheet
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(PayScreen), findsOneWidget);
    expect(b.perPerson().values.reduce((a, c) => a + c), 4890);
    await tester.tap(find.byType(FasanButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(store.bills.single.id, 'demo');
    expect(store.bills.single.done, isTrue);
  });

  testWidgets('Angefangen: Speichern und schließen behält die Rechnung, Fortsetzen im Bon-Bildschirm', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory()..onboarded = true;
    final b = demoBill();
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ui));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(HomeScreen))).push(MaterialPageRoute(builder: (_) => ReviewScreen(bill: b)));
    await tester.pumpAndSettle();
    await addViaPicker(tester, 'Anna');
    await tester.tap(find.text('Continue later'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(store.drafts.single.id, 'demo');
    expect(store.drafts.single.step, 1);
    expect(store.drafts.single.ps.single.name, 'Anna');
    expect(find.text('No group'), findsOneWidget, reason: 'Überschrift (der Gruppenschalter zeigt All groups)');
    await tester.tap(find.text('Abendessen'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.text('Anna'), findsWidgets, reason: 'the person is still there');
    // back from the resumed bill leads home
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Bon-Ansicht: Person wählen, Zeile antippen ordnet zu; Tipp daneben rastet ein; Mengenspalte im Kasten', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('bon');
    final f = File('${dir.path}/bon.png')..writeAsBytesSync(img.encodePng(img.Image(width: 400, height: 1000)..clear(img.ColorRgb8(250, 250, 250))));
    final b = demoBill()
      ..imagePath = f.path
      ..imageAspect = 0.4
      ..people = [Person('Anna', 0), Person('Jo', 1)];
    var changed = 0;
    await tester.pumpWidget(SplitApp(
      store: BillStore.memory(),
      ui: FasanController(settings: const FasanSettings(reduceMotion: true)),
      home: Scaffold(body: ReceiptAssign(bill: b, onChanged: () => changed++)),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.tap(find.text('Anna'));
    await tester.pump();
    // the receipt is fitted to the width: x/y in the image map 1:1 onto the area below the bars
    final area = tester.getTopLeft(find.byType(InteractiveViewer));
    final w = tester.getSize(find.byType(InteractiveViewer)).width - 44, h = w / 0.4; // 44 dp avatar gutter
    // the view starts near the first item row (clamped at the end of a short receipt): read the real shift
    final shift = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value.getTranslation();
    final at = area + Offset(0, shift.y);
    // first item row is y 0.30–0.34; tap the far left (quantity column, outside the old name box)
    await tester.tapAt(at + Offset(0.06 * w, 0.32 * h));
    await tester.pump();
    expect(b.its[0].shares, {0: 1.0});
    // a tap just below the second row (0.39–0.40 is the gap to the third) snaps to the nearer second row
    await tester.tapAt(at + Offset(0.5 * w, 0.392 * h));
    await tester.pump();
    expect(b.its[1].shares, {0: 1.0});
    expect(changed, 2);
  });

  testWidgets('Erster Start: Einführung erscheint, Überspringen führt zur leeren Startseite und bleibt gemerkt', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory();
    await tester.pumpWidget(SplitApp(store: store, ui: FasanController(settings: const FasanSettings(reduceMotion: true))));
    await tester.pumpAndSettle();
    expect(find.text('Photograph the receipt'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Try an example'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(store.onboarded, isTrue);
  });

  testWidgets('Bon ohne Fotos (gelöscht oder aus 0.1) stürzt nicht ab, zeigt Digital', (tester) async {
    final b = demoBill()..people = [Person('Anna', 0)];
    await tester.pumpWidget(SplitApp(
      store: BillStore.memory()..onboarded = true,
      ui: FasanController(settings: const FasanSettings(reduceMotion: true)),
      home: ReceiptScreen(bill: b, initialLayer: ReceiptLayer.original),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(DigitalReceipt), findsOneWidget);
  });

  testWidgets('Schritt 1: Posten −198, Summe auf 198 getippt – Vorzeichen wird gedreht, keine 396-€-Differenz, Rückgängig geht', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory();
    final b = Bill(id: 'neg', created: DateTime(2026, 11, 5), purpose: 'Stadtrundfahrt', items: [BillItem(name: 'Stadtrundfahrt', amount: -19800)]);
    store.upsert(b);
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ui, home: ReviewScreen(bill: b)));
    await tester.pumpAndSettle();
    // total empty, item negative: the sign question comes first (paid or refund) – the user instead types the total
    final totalField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Total');
    await tester.enterText(totalField, '198,00');
    await tester.pumpAndSettle();
    expect(b.total, 19800);
    expect(b.its.single.amount, 19800, reason: 'item turned');
    expect(find.textContaining('differ by'), findsNothing);
    expect(find.textContaining('Signs of the items turned'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(b.its.single.amount, -19800);
    expect(b.total, 19800);
  });
}

