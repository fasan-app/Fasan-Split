// Fasan Split – paying back (Nutzer 04.11.): set up how others can pay me (profile), and a „Bezahlen“ sheet next to every
// „Du gibst … €“. Fasan opens the bank / PayPal / wallet app; nothing is paid through Fasan. model/pay.dart. MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import 'scope.dart';
import 'package:fasan_core/bill.dart' show money;
import 'package:fasan_core/pay.dart';
import 'collab_ui.dart' show QrView;
import 'common.dart';

class PaySetupScreen extends StatefulWidget {
  const PaySetupScreen({super.key});

  @override
  State<PaySetupScreen> createState() => _PaySetupScreenState();
}

class _PaySetupScreenState extends State<PaySetupScreen> {
  late final PayInfo _p = CollabScope.read(context).myPay;
  late final _iban = TextEditingController(text: _p.iban), _holder = TextEditingController(text: _p.holder);
  late final _paypal = TextEditingController(text: _p.paypal), _btc = TextEditingController(text: _p.bitcoin), _xmr = TextEditingController(text: _p.monero);

  @override
  void dispose() {
    for (final c in [_iban, _holder, _paypal, _btc, _xmr]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final de = S.of(context).de;
    final iban = normIban(_iban.text), pp = _paypal.text.trim();
    if (iban.isNotEmpty && !validIban(iban)) {
      showNote(context, trLang(de ? 'de' : 'en', 'pay_ui.theIbanIsNot'));
      return;
    }
    if (pp.isNotEmpty && !validPaypal(pp)) {
      showNote(context, trLang(de ? 'de' : 'en', 'pay_ui.paypalMeNameLetters'));
      return;
    }
    CollabScope.read(context).myPay = PayInfo(iban: iban, holder: _holder.text.trim(), paypal: pp, bitcoin: _btc.text.trim(), monero: _xmr.text.trim());
    Navigator.of(context).maybePop();
    showNote(context, trLang(de ? 'de' : 'en', 'pay_ui.savedOnlyYourGroups'));
  }

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, tt = Theme.of(context).textTheme;
    InputDecoration d(String label, [String? hint]) => InputDecoration(labelText: label, helperText: hint);
    return Scaffold(
      appBar: AppBar(title: Text(trLang(de ? 'de' : 'en', 'pay_ui.howPeopleCanPay'))),
      body: ListView(padding: const EdgeInsets.all(FasanSpace.l), children: [
        Text(
            trLang(de ? 'de' : 'en', 'pay_ui.allOptionalOnlyYour'),
            style: tt.bodyMedium),
        const SizedBox(height: FasanSpace.l),
        TextField(controller: _holder, textCapitalization: TextCapitalization.words, decoration: d(trLang(de ? 'de' : 'en', 'pay_ui.accountHolder'))),
        const SizedBox(height: FasanSpace.s),
        TextField(controller: _iban, textCapitalization: TextCapitalization.characters, decoration: d('IBAN', trLang(de ? 'de' : 'en', 'pay_ui.forTransfersAndSepa'))),
        const SizedBox(height: FasanSpace.l),
        TextField(controller: _paypal, decoration: d(trLang(de ? 'de' : 'en', 'pay_ui.paypalMeName'), trLang(de ? 'de' : 'en', 'pay_ui.onlyTheNameFrom'))),
        const SizedBox(height: FasanSpace.l),
        TextField(
            controller: _btc,
            decoration: d(trLang(de ? 'de' : 'en', 'pay_ui.bitcoinAddressOptional'),
                trLang(de ? 'de' : 'en', 'pay_ui.aFixedAddressLinks'))),
        const SizedBox(height: FasanSpace.s),
        TextField(controller: _xmr, decoration: d(trLang(de ? 'de' : 'en', 'pay_ui.moneroAddressOptional'))),
        const SizedBox(height: FasanSpace.xl),
        FasanButton(label: trLang(de ? 'de' : 'en', 'pay_ui.save'), icon: Icons.check_rounded, expand: true, onPressed: _save),
      ]),
    );
  }
}

/// „Bezahlen“: [cents] in [currency] to [name] ([pub] = their key when they use the app). Shows the ways they shared.
Future<void> payFlow(BuildContext context, {required String name, String? pub, required int cents, required String currency, String purpose = ''}) async {
  final de = S.of(context).de;
  final info = pub == null ? null : CollabScope.read(context).payOf(pub);
  final amount = '${money(cents, de: de)} ${currency == 'EUR' ? '€' : currency}';
  final text = purpose.isEmpty ? 'Fasan Split' : 'Fasan Split: $purpose';
  Future<void> open(Uri u) async {
    if (!await launchUrl(u, mode: LaunchMode.externalApplication) && context.mounted) {
      showNote(context, trLang(de ? 'de' : 'en', 'pay_ui.noAppFoundFor'));
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(FasanSpace.l), children: [
          Text(trLang(de ? 'de' : 'en', 'pay_ui.to', [amount, name]), style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: FasanSpace.s),
          if (info == null || info.isEmpty)
            Text(trLang(de ? 'de' : 'en', 'pay_ui.hasNotAddedPayment', [name]))
          else ...[
            if (info.iban.isNotEmpty && currency == 'EUR') ...[
              Text(trLang(de ? 'de' : 'en', 'pay_ui.transferScanTheQr'), style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: FasanSpace.s),
              Center(child: QrView(epcPayload(name: info.holder.isEmpty ? name : info.holder, iban: info.iban, cents: cents, text: text), size: 200)),
              const SizedBox(height: FasanSpace.s),
              SelectableText('${info.holder.isEmpty ? name : info.holder}\n${info.iban}\n$amount · $text'),
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: Text(trLang(de ? 'de' : 'en', 'pay_ui.copyIban')),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: info.iban));
                  showNote(ctx, trLang(de ? 'de' : 'en', 'pay_ui.ibanCopied'));
                },
              ),
              const Divider(),
            ],
            if (info.paypal.isNotEmpty)
              ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: Text(trLang(de ? 'de' : 'en', 'pay_ui.payWithPaypal')), subtitle: Text('paypal.me/${info.paypal} · $amount'), onTap: () => open(paypalUri(info.paypal, cents, currency))),
            if (info.bitcoin.isNotEmpty)
              ListTile(leading: const Icon(Icons.currency_bitcoin_rounded), title: Text(trLang(de ? 'de' : 'en', 'pay_ui.openBitcoinWallet')), subtitle: Text(trLang(de ? 'de' : 'en', 'pay_ui.convertTheAmountIn')), onTap: () => open(bitcoinUri(info.bitcoin, label: name))),
            if (info.monero.isNotEmpty)
              ListTile(leading: const Icon(Icons.lock_outline_rounded), title: Text(trLang(de ? 'de' : 'en', 'pay_ui.openMoneroWallet')), subtitle: Text(trLang(de ? 'de' : 'en', 'pay_ui.convertTheAmountIn2')), onTap: () => open(moneroUri(info.monero, name: name))),
          ],
          const SizedBox(height: FasanSpace.s),
          Text(trLang(de ? 'de' : 'en', 'pay_ui.afterwardsSettleTheReceipt'), style: Theme.of(ctx).textTheme.bodySmall),
        ]),
      ),
    ),
  );
}
