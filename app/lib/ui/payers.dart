// Fasan Split – who paid: one person, or several with their own amounts (Nutzer 05.11.: in the bill screen, not on a later step).
// The sheet works directly on `bill.payer` / `bill.paid` (empty `paid` = [payer] paid everything). MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../model/bill.dart';
import 'common.dart';

/// Equal parts of the receipt for everyone in `paid` (exact cents, the first ones get the leftover cent).
void spreadPaidEqually(Bill b) {
  final who = b.paid.keys.toList()..sort();
  if (who.isEmpty) return;
  final total = b.effectiveTotal, each = total ~/ who.length;
  var rest = total - each * who.length;
  for (final i in who) {
    b.paid[i] = each + (rest-- > 0 ? 1 : 0);
  }
  syncPayer(b);
}

/// The one who paid most stands for the bill where only one name is shown.
void syncPayer(Bill b) {
  if (b.paid.isEmpty) return;
  b.payer = (b.paid.entries.toList()..sort((x, y) => y.value.compareTo(x.value))).first.key;
}

/// Short text for the line in the bill screen: the name, or „2 paid“.
String payersSummary(BuildContext context, Bill b) {
  if (b.multiPay) return context.tr('bill.paidSeveral', [b.paid.values.where((v) => v > 0).length]);
  final i = b.payer;
  return i != null && i < b.ps.length ? b.ps[i].name : '';
}

/// Opens the sheet; [changed] runs after every change (the screen saves and rebuilds).
Future<void> showPayersSheet(BuildContext context, Bill b, {required VoidCallback changed}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PayersSheet(bill: b, changed: changed, signContext: context),
    );

class _PayersSheet extends StatefulWidget {
  const _PayersSheet({required this.bill, required this.changed, required this.signContext});

  final Bill bill;
  final VoidCallback changed;

  /// Context of the screen below the sheet: it carries the currency scope for the sign.
  final BuildContext signContext;

  @override
  State<_PayersSheet> createState() => _PayersSheetState();
}

class _PayersSheetState extends State<_PayersSheet> {
  Bill get b => widget.bill;
  late bool _multi = b.paid.length > 1;
  final Map<int, TextEditingController> _amount = {};
  int _round = 0; // changes when amounts are set by the program: the fields start over with the new text

  @override
  void dispose() {
    for (final c in _amount.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctl(int i) => _amount.putIfAbsent(i, () => TextEditingController(text: money(b.paid[i] ?? 0, de: context.langCode == 'de')));

  void _refresh() {
    for (final c in _amount.values) {
      c.dispose();
    }
    _amount.clear();
    _round++;
  }

  void _toggle(int i) {
    setState(() {
      if (!_multi) {
        b.paid.clear();
        b.payer = b.payer == i ? null : i;
      } else {
        if (b.paid.containsKey(i)) {
          b.paid.remove(i);
        } else {
          b.paid[i] = 0;
        }
        spreadPaidEqually(b);
        if (b.paid.isEmpty) b.payer = null;
        _refresh();
      }
    });
    widget.changed();
  }

  void _switch() {
    setState(() {
      _multi = !_multi;
      if (_multi) {
        if (b.payer != null) b.paid = {b.payer!: 0};
        spreadPaidEqually(b);
      } else {
        b.paid.clear();
      }
      _refresh();
    });
    widget.changed();
  }

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme, de = context.langCode == 'de';
    final sign = billSign(widget.signContext, b);
    return Padding(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, MediaQuery.viewInsetsOf(context).bottom + FasanSpace.l),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('payers.title'), style: tt.titleMedium),
          const SizedBox(height: FasanSpace.s),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < b.ps.length; i++)
              ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 2 * FasanSpace.l), child: FittedBox(fit: BoxFit.scaleDown, child: FasanPersonChip(name: b.ps[i].name, index: b.ps[i].color, selected: _multi ? b.paid.containsKey(i) : b.payer == i, onTap: () => _toggle(i)))),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: Icon(_multi ? Icons.person_rounded : Icons.group_rounded, size: 18),
              label: Text(context.tr(_multi ? 'payers.one' : 'payers.several')),
              onPressed: b.ps.length < 2 ? null : _switch,
            ),
          ),
          if (_multi && b.paid.isNotEmpty) ...[
            for (final i in (b.paid.keys.toList()..sort()))
              Padding(
                padding: const EdgeInsets.only(bottom: FasanSpace.xs),
                child: Row(children: [
                  FasanAvatar(name: b.ps[i].name, index: b.ps[i].color, size: 28),
                  const SizedBox(width: FasanSpace.s),
                  Expanded(child: Text(b.ps[i].name, style: tt.bodyLarge)),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      key: ValueKey('paid-$i-$_round'),
                      controller: _ctl(i),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.end,
                      decoration: InputDecoration(suffixText: sign, isDense: true),
                      onChanged: (v) {
                        setState(() {
                          b.paid[i] = parseMoney(v) ?? 0;
                          syncPayer(b);
                        });
                        widget.changed();
                      },
                    ),
                  ),
                ]),
              ),
            Row(children: [
              Expanded(
                child: Text(
                  b.paidGap == 0
                      ? context.tr('payers.fits')
                      : b.paidGap > 0
                          ? context.tr('payers.missing', ['${money(b.paidGap, de: de)} $sign'])
                          : context.tr('payers.tooMuch', ['${money(-b.paidGap, de: de)} $sign']),
                  style: tt.bodySmall!.copyWith(color: b.paidGap == 0 ? l.accent : Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    spreadPaidEqually(b);
                    _refresh();
                  });
                  widget.changed();
                },
                child: Text(context.tr('payers.equally')),
              ),
            ]),
          ],
          const SizedBox(height: FasanSpace.m),
          Align(alignment: Alignment.centerRight, child: FasanButton(label: context.tr('payers.close'), onPressed: () => Navigator.pop(context))),
        ]),
      ),
    );
  }
}
