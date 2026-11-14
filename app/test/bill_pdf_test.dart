// SPDX-License-Identifier: MPL-2.0
// Fasan Split – bill as PDF (Roadmap 2, 14.11.): every item with quantity, name, people and amount, the total and each person's
// share are in the document, with € and umlauts. Invented bill only. The text check needs pdftotext (poppler); where it is missing
// only the structure is checked, and the test says so. MPL-2.0
import 'dart:io';

import 'package:fasan_core/bill.dart';
import 'package:fasan_split/ui/bill_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Bill bill() => Bill(id: 'p', created: DateTime(2026, 11, 14), total: 3150, purpose: 'Strandbar Erfunden', people: [Person('Pia', 0), Person('Jürgen', 1)], items: [
        BillItem(name: 'Sprudel', amount: 1050, qty: 3, shares: {0: 1, 1: 2}),
        BillItem(name: 'Käsebrot', amount: 2100, qty: 2, shares: {1: 1}),
      ])
        ..payer = 0;

  test('PDF enthält je Posten Menge, Name, Personen und Betrag, die Summe und den Anteil je Person', () async {
    final b = bill();
    final n0 = pdfItemName(b.its[0]), n1 = pdfItemName(b.its[1]); // plain names from the dictionary, as in the app
    final bytes = await billPdf(b, lang: 'de', fonts: await pdfFonts(), compress: false);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(pdfFileName(bill()), 'Strandbar-Erfunden-2026-11-14.pdf');
    final tool = await Process.run('which', ['pdftotext']);
    if (tool.exitCode != 0) {
      markTestSkipped('pdftotext fehlt: nur der Aufbau ist geprüft, nicht der Text');
      return;
    }
    final dir = Directory.systemTemp.createTempSync('pdf');
    final f = File('${dir.path}/b.pdf')..writeAsBytesSync(bytes);
    if (Platform.environment['FASAN_PDF_OUT'] case final out?) f.copySync(out); // to look at it (14.11.)
    final txt = (await Process.run('pdftotext', ['-layout', f.path, '-'])).stdout as String;
    dir.deleteSync(recursive: true);
    final lines = txt.split('\n').map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim()).toList();
    expect(lines.any((l) => l.startsWith('Strandbar Erfunden')), isTrue, reason: txt);
    expect(lines.any((l) => l.contains('14.11.2026') && l.contains('Bezahlt von Pia')), isTrue, reason: txt);
    expect(lines.any((l) => l == '3 $n0 Pia, Jürgen 10,50 €'), isTrue, reason: txt);
    expect(lines.any((l) => l == '2 $n1 Jürgen 21,00 €'), isTrue, reason: txt);
    expect(lines.any((l) => l == 'Summe 31,50 €'), isTrue, reason: txt);
    expect(lines.any((l) => l == 'Pia 3,50 €'), isTrue, reason: txt);
    expect(lines.any((l) => l == 'Jürgen 28,00 €'), isTrue, reason: txt);
  });
}
