// Fasan Split – one item: change name, amount and quantity AND say who had it, in the same sheet (Nutzer 05.11.: both at once). Every
// change counts at once (no OK to press); the people chips are the ones of the assign list. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/tr.dart';
import '../model/bill.dart';
import '../recognition/reader.dart' show nameAlternatives;
import 'assign.dart' show PeoplePicker;
import 'common.dart';
import 'person_picker.dart';

/// Opens the sheet. [changed] runs after every change; [onDelete] when the item is deleted (the screen puts it back on „undo“).
Future<void> showItemSheet(BuildContext context, Bill bill, BillItem item, {required VoidCallback changed, required VoidCallback onDelete, bool focusAmount = false}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ItemSheet(bill: bill, item: item, changed: changed, onDelete: onDelete, signContext: context),
    );

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.bill, required this.item, required this.changed, required this.onDelete, required this.signContext});

  final Bill bill;
  final BillItem item;
  final VoidCallback changed, onDelete;
  final BuildContext signContext;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  BillItem get it => widget.item;
  late final _name = TextEditingController(text: it.name);
  late final _amount = TextEditingController(text: money(it.amount, de: context.langCode == 'de'));
  late final _qty = TextEditingController(text: '${it.qty}');

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _apply() {
    final n = _name.text.trim();
    if (n.isNotEmpty) it.name = n;
    final a = parseMoney(_amount.text);
    if (a != null) it.amount = a;
    final q = int.tryParse(_qty.text.trim());
    if (q != null && q >= 1) it.qty = q;
    it.sure = true; // the user looked at it
    widget.changed();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme, de = context.langCode == 'de';
    final sign = billSign(widget.signContext, widget.bill);
    final alts = nameAlternatives(it.name);
    return Padding(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, MediaQuery.viewInsetsOf(context).bottom + FasanSpace.l),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (it.snippet case final s?) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: Snippet(s, height: 36)),
          TextField(controller: _name, decoration: InputDecoration(labelText: context.tr('item.name')), textInputAction: TextInputAction.next, onChanged: (_) => _apply()),
          if (alts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FasanSpace.xs),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final a in alts)
                  ActionChip(
                    label: Text(a),
                    onPressed: () {
                      _name.text = a;
                      _apply();
                    },
                  ),
              ]),
            ),
          const SizedBox(height: FasanSpace.s),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _amount,
                decoration: InputDecoration(labelText: context.tr('item.amount'), suffixText: sign),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-−0-9.,]'))],
                onChanged: (_) => _apply(),
              ),
            ),
            const SizedBox(width: FasanSpace.s),
            Expanded(child: TextField(controller: _qty, decoration: InputDecoration(labelText: context.tr('item.qty')), keyboardType: TextInputType.number, onChanged: (_) => _apply())),
          ]),
          if (it.suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FasanSpace.s),
              child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(context.tr('item.suggestions'), style: tt.bodySmall),
                for (final s in it.suggestions)
                  ActionChip(
                    label: Text(money(s, de: de)),
                    onPressed: () {
                      _amount.text = money(s, de: de);
                      _apply();
                    },
                  ),
              ]),
            ),
          const SizedBox(height: FasanSpace.l),
          FasanLabel(context.tr('item.who')),
          const SizedBox(height: FasanSpace.s),
          PeoplePicker(
            bill: widget.bill,
            item: it,
            addPerson: (ctx) => addPersonWithPicker(ctx, widget.bill),
            onChanged: () {
              widget.changed();
              setState(() {});
            },
          ),
          const SizedBox(height: FasanSpace.l),
          Row(children: [
            FasanButton(
              label: context.tr('item.delete'),
              kind: FasanButtonKind.quiet,
              icon: Icons.delete_outline,
              onPressed: () {
                widget.onDelete();
                Navigator.pop(context);
              },
            ),
            const Spacer(),
            FasanButton(label: context.tr('item.done'), onPressed: () => Navigator.pop(context)),
          ]),
        ]),
      ),
    );
  }
}
