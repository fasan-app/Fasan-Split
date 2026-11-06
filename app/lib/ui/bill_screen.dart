// Fasan Split – THE bill screen (Nutzer 05.11.): total and purpose, who was there, who paid, the items – changed and assigned on
// one screen. Replaces the old steps 1 (total), 2 (people) and 3 (assign); what follows is the summary (PayScreen). All texts
// come from lib/l10n (context.tr). Researched layout: docs/recherche/2026-11-05-ein-bildschirm-bon.md. MPL-2.0
import 'dart:math' as math;

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart' show S;
import '../l10n_bill.dart';
import '../l10n/tr.dart';
import 'scope.dart';
import '../model/bill.dart';
import '../flows/scan_bill.dart' show remainderName;
import '../recognition_service.dart';
import '../state/images.dart';
import 'assign.dart';
import 'category_ui.dart';
import 'common.dart';
import 'currency_ui.dart';
import 'flow.dart' show PayScreen, RefundNote, addPersonTo, removePersonFrom, rereadFlow;
import 'item_sheet.dart';
import 'marquee_text.dart';
import 'payers.dart';
import 'person_picker.dart';
import 'swipe.dart';
import 'when_where.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.bill, this.scan});

  final Bill bill;
  final ScanResultData? scan;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final _purpose = TextEditingController(text: widget.bill.purpose);
  late final _total = TextEditingController(text: widget.bill.total == null ? '' : money(widget.bill.total!, de: context.langCode == 'de'));

  Bill get b => widget.bill;

  /// The person whose items are being tapped (tap a person, then the items they had).
  int? _active;

  /// Receipt snippets under every item (otherwise only under items that are not sure).
  bool _snippets = true; // default on (Nutzer 06.11.: the receipt snippet is the only crisis-proof sign that an item is right); compact, switch in ⋮

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).watchHistory(b);
    });
    // a bill saved before the sign rule: turn the signs once when it is opened
    if (b.alignSigns()) {
      // after the first frame: the language (an inherited widget) cannot be read in initState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _total.text = b.total == null ? '' : money(b.total!, de: context.langCode == 'de');
        StoreScope.read(context).upsert(b);
      });
    }
  }

  @override
  void dispose() {
    _purpose.dispose();
    _total.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Undo (−1) / redo (+1) through the history of this bill.
  void _step(int dir) {
    if (StoreScope.read(context).stepHistory(b, dir)) {
      setState(() => _total.text = b.total == null ? '' : money(b.total!, de: context.langCode == 'de'));
    }
  }

  // ---- signs ----

  /// Items and total point opposite ways (a „-198,00“ from the institution, total corrected to 198): turn the items, say so, and
  /// let the user take it back with one tap.
  void _alignSigns() {
    final before = [for (final p in b.its) p.amount], beforeTotal = b.total;
    if (!b.alignSigns()) return;
    StoreScope.read(context).upsert(b);
    setState(() => _total.text = b.total == null ? '' : money(b.total!, de: context.langCode == 'de'));
    showNote(
      context,
      context.tr('bill.signTurned'),
      actionLabel: context.tr('bill.undo'),
      duration: const Duration(seconds: 8),
      onAction: () {
        setState(() {
          for (var i = 0; i < b.its.length && i < before.length; i++) {
            b.its[i].amount = before[i];
          }
          b.total = beforeTotal;
          _total.text = b.total == null ? '' : money(b.total!, de: context.langCode == 'de');
          b.checked = false;
        });
        StoreScope.read(context).upsert(b);
      },
    );
  }

  void _answerSign(bool refund) {
    setState(() {
      b.resolveSign(refund: refund);
      _total.text = b.total == null ? '' : money(b.total!, de: context.langCode == 'de');
    });
    StoreScope.read(context).upsert(b);
  }

  // ---- people ----

  Future<void> _addPerson() async {
    final idx = await addPersonWithPicker(context, b);
    if (idx == null || !mounted) return;
    FasanHaptics.of(context).confirm();
    setState(() {});
  }

  /// Group members that are not on this bill yet (names), or – without a group – recent names.
  List<String> _suggestions() {
    final collab = CollabScope.read(context), store = StoreScope.read(context);
    final have = {for (final p in b.ps) p.name.toLowerCase()};
    final names = b.group != null ? collab.peopleOf(b.group!) : store.recentNames;
    final me = (collab.identity?.name ?? store.me).trim();
    return [
      if (b.group != null && me.isNotEmpty) me,
      ...names,
    ].where((n) => n.trim().isNotEmpty && n != '—').fold<List<String>>([], (a, n) => a.any((x) => x.toLowerCase() == n.toLowerCase()) ? a : [...a, n]).where((n) => !have.contains(n.toLowerCase())).take(8).toList();
  }

  // ---- items ----

  bool _everyone(BillItem it) => b.ps.isNotEmpty && List.generate(b.ps.length, (i) => (it.shares[i] ?? 0) > 0).every((x) => x);

  /// Swipe right: everyone has this item, or – if everyone already has it – nobody.
  void _toggleEveryone(BillItem it) {
    if (b.ps.isEmpty) {
      showNote(context, context.tr('bill.needPeople'));
      return;
    }
    FasanHaptics.of(context).confirm();
    setState(() => it.shares = _everyone(it) ? {} : {for (var i = 0; i < b.ps.length; i++) i: 1});
  }

  /// Long press on a person: paid, all open items, remove.
  Future<void> _personMenu(int i) async {
    final name = b.ps[i].name;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        // scrolls on a phone held sideways (the four entries are taller than the sheet there)
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: FasanAvatar(name: name, index: b.ps[i].color, size: 32), title: MarqueeText(name, style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(leading: const Icon(Icons.payments_outlined), title: Text(ctx.tr('person.setPayer')), onTap: () => Navigator.pop(ctx, 'payer')),
          ListTile(leading: const Icon(Icons.done_all_rounded), title: Text(ctx.tr('person.allOpen')), enabled: b.unassigned > 0, onTap: () => Navigator.pop(ctx, 'open')),
          ListTile(leading: const Icon(Icons.person_remove_outlined), title: Text(ctx.tr('person.remove')), onTap: () => Navigator.pop(ctx, 'remove')),
        ])),
      ),
    );
    if (!mounted || choice == null) return;
    setState(() {
      switch (choice) {
        case 'payer':
          b.paid.clear();
          b.payer = i;
        case 'open':
          for (final it in b.its.where((x) => !x.assigned)) {
            it.shares[i] = 1;
          }
        case 'remove':
          removePersonFrom(b, i);
          _active = null;
      }
    });
  }

  Future<void> _openItem(BillItem it) async {
    await showItemSheet(context, b, it, changed: _changed, onDelete: () => _deleteItem(it));
    if (mounted) {
      setState(() => b.checked = false);
      _alignSigns();
    }
  }

  void _deleteItem(BillItem it) {
    final at = b.its.indexOf(it);
    if (at < 0) return;
    setState(() {
      b.its.removeAt(at);
      b.checked = false;
    });
    showNote(
      context,
      context.tr('bill.removed', [it.title]),
      actionLabel: context.tr('bill.undo'),
      onAction: () {
        setState(() => b.its.insert(math.min(at, b.its.length), it));
        StoreScope.read(context).upsert(b);
      },
    );
  }

  Future<void> _addItem() async {
    final it = BillItem(name: context.tr('bill.items'), amount: 0);
    setState(() => b.its.add(it));
    await _openItem(it);
  }

  void _tapItem(BillItem it) {
    // the active person may have been removed in the item sheet meanwhile: then it is just a tap on the item
    final a = _active != null && _active! < b.ps.length ? _active : null;
    if (a == null) {
      _active = null;
      _openItem(it);
      return;
    }
    FasanHaptics.of(context).tap();
    setState(() {
      if ((it.shares[a] ?? 0) > 0) {
        it.shares.remove(a);
      } else {
        it.shares[a] = 1;
      }
    });
  }

  // ---- menu and check ----

  void _evenly() {
    final before = [for (final it in b.its) Map<int, double>.of(it.shares)];
    for (final it in b.its) {
      it.shares = {for (var i = 0; i < b.ps.length; i++) i: 1};
    }
    FasanHaptics.of(context).confirm();
    setState(() {});
    showNote(context, context.tr('bill.splitEvenlyDone'), actionLabel: context.tr('bill.undo'), duration: const Duration(seconds: 6), onAction: () {
      if (!mounted) return;
      setState(() {
        for (var k = 0; k < b.its.length && k < before.length; k++) {
          b.its[k].shares = before[k];
        }
      });
    });
  }

  void _check() {
    final de = context.langCode == 'de', sign = billSign(context, b);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final tt = Theme.of(ctx).textTheme, l = FasanLook.of(ctx);
        final diff = b.difference, hasTotal = b.total != null;
        Widget line(String k, int cents, {bool strong = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(ctx.tr(k), style: tt.bodyMedium)),
                const SizedBox(width: FasanSpace.s),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('${money(cents, de: de)} $sign', style: tt.bodyLarge!.copyWith(fontWeight: strong ? FontWeight.w700 : null)))),
              ]),
            );
        final ok = hasTotal && diff == 0 && b.its.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.l),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ctx.tr('check.title'), style: tt.titleMedium),
              const SizedBox(height: FasanSpace.s),
              line('check.itemsSum', b.itemSum),
              if (hasTotal) line('check.total', b.total!) else Text(ctx.tr('check.noTotal'), style: tt.bodyMedium),
              if (hasTotal) line('check.diff', diff, strong: diff != 0),
              const SizedBox(height: FasanSpace.s),
              Row(children: [
                Icon(ok ? Icons.verified_outlined : Icons.error_outline, size: 18, color: ok ? l.accent : Theme.of(ctx).colorScheme.error),
                const SizedBox(width: FasanSpace.s),
                Expanded(child: Text(ok ? ctx.tr('bill.checkOk') : (hasTotal ? ctx.tr('bill.checkDiff', ['${money(diff.abs(), de: de)} $sign']) : ctx.tr('check.noTotal')), style: tt.bodyMedium)),
              ]),
              if (hasTotal && diff != 0)
                TextButton.icon(
                  icon: const Icon(Icons.functions_rounded),
                  label: Text(ctx.tr('check.setTotal', ['${money(b.itemSum, de: de)} $sign'])),
                  onPressed: () {
                    setState(() {
                      b.total = b.itemSum;
                      _total.text = money(b.total!, de: context.langCode == 'de');
                      b.checked = false;
                    });
                    Navigator.pop(ctx);
                  },
                ),
              if (hasTotal && diff > 0)
                TextButton.icon(
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: Text(ctx.tr('check.addRemainder', ['${money(diff, de: de)} $sign', remainderName(diff, b.itemSum)])),
                  onPressed: () {
                    setState(() => b.its.add(BillItem(name: remainderName(diff, b.itemSum), amount: diff, sure: false, note: 'anteilig verteilt', proportional: true)));
                    Navigator.pop(ctx);
                  },
                ),
            ]),
          ),
        );
      }),
    );
  }

  // ---- done ----

  /// Fertig: everything is assigned and someone paid → the summary. Otherwise say what is missing (a note, not a dead button).
  void _finish() {
    String? problem;
    if (b.needsSignQuestion) {
      problem = S.of(context).signTitle;
    } else if (b.its.isEmpty) {
      problem = context.tr('bill.needItems');
    } else if (b.ps.length < 2) {
      problem = context.tr('bill.needPeople');
    } else if (b.unassigned > 0) {
      problem = context.trn('bill.openItems', b.unassigned);
    } else if (b.payer == null) {
      problem = context.tr('bill.needPayer');
    }
    if (problem != null) {
      FasanHaptics.of(context).warn();
      showNote(context, problem);
      return;
    }
    b.purpose = _purpose.text.trim();
    b.step = 4;
    StoreScope.read(context).upsert(b);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayScreen(bill: b)));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final de = context.langCode == 'de', sign = billSign(context, b);
    final open = b.unassigned;
    final suggestions = _suggestions();
    final diff = b.difference;
    final showDiff = b.total != null && diff != 0 && !b.needsSignQuestion;
    final hasImage = imageExists(b.originalPath);
    final active = _active != null && _active! < b.ps.length ? _active : null;
    final payer = payersSummary(context, b);

    return StepScaffold(
      title: context.tr('bill.title'),
      step: 1,
      showStep: false,
      bill: b,
      actions: [
        IconButton(tooltip: context.tr('bill.undo'), icon: const Icon(Icons.undo_rounded), onPressed: store.canUndo(b) ? () => _step(-1) : null),
        IconButton(tooltip: context.tr('bill.redo'), icon: const Icon(Icons.redo_rounded), onPressed: store.canRedo(b) ? () => _step(1) : null),
        IconButton(tooltip: context.tr('bill.checkTip'), icon: const Icon(Icons.fact_check_outlined), onPressed: _check),
        PopupMenuButton<String>(
          tooltip: t.more,
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) {
            switch (v) {
              case 'reread':
                rereadFlow(context, b);
              case 'evenly':
                _evenly();
              case 'snippets':
                setState(() => _snippets = !_snippets);
              case 'receipt':
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => AssignScreen(bill: b, initialMode: AssignMode.receipt)));
            }
          },
          // every entry is always there; what cannot work right now is shown disabled with the reason (Prüfliste G1: Apple
          // „disable instead of hide“; Nutzer 06.11.: in the browser the menu showed one entry or none)
          itemBuilder: (_) {
            final noPhoto = context.tr(photoComing(context, b) ? 'bill.photoComing' : 'bill.photoHere');
            final hasScan = imageExists(b.imagePath), canEven = b.ps.length >= 2 && b.its.isNotEmpty;
            final hasSnippets = b.its.any((i) => i.snippet != null);
            ListTile row(IconData icon, String title, String? why) =>
                ListTile(leading: Icon(icon), title: Text(title), subtitle: why == null ? null : Text(why), enabled: why == null);
            return [
              PopupMenuItem(value: 'reread', enabled: hasImage, child: row(Icons.document_scanner_outlined, context.tr('bill.reread'), hasImage ? null : noPhoto)),
              PopupMenuItem(value: 'evenly', enabled: canEven, child: row(Icons.groups_2_outlined, context.tr('bill.splitEvenly'), canEven ? null : context.tr('bill.needTwoPeople'))),
              CheckedPopupMenuItem(
                value: 'snippets',
                checked: _snippets && hasSnippets,
                enabled: hasSnippets,
                child: hasSnippets ? Text(context.tr('bill.snippets')) : ListTile(title: Text(context.tr('bill.snippets')), subtitle: Text(noPhoto), enabled: false),
              ),
              PopupMenuItem(value: 'receipt', enabled: hasScan, child: row(Icons.receipt_long_outlined, context.tr('bill.assignOnReceipt'), hasScan ? null : noPhoto)),
            ];
          },
        ),
      ],
      action: open == 0 || b.its.isEmpty ? context.tr('bill.done') : context.trn('bill.open', open),
      onAction: _finish,
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context)),
        children: [
          // head: purpose and total on one row; the total is the only big number on the screen
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _purpose,
                decoration: InputDecoration(labelText: context.tr('bill.purpose'), hintText: t.purposeHint),
                textInputAction: TextInputAction.next,
                onChanged: (v) {
                  b.purpose = v.trim();
                  StoreScope.read(context).upsert(b);
                },
              ),
            ),
            const SizedBox(width: FasanSpace.s),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _total,
                textAlign: TextAlign.end,
                decoration: InputDecoration(labelText: context.tr('bill.total'), suffixText: sign),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: tt.titleLarge,
                onChanged: (v) {
                  setState(() {
                    b.total = parseMoney(v);
                    b.checked = false;
                  });
                  _alignSigns();
                },
              ),
            ),
          ]),
          const SizedBox(height: FasanSpace.xs),
          Wrap(spacing: 4, runSpacing: 0, children: [CurrencyChip(bill: b), CategoryChip(bill: b)]),
          WhenWhere(bill: b, compact: true, onChanged: _changed),
          const SizedBox(height: FasanSpace.s),

          // people: chips of everyone on the bill (tap = „now tap their items“), suggestions, then who paid
          FasanLabel(context.tr('bill.people')),
          const SizedBox(height: FasanSpace.xs),
          Wrap(spacing: 4, runSpacing: 0, children: [
            for (var i = 0; i < b.ps.length; i++)
              // long press: the same things as a menu (paid, all open items, remove) – tap = their items, x = remove
              GestureDetector(
                onLongPress: () => _personMenu(i),
                child: InputChip(
                  key: ValueKey('person-$i'),
                  visualDensity: VisualDensity.compact,
                  labelPadding: const EdgeInsets.only(right: 2),
                  avatar: FasanAvatar(name: b.ps[i].name, index: b.ps[i].color, size: 22),
                  label: MarqueeLabel(b.ps[i].name, style: Theme.of(context).chipTheme.labelStyle ?? tt.labelLarge),
                  selected: active == i,
                  showCheckmark: false,
                  selectedColor: l.accent.withValues(alpha: 0.25),
                  onPressed: () => setState(() => _active = active == i ? null : i),
                  onDeleted: () {
                    removePersonFrom(b, i);
                    setState(() => _active = null);
                  },
                ),
              ),
            ActionChip(
              key: const ValueKey('add-person'),
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.person_add_alt_rounded, size: 18),
              label: Text(context.tr('bill.addPerson')),
              onPressed: _addPerson,
            ),
          ]),
          if (suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FasanSpace.xs),
              child: Wrap(spacing: 4, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final n in suggestions)
                  ActionChip(
                    key: ValueKey('suggest-$n'),
                    visualDensity: VisualDensity.compact,
                    label: Text('+ $n'),
                    onPressed: () {
                      if (addPersonTo(b, n)) {
                        FasanHaptics.of(context).tap();
                        setState(() {});
                      }
                    },
                  ),
                if (b.group != null && suggestions.length >= 2)
                  ActionChip(
                    key: const ValueKey('suggest-all'),
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.groups_2_outlined, size: 18),
                    label: Text(context.tr('bill.allFromGroup')),
                    onPressed: () {
                      for (final n in suggestions) {
                        addPersonTo(b, n);
                      }
                      FasanHaptics.of(context).confirm();
                      setState(() {});
                    },
                  ),
              ]),
            ),
          if (active != null)
            Container(
              margin: const EdgeInsets.only(top: FasanSpace.s),
              padding: const EdgeInsets.only(left: FasanSpace.m),
              decoration: BoxDecoration(color: l.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(l.radius * 0.5)),
              child: Row(children: [
                // a long name wraps and is cut; the button stays short
                Expanded(child: Text(context.tr('bill.activeHint', [b.ps[active].name]), style: tt.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                TextButton(key: const ValueKey('active-stop'), onPressed: () => setState(() => _active = null), child: Text(context.tr('item.done'))),
              ]),
            ),
          if (b.ps.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: FasanSpace.xs),
              child: Row(children: [
                Text('${context.tr('bill.paidBy')}:', style: tt.labelLarge!.copyWith(color: l.textMuted)),
                const SizedBox(width: FasanSpace.s),
                // a long name is cut inside the chip instead of pushing the row wider than the screen
                Flexible(
                  child: ActionChip(
                    key: const ValueKey('payer'),
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.payments_outlined, size: 18, color: payer.isEmpty ? l.accent : null),
                    label: MarqueeLabel(payer.isEmpty ? context.tr('bill.paidByNone') : payer, maxWidth: 230, style: (Theme.of(context).chipTheme.labelStyle ?? tt.labelLarge)?.copyWith(color: payer.isEmpty ? l.accent : null)),
                    onPressed: () => showPayersSheet(context, b, changed: _changed),
                  ),
                ),
              ]),
            ),

          // the sign question (only when the total is negative) and the refund note
          if (b.needsSignQuestion) ...[
            const SizedBox(height: FasanSpace.s),
            Container(
              padding: const EdgeInsets.all(FasanSpace.m),
              decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.7), border: Border.all(color: l.accent)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.signTitle, style: tt.titleMedium),
                const SizedBox(height: FasanSpace.xs),
                Text(t.signText, style: tt.bodySmall),
                const SizedBox(height: FasanSpace.s),
                Row(children: [
                  Expanded(child: FasanButton(label: t.signPaid, onPressed: () => _answerSign(false))),
                  const SizedBox(width: FasanSpace.s),
                  Expanded(child: FasanButton(label: t.signRefund, onPressed: () => _answerSign(true))),
                ]),
              ]),
            ),
          ] else if (b.refund) ...[
            const SizedBox(height: FasanSpace.s),
            const RefundNote(),
          ],
          // quiet by default: a line only when something does not add up (the check button at the top shows the details)
          if (showDiff || widget.scan?.contradiction == true)
            InkWell(
              onTap: _check,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: FasanSpace.s),
                child: Row(children: [
                  Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: FasanSpace.s),
                  Expanded(child: Text(showDiff ? context.tr('bill.checkDiff', ['${money(diff.abs(), de: de)} $sign']) : t.contradiction, style: tt.bodySmall)),
                  Icon(Icons.chevron_right_rounded, size: 18, color: l.textMuted),
                ]),
              ),
            ),

          // items
          const SizedBox(height: FasanSpace.m),
          Row(children: [
            FasanLabel('${context.tr('bill.items')} · ${b.its.length}'),
            const SizedBox(width: FasanSpace.s),
            // a very long amount shrinks instead of overflowing the row
            Expanded(child: Align(alignment: Alignment.centerRight, child: FittedBox(fit: BoxFit.scaleDown, child: Money(b.itemSum, style: tt.bodyMedium)))),
          ]),
          const SizedBox(height: FasanSpace.xs),
          for (var i = 0; i < b.its.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              // like the bills on the start page: right = the main action (everyone / nobody), left = delete (with „undo“)
              child: SwipeActions(
                key: ValueKey('item-${b.its[i].hashCode}'),
                id: 'item-${identityHashCode(b.its[i])}',
                start: SwipeSide(_everyone(b.its[i]) ? Icons.person_off_outlined : Icons.groups_2_outlined, context.tr(_everyone(b.its[i]) ? 'item.swipeNone' : 'item.swipeAll'), l.accent),
                end: SwipeSide(Icons.delete_outline_rounded, context.tr('item.delete'), Colors.red.shade700),
                // the right swipe does its work here and says „no“: the row springs back (a Dismissible that is dismissed but stays
                // in the list is an error of the framework)
                confirmDismiss: (dir) async {
                  if (dir == DismissDirection.startToEnd) {
                    _toggleEveryone(b.its[i]);
                    return false;
                  }
                  return true;
                },
                onDismissed: (_) => _deleteItem(b.its[i]),
                child: _ItemTile(
                  bill: b,
                  item: b.its[i],
                  active: active,
                  showSnippet: _snippets || !b.its[i].sure,
                  onTap: () => _tapItem(b.its[i]),
                  onLongPress: () => _openItem(b.its[i]),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: FasanButton(label: context.tr('bill.addItem'), icon: Icons.add, kind: FasanButtonKind.quiet, onPressed: _addItem),
          ),
        ],
      ),
    );
  }
}

