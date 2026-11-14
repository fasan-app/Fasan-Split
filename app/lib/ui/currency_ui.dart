// SPDX-License-Identifier: MPL-2.0
// Fasan Split – currency of a bill: chip with rate and its date, picker, „Kurs aktualisieren“, manual rate
// (Nutzer 04.11.; state/rates.dart). MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'package:fasan_ui/fasan_ui.dart' show FasanLook;
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'scope.dart';
import 'package:fasan_core/bill.dart';
import '../state/rates.dart';
import 'collab_ui.dart' show askText;
import 'common.dart';

String _day(DateTime d, bool de) => de ? '${d.day}.${d.month}.${d.year}' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Rate text: „1 USD = 0,9213 € · EZB 03.11.2026“ (or „von Hand“).
String rateText(Bill b, String home, bool de) {
  if (b.currency == null || b.currency == home || b.rate == null) return '';
  final r = b.rate!.toStringAsFixed(4).replaceAll('.', trLang(de ? 'de' : 'en', 'currency_ui.text'));
  final when = b.rateDate == null ? (trLang(de ? 'de' : 'en', 'currency_ui.byHand')) : '${trLang(de ? 'de' : 'en', 'currency_ui.ecb')} ${_day(b.rateDate!, de)}';
  return '1 ${b.currency} = $r ${currencySign(home)} · $when';
}

class CurrencyChip extends StatefulWidget {
  const CurrencyChip({super.key, required this.bill});

  final Bill bill;

  @override
  State<CurrencyChip> createState() => _CurrencyChipState();
}

class _CurrencyChipState extends State<CurrencyChip> {
  bool _busy = false;

