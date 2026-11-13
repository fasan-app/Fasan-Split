// SPDX-License-Identifier: MPL-2.0
// Fasan Split – items sent in a chat message, shown under the message. Split out of collab_ui.dart (13.11., Umbau). MPL-2.0
import '../l10n/tr.dart';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import 'package:fasan_core/bill.dart' show Bill;
import 'bill_screen.dart' show ItemTile;
import 'group_header.dart' show openBill;

// The screen an invitation link opens lives in join_screen.dart (exported here for the old imports).

/// Items sent into the chat (send_items.dart): the bill's name and just those items, the same tiles as in the bill; a tap opens the bill.
class SentItems extends StatelessWidget {
  const SentItems({super.key, required this.bill, required this.items});

  final Bill bill;
  final List<int> items;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final shown = [for (final i in items) if (i >= 0 && i < bill.its.length) i];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(bill.purpose.isEmpty ? 'Bon' : bill.purpose, style: tt.labelMedium!.copyWith(color: l.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (shown.isEmpty) Text(trLang(S.of(context).de ? 'de' : 'en', 'collab_ui.receiptNotAvailable'), style: tt.bodySmall),
        for (final i in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ItemTile(bill: bill, item: bill.its[i], active: null, showSnippet: true, onTap: () => openBill(context, bill, focusItem: i), onLongPress: () => openBill(context, bill, focusItem: i)),
          ),
      ]),
    );
  }
}

