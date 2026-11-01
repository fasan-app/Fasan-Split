import 'package:fasan_split/model/bill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Aufteilen verliert keinen Cent (größter Rest)', () {
    final p = Bill.split(1000, {0: 1, 1: 1, 2: 1});
    expect(p.values.reduce((a, b) => a + b), 1000);
    expect(p.values.toSet(), {333, 334});
    final q = Bill.split(-100, {0: 1, 1: 1, 2: 1});
    expect(q.values.reduce((a, b) => a + b), -100);
    final r = Bill.split(640, {0: 3, 1: 1}); // 4 × Pastel de Nata: 3 für A, 1 für B
    expect(r, {0: 480, 1: 160});
  });

  test('Je Person, Differenz zum Bon, Überweisungen an den Zahler', () {
    final b = Bill(id: '1', created: DateTime(2026), total: 3600, people: [Person('A', 0), Person('B', 1), Person('C', 2)], items: [
      BillItem(name: 'Wein', amount: 2400, shares: {0: 1, 1: 1, 2: 1}),
      BillItem(name: 'Bacalhau', amount: 1100, shares: {0: 1}),
    ])
      ..payer = 0;
    final pp = b.perPerson();
    expect(pp.values.reduce((a, c) => a + c), 3600, reason: 'Trinkgeld 1,00 wird anteilig verteilt');
    expect(b.transfers().map((x) => x.$1).toSet(), {1, 2});
    expect(b.transfers().every((x) => x.$2 == 0), isTrue);
  });

  test('Beträge lesen und schreiben', () {
    expect(parseMoney('12,5'), 1250);
    expect(parseMoney('-0,39'), -39);
    expect(parseMoney('−3.20 €'), -320);
    expect(parseMoney('abc'), isNull);
    expect(money(123456), '1234,56');
    expect(money(-39), '−0,39');
  });

  test('CSV mit Semikolon, Dezimalkomma und BOM', () {
    final b = Bill(id: '1', created: DateTime(2026), people: [Person('Anna', 0), Person('Jo', 1)], items: [BillItem(name: 'Sumo "Laranja"', amount: 350, shares: {0: 1, 1: 1})])..payer = 1;
    final csv = billCsv(b);
    expect(csv.startsWith('﻿'), isTrue);
    expect(csv, contains('"Sumo ""Laranja""";1;3,50;1,75;1,75'));
    expect(csv, contains('"Bezahlt von";;"Jo"'));
  });

  test('Speichern und Laden', () {
    final b = Bill(id: 'x', created: DateTime(2026, 11, 1), purpose: 'Test', total: 500, people: [Person('A', 3)], items: [BillItem(name: 'P', amount: 500, qty: 2, shares: {0: 2}, boxes: const [NBox(0.1, 0.2, 0.9, 0.25)])]);
    final c = Bill.fromJson(b.toJson());
    expect(c.purpose, 'Test');
    expect(c.its.first.shares, {0: 2.0});
    expect(c.its.first.boxes.first.y1, 0.25);
    expect(c.ps.first.color, 3);
  });
}
