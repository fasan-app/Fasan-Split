// SPDX-License-Identifier: MPL-2.0
// Fasan Split – a bill as PDF (Roadmap 2, Familienbeschluss 02.11.: „drei Ansichten, digital auch als PDF“). The digital view on
// paper: what, when, total, who paid, every item with quantity, amount and people, and what each person's share is. Built with the
// pdf package (Apache-2.0, pure Dart, also on the web); the font comes from the app bundle (Inter of fasan_ui), never from the net.
// No photo of the receipt goes in: the PDF is meant to be passed on, the photo stays in the app. MPL-2.0
import 'dart:typed_data';

import 'package:fasan_core/bill.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/tr.dart' show trLang;
import 'common.dart' show showNote;

/// Fonts of the PDF: Inter regular and bold of fasan_ui (they carry €, umlauts and the minus sign).
Future<({ByteData regular, ByteData bold})> pdfFonts() async => (
      regular: await rootBundle.load('packages/fasan_ui/fonts/Inter-400.ttf'),
      bold: await rootBundle.load('packages/fasan_ui/fonts/Inter-700.ttf'),
    );

/// Item name for paper: the plain name without its symbol (emoji are not in the PDF font), else the cleaned receipt name.
String pdfItemName(BillItem it) => it.food?.name ?? it.cleanName;

/// The PDF bytes of [b] in [lang] ('de' or 'en'). [compress] off only for tests (the text can then be read in the bytes).
Future<Uint8List> billPdf(Bill b, {required String lang, required ({ByteData regular, ByteData bold}) fonts, bool compress = true}) {
  final de = lang == 'de';
  final cur = b.currency == null || b.currency == 'EUR' ? '€' : b.currency!;
  String amt(int c) => '${money(c, de: de)} $cur';
  final reg = pw.Font.ttf(fonts.regular), bold = pw.Font.ttf(fonts.bold);
  final theme = pw.ThemeData.withFont(base: reg, bold: bold);
  final title = b.purpose.trim().isEmpty ? trLang(lang, 'pdf.untitled') : b.purpose.trim();
  final d = b.date;
  String two(int n) => n.toString().padLeft(2, '0');
  final date = de ? [d.day, d.month, d.year].join('.') : [d.year, two(d.month), two(d.day)].join('-'); // 14.11.2026 / 2026-11-14
  final payer = b.payer != null && b.payer! < b.ps.length ? b.ps[b.payer!].name : null;
  final per = b.perPerson();
  final doc = pw.Document(compress: compress, theme: theme, title: title, creator: 'Fasan Split', producer: 'Fasan Split');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => [
      pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 22)),
      pw.SizedBox(height: 4),
      pw.Text([date, if (payer != null) trLang(lang, 'pdf.paidBy', [payer])].join(' · '), style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: [trLang(lang, 'pdf.qty'), trLang(lang, 'pdf.item'), trLang(lang, 'pdf.who'), trLang(lang, 'pdf.amount')],
        data: [
          for (final it in b.its)
            [
              '${it.qty}',
              pdfItemName(it),
              [for (final e in it.shares.entries) if (e.value > 0 && e.key < b.ps.length) b.ps[e.key].name].join(', '),
              amt(it.amount),
            ],
        ],
        headerStyle: pw.TextStyle(font: bold, fontSize: 10),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignments: {0: pw.Alignment.centerRight, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft, 3: pw.Alignment.centerRight},
        headerAlignments: {0: pw.Alignment.centerRight, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft, 3: pw.Alignment.centerRight},
        columnWidths: {0: const pw.FixedColumnWidth(48), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(2), 3: const pw.FixedColumnWidth(80)},
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5), bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.5)),
        headerDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey600))),
      ),
      pw.SizedBox(height: 8),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Text('${trLang(lang, 'pdf.total')}  ', style: pw.TextStyle(font: bold, fontSize: 12)),
        pw.Text(amt(b.effectiveTotal), style: pw.TextStyle(font: bold, fontSize: 12)),
      ]),
      if (per.values.any((v) => v != 0)) ...[
        pw.SizedBox(height: 20),
        pw.Text(trLang(lang, 'pdf.perPerson'), style: pw.TextStyle(font: bold, fontSize: 12)),
        pw.SizedBox(height: 6),
        for (final e in per.entries)
          if (e.key < b.ps.length)
            pw.Row(children: [pw.Expanded(child: pw.Text(b.ps[e.key].name, style: const pw.TextStyle(fontSize: 11))), pw.Text(amt(e.value), style: const pw.TextStyle(fontSize: 11))]),
      ],
      pw.SizedBox(height: 24),
      pw.Text(trLang(lang, 'pdf.footer'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ],
  ));
  return doc.save();
}

/// File name for [b]: purpose and date, only safe characters.
String pdfFileName(Bill b) {
  final base = b.purpose.trim().isEmpty ? 'Bon' : b.purpose.trim();
  final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9ÄÖÜäöüß _-]'), '').replaceAll(' ', '-');
  final d = b.date;
  return '${safe.isEmpty ? 'Bon' : safe}-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.pdf';
}

/// „Als PDF teilen“ from the bill menu: builds the PDF and hands it to the share sheet of the system; where there is none (desktop
/// browsers without Web Share), it is saved as a file instead – the same two ways as the backup (backup_ui.dart).
Future<void> sharePdfFlow(BuildContext context, Bill b, String lang) async {
  final bytes = await billPdf(b, lang: lang, fonts: await pdfFonts());
  final name = pdfFileName(b);
  try {
    final r = await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)], subject: name));
    if (r.status != ShareResultStatus.unavailable) return;
  } catch (_) {
    // no share sheet here: save instead
  }
  final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'application/pdf');
  if (uri != null && context.mounted) showNote(context, trLang(lang, 'pdf.saved'));
}
