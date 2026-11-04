// Fasan Split – the bill flow: 1 total and purpose, 2 who was there, 3 assign, 4 who paid + result. MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../l10n_bill.dart';
import '../l10n_groups.dart';
import '../main.dart';
import '../state/scan_queue.dart';
import '../state/images.dart';
import '../model/bill.dart';
import '../recognition_service.dart';
import 'assign.dart';
import 'category_ui.dart';
import 'currency_ui.dart';
import 'collab_ui.dart';
import '../model/scan_bill.dart' show remainderName;
import 'bill_notes.dart';
import 'common.dart';
import 'when_where.dart';
import 'diagnose.dart';

// ---------------------------------------------------------------------------------------------------------------------
// 1. total and purpose

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.bill, this.scan});

  final Bill bill;
  final ScanResultData? scan;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final _purpose = TextEditingController(text: widget.bill.purpose);
  late final _total = TextEditingController(text: widget.bill.total == null ? '' : money(widget.bill.total!));

  Bill get b => widget.bill;
  int _pulse = 0;
  bool _wasOk = false;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    final diff = b.difference;
    // The total matches the items: one ring pulse around the total and a light haptic (attention rules: once).
    final ok = b.total != null && diff == 0 && b.its.isNotEmpty;
    if (ok && !_wasOk) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _pulse++);
        FasanHaptics.of(context).confirm();
      });
    }
    _wasOk = ok;
    final status = b.checked && diff == 0
        ? _Status(icon: Icons.verified_outlined, text: t.checked, color: l.accent)
        : (diff != 0 && b.total != null
            ? _Status(icon: Icons.error_outline, text: t.diff('${money(diff.abs(), de: t.de)} ${billSign(context, b)}'), color: Theme.of(context).colorScheme.error)
            : (widget.scan?.contradiction == true ? _Status(icon: Icons.help_outline, text: t.contradiction, color: Theme.of(context).colorScheme.error) : null));
    return StepScaffold(
      title: t.totalAndPurpose,
      step: 1,
      bill: b,
      actions: [
        if (imageExists(b.originalPath))
          IconButton(tooltip: t.de ? 'Bon neu lesen' : 'Read receipt again', icon: const Icon(Icons.document_scanner_outlined), onPressed: () => rereadFlow(context, b)),
      ],
      action: t.next,
      onAction: (b.its.isEmpty && b.total == null) || b.needsSignQuestion
          ? null
          : () {
              b.purpose = _purpose.text.trim();
              StoreScope.read(context).upsert(b);
              // people already chosen here (Nutzer 04.11.): straight to assigning, else the people step
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => b.ps.length >= 2 ? AssignScreen(bill: b) : PeopleScreen(bill: b)));
            },
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context)),
        children: [
          // compact head: the items are the main thing, purpose/total/date/place take two rows (Nutzer 02.11.)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _purpose,
                decoration: InputDecoration(labelText: t.purpose, hintText: t.purposeHint),
                textInputAction: TextInputAction.next,
                // saved while typing: leaving without „Weiter“ or a finishing scan must not lose the name
                onChanged: (v) {
                  b.purpose = v.trim();
                  StoreScope.read(context).upsert(b);
                },
              ),
            ),
            const SizedBox(width: FasanSpace.s),
            Expanded(
              flex: 2,
              child: FasanGlow(pulse: _pulse, strength: 0, radius: 6, child: TextField(
                controller: _total,
                textAlign: TextAlign.end,
                decoration: InputDecoration(labelText: t.total, suffixText: billSign(context, b)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: tt.titleLarge,
                onChanged: (v) => setState(() {
                  b.total = parseMoney(v);
                  b.checked = false;
                }),
              )),
            ),
          ]),
          const SizedBox(height: FasanSpace.s),
          // currency and category right where the total is checked (Nutzer 04.11.)
          Wrap(spacing: 4, runSpacing: 0, children: [CurrencyChip(bill: b), CategoryChip(bill: b)]),
          // who was there and who paid, right at the start (Nutzer 04.11.: not only at the end)
          QuickPeople(bill: b, onChanged: () => setState(() {})),
          const SizedBox(height: FasanSpace.s),
          WhenWhere(bill: b, compact: true, onChanged: () => setState(() {})),
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
          if (status != null) ...[const SizedBox(height: FasanSpace.xs), status],
          // the receipt says more than its items (Ferreiras 7,90, Nutzer 04.11.): one tap makes it a line that is shared
          // like the items (whoever had more pays more of it); it can be renamed or removed like any line
          if (b.total != null && diff > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.playlist_add_rounded),
                label: Text(t.de
                    ? '${money(diff, de: true)} ${billSign(context, b)} als Zeile „${remainderName(diff, b.itemSum)}“ anteilig verteilen'
                    : 'Add ${money(diff, de: false)} ${billSign(context, b)} as “${remainderName(diff, b.itemSum)}”, shared proportionally'),
                onPressed: () => setState(() {
                  b.its.add(BillItem(name: remainderName(diff, b.itemSum), amount: diff, sure: false, note: 'anteilig verteilt', proportional: true));
                  StoreScope.read(context).upsert(b);
                }),
              ),
            ),
          const SizedBox(height: FasanSpace.l),
          Row(children: [
            FasanLabel('${t.items} · ${b.its.length}'),
            const Spacer(),
            Money(b.itemSum, style: tt.bodyMedium),
          ]),
          const SizedBox(height: FasanSpace.s),
          for (var i = 0; i < b.its.length; i++) _ItemRow(item: b.its[i], onTap: () => _edit(i)),
          const SizedBox(height: FasanSpace.s),
          Align(
            alignment: Alignment.centerLeft,
            child: FasanButton(label: t.addItem, icon: Icons.add, kind: FasanButtonKind.quiet, onPressed: _add),
          ),
        ],
      ),
    );
  }

  void _answerSign(bool refund) {
    setState(() {
      b.resolveSign(refund: refund);
      _total.text = b.total == null ? '' : money(b.total!);
    });
    StoreScope.read(context).upsert(b);
  }

  Future<void> _edit(int i) async {
    final it = b.its[i];
    var deleted = false;
    final changed = await editItem(context, it, onDelete: () => deleted = true);
    if (!changed) return;
    setState(() {
      if (deleted) b.its.removeAt(i);
      b.checked = false;
    });
  }

  Future<void> _add() async {
    final it = BillItem(name: S.of(context).de ? 'Posten' : 'Item', amount: 0);
    if (await editItem(context, it)) setState(() => b.its.add(it));
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    // one small line, not a big box (space belongs to the items)
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: l.radius * 0.2, vertical: 4),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: FasanSpace.s),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final BillItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final unsure = !item.sure || (item.certainty != null && item.certainty! < 60);
    // Each item is one card: name, amount and its line picture share one region, with clear gaps between items
    // (Common Region; 0.2 showed the picture between two names and it was unclear which it belonged to).
    return Padding(
      padding: const EdgeInsets.only(bottom: FasanSpace.s),
      child: Material(
        color: l.surfaceAlt,
        borderRadius: BorderRadius.circular(l.radius * 0.5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(l.radius * 0.5),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FasanSpace.m, 10, FasanSpace.m, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ItemTitle(item)),
                if (unsure)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: Tooltip(message: t.unsure, child: Icon(Icons.help_outline, size: 18, color: Theme.of(context).colorScheme.error)),
                  ),
                Money(item.amount),
              ]),
              if (item.note != null) Text(item.note!, style: tt.bodySmall),
              if (item.snippet != null) Padding(padding: const EdgeInsets.only(top: 6), child: Snippet(item.snippet, height: 24)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// 2. who was there

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.bill});

  final Bill bill;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _name = TextEditingController();
  Bill get b => widget.bill;

  void _add(String n) {
    final name = n.trim();
    if (name.isEmpty || b.ps.any((p) => p.name.toLowerCase() == name.toLowerCase())) return;
    final used = b.ps.map((p) => p.color).toSet();
    var c = 0;
    while (used.contains(c) && c < 64) {
      c++;
    }
    setState(() => b.ps.add(Person(name, c)));
    _name.clear();
    FasanHaptics.of(context).tap();
  }

  void _invite(String person) {
    final g = b.group == null ? null : CollabScope.read(context).groupByLocalName(b.group!);
    if (g == null || !g.isAdmin || g.session.memberOfPerson(person) != null) return;
    StoreScope.read(context).upsert(b); // the person must be in the group's bills before the invitation
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: g, person: person)));
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final store = StoreScope.of(context);
    final recent = store.recentNames.where((n) => !b.ps.any((p) => p.name == n)).toList();
    final g = b.group;
    final fromGroup = g == null || g.isEmpty ? const <String>[] : CollabScope.read(context).peopleOf(g).where((n) => !b.ps.any((p) => p.name == n)).toList();
    return StepScaffold(
      title: t.whoWasThere,
      step: 2,
      bill: b,
      action: b.ps.length < 2 ? t.needPeople : t.next,
      onAction: b.ps.length < 2
          ? null
          : () {
              StoreScope.read(context).upsert(b);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => AssignScreen(bill: b)));
            },
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context)),
        children: [
          Row(children: [
            Expanded(child: TextField(controller: _name, decoration: InputDecoration(labelText: t.addPerson), textCapitalization: TextCapitalization.words, onSubmitted: _add)),
            const SizedBox(width: FasanSpace.s),
            FasanButton(label: t.add, onPressed: () => _add(_name.text)),
          ]),
          const SizedBox(height: FasanSpace.l),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < b.ps.length; i++)
              InputChip(
                avatar: FasanAvatar(name: b.ps[i].name, index: b.ps[i].color, size: 28),
                label: Text(b.ps[i].name),
                // Bill in a live group (admin): tap a person to invite them; the new member is linked to this name.
                onPressed: () => _invite(b.ps[i].name),
                onDeleted: () => setState(() {
                  b.ps.removeAt(i);
                  for (final it in b.its) {
                    it.shares = {for (final e in it.shares.entries) if (e.key != i) (e.key > i ? e.key - 1 : e.key): e.value};
                  }
                  if (b.payer == i) b.payer = null;
                }),
              ),
          ]),
          if (fromGroup.isNotEmpty) ...[
            const SizedBox(height: FasanSpace.l),
            ActionChip(
              avatar: const Icon(Icons.group_add_outlined, size: 18),
              label: Text(t.allFromGroup(g!)),
              onPressed: () {
                for (final n in fromGroup) {
                  _add(n);
                }
              },
            ),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: FasanSpace.xl),
            FasanLabel(t.recent),
            const SizedBox(height: FasanSpace.s),
            // long press removes a name from the suggestions; the app says when bills still hold it (Nutzer 04.11.)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in recent)
                GestureDetector(
                  onLongPress: () {
                    final s = StoreScope.read(context);
                    s.forget(n);
                    final inTrash = s.trashedWith(n);
                    final live = s.bills.where((x) => x.trashedAt == null && x.ps.any((p) => p.name == n)).length;
                    showNote(
                      context,
                      [
                        t.de ? '„$n“ ist aus den Vorschlägen entfernt.' : '“$n” removed from the suggestions.',
                        if (live > 0) t.de ? 'In $live Bons bleibt der Name stehen (dort hat die Person Kosten).' : 'It stays in $live receipts (costs there).',
                        if (inTrash > 0) t.de ? '$inTrash Bons im Papierkorb tragen ihn noch.' : '$inTrash receipts in the trash still carry it.',
                      ].join(' '),
                    );
                  },
                  child: ActionChip(label: Text(n), onPressed: () => _add(n)),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// „Bon neu lesen“: after asking, the newest recognition reads the original photo again (ScanQueue.reread).
Future<void> rereadFlow(BuildContext context, Bill bill) async {
  final t = S.of(context), q = ScanQueue.current, path = bill.originalPath;
  if (q == null || path == null) return;
  final ok = await confirmDialog(
    context,
    t.de ? 'Bon neu lesen' : 'Read receipt again',
    t.de
        ? 'Die Posten werden mit der neuesten Erkennung neu gelesen. Die Zuordnung der Posten geht dabei verloren. Personen, Zahler, Gruppe, Kategorie und Name bleiben.'
        : 'The items are read again with the newest recognition. The assignment of the items is lost; people, payer, group, category and name stay.',
    t.de ? 'Neu lesen' : 'Read again',
  );
  if (!ok || !context.mounted) return;
  final bytes = await readImage(path);
  if (bytes == null || !context.mounted) return;
  await q.reread(bill, bytes);
  if (context.mounted) closeBillFlow(context);
}

/// Adds [name] to the bill with the first free colour; false if the name is there already.
bool addPersonTo(Bill b, String name) {
  final n = name.trim();
  if (n.isEmpty || b.ps.any((p) => p.name.toLowerCase() == n.toLowerCase())) return false;
  final used = b.ps.map((p) => p.color).toSet();
  var c = 0;
  while (used.contains(c) && c < 64) {
    c++;
  }
  b.ps.add(Person(n, c));
  return true;
}

/// Removes person [i]; shares and payer move with the indices.
void removePersonFrom(Bill b, int i) {
  b.ps.removeAt(i);
  for (final it in b.its) {
    it.shares = {for (final e in it.shares.entries) if (e.key != i) (e.key > i ? e.key - 1 : e.key): e.value};
  }
  if (b.payer == i) {
    b.payer = null;
  } else if (b.payer != null && b.payer! > i) {
    b.payer = b.payer! - 1;
  }
  b.paid = {for (final e in b.paid.entries) if (e.key != i) (e.key > i ? e.key - 1 : e.key): e.value};
}

/// Step 1: who was there and who paid, in one row of chips. Tap a person = paid (again = not); x = remove; + and the
/// recent names add someone.
class QuickPeople extends StatelessWidget {
  const QuickPeople({super.key, required this.bill, required this.onChanged});

  final Bill bill;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context), b = bill;
    final recent = store.recentNames.where((n) => !b.ps.any((p) => p.name == n)).take(6).toList();
    void changed() {
      FasanHaptics.of(context).tap();
      store.upsert(b);
      onChanged();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        b.ps.isEmpty ? t.whoWasThere : (b.payer == null ? (t.de ? 'Wer war dabei? Tippe, wer bezahlt hat.' : 'Who was there? Tap who paid.') : t.whoWasThere),
        style: tt.labelLarge!.copyWith(color: l.textMuted),
      ),
      const SizedBox(height: FasanSpace.xs),
      Wrap(spacing: 4, runSpacing: 0, children: [
        for (var i = 0; i < b.ps.length; i++)
          InputChip(
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.only(right: 2),
            avatar: FasanAvatar(name: b.ps[i].name, index: b.ps[i].color, size: 22),
            label: Text(b.payer == i ? '${b.ps[i].name} · ${t.de ? 'bezahlt' : 'paid'}' : b.ps[i].name),
            selected: b.payer == i,
            showCheckmark: false,
            selectedColor: l.accent.withValues(alpha: 0.2),
            onPressed: () {
              b.payer = b.payer == i ? null : i;
              changed();
            },
            onDeleted: () {
              removePersonFrom(b, i);
              changed();
            },
          ),
        ActionChip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.person_add_alt_rounded, size: 18),
          label: Text(t.addPerson),
          onPressed: () async {
            final n = await askText(context, t.addPerson, t.friendName);
            if (n != null && addPersonTo(b, n)) changed();
          },
        ),
        for (final n in recent)
          ActionChip(
            visualDensity: VisualDensity.compact,
            label: Text('+ $n'),
            onPressed: () {
              if (addPersonTo(b, n)) changed();
            },
          ),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// 4. who paid + result

class PayScreen extends StatefulWidget {
  const PayScreen({super.key, required this.bill});

  final Bill bill;

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  Bill get b => widget.bill;
  late bool _multi = b.multiPay;
  final Map<int, TextEditingController> _amount = {};

  @override
  void dispose() {
    for (final c in _amount.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctl(int i) => _amount.putIfAbsent(i, () => TextEditingController(text: money(b.paid[i] ?? 0, de: S.of(context).de)));

  /// Equal parts of the receipt for everyone who paid (exact cents, the first ones get the leftover cent).
  void _spreadEqually() {
    final who = b.paid.keys.toList()..sort();
    if (who.isEmpty) return;
    final total = b.effectiveTotal, each = total ~/ who.length;
    var rest = total - each * who.length;
    for (final i in who) {
      b.paid[i] = each + (rest-- > 0 ? 1 : 0);
      _ctl(i).text = money(b.paid[i]!, de: S.of(context).de);
    }
    _syncPayer();
  }

  /// The one who paid most stands for the bill in lists and balances that show one name.
  void _syncPayer() {
    if (b.paid.isEmpty) return;
    b.payer = (b.paid.entries.toList()..sort((x, y) => y.value.compareTo(x.value))).first.key;
  }

  void _togglePayer(int i) => setState(() {
        if (!_multi) {
          b.paid.clear();
          b.payer = i;
          return;
        }
        if (b.paid.containsKey(i)) {
          b.paid.remove(i);
          _amount.remove(i)?.dispose();
        } else {
          b.paid[i] = 0;
        }
        _spreadEqually();
        if (b.paid.isEmpty) b.payer = null;
      });

  // Step 4 is the summary (Nutzer 04.11.: the old „Wer hat bezahlt?“ screen asked again what step 3 already knew and
  // raised question marks). Who paid stays changeable in one small row; the result is the main thing; „Eintragen“ puts
  // the bill under Offen, it counts in the balances, and goes to the archive once it is settled.
  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    return StepScaffold(
      title: t.de ? 'Übersicht' : 'Summary',
      step: 4,
      bill: b,
      action: t.de ? 'Eintragen' : 'Save',
      onAction: b.payer == null || b.paidGap != 0
          ? null
          : () {
              // The numbers are checked twice (Beschluss 03.11.): a mismatch stops here, nothing is saved as finished.
              if (b.audit().isNotEmpty) {
                FasanHaptics.of(context).warn();
                showNote(context, t.splitCheckBad, duration: const Duration(seconds: 6));
                return;
              }
              b.done = true;
              if (b.transfers().isEmpty) b.settled = true; // nobody owes anything: nothing to settle
              StoreScope.read(context).upsert(b);
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => ResultScreen(bill: b)), isBillOrigin);
            },
      body: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context)),
        children: [
          Text(b.payer == null ? (t.de ? 'Wer hat bezahlt? Tippe auf eine Person.' : 'Who paid? Tap a person.') : (t.de ? 'Bezahlt hat' : 'Paid by'),
              style: tt.labelLarge!.copyWith(color: b.payer == null ? l.accent : l.textMuted)),
          const SizedBox(height: FasanSpace.xs),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < b.ps.length; i++)
              FasanPersonChip(name: b.ps[i].name, index: b.ps[i].color, selected: _multi ? b.paid.containsKey(i) : b.payer == i, onTap: () => _togglePayer(i)),
          ]),
          // several payers with their own amounts (Nutzer 04.11.)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: Icon(_multi ? Icons.person_rounded : Icons.group_rounded, size: 18),
              label: Text(_multi ? (t.de ? 'Nur eine Person hat bezahlt' : 'Only one person paid') : (t.de ? 'Mehrere haben bezahlt' : 'Several people paid')),
              onPressed: () => setState(() {
                _multi = !_multi;
                if (_multi) {
                  if (b.payer != null) b.paid = {b.payer!: 0};
                  _spreadEqually();
                } else {
                  b.paid.clear();
                }
              }),
            ),
          ),
          if (_multi && b.paid.isNotEmpty) ...[
            for (final i in (b.paid.keys.toList()..sort()))
              Padding(
                padding: const EdgeInsets.only(bottom: FasanSpace.xs),
                child: Row(children: [
                  FasanAvatar(name: b.ps[i].name, index: b.ps[i].color, size: 28),
                  const SizedBox(width: FasanSpace.s),
                  Expanded(child: Text(b.ps[i].name, style: Theme.of(context).textTheme.bodyLarge)),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _ctl(i),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.end,
                      decoration: InputDecoration(suffixText: billSign(context, b), isDense: true),
                      onChanged: (v) => setState(() {
                        b.paid[i] = parseMoney(v) ?? 0;
                        _syncPayer();
                      }),
                    ),
                  ),
                ]),
              ),
            if (b.paidGap != 0)
              Text(
                b.paidGap > 0
                    ? (t.de ? 'Noch ${money(b.paidGap, de: true)} ${billSign(context, b)} offen bis zur Bon-Summe' : '${money(b.paidGap, de: false)} ${billSign(context, b)} still missing')
                    : (t.de ? '${money(-b.paidGap, de: true)} ${billSign(context, b)} mehr als die Bon-Summe' : '${money(-b.paidGap, de: false)} ${billSign(context, b)} more than the total'),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.red.shade600),
              )
            else
              Text(t.de ? 'Passt: zusammen genau die Bon-Summe.' : 'Fits: together exactly the total.', style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.green.shade600)),
          ],
          if (b.advance > 0) ...[
            const SizedBox(height: FasanSpace.m),
            Text('${t.advance}: ${money(b.advance, de: t.de)} ${billSign(context, b)}', style: tt.bodyMedium),
          ],
          const SizedBox(height: FasanSpace.l),
          if (b.payer != null) ...[
            ResultBody(bill: b),
            const SizedBox(height: FasanSpace.m),
            Text(
              t.de
                  ? 'Nach „Eintragen“ steht der Bon unter Offen und zählt im Saldo. Ins Archiv kommt er, wenn alles bezahlt ist.'
                  : 'After “Save” the receipt is under Open and counts in the balances. It goes to the archive once everything is paid.',
              style: tt.bodySmall!.copyWith(color: l.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Marks a bill as refund (money came back): the payer passes the others' share on. Shown in Review and Result.
class RefundNote extends StatelessWidget {
  const RefundNote({super.key});

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Row(children: [
      Icon(Icons.undo_rounded, size: 18, color: FasanLook.of(context).accent),
      const SizedBox(width: FasanSpace.s),
      Expanded(child: Text('${t.refundBadge}. ${t.refundHint}', style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

/// Per person, transfers, unassigned items.
class ResultBody extends StatelessWidget {
  const ResultBody({super.key, required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    final pp = bill.perPerson();
    final open = bill.its.where((p) => !p.assigned).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FasanLabel(t.result),
      const SizedBox(height: FasanSpace.s),
      for (var i = 0; i < bill.ps.length; i++)
        Container(
          constraints: BoxConstraints(minHeight: l.minTap),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: l.hairline))),
          child: Row(children: [
            FasanAvatar(name: bill.ps[i].name, index: bill.ps[i].color, size: 32),
            const SizedBox(width: FasanSpace.m),
            Expanded(child: Text(t.perPerson(bill.ps[i].name), style: tt.bodyLarge)),
            Money(pp[i] ?? 0),
          ]),
        ),
      if (bill.difference != 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${t.differenceSpread}: ${money(bill.difference, de: t.de, sign: true)} ${billSign(context, bill)}', style: tt.bodySmall)),
      const SizedBox(height: FasanSpace.l),
      for (final (from, to, c) in bill.transfers())
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            FasanAvatar(name: bill.ps[from].name, index: bill.ps[from].color, size: 26),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded, size: 18, color: l.textMuted),
            const SizedBox(width: 6),
            FasanAvatar(name: bill.ps[to].name, index: bill.ps[to].color, size: 26),
            const SizedBox(width: FasanSpace.m),
            Expanded(child: Text(t.owes(bill.ps[from].name, bill.ps[to].name, '${money(c, de: t.de)} ${billSign(context, bill)}'), style: tt.bodyMedium)),
          ]),
        ),
      const SizedBox(height: FasanSpace.m),
      _AuditLine(bill: bill),
      if (open.isNotEmpty) ...[
        const SizedBox(height: FasanSpace.l),
        Text('${t.notAssigned}: ${open.map((p) => p.title).join(', ')}', style: tt.bodySmall!.copyWith(color: Theme.of(context).colorScheme.error)),
      ],
    ]);
  }
}

/// „Rechenprüfung“: every number is computed twice; a mismatch is shown loudly. The expandable part shows how each
/// person's amount is made up (item by item, in cents).
class _AuditLine extends StatelessWidget {
  const _AuditLine({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final issues = bill.audit();
    final ok = issues.isEmpty;
    final pp = bill.perPerson();
    final total = pp.values.fold<int>(0, (a, x) => a + x);
    final color = ok ? FasanLook.of(context).textMuted : Theme.of(context).colorScheme.error;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        leading: Icon(ok ? Icons.verified_outlined : Icons.error_outline_rounded, color: color),
        title: Text(ok ? '${t.splitCheck}: ${money(total, de: t.de)} ${billSign(context, bill)}' : t.splitCheckBad, style: tt.bodyMedium!.copyWith(color: color)),
        children: [
          for (var p = 0; p < bill.ps.length; p++) ...[
            Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(bill.ps[p].name, style: tt.labelLarge))),
            for (var n = 0; n < bill.its.length; n++)
              if (bill.partsOf(n)[p] case final c? when c != 0)
                Row(children: [
                  Expanded(child: Text(bill.its[n].title, style: tt.bodySmall, overflow: TextOverflow.ellipsis)),
                  Text('${money(c, de: t.de)} ${billSign(context, bill)}', style: tt.bodySmall),
                ]),
          ],
          if (!ok)
            for (final i in issues) Text(i.toString(), style: tt.bodySmall!.copyWith(color: color)),
        ],
      ),
    );
  }
}

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.bill});

  final Bill bill;

  String _text(S t, String cur) {
    final b = StringBuffer('${bill.purpose.isEmpty ? t.appName : bill.purpose}: ${money(bill.effectiveTotal, de: t.de)} $cur${bill.refund ? ' (${t.refundBadge})' : ''}\n');
    final pp = bill.perPerson();
    for (var i = 0; i < bill.ps.length; i++) {
      b.writeln('${bill.ps[i].name}: ${money(pp[i] ?? 0, de: t.de)} $cur');
    }
    for (final (from, to, c) in bill.transfers()) {
      b.writeln(t.owes(bill.ps[from].name, bill.ps[to].name, '${money(c, de: t.de)} $cur'));
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final store = StoreScope.of(context);
    return CurrencyScope(code: bill.currency ?? store.homeCurrency, child: Scaffold(
      appBar: AppBar(
        title: Text(bill.purpose.isEmpty ? t.appName : bill.purpose),
        actions: [
          IconButton(
            tooltip: t.edit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(bill: bill))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'log') shareRecognitionLog(context, bill);
              if (v == 'reread') rereadFlow(context, bill);
              if (v == 'del') {
                store.remove(bill);
                Navigator.of(context).maybePop();
              }
            },
            itemBuilder: (_) => [
              if (imageExists(bill.originalPath)) PopupMenuItem(value: 'reread', child: Text(t.de ? 'Bon neu lesen' : 'Read receipt again')),
              PopupMenuItem(value: 'log', child: Text(t.shareLog)),
              PopupMenuItem(value: 'del', child: Text(t.deleteBill)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.xxxl),
        children: [
          PinnedNotes(bill: bill),
          Money(bill.effectiveTotal, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: FasanSpace.s),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [CategoryChip(bill: bill), CurrencyChip(bill: bill)]),
          ),
          if (bill.refund) ...[const SizedBox(height: FasanSpace.s), const RefundNote()],
          const SizedBox(height: FasanSpace.l),
          if (bill.payer != null) ResultBody(bill: bill) else Text(t.whoPaid),
          const SizedBox(height: FasanSpace.l),
          BillNotes(bill: bill),
          const SizedBox(height: FasanSpace.xl),
          // Nutzer 04.11.: the archive is for bills that are paid back; this is where one says so
          if (bill.done && bill.payer != null && bill.transfers().isNotEmpty) ...[
            FasanButton(
              label: bill.settled ? (t.de ? 'Wieder offen (nicht bezahlt)' : 'Open again (not paid)') : (t.de ? 'Alles bezahlt – ausgleichen' : 'All paid – settle'),
              icon: bill.settled ? Icons.undo_rounded : Icons.task_alt_rounded,
              kind: bill.settled ? FasanButtonKind.secondary : FasanButtonKind.primary,
              expand: true,
              onPressed: () {
                final settled = !bill.settled;
                store.setSettled([bill], settled);
                showNote(context, settled ? t.archivedN(1) : t.reopenedN(1));
                if (settled) Navigator.of(context).maybePop();
              },
            ),
            const SizedBox(height: FasanSpace.s),
          ],
          FasanButton(label: t.shareText, icon: Icons.ios_share_rounded, kind: FasanButtonKind.secondary, expand: true, onPressed: () => SharePlus.instance.share(ShareParams(text: _text(t, billSign(context, bill))))),
          const SizedBox(height: FasanSpace.s),
          FasanButton(
            label: t.exportCsv,
            icon: Icons.table_view_outlined,
            kind: FasanButtonKind.secondary,
            expand: true,
            onPressed: () => SharePlus.instance.share(ShareParams(files: [
              XFile.fromData(Uint8List.fromList(utf8.encode(billCsv(bill, de: t.de))), mimeType: 'text/csv', name: 'fasan-split.csv'),
            ])),
          ),
        ],
      ),
    ));
  }
}
