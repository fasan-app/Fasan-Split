// Fasan Split – date and place of a receipt from its printed lines (Beschluss 02.11.: Ort und Datum aus dem Bon selbst,
// weil Bons oft später erfasst werden; GPS nur als Hinweis). Tested against fasan-diagnose/tests/echt. MPL-2.0
//
// - Date: ISO (2026-10-24), German/PT (24.10.2026, 24/10/2026, 28.05.24). Years 2000 … next year only.
// - Address: the line with a postcode (PT „1250-099 Lisboa“, DE „60385 Frankfurt“) plus the street line above it
//   (street word or a house number). Searched top-down, so the shop's address wins over later card-terminal blocks.
// - NIF/VAT: PT „NIF“, „Contribuinte“, „N. Contrib.“ with 9 digits (the customer's „Consumidor final“ is skipped),
//   DE „USt-ID/UID DE…“.

class ReceiptMeta {
  const ReceiptMeta({this.date, this.street, this.postcodeCity, this.taxId});

  final DateTime? date;
  final String? street;
  final String? postcodeCity;
  final String? taxId;

  String? get address => [street, postcodeCity].whereType<String>().where((s) => s.isNotEmpty).join(', ').ifEmpty();
}

extension on String {
  String? ifEmpty() => isEmpty ? null : this;
}

final _iso = RegExp(r'\b(20\d{2})-(\d{2})-(\d{2})');
final _dmy = RegExp(r'\b(\d{1,2})[./](\d{1,2})[./](20\d{2}|\d{2})\b');
final _ptPost = RegExp(r'\b(\d{4})\s?-\s?(\d{3})\b\s*(.*)');
final _dePost = RegExp(r'\b(\d{5})\s+([A-ZÄÖÜ][A-Za-zÄÖÜäöüß.\- ]{2,})');
final _street = RegExp(
    r'\b(rua|r\.|av\.|avenida|pra[cç]a|largo|travessa|cal[cç]ada|estrada|alameda|cruzes|stra(ss|ß)e|str\.|gasse|weg|platz|allee|ring|damm|ufer)\b',
    caseSensitive: false);
final _nifPt = RegExp(r'(nif|contribuinte|contrib\.?|n\.?\s*contrib\.?|nipc)\b[^0-9]{0,24}(\d{3}\s?\d{3}\s?\d{3})', caseSensitive: false);
final _vatDe = RegExp(r'\b(?:ust\.?\s?-?id\.?\s?-?nr\.?|uid\s*nr\.?|ust-?idnr\.?)\s*[:.]?\s*(DE\s?\d{9})', caseSensitive: false);

DateTime? _date(String t, int maxYear) {
  final m = _iso.firstMatch(t);
  if (m != null) {
    final d = _make(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), maxYear);
    if (d != null) return d;
  }
  for (final m in _dmy.allMatches(t)) {
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    final d = _make(y, int.parse(m[2]!), int.parse(m[1]!), maxYear);
    if (d != null) return d;
  }
  return null;
}

DateTime? _make(int y, int mo, int d, int maxYear) {
  if (y < 2000 || y > maxYear || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final x = DateTime(y, mo, d);
  return x.month == mo ? x : null; // rejects 31.02.
}

/// [qrDate] / [qrNif]: from the Portuguese AT QR code (fields F = YYYYMMDD and A) when read; they win.
ReceiptMeta extractMeta(List<String> lines, {String? qrDate, String? qrNif, DateTime? now}) {
  final maxYear = (now ?? DateTime.now()).year + 1;
  DateTime? date;
  if (qrDate != null && RegExp(r'^\d{8}$').hasMatch(qrDate)) {
    date = _make(int.parse(qrDate.substring(0, 4)), int.parse(qrDate.substring(4, 6)), int.parse(qrDate.substring(6, 8)), maxYear);
  }
  for (final l in lines) {
    if (date != null) break;
    date = _date(l, maxYear);
  }
  String? street, city;
  for (var i = 0; i < lines.length && city == null; i++) {
    final l = lines[i].trim();
    final pt = _ptPost.firstMatch(l);
    final de = pt == null ? _dePost.firstMatch(l) : null;
    if (pt == null && de == null) continue;
    // a date like „2026-10-24“ is not a postcode
    if (pt != null && _iso.hasMatch(l)) continue;
    var rest = pt != null ? pt[3]!.trim() : de![2]!.trim();
    // „1100-241“ with the city on the next line (Confeitaria Nacional, Esplanada)
    if (rest.isEmpty && i + 1 < lines.length && RegExp(r'^[A-Za-zÀ-ÿ .\-]{3,30}$').hasMatch(lines[i + 1].trim())) rest = lines[i + 1].trim();
    city = pt != null ? '${pt[1]}-${pt[2]} $rest'.trim() : '${de![1]} $rest';
    for (var k = i - 1; k >= 0 && k >= i - 2; k--) {
      final s = lines[k].trim();
      if (_street.hasMatch(s) || RegExp(r'[A-Za-z]{3,}.*\d').hasMatch(s) && !RegExp(r'tel|nif|contrib|@|www', caseSensitive: false).hasMatch(s)) {
        street = s;
        break;
      }
    }
  }
  String? tax = qrNif;
  if (tax == null) {
    for (final l in lines) {
      if (RegExp(r'consumidor', caseSensitive: false).hasMatch(l)) continue;
      final m = _nifPt.firstMatch(l);
      if (m != null) {
        tax = m[2]!.replaceAll(' ', '');
        break;
      }
      final v = _vatDe.firstMatch(l);
      if (v != null) {
        tax = v[1]!.replaceAll(' ', '');
        break;
      }
    }
  }
  return ReceiptMeta(date: date, street: street, postcodeCity: city, taxId: tax);
}
