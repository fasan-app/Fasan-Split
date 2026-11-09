// SPDX-License-Identifier: MPL-2.0
// Datum, Ort und Steuernummer aus Bonzeilen; Zeilen nach dem Muster echter Bons, aber vollständig erfunden (keine echten Lokale, Adressen oder Steuernummern).
import 'package:fasan_reader/place.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 2);
  void check(String name, List<String> lines, {required DateTime date, required String city, String? street, String? tax}) {
    test(name, () {
      final m = extractMeta(lines, now: now);
      expect(m.date, date, reason: 'Datum');
      expect(m.postcodeCity, city, reason: 'PLZ/Ort');
      if (street != null) expect(m.street, street, reason: 'Straße');
      if (tax != null) expect(m.taxId, tax, reason: 'NIF/USt');
    });
  }

  check('Café Beispiel (PT, Ort in eigener Zeile)', ['CAFE BEISPIEL PRACA', 'NIF:500000018', 'Rua das Flores Imaginarias', 'Jardim Exemplo 1000-001', 'Vilaficticia', '2026-03-12 FATURA SIMPLIFICADA N:', '11:52 MESA N: 105/0'],
      date: DateTime(2026, 3, 12), city: '1000-001 Vilaficticia', street: 'Rua das Flores Imaginarias', tax: '500000018');
  check('Loja Exemplo (Contribuinte)', ['ATCUD:AAAAAAAA-0001', 'Loja Exemplo', 'Exemplo e Filhos, Lda.', 'Rua Fantasia no12 R/C', '2000-002 Vilaficticia', 'Tel. 900000000', 'Contribuinte: 510000029', '2026-03-11 TALAO DE CONTROLO N:'],
      date: DateTime(2026, 3, 11), city: '2000-002 Vilaficticia', street: 'Rua Fantasia no12 R/C', tax: '510000029');
  check('Pastelaria Modelo (Consumidor final übersprungen)', ['Pastelaria Modelo 2', 'Praça Imaginada 18B', '3000-003', 'Vilaficticia', 'N. Contrib. 502000031', 'NIF: Consumidor final', '2026-03-14 13:27'],
      date: DateTime(2026, 3, 14), city: '3000-003 Vilaficticia', street: 'Praça Imaginada 18B', tax: '502000031');
  check('Burger Exemplo (NIF mit Leerzeichen, Datum mit Schrägstrich)', ['Burger Exemplo Terminal 2', 'NIF e CRC Cidadeficticia: 501 000 046', 'Parque Exemplo, Edificio 7 - Piso 2', '4000-004 Portoficticio', 'REG 30 15/03/2026 15:19:16'],
      date: DateTime(2026, 3, 15), city: '4000-004 Portoficticio', tax: '501000046');
  check('Markt Beispiel (zweistelliges Jahr)', ['Markt Beispiel', 'MUSTERSTRASSE 1', '12345 BEISPIELSTADT', '814998 Bio Spaghetti 0,85 A', '*1096 018/035/005/802 28.05.24 18:36', 'Ust.-ID-Nr.:DE 111111111'],
      date: DateTime(2024, 5, 28), city: '12345 BEISPIELSTADT', street: 'MUSTERSTRASSE 1', tax: 'DE111111111');
  check('Supermarkt Muster (TSE-Zeit und Datum)', ['SUPERMARKT MUSTER', 'Beispielweg 2', '12345 Beispielstadt - Nord', 'UID Nr.: DE222222222', 'TSE-Start: 2026-05-17T23:07:11.000', '17.05.2026 23:08 Bon-Nr.:1234'],
      date: DateTime(2026, 5, 17), city: '12345 Beispielstadt - Nord', street: 'Beispielweg 2', tax: 'DE222222222');
  check('Laden Probe (Ust.ID Nr)', ['Laden Probe, Kiosk & Mehr', 'Probegasse 3', '12345 Beispielstadt am Main', 'Datum und Uhrzeit: 21.06.2026, 16:33', 'Ust.ID Nr: DE333333333'],
      date: DateTime(2026, 6, 21), city: '12345 Beispielstadt am Main', street: 'Probegasse 3', tax: 'DE333333333');
  test('QR-Datum und QR-NIF gewinnen', () {
    final m = extractMeta(['2026-03-12'], qrDate: '20260313', qrNif: '123456789', now: now);
    expect(m.date, DateTime(2026, 3, 13));
    expect(m.taxId, '123456789');
  });
  test('Unmögliche Daten und Zukunft werden verworfen', () {
    expect(extractMeta(['31.02.2026', '01.01.2031'], now: now).date, isNull);
  });

  test('NIF-Prüfziffer (Modulo 11)', () {
    expect(validNifPt('500000018'), isTrue);
    expect(validNifPt('510000029'), isTrue);
    expect(validNifPt('500000019'), isFalse);
    expect(validNifPt('5108828'), isFalse);
  });

  // Zeilen nach dem Muster der Protokolle 02.11. (erfunden): der Gewinner für die Posten hatte keinen oder einen verlesenen Kopf.
  test('Kopf aus dem besten Durchlauf, nicht aus dem Posten-Gewinner (Restaurante Exemplo)', () {
    final h = bestHeader([
      ['CONSUMIDOR FINAL', 'Contribuinte:Consumidor final.', 'QTD UNI DESCRICAO VA 3,50 VALOR', 'Un1 TULIPA 23% 3,50'],
      ['RESTAURANTE EXEMPLO', 'EMPRESA VALIDA LDA', 'NIF: 510000029', 'RUA IMAGINARIA DO SUL 31A', '2000-005 VILAFICTICIA', 'TELF: 200 000 000',
        '2026-03-13 FATURA-RECIBO N:', 'Original FT 1A2601/11114', 'CONSUMIDOR FINAL', 'QTD UNI DESCRICAO IVA LOR'],
    ], now: now);
    expect(h.shop, 'RESTAURANTE EXEMPLO');
    expect(h.meta.taxId, '510000029');
    expect(h.meta.address, 'RUA IMAGINARIA DO SUL 31A, 2000-005 VILAFICTICIA');
    expect(h.meta.date, DateTime(2026, 3, 13));
  });

  test('Verlesener Kopf verliert gegen sauberen (Loja Exemplo)', () {
    final h = bestHeader([
      ['ATOUD AAAAAAAA-0001', 'Loja Exemplo,', 'Exemplo e Filhos,tidia', 'Vara fantasla hobo R/C', '2000-002 Vil00.c',
        'Centribuinte: 5l00o0o29', 'TALAO DE CONTROLO N:', '2026-03-11', 'QTD UNI DESCRICÃO IVA VALOR'],
      ['ATCUD:AAAAAAAA-0001', 'Loja Exemplo', 'Exemplo e Filhos, Lda.', 'Rua Fantasia no12 R/C', '2000-002 Vilaficticia',
        'Tel. 900000000 chamada para a rede fixa', 'Contribuinte: 510000029', '2026-03-11 TALÃO DE CONTROLO N:', 'QTD UNI DESCRICAO'],
    ], now: now);
    expect(h.shop, 'Loja Exemplo');
    expect(h.meta.taxId, '510000029');
    expect(h.meta.address, 'Rua Fantasia no12 R/C, 2000-002 Vilaficticia');
  });

  // Abbruchkriterium der Erkennung: Name plus gültige Steuernummer oder sauber gelesene Adresse.
  group('ReceiptHeader.complete', () {
    test('Name, gültige NIF und saubere Adresse genügen', () {
      final h = bestHeader([
        ['RESTAURANTE EXEMPLO', 'EMPRESA VALIDA LDA', 'NIF: 510000029', 'RUA IMAGINARIA DO SUL 31A', '2000-005 VILAFICTICIA', '2026-03-13 FATURA-RECIBO N:', 'QTD UNI DESCRICAO IVA LOR'],
      ], now: now);
      expect(h.complete, isTrue);
    });
    test('verlesene NIF und verlesene Adresse: nicht vollständig (Loja Exemplo, schlechter Durchlauf)', () {
      final h = bestHeader([
        ['ATOUD AAAAAAAA-0001', 'Loja Exemplo,', 'Vara fantasla hobo R/C', '2000-002 Vil00.c', 'Centribuinte: 5l00o0o29', '2026-03-11', 'QTD UNI DESCRICÃO IVA VALOR'],
      ], now: now);
      expect(h.complete, isFalse);
    });
    test('ohne Namen nie vollständig', () {
      final h = bestHeader([
        ['NIF: 510000029', '2000-005 VILAFICTICIA', '2026-03-13 12:03', 'QTD UNI DESCRICAO IVA LOR'],
      ], now: now);
      expect(h.shop, '');
      expect(h.complete, isFalse);
    });
    test('Adresse ohne Steuernummer reicht nicht, mit USt-ID schon (Marktkette: erst die ganze Adresse)', () {
      final ohne = bestHeader([
        ['Bäckerei Sonnenschein', 'Probegasse 3', '12345 Beispielstadt am Main', '21.06.2026, 16:33'],
      ], now: now);
      expect(ohne.complete, isFalse);
      final mit = bestHeader([
        ['Laden Probe, Kiosk & Mehr', 'Probegasse 3', '12345 Beispielstadt am Main', 'Ust.ID Nr: DE333333333'],
      ], now: now);
      expect(mit.complete, isTrue);
    });
    test('USt-ID ohne Postleitzahl reicht nicht (Supermarkt Muster)', () {
      final h = bestHeader([
        ['SUPERMARKT MUSTER', 'Beispielweg 2', 'UID Nr.: DE222222222', '17.05.2026 23:08 Bon-Nr.:1234'],
      ], now: now);
      expect(h.complete, isFalse);
    });
  });
}
