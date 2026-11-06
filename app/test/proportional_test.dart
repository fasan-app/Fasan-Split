// Fasan Split – a line without items (VAT 0 % row, service) is shared like the other items, not evenly (Nutzer 04.11.).
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_core/bill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Anteilig: wer mehr hatte, zahlt mehr; Summe exakt; bleibt in JSON und im Abgleich', () {
    final b = Bill(id: 'f', created: DateTime(2026, 10, 25), total: 8690, people: [Person('Anna', 0), Person('Ben', 1)], items: [
      BillItem(name: 'Burrito', amount: 6000, shares: {0: 1}),
      BillItem(name: 'Tea', amount: 1900, shares: {1: 1}),
      BillItem(name: 'Ohne Postenzeile', amount: 790, proportional: true),
    ])
      ..payer = 0;
    final pp = b.perPerson();
    expect(pp[0]! + pp[1]!, 8690);
    expect(pp[0], 6000 + 600); // 790 × 6000/7900
    expect(pp[1], 1900 + 190);
    expect(b.audit(), isEmpty);
    expect(b.its[2].assigned, isTrue);
    expect(Bill.fromJson(b.toJson()).its[2].proportional, isTrue);
    final doc = LwwDoc('aa');
    BillSync.write(doc, b);
    expect(BillSync.read(doc, id: 'f').its.firstWhere((i) => i.name == 'Ohne Postenzeile').proportional, isTrue);
  });
}
