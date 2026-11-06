// Fixed amounts per person on an item (Aufteilen „fest“, Nutzer 06.11.). MPL-2.0
import 'package:fasan_split/collab/bill_sync.dart';
import 'package:fasan_split/collab/lww.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/model/split_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Fester Betrag zuerst, Rest nach Anteilen der anderen, Summe stimmt', () {
    final r = SplitMath.splitFixed(1000, {0: 1, 1: 1, 2: 1}, {0: 300});
    expect(r[0], 300);
    expect(r[1]! + r[2]!, 700);
    expect(r.values.fold<int>(0, (a, b) => a + b), 1000);
    // everybody fixed but the amounts do not add up: the difference is spread in proportion
    final q = SplitMath.splitFixed(1000, {0: 1, 1: 1}, {0: 300, 1: 600});
    expect(q.values.fold<int>(0, (a, b) => a + b), 1000);
    expect(q[0]! < q[1]!, isTrue);
    // fixed amount of someone who is not on the item does not count
    expect(SplitMath.splitFixed(900, {0: 1, 1: 1}, {2: 500}), SplitMath.split(900, {0: 1, 1: 1}));
  });

  test('Bon: Betrag je Person, Prüfung ohne Befund, Person entfernen verschiebt Festbeträge, Sync hin und zurück', () {
    final b = Bill(id: 'f', created: DateTime(2026, 11, 6), total: 2000, people: [Person('A', 0), Person('B', 1), Person('C', 2)], items: [
      BillItem(name: 'Fondue', amount: 2000, shares: {0: 1, 1: 1, 2: 1}, fixed: {2: 500}),
    ]);
    final pp = b.perPerson();
    expect(pp[2], 500);
    expect(pp[0]! + pp[1]!, 1500);
    expect(b.audit(), isEmpty);
    final doc = LwwDoc('aa');
    BillSync.write(doc, b);
    final back = BillSync.read(doc, id: 'f');
    expect(back.its.single.fixed, {2: 500});
    expect(back.perPerson(), pp);
    b.removePerson(0);
    expect(b.its.single.fixed, {1: 500});
    expect(Bill.fromJson(b.toJson()).its.single.fixed, {1: 500});
  });
}
