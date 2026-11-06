// Fasan Split – date and place of a receipt from its printed lines (Beschluss 02.11.: Ort und Datum aus dem Bon selbst,
// weil Bons oft später erfasst werden; GPS nur als Hinweis). Tested against fasan-diagnose/tests/echt. MPL-2.0
//
// - Date: ISO (2026-10-24), German/PT (24.10.2026, 24/10/2026, 28.05.24). Years 2000 … next year only.
// - Address: the line with a postcode (PT „1250-099 Lisboa“, DE „60385 Frankfurt“) plus the street line above it
//   (street word or a house number). Searched top-down, so the shop's address wins over later card-terminal blocks.
// - NIF/VAT: PT „NIF“, „Contribuinte“, „N. Contrib.“ with 9 digits (the customer's „Consumidor final“ is skipped),
//   DE „USt-ID/UID DE…“.

import 'dart:math' as math;

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

/// Portuguese NIF check digit: weights 9…2 on the first 8 digits, check = 11 − (sum mod 11), 10 and 11 become 0
/// (Business::PT::NIF README; jsvat portugal.ts; atractor.pt „The check digit of Portuguese ID Card“).
/// A misread digit fails this test with probability ~10/11, so a valid NIF marks a cleanly read header.
bool validNifPt(String nif) {
  if (!RegExp(r'^\d{9}$').hasMatch(nif)) return false;
  var sum = 0;
  for (var i = 0; i < 8; i++) {
    sum += int.parse(nif[i]) * (9 - i);
  }
  var c = 11 - sum % 11;
  if (c > 9) c = 0;
  return c == int.parse(nif[8]);
}

/// Shop name, address, date and tax id of a receipt, taken from the best read header among all recognition passes.
class ReceiptHeader {
  const ReceiptHeader({required this.shop, required this.meta});

  final String shop;
  final ReceiptMeta meta;

  /// Shop name, a valid tax id (PT NIF or DE USt-ID) AND a cleanly read address (street and postcode line). With a checked
  /// total this is the signal to stop reading further passes (Nutzer 02.11.: 46,5 s, obwohl Lauf 2 schon ok war).
  /// Measured on the 13 real receipts: „Name + USt-ID“ alone stopped too early (Aldi: wrong postcode from the first pass,
  /// REWE: no postcode), so the address has to be complete as well.
  bool get complete {
    if (shop.isEmpty) return false;
    final nif = meta.taxId;
    if (nif == null || !(validNifPt(nif) || RegExp(r'^DE\s?\d{9}$').hasMatch(nif))) return false;
    final street = meta.street, city = meta.postcodeCity;
    return street != null && city != null && lineQuality(street) >= 0.7 && lineQuality(city) >= 0.7;
  }
}

// Lines that are never the shop name: customer block, document type, table, tax and contact lines.
final _notShopName = RegExp(
    r'\d{4}|tel|nif|www|@|rua |str\.|avenida|street|consumidor|contribuinte|fatura|factura|recibo|original|tal[aã]o|mesa|atcud|'
    r'qtd|descri|iva\b|total|operador|caixa|documento|ust|steuer|beleg|bon\b|kasse',
    caseSensitive: false);

/// How cleanly a line is read: share of tokens that look like words or numbers, not „5lu88zeg7“ or „Lis00.c“.
double lineQuality(String s) {
  final tokens = s.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return 0;
  var good = 0;
  for (final t in tokens) {
    final x = t.replaceAll(RegExp(r'^[^\wÀ-ÿ]+|[^\wÀ-ÿ]+$'), '');
    if (RegExp(r'^[A-Za-zÀ-ÿ][a-zà-ÿ]*$|^[A-ZÀ-Þ]+$|^[A-Za-zÀ-ÿ]{1,3}\.?$').hasMatch(x) || RegExp(r'^[\d.,/:\-]+$').hasMatch(x)) good++;
  }
  return good / tokens.length;
}

/// Picks the header from all passes (Nutzer 02.11.: „Wofür, Ort, Adresse, Restaurantname kompletter Unfug“). Cause in the
/// logs: the item winner was used for the header too, although it was cut below the header (Restaurante da Sé: winner began
/// at „CONSUMIDOR FINAL“) or read it garbled (Estrela do Bairro: „Vara fiario de Noticias hobo R/C“, while another pass
/// read „Rua Diario de Noticias no66 R/C“). Now every pass is scored: valid NIF check digit, clean postcode line,
/// clean shop line; the best pass gives address and name. QR data (AT code) wins for NIF and date.
ReceiptHeader bestHeader(List<List<String>> passes, {String? qrDate, String? qrNif, DateTime? now}) {
  ReceiptMeta? bestMeta;
  var bestScore = -1.0;
  String shop = '';
  var shopScore = 0.0;
  DateTime? anyDate;
  String? anyNif = qrNif != null && validNifPt(qrNif) ? qrNif : null;
  for (final lines in passes) {
    // the header ends at the item table
    final end = lines.indexWhere((l) => RegExp(r'\b(qtd|descri[cç][aã]o|artikel|menge)\b', caseSensitive: false).hasMatch(l));
    final head = lines.take(end > 0 ? end : math.min(lines.length, 16)).toList();
    final m = extractMeta(head, qrDate: qrDate, qrNif: qrNif, now: now);
    anyDate ??= m.date ?? extractMeta(lines, now: now).date;
    var score = 0.0;
    final nif = m.taxId;
    if (nif != null && validNifPt(nif)) {
      score += 4;
      anyNif ??= nif;
    }
    if (m.postcodeCity != null) score += 2 * lineQuality(m.postcodeCity!);
    if (m.street != null) score += 1.5 * lineQuality(m.street!);
    if (score > bestScore) {
      bestScore = score;
      bestMeta = m;
    }
    for (final l in head.take(6)) {
      final t = l.trim();
      final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(t).length;
      if (letters < 5 || _notShopName.hasMatch(t)) continue;
      // earlier lines are more likely the name; clean reading counts most
      final s = lineQuality(t) * 3 + (head.indexOf(l) == 0 ? 1 : 0) + math.min(letters, 20) / 20;
      if (s > shopScore) {
        shopScore = s;
        shop = t.replaceAll(RegExp(r'[,.;:]+$'), '');
      }
      break; // only the first candidate of each pass
    }
  }
  final m = bestMeta ?? const ReceiptMeta();
  return ReceiptHeader(
    shop: shopScore >= 2.5 ? shop : '',
    meta: ReceiptMeta(date: m.date ?? anyDate, street: m.street, postcodeCity: m.postcodeCity, taxId: anyNif ?? m.taxId),
  );
}
