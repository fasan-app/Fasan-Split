// SPDX-License-Identifier: MPL-2.0
// „Posten schicken“ (Nutzer 09.11. 19:04): pick items with check marks and send them as a card into the chat of the bill's group.
// Entry points: the item sheet, the ⋮ of a bill, and the item list (filtered). The card in the chat shows only these items.
import 'package:fasan_core/bill.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import 'common.dart';
import 'scope.dart';

/// The live group a bill belongs to, or null (loose or local-only bills have no chat).
dynamic _groupOf(BuildContext context, Bill b) {
  final c = CollabScope.read(context);
  if (b.group == null) return null;
  for (final g in c.groups.values) {
    if (!g.secret.direct && g.localName == b.group) return g;
  }
  return null;
}

/// Whether [b] can be sent to a chat at all (it belongs to a live group).
/// A hidden bill never goes into the chat: the card would be readable for the whole group (Sichtbarkeit je Rechnung).
bool canSendItems(BuildContext context, Bill b) => !b.hidden && _groupOf(context, b) != null;

/// Asks which items of [bill] to send ([preselected]: positions in `bill.its`), then sends one chat card. Returns true when sent.
Future<bool> sendItemsFlow(BuildContext context, Bill bill, {Set<int> preselected = const {}}) async {
  final lang = context.langCode;
  final g = _groupOf(context, bill);
  if (bill.hidden) {
    showNote(context, trLang(lang, 'vis.noSend'));
    return false;
  }
  if (g == null) {
    showNote(context, trLang(lang, 'send.noGroup'));
    return false;
  }
  final picked = await showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SendItemsSheet(bill: bill, preselected: preselected),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return false;
  final idx = picked.toList()..sort();
  final names = [for (final i in idx) bill.its[i].title];
  final text = idx.length == 1 ? names.first : trLang(lang, 'send.text', ['${idx.length}', bill.purpose.isEmpty ? names.first : bill.purpose]);
  CollabScope.read(context).sendMessage(g, text, bill: bill.id, items: idx);
  showNote(context, trLang(lang, 'send.done', [g.localName as String]));
  return true;
}

/// Sends the given items of several bills: one card per bill (used by the filtered item list).
Future<void> sendItemsOfBills(BuildContext context, Map<Bill, Set<int>> byBill) async {
  final lang = context.langCode;
  final c = CollabScope.read(context);
  var n = 0, skipped = 0;
  for (final e in byBill.entries) {
    final g = _groupOf(context, e.key);
    if (g == null || e.value.isEmpty) {
      skipped++;
      continue;
    }
    final idx = e.value.toList()..sort();
    final names = [for (final i in idx) e.key.its[i].title];
    c.sendMessage(g, idx.length == 1 ? names.first : trLang(lang, 'send.text', ['${idx.length}', e.key.purpose.isEmpty ? names.first : e.key.purpose]), bill: e.key.id, items: idx);
    n++;
  }
  if (context.mounted) showNote(context, n == 0 ? trLang(lang, 'send.noGroup') : trLang(lang, skipped == 0 ? 'send.doneMany' : 'send.doneSome', ['$n', '$skipped']));
}

class _SendItemsSheet extends StatefulWidget {
  const _SendItemsSheet({required this.bill, required this.preselected});

  final Bill bill;
  final Set<int> preselected;

  @override
  State<_SendItemsSheet> createState() => _SendItemsSheetState();
}

class _SendItemsSheetState extends State<_SendItemsSheet> {
  late final Set<int> _on = {...widget.preselected};

  @override
  Widget build(BuildContext context) {
    final b = widget.bill, de = context.langCode == 'de', tt = Theme.of(context).textTheme;
    final all = _on.length == b.its.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, FasanSpace.l),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(context.tr('send.title'), style: tt.titleMedium)),
          TextButton(onPressed: () => setState(() => all ? _on.clear() : _on.addAll([for (var i = 0; i < b.its.length; i++) i])), child: Text(context.tr(all ? 'send.none' : 'send.all'))),
        ]),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (var i = 0; i < b.its.length; i++)
              CheckboxListTile(
                key: ValueKey('send-item-$i'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _on.contains(i),
                onChanged: (v) => setState(() => v == true ? _on.add(i) : _on.remove(i)),
                title: Text(b.its[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                secondary: Text(money(b.its[i].amount, de: de)),
              ),
          ]),
        ),
        const SizedBox(height: FasanSpace.s),
        FasanButton(key: const ValueKey('send-go'), label: context.tr('send.go', ['${_on.length}']), onPressed: _on.isEmpty ? null : () => Navigator.pop(context, _on)),
      ]),
    );
  }
}
