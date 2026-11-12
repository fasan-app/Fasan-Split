// SPDX-License-Identifier: MPL-2.0
// Fasan Split – a person's balance with its certainty (Nutzer 12.11.): the amount counts finished bills only; what makes it uncertain
// stands next to it in words (never colour alone, Prüfliste G3). MPL-2.0
import 'package:fasan_core/bill.dart' show money;
import 'package:fasan_core/settle.dart' show BalanceGap;
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../l10n/tr.dart' show trLang;
import 'common.dart';

/// Why the balance is uncertain, as short text parts („2 Bons noch nicht fertig“, „1 Bon ohne Zahler“).
List<String> gapReasons(BalanceGap gap, String lang) => [
      if (gap.openBills > 0) trLang(lang, gap.openBills == 1 ? 'balance.oneOpenBill' : 'balance.openBills', ['${gap.openBills}']),
      if (gap.noPayer > 0) trLang(lang, gap.noPayer == 1 ? 'balance.oneNoPayer' : 'balance.noPayers', ['${gap.noPayer}']),
    ];

/// Amount (0,00 € when nothing is finished) and, if the balance is uncertain, a line „ungewiss“ with the reasons.
class PersonBalance extends StatelessWidget {
  const PersonBalance({super.key, required this.cents, required this.gap, this.big = false});

  final int cents;
  final BalanceGap? gap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme, t = S.of(context);
    final lang = t.de ? 'de' : 'en';
    final sign = signOf(context);
    final uncertain = gap?.uncertain ?? false;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('${money(cents, de: t.de, sign: cents != 0)} $sign',
          style: (big ? tt.headlineSmall : tt.titleMedium)!.copyWith(color: cents > 0 ? l.accent : (cents == 0 ? l.textMuted : null))),
      if (uncertain)
        Row(key: const ValueKey('balance-uncertain'), mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.help_outline_rounded, size: 14, color: l.textMuted),
          const SizedBox(width: 4),
          Text(trLang(lang, 'balance.uncertain'), style: tt.labelSmall!.copyWith(color: l.textMuted)),
        ]),
    ]);
  }
}
