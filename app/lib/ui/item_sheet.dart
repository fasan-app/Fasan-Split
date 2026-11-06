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
      showDragHandle: true,
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
          if (widget.bill.ps.any((p) => (it.shares[widget.bill.ps.indexOf(p)] ?? 0) > 0)) _FixedAmounts(bill: widget.bill, item: it, changed: widget.changed),
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

/// „Fester Betrag“ (split kind „fest“, Nutzer 06.11.): people on the item can pay an exact amount; the rest of the item follows
/// the shares of the others (SplitMath.splitFixed). Folded away until needed.
class _FixedAmounts extends StatefulWidget {
  const _FixedAmounts({required this.bill, required this.item, required this.changed});

  final Bill bill;
  final BillItem item;
  final VoidCallback changed;

  @override
  State<_FixedAmounts> createState() => _FixedAmountsState();
}

class _FixedAmountsState extends State<_FixedAmounts> {
  final _c = <int, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill, it = widget.item, de = context.langCode == 'de';
    final people = [for (var i = 0; i < b.ps.length; i++) if ((it.shares[i] ?? 0) > 0) i];
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: it.fixed.isNotEmpty,
        title: Text(context.tr('item.fixed'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        children: [
          Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: Align(alignment: Alignment.centerLeft, child: Text(context.tr('item.fixedHint'), style: Theme.of(context).textTheme.bodySmall))),
          for (final i in people)
            Padding(
              padding: const EdgeInsets.only(bottom: FasanSpace.s),
              child: Row(children: [
                Expanded(child: Text(b.ps[i].name)),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _c.putIfAbsent(i, () => TextEditingController(text: it.fixed[i] == null ? '' : money(it.fixed[i]!, de: de))),
                    decoration: InputDecoration(hintText: context.tr('item.fixedNone')),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (v) {
                      final a = parseMoney(v);
                      if (a == null) {
                        it.fixed.remove(i);
                      } else {
                        it.fixed[i] = a;
                      }
                      widget.changed();
                    },
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