  Future<void> _fetch(String code) async {
    final store = StoreScope.read(context), t = S.of(context), b = widget.bill;
    setState(() => _busy = true);
    try {
      final r = await EcbRates().rate(code, store.homeCurrency, date: b.receiptDate);
      if (!mounted) return;
      if (r == null) {
        showNote(context, trLang(t.de ? 'de' : 'en', 'currency_ui.noEcbRateEnter'));
      } else {
        b.rate = r.$1;
        b.rateDate = r.$2;
        store.upsert(b);
      }
    } catch (_) {
      if (mounted) showNote(context, trLang(t.de ? 'de' : 'en', 'currency_ui.ecbNotReachableEnter'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manual(String code) async {
    final t = S.of(context), store = StoreScope.read(context), b = widget.bill;
    final v = await askText(context, trLang(t.de ? 'de' : 'en', 'currency_ui.rateIn', [code, store.homeCurrency]), '0,92');
    final x = double.tryParse((v ?? '').replaceAll(',', '.'));
    if (x == null || x <= 0 || !mounted) return;
    b.rate = x;
    b.rateDate = null; // by hand
    store.upsert(b);
  }

  Future<void> _pick() async {
    final t = S.of(context), store = StoreScope.read(context), b = widget.bill;
    final home = store.homeCurrency;
    final cur = b.currency ?? home;
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(trLang(t.de ? 'de' : 'en', 'currency_ui.currencyOfTheReceipt'), style: Theme.of(ctx).textTheme.titleMedium)),
            if (cur != home) ...[
              if (store.ratesOnline) ListTile(leading: const Icon(Icons.refresh_rounded), title: Text(trLang(t.de ? 'de' : 'en', 'currency_ui.updateRateEcb')), onTap: () => Navigator.pop(ctx, '!fetch')),
              ListTile(leading: const Icon(Icons.edit_outlined), title: Text(trLang(t.de ? 'de' : 'en', 'currency_ui.rateByHand')), onTap: () => Navigator.pop(ctx, '!manual')),
              const Divider(),
            ],
            for (final c in ecbCurrencies)
              ListTile(
                leading: SizedBox(width: 36, child: Center(child: Text(currencySign(c), style: Theme.of(ctx).textTheme.titleMedium))),
                title: Text(c),
                trailing: c == cur ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ]),
        ),
      ),
    );
    if (r == null || !mounted) return;
    return _apply(r, cur);
  }

  /// Applies a choice of the sheet (or the suggestion read from the receipt).
  Future<void> _apply(String r, String cur) async {
    final store = StoreScope.read(context), b = widget.bill, home = store.homeCurrency;
    b.currencyGuess = null; // decided either way
    if (r == '!fetch') return _fetch(cur);
    if (r == '!manual') return _manual(cur);
    if (r == home) {
      b
        ..currency = null
        ..rate = null
        ..rateDate = null;
      store.upsert(b);
      return;
    }
    b
      ..currency = r
      ..rate = null
      ..rateDate = null;
    store.upsert(b);
    store.ratesOnline ? await _fetch(r) : await _manual(r);
  }

  /// The receipt seems to be in another currency (Roadmap 2): take it (then the rate as usual) or keep the home currency.
  Future<void> _askGuess(String guess) async {
    final store = StoreScope.read(context), lang = S.of(context).de ? 'de' : 'en', home = store.homeCurrency;
    final take = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trLang(lang, 'currency.guessTitle', [guess])),
        content: Text(trLang(lang, 'currency.guessText', [guess, home])),
        actions: [
          TextButton(key: const ValueKey('currency-guess-no'), onPressed: () => Navigator.pop(ctx, false), child: Text(trLang(lang, 'currency.guessKeep', [home]))),
          FilledButton(key: const ValueKey('currency-guess-yes'), onPressed: () => Navigator.pop(ctx, true), child: Text(trLang(lang, 'currency.guessTake', [guess]))),
        ],
      ),
    );
    if (take == null || !mounted) return;
    if (take) return _apply(guess, home);
    widget.bill.currencyGuess = null;
    store.upsert(widget.bill);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), store = StoreScope.of(context), b = widget.bill;
    final home = store.homeCurrency, code = b.currency ?? home;
    final rt = rateText(b, home, t.de);
    final guess = b.currency == null ? b.currencyGuess : null;
    if (guess != null && guess != home) {
      return ActionChip(
        key: const ValueKey('currency-guess'),
        visualDensity: VisualDensity.compact,
        avatar: Text(currencySign(guess)),
        side: BorderSide(color: FasanLook.of(context).accent),
        label: Text(trLang(t.de ? 'de' : 'en', 'currency.guessChip', [guess])),
        onPressed: _busy ? null : () => _askGuess(guess),
      );
    }
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(currencySign(code)),
      label: Text(code == home ? code : (rt.isEmpty ? '$code · ${trLang(t.de ? 'de' : 'en', 'currency_ui.rateMissing')}' : '$code · $rt')),
      onPressed: _busy ? null : _pick,
    );
  }
}

/// Settings rows: home currency, rates from the ECB on or off.
List<Widget> currencyTiles(BuildContext context) {
  final t = S.of(context), store = StoreScope.of(context);
  return [
    ListTile(
      leading: const Icon(Icons.currency_exchange_rounded),
      title: Text(trLang(t.de ? 'de' : 'en', 'currency_ui.homeCurrency')),
      subtitle: Text(store.homeCurrency),
      onTap: () async {
        final c = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
              child: ListView(shrinkWrap: true, children: [
                for (final c in ecbCurrencies) ListTile(title: Text('$c  ${currencySign(c)}'), trailing: c == store.homeCurrency ? const Icon(Icons.check_rounded) : null, onTap: () => Navigator.pop(ctx, c)),
              ]),
            ),
          ),
        );
        if (c != null) store.homeCurrency = c;
      },
    ),
    SwitchListTile(
      secondary: const Icon(Icons.cloud_download_outlined),
      title: Text(trLang(t.de ? 'de' : 'en', 'currency_ui.exchangeRatesFromThe')),
      subtitle: Text(trLang(t.de ? 'de' : 'en', 'currency_ui.readOnlyOnlyFor')),
      value: store.ratesOnline,
      onChanged: (v) => store.ratesOnline = v,
    ),
  ];
}
