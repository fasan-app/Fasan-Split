// SPDX-License-Identifier: MPL-2.0
// Fasan Split – dialogs for payments between people: interim payment and „paid“ (moved out of groups.dart, Umbau 14.11.). MPL-2.0
import '../l10n/tr.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import '../l10n.dart';
import 'scope.dart';
import 'package:fasan_core/bill.dart';
import 'common.dart';
/// The payment flows are used inside the people sheet of the group: after booking, the sheet closes so the note with „Rückgängig“
/// below it can be tapped (a modal sheet would cover it).
void _closeSheet(BuildContext context) {
  if (context.mounted && ModalRoute.of(context) is PopupRoute) Navigator.of(context).pop();
}

/// Interim payment or lent money: asks who gave whom how much and books it like a settlement payment (store.recordPayment).
Future<void> giveFlow(BuildContext context, String group, List<String> people) async {
  final lang = S.of(context).de ? 'de' : 'en';
  final r = await showDialog<({bool loan, String from, String to, int cents, String subject})>(context: context, builder: (_) => _GiveDialog(lang: lang, people: people));
  if (r == null || !context.mounted) return;
  final store = StoreScope.read(context);
  final shown = '${money(r.cents, de: lang == 'de')} ${signOf(context)}';
  final b = store.recordPayment(group, r.from, r.to, r.cents,
      purpose: r.subject.isNotEmpty ? r.subject : trLang(lang, r.loan ? 'groups.loanPurpose' : 'groups.paymentPurpose', [r.from, r.to]), item: trLang(lang, r.loan ? 'groups.loanItem' : 'groups.paymentItem'));
  showNote(context, trLang(lang, r.loan ? 'groups.loanDone' : 'groups.markPaidDone', [r.from, r.to, shown]), actionLabel: context.tr('bill.undo'), onAction: () => store.remove(b));
  _closeSheet(context);
}

class _GiveDialog extends StatefulWidget {
  const _GiveDialog({required this.lang, required this.people});

  final String lang;
  final List<String> people;

  @override
  State<_GiveDialog> createState() => _GiveDialogState();
}

class _GiveDialogState extends State<_GiveDialog> {
  final _field = TextEditingController();
  final _subject = TextEditingController();
  bool _loan = false;
  String? _from, _to;

  @override
  void dispose() {
    _field.dispose();
    _subject.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), lang = widget.lang;
    final v = parseMoney(_field.text);
    final valid = _from != null && _to != null && _from != _to && v != null && v > 0;
    DropdownButtonFormField<String> pick(String label, String? value, ValueChanged<String?> on) => DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [for (final p in widget.people) DropdownMenuItem(value: p, child: Text(p))],
          onChanged: on,
        );
    return AlertDialog(
      title: Text(trLang(lang, 'groups.give')),
      // fixed width: the dropdowns cannot give intrinsic sizes, which AlertDialog asks for
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(trLang(lang, 'groups.giveHint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: FasanSpace.m),
          FasanSegmented<bool>(values: const [false, true], selected: _loan, label: (x) => trLang(lang, x ? 'groups.giveLoan' : 'groups.givePay'), onChanged: (x) => setState(() => _loan = x)),
          const SizedBox(height: FasanSpace.m),
          pick(trLang(lang, 'groups.giveFrom'), _from, (x) => setState(() => _from = x)),
          const SizedBox(height: FasanSpace.s),
          pick(trLang(lang, 'groups.giveTo'), _to, (x) => setState(() => _to = x)),
          const SizedBox(height: FasanSpace.s),
          TextField(
            controller: _field,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: trLang(lang, 'groups.markPaidAmount'), suffixText: signOf(context)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: FasanSpace.s),
          TextField(
            key: const ValueKey('give-subject'),
            controller: _subject,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: trLang(lang, 'groups.giveSubject')),
          ),
        ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: valid ? () => Navigator.pop(context, (loan: _loan, from: _from!, to: _to!, cents: v, subject: _subject.text.trim())) : null, child: Text(t.ok)),
      ],
    );
  }
}

/// Asks, then books „[from] gave [to] [cents]“ in the group [group] of the surrounding page (store.recordPayment), with undo.
Future<void> markPaidIn(BuildContext context, String group, String from, String to, int cents) async {
  final t = S.of(context);
  final lang = t.de ? 'de' : 'en';
  final amount = '${money(cents, de: t.de)} ${signOf(context)}';
  // the amount can be changed: a part paid now, the rest later (only between 0 and the open amount)
  final paid = await showDialog<int>(context: context, builder: (_) => _PaidDialog(lang: lang, de: t.de, cents: cents, ask: trLang(lang, 'groups.markPaidAsk', [from, to, amount]), amount: amount));
  if (paid == null || !context.mounted) return;
  final store = StoreScope.read(context);
  final shown = '${money(paid, de: t.de)} ${signOf(context)}';
  final b = store.recordPayment(group, from, to, paid, purpose: trLang(lang, 'groups.paymentPurpose', [from, to]), item: trLang(lang, 'groups.paymentItem'));
  showNote(context, trLang(lang, 'groups.markPaidDone', [from, to, shown]), actionLabel: context.tr('bill.undo'), onAction: () => store.remove(b));
  _closeSheet(context);
}

/// Amount for „paid“: the open amount, editable down to a part. Owns its text controller and frees it with the dialog (06.11.: before,
/// a controller made outside the dialog could only be left to the garbage collector, because the dialog still builds while it fades out).
class _PaidDialog extends StatefulWidget {
  const _PaidDialog({required this.lang, required this.de, required this.cents, required this.ask, required this.amount});

  final String lang, ask, amount;
  final bool de;
  final int cents;

  @override
  State<_PaidDialog> createState() => _PaidDialogState();
}

class _PaidDialogState extends State<_PaidDialog> {
  late final _field = TextEditingController(text: money(widget.cents, de: widget.de));

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final v = parseMoney(_field.text);
    final valid = v != null && v > 0 && v <= widget.cents;
    return AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.ask),
        const SizedBox(height: FasanSpace.m),
        TextField(
          controller: _field,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: trLang(widget.lang, 'groups.markPaidAmount'),
            suffixText: signOf(context),
            errorText: _field.text.isEmpty || valid ? null : trLang(widget.lang, 'groups.markPaidTooMuch', [widget.amount]),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: valid ? () => Navigator.pop(context, v) : null, child: Text(trLang(widget.lang, 'groups.markPaid'))),
      ],
    );
  }
}
