// Bedienablauf ohne Erkennung: Summe → Personen → Zuordnen (alle vier Varianten) → Bezahlt → Ergebnis.
import 'package:fasan_split/main.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/assign.dart';
import 'package:fasan_split/ui/flow.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    final store = BillStore.memory();
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
    await tester.tap(find.byIcon(Icons.groups_2_outlined)); // split everything evenly
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
  });

  test('Zoom im Bon: jede Zeile mindestens 48 dp', () {
    final b = demoBill()..imageAspect = 0.4;
    final w = ReceiptAssignZoom.width(b, 393, 48);
    final h = w / 0.4;
    for (final it in b.its) {
      for (final x in it.boxes) {
        expect((x.y1 - x.y0) * h, greaterThanOrEqualTo(48 - 1e-6));
      }
    }
  });
}
