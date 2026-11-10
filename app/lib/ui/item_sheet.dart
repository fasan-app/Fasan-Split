// SPDX-License-Identifier: MPL-2.0
// Fasan Split – one item: change name, amount and quantity AND say who had it, in the same sheet (Nutzer 05.11.: both at once). Every
// change counts at once (no OK to press); the people chips are the ones of the assign list. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/tr.dart';
import 'package:fasan_core/bill.dart';
import 'package:fasan_reader/reader.dart' show nameAlternatives;
import 'assign.dart' show PeoplePicker;
import 'scope.dart';
import 'common.dart';
import 'person_picker.dart';
import 'send_items.dart';

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
  late final _note = TextEditingController(text: it.note ?? '');

  @override
  void dispose() {
    _note.dispose();
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
    final nt = _note.text.trim();
    it.note = nt.isEmpty ? null : nt;
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
          _lockRow(context),
          IgnorePointer(
            ignoring: _lockedForMe(context),
            child: Opacity(
              opacity: _lockedForMe(context) ? 0.5 : 1,
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
          const SizedBox(height: FasanSpace.s),
          TextField(key: const ValueKey('item-note'), controller: _note, minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: context.tr('item.noteLabel')), onChanged: (_) => _apply()),
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
          _MaybeBox(bill: widget.bill, item: it, changed: () {
            widget.changed();
            setState(() {});
          }),
          if (widget.bill.ps.any((p) => (it.shares[widget.bill.ps.indexOf(p)] ?? 0) > 0)) _FixedAmounts(bill: widget.bill, item: it, changed: widget.changed),
          const SizedBox(height: FasanSpace.s),
          Align(
            alignment: Alignment.centerLeft,
            child: FasanButton(
              key: const ValueKey('send-this-item'),
              label: context.tr('send.item'),
              kind: FasanButtonKind.quiet,
              icon: Icons.forward_to_inbox_outlined,
              onPressed: () {
                final i = widget.bill.its.indexOf(it);
                sendItemsFlow(context, widget.bill, preselected: i < 0 ? const {} : {i});
              },
            ),
          ),
          const SizedBox(height: FasanSpace.s),
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
          ),
        ]),
      ),
    );
  }

  /// Locked by somebody else (item or whole bill): the fields below are shown but cannot be changed.
  bool _lockedForMe(BuildContext context) {
    final c = CollabScope.of(context);
    return c.lockedAgainstMe(widget.bill, it.lockBy) || c.lockedAgainstMe(widget.bill, widget.bill.lockBy);
  }

  /// The padlock of the item (Nutzer 07.11.): everyone may enter for everyone until somebody locks.
  Widget _lockRow(BuildContext context) {
    final c = CollabScope.of(context), b = widget.bill;
    final locked = it.lockBy != null, other = _lockedForMe(context);
    final who = locked ? c.lockerName(b, it.lockBy!) : '';
    final canToggle = c.canLock(b) && !other;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded),
      title: Text(context.tr(locked ? 'lock.itemOn' : 'lock.itemOff')),
      subtitle: Text(!c.canLock(b)
          ? context.tr('lock.needGroup')
          : other
              ? context.tr('lock.heldBy', [b.lockBy != null && c.lockedAgainstMe(b, b.lockBy) ? c.lockerName(b, b.lockBy!) : who])
              : context.tr(locked ? 'lock.itemMine' : 'lock.itemHint')),
      value: locked,
      onChanged: canToggle
          ? (_) {
              c.toggleItemLock(b, it);
              widget.changed();
              setState(() {});
            }
          : null,
    );
  }
}


/// „vllt“ (Stellvertreter, Nutzer 06.11.): tentative assignments. Whoever enters for somebody else only proposes; the proposal is
/// not counted in any sum until it is accepted here (docs/KONZEPT-STELLVERTRETER.md). Shown only in a live group.
class _MaybeBox extends StatelessWidget {
  const _MaybeBox({required this.bill, required this.item, required this.changed});

  final Bill bill;
  final BillItem item;
  final VoidCallback changed;

  @override
  Widget build(BuildContext context) {
    final c = CollabScope.of(context), me = c.identity?.pub;
    final live = me != null && bill.group != null && c.canLock(bill);
    final pending = [for (final e in item.maybe.entries) if (e.key < bill.ps.length) e];
    if (!live && pending.isEmpty) return const SizedBox.shrink();
    final free = [for (var i = 0; i < bill.ps.length; i++) if ((item.shares[i] ?? 0) <= 0 && !item.maybe.containsKey(i)) i];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final e in pending)
        Padding(
          padding: const EdgeInsets.only(top: FasanSpace.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              context.tr('maybe.row', [bill.ps[e.key].name, c.lockerName(bill, e.value).isEmpty ? '?' : c.lockerName(bill, e.value)]),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Wrap(spacing: FasanSpace.s, children: [
              FasanButton(
                key: ValueKey('maybe-accept-${e.key}'),
                label: context.tr('maybe.accept'),
                kind: FasanButtonKind.quiet,
                onPressed: () {
                  item.maybe.remove(e.key);
                  if ((item.shares[e.key] ?? 0) <= 0) item.togglePerson(e.key);
                  changed();
                },
              ),
              FasanButton(
                key: ValueKey('maybe-decline-${e.key}'),
                label: context.tr('maybe.decline'),
                kind: FasanButtonKind.quiet,
                onPressed: () {
                  item.maybe.remove(e.key);
                  changed();
                },
              ),
            ]),
          ]),
        ),
      if (live && free.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<int>(
            key: const ValueKey('maybe-propose'),
            tooltip: context.tr('maybe.propose'),
            onSelected: (i) {
              item.maybe[i] = me;
              changed();
            },
            itemBuilder: (_) => [for (final i in free) PopupMenuItem(value: i, child: Text(bill.ps[i].name))],
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.help_outline_rounded, size: 20),
                const SizedBox(width: FasanSpace.s),
                Text(context.tr('maybe.propose')),
              ]),
            ),
          ),
        ),
    ]);
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
