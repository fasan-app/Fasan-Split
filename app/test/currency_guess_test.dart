// SPDX-License-Identifier: MPL-2.0
// Currency read from the receipt (Roadmap 2, 14.11.): invented lines only. The real receipts are checked in test/e2e_test.dart
// („GESAMT Währung“). MPL-2.0
import 'package:fasan_reader/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Klare Zeichen entscheiden, ein einzelner Treffer nicht, Gleichstand nicht', () {
    expect(guessCurrency(['Kaffee 3,50 €', 'Kuchen 4,20 €', 'SUMME EUR 7,70']), 'EUR');
    expect(guessCurrency(['Rösti 18.50 CHF', 'Total CHF 24.00', 'MWST 8.1%']), 'CHF');
    expect(guessCurrency(['Tea £2.40', 'Scone £3.10', 'TOTAL GBP 5.50']), 'GBP');
    expect(guessCurrency(['Coffee \$3.50', 'Bagel \$4.25', 'TOTAL \$7.75']), 'USD');
    expect(guessCurrency(['Pivo 59 Kč', 'Celkem 118 Kč']), 'CZK');
    expect(guessCurrency(['Brot 2,10', 'Summe 2,10']), isNull, reason: 'kein Zeichen');
    expect(guessCurrency(['Total CHF 24.00']), isNull, reason: 'nur ein Treffer');
    expect(guessCurrency(['12,00 €', 'CHF 12.00', '€ 3', 'CHF 3']), isNull, reason: 'Gleichstand entscheidet nichts');
  });

  test('Kein Fehlalarm durch ähnliche Wörter', () {
    expect(guessCurrency(['TLF 0049 123', 'Fritten 3,50 €', 'Summe 3,50 €']), 'EUR', reason: '„TLF“ ist nicht TL');
    expect(guessCurrency(['Nr. 4711 SEKT', 'Sekt 9,90 €', 'Summe 9,90 €']), 'EUR', reason: '„SEKT“ ist nicht SEK');
  });
}