/// One item in the list: name, who has it, price. Tap: change and assign (or, with a person active, toggle that person).
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.bill, required this.item, required this.active, required this.showSnippet, required this.onTap, required this.onLongPress});

  final Bill bill;
  final BillItem item;
  final int? active;
  final bool showSnippet;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final unassigned = bill.ps.length >= 2 && !item.assigned;
    final mine = active != null && (item.shares[active] ?? 0) > 0;
    return Material(
      color: mine ? l.accent.withValues(alpha: 0.14) : l.surfaceAlt,
      borderRadius: BorderRadius.circular(l.radius * 0.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(l.radius * 0.5),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(minHeight: l.minTap),
          padding: const EdgeInsets.fromLTRB(FasanSpace.m, 8, FasanSpace.m, 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(l.radius * 0.5), border: unassigned ? Border.all(color: l.accent.withValues(alpha: 0.5)) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: ItemTitle(item, maxLines: 1)),
              if (!item.sure)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.help_outline, size: 18, color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(width: FasanSpace.xs),
              // many people or a huge amount shrink to fit; the name gives way first (it has an ellipsis)
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: ShareAvatars(bill: bill, item: item))),
              const SizedBox(width: FasanSpace.m),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Money(item.amount))),
            ]),
            if (item.note != null) Text(item.note!, style: tt.bodySmall),
            if (showSnippet && item.snippet != null) Padding(padding: const EdgeInsets.only(top: 4), child: Snippet(item.snippet, height: 22)),
          ]),
        ),
      ),
    );
  }
}
