// Reader rules found with the world corpus (06.11., fasan-diagnose/tests/welt): each test fails without its rule. Lines are given
// as the OCR delivers them (one text line per row). MPL-2.0
import 'package:fasan_reader/model.dart';
import 'package:fasan_reader/reader.dart';
import 'package:flutter_test/flutter_test.dart';

Line _z(String t, int y) => Line(const [])
  ..text = t
  ..box = Box(0, y * 20.0, 500, y * 20.0 + 20)
  ..conf = 95
  ..glyphs = [for (final r in t.runes) Glyph(String.fromCharCode(r), 0.999)];

ReadResult _read(List<String> rows) => readLines([for (var i = 0; i < rows.length; i++) _z(rows[i], i)], null);

String _items(ReadResult r) => r.items.map((i) => '${i.name}=${i.amount}').join(' | ');

void main() {
  test('Gewichtszeile „0.482 kg NET @ \$4.50/kg 2.17“: Name eine Zeile höher, keine Steuerzeile (Woolworths)', () {
    final r = _read([
      'Woolworths',
      'TAX INVOICE - ABN 88 000 014 675',
      'MM Naturally RoastedChicken Double Brst 1.96',
      'Potato Red Washed Lse',
      '0.482 kg NET @ \$4.50/kg 2.17',
      'Apple Bravo LSE',
      '0.177 kg NET @ \$7.50/kg 1.33',
      'Mango Calypso 2.50',
      '4 SUBTOTAL \$7.96',
      'TOTAL \$7.96',
    ]);
    expect(_items(r), 'MM Naturally RoastedChicken Double Brst=196 | Potato Red Washed Lse=217 | Apple Bravo LSE=133 | Mango Calypso=250');
    expect(r.total, 796);
    expect(r.check.ok, isTrue);
  });

  test('Stückzeile „1.000ea @ \$ 8.99/ea \$ 8.99“: Name eine Zeile höher (Colonial)', () {
    final r = _read([
      'Chadstone VIC 3148',
      'Fruit \'N\' Nut Mix Premium 500g',
      '1.000ea @ \$ 8.99/ea \$ 8.99',
      'MANGOES TPP KG',
      '0.260kg @\$ 9.99/kg \$ 2.60',
      'Number of Items: 2',
      'Subtotal \$ 11.59',
      'Total Due \$ 11.59',
    ]);
    expect(_items(r), 'Fruit \'N\' Nut Mix Premium 500g=899 | MANGOES TPP=260');
  });

  test('Rundung mit verkehrtem Vorzeichen gedruckt: die Summe entscheidet (Colonial „Rounding \$ 0.02“ = −2 Cent)', () {
    final r = _read([
      'Chadstone VIC 3148',
      'CUSTARD APPLES KG 3.95',
      'BERRIES BLUEBERRIES 125G 8.99',
      'Subtotal \$ 12.94',
      'Rounding \$ 0.04',
      'Total Due \$ 12.90',
    ]);
    expect(r.total, 1290);
    expect(r.check.ok, isTrue);
    expect(r.items.where((i) => i.surcharge == 'rundung').map((i) => i.amount).toList(), [-4]);
  });

  test('Negative Rundung wird nie Rabatt am letzten Artikel', () {
    final r = _read([
      'Woolworths',
      'Mango Calypso 2.50',
      'Paper Shopping Bag 0.25',
      '2 SUBTOTAL \$2.75',
      'Rounding -\$0.01',
      'TOTAL \$2.74',
    ]);
    expect(r.items.firstWhere((i) => i.name.contains('Bag')).amount, 25);
    expect(r.total, 274);
  });

  test('„Total for 3 items: \$12.85“ ist die Summe, keine Stückzahl (Coles)', () {
    final r = _read([
      'coles',
      'Description \$',
      'UNCLE TOBYS PORRIDGE 1KG 6.50',
      'T2 FRENCH EARL GREY 25PACK 5.84',
      'BROOKS MANGOES 1EACH 0.50',
      'Sub Total: \$12.84',
      'Rounding: \$0.01',
      'Total for 3 items: \$12.85',
    ]);
    expect(r.total, 1285);
    expect(r.check.ok, isTrue);
  });

  test('Minus vor dem Währungszeichen „-\$1.00“ bleibt negativ', () {
    expect(amountsIn('CK DELI SALADS 2FOR\$6 -\$1.00', '.').map((a) => a.v).toList(), [-100]);
    expect(amountsIn('YOGURT 2 FOR £3 -£0.85', '.').map((a) => a.v).toList(), [-85]);
    expect(amountsIn('Mango 2.50', '.').map((a) => a.v).toList(), [250]);
  });

  test('Menge „13 X \$4.50 = \$58.50“ unter dem Namen (Shanghai Dynasty)', () {
    final r = _read([
      'BILL',
      'DESCRIPTION AMOUNT',
      'SML DIMSIM',
      '13 X \$4.50 = \$58.50',
      'Chinese tea',
      '10 X \$2.00 = \$20.00',
      'Total: \$78.50',
    ]);
    expect(r.items.map((i) => '${i.qty.round()}× ${i.name}=${i.amount}').join(' | '), '13× SML DIMSIM=5850 | 10× Chinese tea=2000');
  });

  test('„Korean Chicken Wings 1 item(s) \$15.00“: Zählwort gehört nicht zum Namen', () {
    final r = _read([
      'BILL',
      'Korean Chicken Wings 1 item(s) \$15.00',
      'Steamed Brown & White Rice',
      '1 item(s) \$3.00',
      'Sub Total \$18.00',
      'Total \$18.00',
    ]);
    expect(_items(r), 'Korean Chicken Wings=1500 | Steamed Brown & White Rice=300');
  });

  test('„Qty 2 @ \$2.00 each 4.00“ unter dem Namen: Menge 2 (Woolworths)', () {
    final r = _read([
      'Woolworths',
      'Mango Calypso 2.50',
      'Avocado Hass',
      'Qty 20 \$2.00 each 4.00',
      '3 SUBTOTAL \$6.50',
      'TOTAL \$6.50',
    ]);
    expect(r.items.map((i) => '${i.qty.round()}× ${i.name}=${i.amount}').join(' | '), '1× Mango Calypso=250 | 2× Avocado Hass=400');
  });

  test('„Sub Total :“ mit Leerzeichen ist Zwischensumme, nicht Summe (Coles)', () {
    final r = _read([
      'coles',
      'POTATO SALAD 250GRAM 3.50',
      'COLESLAW SALAD 250GRAM 3.50',
      'Sub Total : \$7.00',
      'Total for 2 items: \$6.00',
    ]);
    // the team discount line was not read: better unchecked with the printed total than „checked“ with the subtotal
    expect(r.total, 600);
    expect(r.check.ok, isFalse);
  });

  test('Mengenspalte vor dem Einzelpreis „EDE MICRO 3 KESKIKO 2 3,50 7,00“ (Finnland)', () {
    final r = _read([
      'Tuote Määrä A-hinta Summa',
      'EDE MICRO 3 KESKIKO 2 3,50 7,00',
      'ORT VELOCITY HOPE R 1 88,90 88,90',
      'YHTEENSÄ EUR 95,90',
    ]);
    expect(r.items.map((i) => '${i.qty.round()}× ${i.name}=${i.amount}').join(' | '), '2× EDE MICRO 3 KESKIKO=700 | 1× ORT VELOCITY HOPE R=8890');
  });

  test('„2 @ \$0.25 EACH“ unter dem Namen: Menge 2 (Coles)', () {
    final r = _read([
      'coles',
      'Mango Calypso 2.50',
      '100% RECYCLE PAPER B 1EACH 0.50',
      '2 @ \$0.25 EACH',
      'Sub Total: \$3.00',
      'Total for 3 items: \$3.00',
    ]);
    expect(r.items.map((i) => '${i.qty.round()}× ${i.name}=${i.amount}').join(' | '), '1× Mango Calypso=250 | 2× 100% RECYCLE PAPER B 1EACH=50');
  });

  test('Summenwort da, Betrag unlesbar: Bargeldzeile bestätigt nichts (blasser Druck)', () {
    final r = _read([
      'Colonial Chadstone VIC 3148',
      '* -Shopping Bag 0.10',
      'PAPAYA RED 0.10',
      'Total Que 51.',
      '19',
      'GST Boncorent 2.3',
      'Cash 0.20 52.0',
    ]);
    expect(r.check.ok, isFalse);
  });
}
