// Bedienablauf ohne Erkennung: Summe → Personen → Zuordnen (alle vier Varianten) → Bezahlt → Ergebnis.
import 'package:fasan_split/main.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/assign.dart';
import 'package:fasan_split/ui/flow.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:fasan_split/ui/receipt_view.dart';

Bill demoBill() => Bill(id: 'demo', created: DateTime(2026, 11, 1), purpose: 'Abendessen', total: 4890, checked: true, items: [
      BillItem(name: 'Bacalhau à Brás', amount: 1850, boxes: const [NBox(0.05, 0.30, 0.95, 0.34)]),
      BillItem(name: 'Vinho Verde', amount: 2400, boxes: const [NBox(0.05, 0.35, 0.95, 0.39)]),
      BillItem(name: 'Pastel de Nata', amount: 640, qty: 4, boxes: const [NBox(0.05, 0.40, 0.95, 0.44), NBox(0.05, 0.44, 0.6, 0.47)]),
    ]);

void main() {
  testWidgets('Ablauf von Summe bis Ergebnis', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // this test walks through all four assign modes: focus and cards are switched on (off by default since 04.11.)
    final store = BillStore.memory()..assignExtraModes = true;
    AssignScreen.lastMode = AssignMode.focus;
    final b = demoBill();
    // Korn und Bildstandwackeln laufen bei voller Akku-Stufe dauerhaft (FasanFilm-Ticker, 24 Hz), dann wird
    // pumpAndSettle nie fertig. Dieser Test prüft die Bedienung, darum mit „Animationen entfernen“.
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ui, home: ReviewScreen(bill: b)));
    await tester.pumpAndSettle();
    expect(find.text('Bacalhau à Brás'), findsOneWidget);
    await tester.tap(find.byType(FasanButton).last); // Next
    await tester.pumpAndSettle();
    expect(find.byType(PeopleScreen), findsOneWidget);
    for (final n in ['Anna', 'Jo', 'Mia']) {
      await tester.enterText(find.byType(TextField), n);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }
    expect(b.ps.length, 3);
    await tester.tap(find.byType(FasanButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(AssignScreen), findsOneWidget);
    // Fokus: first item for Anna, then "Everyone" for the rest
    await tester.tap(find.widgetWithText(FasanPersonChip, 'Anna'));
    await tester.pumpAndSettle();
    expect(b.its[0].shares, {0: 1});
    // other variants render
    for (final label in ['List', 'Cards', 'Focus']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    await tester.tap(find.byIcon(Icons.more_vert_rounded)); // menu „Mehr“ → split everything evenly
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split everything evenly'));
    await tester.pumpAndSettle();
    expect(b.unassigned, 0);
    await tester.tap(find.byType(FasanButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(PayScreen), findsOneWidget);
    await tester.tap(find.widgetWithText(FasanPersonChip, 'Jo'));
    await tester.pumpAndSettle();
    expect(b.payer, 1);
    expect(b.perPerson().values.reduce((a, c) => a + c), 4890);
    await tester.tap(find.byType(FasanButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(store.bills.single.id, 'demo');
    expect(store.bills.single.done, isTrue);
  });

  testWidgets('Angefangen: Speichern und schließen behält die Rechnung, Fortsetzen am letzten Schritt', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory()..onboarded = true;
    final b = demoBill();
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ui));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(HomeScreen))).push(MaterialPageRoute(builder: (_) => PeopleScreen(bill: b)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(store.drafts.single.id, 'demo');
    expect(store.drafts.single.step, 2);
    expect(find.text('No group'), findsOneWidget);
    await tester.tap(find.text('Abendessen'));
    await tester.pumpAndSettle();
    expect(find.byType(PeopleScreen), findsOneWidget);
    // back from a resumed step leads to the previous step, then home (Nutzer 02.11.)
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.byType(PeopleScreen), findsNothing);
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
}
