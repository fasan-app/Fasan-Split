// Zuordnen: Alle springt standardmäßig nicht weiter, Plus fügt am Posten hinzu, Stück je Person als Bruch.
import 'package:fasan_split/main.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/assign.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bill bill() => Bill(id: 'x', created: DateTime(2026, 11, 3), total: 1380, people: [Person('Chris', 0), Person('Andi', 1)], items: [
        BillItem(name: 'Coca Cola', amount: 960, qty: 3),
        BillItem(name: 'Wasser', amount: 420),
      ]);

  Future<void> show(WidgetTester t, BillStore s, Bill b) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    t.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(t.platformDispatcher.clearLocalesTestValue);
    const tilt = MethodChannel('app.fasan.ui/tilt');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, null));
    // these tests use the focus mode, which is off by default since 04.11.
    s.assignExtraModes = true;
    AssignScreen.lastMode = AssignMode.focus;
    await t.pumpWidget(SplitApp(store: s, ui: FasanController(settings: const FasanSettings(reduceMotion: true)), home: AssignScreen(bill: b)));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Alle: 1,5 Stück je Person und kein automatisches Weiterspringen', (t) async {
    final s = BillStore.memory([]);
    final b = bill();
    await show(t, s, b);
    await t.tap(find.text('Alle'));
    await t.pump(const Duration(milliseconds: 2500));
    expect(find.text('1 / 2'), findsOneWidget, reason: 'bleibt auf dem Posten');
    expect(find.text('1,5'), findsNWidgets(2));
    expect(b.audit(), isEmpty);
    expect(b.perPerson()[0], 480);
  });

  testWidgets('Einstellung „Sofort“ springt weiter', (t) async {
    final s = BillStore.memory([])..autoNext = 2;
    await show(t, s, bill());
    await t.tap(find.text('Alle'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('Plus fügt eine Person hinzu und weist sie dem Posten zu', (t) async {
    final s = BillStore.memory([]);
    final b = bill();
    await show(t, s, b);
    await t.tap(find.text('Person hinzufügen'));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextField), 'Eva');
    await t.tap(find.text('Hinzufügen'));
    await t.pump(const Duration(milliseconds: 400));
    expect(b.ps.map((p) => p.name), ['Chris', 'Andi', 'Eva']);
    expect(b.its[0].shares[2], 1);
  });

  testWidgets('Langdruck: „Nur diese Person“', (t) async {
    final s = BillStore.memory([]);
    final b = bill();
    for (final it in b.its) {
      it.shares = {0: 1, 1: 1};
    }
    await show(t, s, b);
    await t.longPress(find.text('Andi').first);
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Nur diese Person'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    // only this person had it: all pieces of the item (07.11.: 3 × Cola for one person is complete only on purpose)
    expect(b.its[0].shares, {1: b.its[0].qty.toDouble()});
    expect(b.its[0].fill, ItemFill.complete);
  });

  testWidgets('3 × Cola: eine Person antippen = 1 Stück, Posten teilweise; Plus bis alle 3 verteilt = komplett (Nutzer 07.11.)', (t) async {
    final s = BillStore.memory([]);
    final b = bill();
    await show(t, s, b);
    await t.tap(find.text('Andi').first);
    await t.pump(const Duration(milliseconds: 300));
    final cola = b.its[0];
    expect(cola.shares, {1: 1.0});
    expect(cola.fill, ItemFill.partial, reason: 'ein Antippen darf nicht alle drei Stück zuteilen');
    expect(find.text('Noch 2 Stück offen'), findsOneWidget);
    expect(b.perPerson()[1], 320, reason: '1 von 3 Stück von 9,60 €');
    await t.tap(find.byIcon(Icons.add_circle_outline));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.byIcon(Icons.add_circle_outline));
    await t.pump(const Duration(milliseconds: 200));
    expect(cola.fill, ItemFill.complete);
    expect(find.text('Alle 3 Stück sind verteilt.'), findsOneWidget);
    expect(b.perPerson()[1], 960);
    expect(b.audit(), isEmpty);
  });

  testWidgets('Wasserflaschen: 2 für Andi, die dritte teilen Chris und Andi – „Stück teilen“', (t) async {
    final s = BillStore.memory([]);
    final b = bill();
    await show(t, s, b);
    await t.tap(find.text('Andi').first);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byIcon(Icons.add_circle_outline));
    await t.pump(const Duration(milliseconds: 200));
    expect(b.its[0].remainingUnits, 1);
    await t.tap(find.text('Stück teilen'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Chris')));
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Andi')));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await t.pump(const Duration(milliseconds: 300));
    expect(b.its[0].shares[1], closeTo(2.5, 1e-9));
    expect(b.its[0].shares[0], closeTo(0.5, 1e-9));
    expect(b.its[0].fill, ItemFill.complete);
    expect(b.perPerson()[1], 800);
    expect(b.perPerson()[0], 160);
    expect(b.audit(), isEmpty);
  });

  test('Person entfernen schiebt Anteile und Zahler nach', () {
    final b = Bill(id: 'y', created: DateTime(2026), people: [Person('A', 0), Person('B', 1), Person('C', 2)], items: [BillItem(name: 'x', amount: 300, shares: {0: 1, 2: 1})])..payer = 2;
    b.removePerson(1);
    expect(b.its[0].shares, {0: 1, 1: 1});
    expect(b.payer, 1);
  });
}
