// Datum, Ort und Steuernummer aus Bonzeilen; Zeilen wie auf den echten Bons in fasan-diagnose/tests/echt.
import 'package:fasan_split/recognition/place.dart';
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

  check('Esplanada (PT, Ort in eigener Zeile)', ['ESPLANADA PRINCIPE REAL', 'NIF:506041743', 'Rua da Escola Politecnica', 'Jardim Principe Real 1250-099', 'Lisboa', '2026-10-24 FATURA SIMPLIFICADA N:', '11:52 MESA N: 105/0'],
      date: DateTime(2026, 10, 24), city: '1250-099 Lisboa', street: 'Rua da Escola Politecnica', tax: '506041743');
  check('Estrela do Bairro (Contribuinte)', ['ATCUD:J66TX9KV-1417', 'Estrela do Bairro', 'Varela e Mestre, Lda.', 'Rua Diario de Noticias no66 R/C', '1200-145 Lisboa', 'Tel. 920230989', 'Contribuinte: 510882897', '2026-10-23 TALAO DE CONTROLO N:'],
      date: DateTime(2026, 10, 23), city: '1200-145 Lisboa', street: 'Rua Diario de Noticias no66 R/C', tax: '510882897');
  check('Confeitaria Nacional (Consumidor final übersprungen)', ['Confeitaria Nacional Belem 2', 'Praça da Figueira 18B', '1100-241', 'Lisboa', 'N. Contrib. 500489793', 'NIF: Consumidor final', '2026-10-26 13:27'],
      date: DateTime(2026, 10, 26), city: '1100-241 Lisboa', street: 'Praça da Figueira 18B', tax: '500489793');
  check('McDonald\'s (NIF mit Leerzeichen, Datum mit Schrägstrich)', ['McDonald\'s Aeroporto Terminal 2', 'NIF e CRC Cascais: 502 167 017', 'Lagoas Park, Edificio 7 - Piso 2', '2740-244 Porto Salvo', 'REG 30 27/10/2026 15:19:16'],
      date: DateTime(2026, 10, 27), city: '2740-244 Porto Salvo', tax: '502167017');
  check('Aldi (zweistelliges Jahr)', ['Aldi Süd', 'BERGER STRASSE 159', '60385 FRANKFURT', '814998 Bio Spaghetti 0,85 A', '*1096 018/035/005/802 28.05.24 18:36', 'Ust.-ID-Nr.:DE 120353444'],
      date: DateTime(2024, 5, 28), city: '60385 FRANKFURT', street: 'BERGER STRASSE 159', tax: 'DE120353444');
  check('REWE (TSE-Zeit und Datum)', ['REWE', 'Heidestr.137', '60385 Frankfurt - Bornheim', 'UID Nr.: DE812706034', 'TSE-Start: 2026-04-11T23:07:11.000', '11.04.2026 23:08 Bon-Nr.:5257'],
      date: DateTime(2026, 4, 11), city: '60385 Frankfurt - Bornheim', street: 'Heidestr.137', tax: 'DE812706034');
  check('Green Soul (Ust.ID Nr)', ['Green Soul CBD, Head & Grow Shop', 'Hasengasse 9', '60311 Frankfurt am Main', 'Datum und Uhrzeit: 16.07.2026, 16:33', 'Ust.ID Nr: DE335161612'],
      date: DateTime(2026, 7, 16), city: '60311 Frankfurt am Main', street: 'Hasengasse 9', tax: 'DE335161612');
  test('QR-Datum und QR-NIF gewinnen', () {
    final m = extractMeta(['2026-10-24'], qrDate: '20261023', qrNif: '123456789', now: now);
    expect(m.date, DateTime(2026, 10, 23));
    expect(m.taxId, '123456789');
  });
  test('Unmögliche Daten und Zukunft werden verworfen', () {
    expect(extractMeta(['31.02.2026', '01.01.2031'], now: now).date, isNull);
  });
}
