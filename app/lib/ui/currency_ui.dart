// Fasan Split – currency of a bill: chip with rate and its date, picker, „Kurs aktualisieren“, manual rate
// (Nutzer 04.11.; state/rates.dart). MPL-2.0
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'scope.dart';
import '../model/bill.dart';
import '../state/rates.dart';
import 'collab_ui.dart' show askText;
import 'common.dart';

String _day(DateTime d, bool de) => de ? '${d.day}.${d.month}.${d.year}' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Rate text: „1 USD = 0,9213 € · EZB 03.11.2026“ (or „von Hand“).
String rateText(Bill b, String home, bool de) {
  if (b.currency == null || b.currency == home || b.rate == null) return '';
  final r = b.rate!.toStringAsFixed(4).replaceAll('.', de ? ',' : '.');
  final when = b.rateDate == null ? (de ? 'von Hand' : 'by hand') : '${de ? 'EZB' : 'ECB'} ${_day(b.rateDate!, de)}';
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
        showNote(context, t.de ? 'Kein Kurs von der EZB. Trag ihn von Hand ein.' : 'No ECB rate. Enter it by hand.');
      } else {
        b.rate = r.$1;
        b.rateDate = r.$2;
        store.upsert(b);
      }
    } catch (_) {
      if (mounted) showNote(context, t.de ? 'EZB nicht erreichbar. Trag den Kurs von Hand ein.' : 'ECB not reachable. Enter the rate by hand.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manual(String code) async {
    final t = S.of(context), store = StoreScope.read(context), b = widget.bill;
    final v = await askText(context, t.de ? 'Kurs: 1 $code in ${store.homeCurrency}' : 'Rate: 1 $code in ${store.homeCurrency}', '0,92');
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
            ListTile(title: Text(t.de ? 'Währung des Bons' : 'Currency of the receipt', style: Theme.of(ctx).textTheme.titleMedium)),
            if (cur != home) ...[
              if (store.ratesOnline) ListTile(leading: const Icon(Icons.refresh_rounded), title: Text(t.de ? 'Kurs aktualisieren (EZB)' : 'Update rate (ECB)'), onTap: () => Navigator.pop(ctx, '!fetch')),
              ListTile(leading: const Icon(Icons.edit_outlined), title: Text(t.de ? 'Kurs von Hand' : 'Rate by hand'), onTap: () => Navigator.pop(ctx, '!manual')),
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

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), store = StoreScope.of(context), b = widget.bill;
    final home = store.homeCurrency, code = b.currency ?? home;
    final rt = rateText(b, home, t.de);
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(currencySign(code)),
      label: Text(code == home ? code : (rt.isEmpty ? '$code · ${t.de ? 'Kurs fehlt' : 'rate missing'}' : '$code · $rt')),
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
      title: Text(t.de ? 'Standardwährung' : 'Home currency'),
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
      title: Text(t.de ? 'Wechselkurse von der EZB' : 'Exchange rates from the ECB'),
      subtitle: Text(t.de ? 'Nur lesen, nur bei Bons in fremder Währung. Die EZB sieht dabei deine IP-Adresse.' : 'Read only, only for receipts in another currency. The ECB sees your IP address.'),
      value: store.ratesOnline,
      onChanged: (v) => store.ratesOnline = v,
    ),
  ];
}
