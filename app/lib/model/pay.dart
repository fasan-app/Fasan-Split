// Fasan Split – ways to be paid back (Nutzer 04.11.: PayPal & Co. on official ways, maximal privacy). Fasan never moves
// money and calls no payment API: a button opens the bank, PayPal or wallet app with the amount filled in; the person
// confirms there. Research: docs/recherche/2026-11-04-anbindungen-zahlung-netz.md. MPL-2.0
//
// SEPA credit transfer QR („GiroCode“, EPC069-12): lines BCD / 002 / 1 (UTF-8) / SCT / BIC (may be empty in 002) /
// name (≤70) / IBAN / EUR amount (dot, 0.01–999999999.99) / purpose / reference / text (≤140), LF separated,
// error correction M. Layout from the search results and the guideline as known – NOT checked against the EPC PDF in
// this session (host not reachable); check with a banking app.
// PayPal.Me: paypal.me/<name>/<amount><ISO currency> (PayPal help „What is PayPal.Me?“; name A–Z, 0–9, ≤20).
// Bitcoin: BIP 21 `bitcoin:<address>`; Monero: `monero:<address>` (monero-project docs/URI_SCHEME.md). No amount for
// crypto: Fasan has no exchange rate for them.

class PayInfo {
  PayInfo({this.iban = '', this.holder = '', this.paypal = '', this.bitcoin = '', this.monero = ''});

  String iban, holder, paypal, bitcoin, monero;

  bool get isEmpty => iban.isEmpty && paypal.isEmpty && bitcoin.isEmpty && monero.isEmpty;

  Map<String, Object?> toJson() => {
        if (iban.isNotEmpty) 'iban': iban,
        if (holder.isNotEmpty) 'holder': holder,
        if (paypal.isNotEmpty) 'paypal': paypal,
        if (bitcoin.isNotEmpty) 'btc': bitcoin,
        if (monero.isNotEmpty) 'xmr': monero,
      };

  static PayInfo fromJson(Map<String, Object?> j) => PayInfo(
        iban: j['iban'] as String? ?? '',
        holder: j['holder'] as String? ?? '',
        paypal: j['paypal'] as String? ?? '',
        bitcoin: j['btc'] as String? ?? '',
        monero: j['xmr'] as String? ?? '',
      );
}

/// IBAN without spaces, upper case.
String normIban(String s) => s.replaceAll(RegExp(r'\s'), '').toUpperCase();

/// ISO 13616 check (mod 97 = 1).
bool validIban(String s) {
  final i = normIban(s);
  if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$').hasMatch(i)) return false;
  final r = i.substring(4) + i.substring(0, 4);
  var rest = 0;
  for (final c in r.codeUnits) {
    final v = c >= 65 ? '${c - 55}' : String.fromCharCode(c);
    for (final d in v.codeUnits) {
      rest = (rest * 10 + d - 48) % 97;
    }
  }
  return rest == 1;
}

/// PayPal.Me name rule (letters and digits, at most 20).
bool validPaypal(String s) => RegExp(r'^[A-Za-z0-9]{1,20}$').hasMatch(s);

String _dot(int cents) => '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

/// Text of the SEPA transfer QR for [cents] euros to [name] / [iban] with the transfer text [text].
String epcPayload({required String name, required String iban, required int cents, String text = ''}) {
  String cut(String s, int n) => s.length <= n ? s : s.substring(0, n);
  return [
    'BCD',
    '002',
    '1',
    'SCT',
    '',
    cut(name.trim(), 70),
    normIban(iban),
    'EUR${_dot(cents)}',
    '',
    '',
    cut(text.trim(), 140),
  ].join('\n');
}

/// PayPal.Me link with amount and currency.
Uri paypalUri(String name, int cents, String currency) => Uri.parse('https://paypal.me/$name/${_dot(cents)}${currency.toUpperCase()}');

Uri bitcoinUri(String address) => Uri.parse('bitcoin:${address.trim()}');
Uri moneroUri(String address) => Uri.parse('monero:${address.trim()}');
