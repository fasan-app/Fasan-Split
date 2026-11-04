// Fasan Split – exchange rates from the European Central Bank (euro reference rates, ecb.europa.eu/stats/eurofxref:
// working days around 16:00 CET, „for information only“, no RUB since 01.03.2022). Only GET, nothing is sent; can be
// switched off (Einstellungen). The rate used is stored with the bill (date shown, manual update). Nutzer 04.11.
// Files: eurofxref-daily.xml (latest), eurofxref-hist-90d.xml (last 90 days, for the receipt date). In the browser the
// ECB answers without Access-Control-Allow-Origin (checked 04.11. with curl and an Origin header; not seen in a real browser) –
// the browser then cannot read it and the rate is entered by hand. MPL-2.0
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Currencies the ECB publishes against the euro (EUR itself included).
const ecbCurrencies = ['EUR', 'USD', 'JPY', 'BGN', 'CZK', 'DKK', 'GBP', 'HUF', 'PLN', 'RON', 'SEK', 'CHF', 'ISK', 'NOK', 'TRY', 'AUD', 'BRL', 'CAD', 'CNY', 'HKD', 'IDR', 'ILS', 'INR', 'KRW', 'MXN', 'MYR', 'NZD', 'PHP', 'SGD', 'THB', 'ZAR'];

/// Short sign for display: €, $, £, else the code.
String currencySign(String code) => switch (code) { 'EUR' => '€', 'USD' => r'$', 'GBP' => '£', 'JPY' => '¥', _ => code };

/// Rates of one day: units of each currency for 1 EUR.
typedef DayRates = ({DateTime day, Map<String, double> perEur});

/// Parses an ECB eurofxref XML file into days (newest first).
List<DayRates> parseEcb(String xml) {
  final out = <DayRates>[];
  final day = RegExp(r'''<Cube time=["']?(\d{4}-\d{2}-\d{2})["']?>(.*?)</Cube>''', dotAll: true);
  final rate = RegExp(r'''currency=["']([A-Z]{3})["']\s+rate=["']([0-9.]+)["']''');
  for (final m in day.allMatches(xml)) {
    final rates = <String, double>{'EUR': 1};
    for (final r in rate.allMatches(m.group(2)!)) {
      rates[r.group(1)!] = double.parse(r.group(2)!);
    }
    out.add((day: DateTime.parse(m.group(1)!), perEur: rates));
  }
  return out;
}

/// Units of [home] for 1 unit of [foreign] on [days]' rates; null if a currency is missing.
double? crossRate(Map<String, double> perEur, String foreign, String home) {
  final f = perEur[foreign], h = perEur[home];
  return f == null || h == null || f == 0 ? null : h / f;
}

class EcbRates {
  EcbRates({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://www.ecb.europa.eu/stats/eurofxref/';
  static const _kCache = 'rates.ecb';

  /// The rate for [foreign] → [home] on [date] (the last published day on or before it); fetches when needed.
  /// Returns (rate, day of the rate) or null without network / unknown currency.
  Future<(double, DateTime)?> rate(String foreign, String home, {DateTime? date}) async {
    if (foreign == home) return (1.0, date ?? DateTime.now());
    final days = await _days(recent: date == null || DateTime.now().difference(date).inDays < 2);
    final want = date ?? DateTime.now();
    for (final d in days) {
      if (!d.day.isAfter(DateTime(want.year, want.month, want.day))) {
        final r = crossRate(d.perEur, foreign, home);
        if (r != null) return (r, d.day);
      }
    }
    return null;
  }

  Future<List<DayRates>> _days({required bool recent}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kCache);
    final today = DateTime.now();
    if (cached != null) {
      final j = jsonDecode(cached) as Map<String, dynamic>;
      final fetched = DateTime.tryParse(j['fetched'] as String? ?? '');
      // a fresh copy at most every 6 hours (rates change once per working day)
      if (fetched != null && today.difference(fetched).inHours < 6 && (!recent || j['kind'] == 'daily' || j['kind'] == 'hist')) {
        return parseEcb(j['xml'] as String);
      }
    }
    final file = recent ? 'eurofxref-daily.xml' : 'eurofxref-hist-90d.xml';
    final res = await _client.get(Uri.parse('$_base$file')).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw StateError('EZB: ${res.statusCode}');
    await prefs.setString(_kCache, jsonEncode({'fetched': today.toIso8601String(), 'kind': recent ? 'daily' : 'hist', 'xml': res.body}));
    return parseEcb(res.body);
  }
}
