// Fasan Split – ways to be paid back (Nutzer 04.11.: PayPal & Co. on official ways, maximal privacy). Fasan never moves
// money and calls no payment API: a button opens the bank, PayPal or wallet app with the amount filled in; the person
// confirms there. Research: docs/recherche/2026-11-04-anbindungen-zahlung-netz.md. MPL-2.0
//
// SEPA credit transfer QR („GiroCode“, EPC069-12): lines BCD / 002 / 1 (UTF-8) / SCT / BIC (may be empty in 002) /
// name (≤70) / IBAN / EUR amount (dot, 0.01–999999999.99) / purpose / reference / text (≤140), LF separated,
// error correction M. Layout from the search results and the guideline as known – NOT checked against the EPC PDF in
// this session (host not reachable); check with a banking app.
// PayPal.Me: paypal.me/<name>/<amount><ISO currency> (PayPal help „What is PayPal.Me?“; name A–Z, 0–9, ≤20).
// Bitcoin: BIP 21/BIP 321 (read 04.11. from github.com/bitcoin/bips): `bitcoin:<address>?label=<name>`, amount would be
// decimal BTC with a dot. BIP 321: an on-chain address in a URI is a one-time instruction, not a contact detail – a
// reusable Lightning offer (BOLT 12, `lno=`) is the better thing to share; the UI says so. Monero (monero-project
// docs/URI_SCHEME.md, read 04.11.): `monero:<address>?recipient_name=<name>`. No amount for crypto: Fasan has no rate.

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
  // The payload is LF separated: a line break (or other control character) in a name or text would shift every field after it.
  String cut(String s, int n) {
    final clean = s.replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ').trim();
    return clean.length <= n ? clean : String.fromCharCodes(clean.runes.take(n));
  }

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

// Query values are percent-encoded per RFC 3986 (UTF-8 bytes, a space is %20). NOT Uri.encodeQueryComponent: it writes a space as
// „+“, and neither BIP 21 (example `message=Donation%20for%20project%20xyz`, „percent-encoded as described in RFC 3986“) nor the
// Monero parser (wallet2::parse_uri → convert_from_url_format, decodes only %xx; docs/URI_SCHEME.md: „Spaces must be … %20“)
// turns „+“ back into a space – the wallet would show „Angi+Muster“. Read 05.11. in bitcoin/bips and monero-project/monero.
String _q(String v) => Uri.encodeComponent(v.trim());

Uri bitcoinUri(String address, {String label = ''}) => Uri.parse('bitcoin:${address.trim()}${label.trim().isEmpty ? '' : '?label=${_q(label)}'}');
Uri moneroUri(String address, {String name = ''}) => Uri.parse('monero:${address.trim()}${name.trim().isEmpty ? '' : '?recipient_name=${_q(name)}'}');
