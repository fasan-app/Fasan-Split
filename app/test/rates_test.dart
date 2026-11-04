// Fasan Split – ECB rates: parsing the official file, cross rates, bills in another currency in the balances. MPL-2.0
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/model/settle.dart';
import 'package:fasan_split/state/rates.dart';
import 'package:flutter_test/flutter_test.dart';

// shape of eurofxref-hist-90d.xml (ecb.europa.eu/stats/eurofxref), shortened
const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
<gesmes:subject>Reference rates</gesmes:subject>
<Cube>
<Cube time='2026-11-03'><Cube currency='USD' rate='1.1000'/><Cube currency='GBP' rate='0.8800'/></Cube>
<Cube time='2026-10-31'><Cube currency='USD' rate='1.0000'/><Cube currency='GBP' rate='0.8000'/></Cube>
</Cube>
</gesmes:Envelope>''';

void main() {
  test('EZB-Datei lesen, Kreuzkurs', () {
    final days = parseEcb(xml);
    expect(days.length, 2);
    expect(days.first.day, DateTime(2026, 11, 3));
    expect(days.first.perEur['USD'], 1.1);
    expect(crossRate(days.first.perEur, 'USD', 'EUR'), closeTo(1 / 1.1, 1e-9));
    expect(crossRate(days.last.perEur, 'GBP', 'USD'), closeTo(1.25, 1e-9));
    expect(crossRate(days.last.perEur, 'XXX', 'EUR'), isNull);
  });

  test('Bon in Dollar zählt im Saldo in Euro', () {
    final b = Bill(id: 'u', created: DateTime(2026, 11, 3), total: 2000, done: true, currency: 'USD', rate: 0.9, people: [Person('Anna', 0), Person('Ben', 1)], items: [
      BillItem(name: 'x', amount: 2000, shares: {0: 1, 1: 1}),
    ])
      ..payer = 0;
    expect(b.toHome(1000), 900);
    expect(balances([b]), {'Anna': 900, 'Ben': -900});
    expect(Bill.fromJson(b.toJson()).rate, 0.9);
  });
}
