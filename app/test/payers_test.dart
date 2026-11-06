// Fasan Split – several payers with different amounts, and what a receipt has more than its items (Nutzer 04.11.:
// „was wenn mehrere Leute gezahlt haben … unterschiedliche Beträge“, Ferreiras 7,90). MPL-2.0
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/flows/scan_bill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Drei Leute, zwei haben unterschiedlich bezahlt: wenige, exakte Überweisungen', () {
    // Anna 30, Ben 30, Cem 30 consumed (90); Anna paid 60, Ben paid 30
    final b = Bill(id: 'x', created: DateTime(2026, 11, 4), total: 9000, people: [Person('Anna', 0), Person('Ben', 1), Person('Cem', 2)], items: [
      BillItem(name: 'Essen', amount: 9000, shares: {0: 1, 1: 1, 2: 1}),
    ])
      ..paid = {0: 6000, 1: 3000}
      ..payer = 0;
    expect(b.multiPay, isTrue);
    expect(b.paidGap, 0);
    expect(b.transfers(), [(2, 0, 3000)], reason: 'nur Cem gibt Anna 30 €');
    expect(b.audit(), isEmpty);
    b.paid = {0: 6000, 1: 2000};
    expect(b.paidGap, 1000);
    expect(b.audit(), isNotEmpty, reason: 'Zahler ergeben nicht die Bon-Summe');
  });

  test('Mehrere Zahler bleiben beim Teilen und beim Entfernen einer Person richtig', () {
    final b = Bill(id: 'x', created: DateTime(2026, 11, 4), total: 3000, people: [Person('Anna', 0), Person('Ben', 1), Person('Cem', 2)], items: [
      BillItem(name: 'Essen', amount: 3000, shares: {0: 1, 1: 1, 2: 1}),
    ])
      ..paid = {1: 1000, 2: 2000}
      ..payer = 2;
    final doc = LwwDoc('me');
    BillSync.write(doc, b);
    final back = BillSync.read(doc, id: 'x');
    expect(back.paid, {1: 1000, 2: 2000});
    expect(Bill.fromJson(b.toJson()).paid, {1: 1000, 2: 2000});
    b.removePerson(0);
    expect(b.paid, {0: 1000, 1: 2000});
  });

  test('Ferreiras: 7,90 sind 10 % der Posten → Zeile „Bedienung 10 %“, anteilig', () {
    expect(remainderName(790, 7900), 'Bedienung 10 %');
    expect(remainderName(333, 7900), 'Ohne Postenzeile');
    final b = Bill(id: 'f', created: DateTime(2026, 10, 25), total: 8690, people: [Person('Chris', 0), Person('Angi', 1)], items: [
      BillItem(name: 'Polvo', amount: 2760, shares: {0: 1}),
      BillItem(name: 'Rest', amount: 5140, shares: {0: 1, 1: 1}),
      BillItem(name: remainderName(790, 7900), amount: 790, proportional: true),
    ])
      ..payer = 0;
    final pp = b.perPerson();
    // Chris had 27,60 + 25,70 = 53,30 of 79,00 → 67,47 % of 7,90 = 5,33
    expect(pp[0]! + pp[1]!, 8690);
    expect(pp[1], 2570 + 257);
  });
}
