// Direction of a bill: amounts stay positive, a negative total asks "paid or money back?". MPL-2.0
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/flow.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Bill uber() {
  final b = Bill(id: 'u', created: DateTime(2026, 10, 25), purpose: 'Uber', total: -1298);
  b.its.add(BillItem(name: 'Fahrt', amount: -1298));
  b.ps.addAll([Person('Anna', 0), Person('Ben', 1)]);
  for (final it in b.its) {
    it.shares = {0: 1, 1: 1};
  }
  return b;
}

void main() {
  test('Negative Summe löst die Frage aus, positive und einzelne negative Zeilen nicht', () {
    expect(uber().needsSignQuestion, isTrue);
    final ok = Bill(id: 'x', created: DateTime(2026), total: 1000);
    ok.its.addAll([BillItem(name: 'Essen', amount: 1200), BillItem(name: 'Rabatt', amount: -200)]);
    expect(ok.needsSignQuestion, isFalse);
  });

  test('Es wurde bezahlt: alles positiv, Richtung normal', () {
    final b = uber()..payer = 0;
    b.resolveSign(refund: false);
    expect(b.total, 1298);
    expect(b.its.single.amount, 1298);
    expect(b.refund, isFalse);
    expect(b.transfers(), [(1, 0, 649)]); // Ben schuldet Anna
    expect(b.audit(), isEmpty);
  });

  test('Geld kam zurück: alles positiv, Richtung umgekehrt', () {
    final b = uber()..payer = 0;
    b.resolveSign(refund: true);
    expect(b.total, 1298);
    expect(b.refund, isTrue);
    expect(b.transfers(), [(0, 1, 649)]); // Anna gibt Ben seinen Anteil zurück
    expect(b.audit(), isEmpty);
  });

  test('Ohne Summe zählt die Postensumme; zweite Antwort ändert nichts', () {
    final b = uber()..total = null;
    expect(b.needsSignQuestion, isTrue);
    b.resolveSign(refund: true);
    b.resolveSign(refund: false);
    expect(b.refund, isTrue, reason: 'schon positiv: keine zweite Umkehr');
    expect(b.its.single.amount, 1298);
  });

  test('Richtung bleibt in JSON und im Gruppenabgleich erhalten', () {
    final b = uber()..payer = 0;
    b.resolveSign(refund: true);
    expect(Bill.fromJson(b.toJson()).refund, isTrue);
    final doc = LwwDoc('aa');
    BillSync.write(doc, b);
    expect(BillSync.read(doc, id: 'u').refund, isTrue);
  });

  test('Erstattung: CSV nennt den Empfänger, Personen-Summe sinkt statt zu steigen', () {
    final r = uber()..payer = 0..done = true;
    r.resolveSign(refund: true);
    expect(billCsv(r), contains('Erstattung erhalten von'));
    final paid = Bill(id: 'p', created: DateTime(2026), purpose: 'Essen', total: 2000, done: true)..payer = 0;
    paid.its.add(BillItem(name: 'Essen', amount: 2000)..shares = {0: 1, 1: 1});
    paid.ps.addAll([Person('Anna', 0), Person('Ben', 1)]);
    final store = BillStore.memory([paid, r]);
    final ben = store.friends.firstWhere((f) => f.name == 'Ben');
    expect(ben.sum, 1000 - 649);
  });

  testWidgets('Ergebnis zeigt die Erstattung', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final b = uber()..payer = 0..done = true;
    b.resolveSign(refund: true);
    final store = BillStore.memory([b])..onboarded = true;
    final ctl = FasanController(settings: FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ctl, home: ResultScreen(bill: b)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RefundNote), findsOneWidget);
    expect(find.textContaining('Erstattung'), findsWidgets);
  });
}
