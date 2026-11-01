// Fasan Split – shared widgets of the flow screens. MPL-2.0

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../model/bill.dart';

/// Screen of the bill flow: title, step, content; the main action sits in a glass bar in the thumb zone
/// (Bergstrom-Lehtovirta & Oulasvirta 2014, GRUNDSAETZE.md).
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.title,
    required this.step,
    required this.body,
    this.action,
    this.onAction,
    this.secondary,
    this.actions,
    this.bottomExtra,
  });

  final String title;
  final int step; // 1–4
  final Widget body;
  final String? action;
  final VoidCallback? onAction;
  final Widget? secondary;
  final List<Widget>? actions;
  final Widget? bottomExtra;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FasanLabel('$step / 4'),
          Text(title),
        ]),
        toolbarHeight: 72,
        actions: actions,
      ),
      body: Stack(children: [
        Positioned.fill(child: body),
        if (action != null || bottomExtra != null)
          Positioned(
            left: FasanSpace.m,
            right: FasanSpace.m,
            bottom: FasanSpace.m + bottom,
            child: FasanGlass(
              padding: const EdgeInsets.all(6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (bottomExtra != null) bottomExtra!,
                if (action != null)
                  Row(children: [
                    if (secondary != null) ...[secondary!, const SizedBox(width: 6)],
                    Expanded(child: FasanButton(label: action!, onPressed: onAction, expand: true)),
                  ]),
              ]),
            ),
          ),
      ]),
      backgroundColor: l.background,
    );
  }
}

/// Space at the end of scrolling content so the glass bar does not cover the last row.
double bottomBarSpace(BuildContext context, {bool extra = false}) => (extra ? 150 : 96) + MediaQuery.paddingOf(context).bottom;

/// The receipt line of an item as a picture (Wiedererkennen statt Erinnern).
class Snippet extends StatelessWidget {
  const Snippet(this.bytes, {super.key, this.height = 28});

  final Uint8List? bytes;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    if (bytes == null) return SizedBox(height: height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ColoredBox(
        color: Colors.white,
        child: Image.memory(bytes!, height: height, fit: BoxFit.contain, alignment: Alignment.centerLeft, gaplessPlayback: true, filterQuality: FilterQuality.medium,
            color: l.brightness == Brightness.dark ? const Color(0xFFE8E8E8) : null, colorBlendMode: l.brightness == Brightness.dark ? BlendMode.modulate : null),
      ),
    );
  }
}

class Money extends StatelessWidget {
  const Money(this.cents, {super.key, this.style, this.sign = false});

  final int cents;
  final TextStyle? style;
  final bool sign;

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de;
    final s = style ?? Theme.of(context).textTheme.bodyLarge!;
    return Text('${money(cents, de: de, sign: sign)} €', style: s.copyWith(fontFeatures: const [FontFeature.tabularFigures()], fontWeight: s.fontWeight ?? FontWeight.w600));
  }
}

/// Avatars of the people sharing an item (never colour stripes, Plan „Rechnung“).
class ShareAvatars extends StatelessWidget {
  const ShareAvatars({super.key, required this.bill, required this.item, this.size = 24});

  final Bill bill;
  final BillItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final people = [
      for (final e in item.shares.entries)
        if (e.value > 0 && e.key < bill.ps.length) (bill.ps[e.key].name, bill.ps[e.key].color)
    ];
    if (people.isEmpty) {
      return Icon(Icons.person_add_alt_1_outlined, size: size * 0.9, color: FasanLook.of(context).textMuted);
    }
    return FasanAvatarStack(people: people, size: size);
  }
}

/// Edit name, amount, quantity of an item; delete. Returns true if changed.
Future<bool> editItem(BuildContext context, BillItem it, {VoidCallback? onDelete}) async {
  final t = S.of(context);
  final name = TextEditingController(text: it.name);
  final amount = TextEditingController(text: money(it.amount, de: t.de));
  final qty = TextEditingController(text: '${it.qty}');
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, MediaQuery.viewInsetsOf(context).bottom + FasanSpace.l),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (it.snippet case final s?) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.m), child: Snippet(s, height: 40)),
        TextField(controller: name, decoration: InputDecoration(labelText: t.name), textInputAction: TextInputAction.next),
        const SizedBox(height: FasanSpace.s),
        Row(children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: amount,
              decoration: InputDecoration(labelText: t.amount, suffixText: '€'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-−0-9.,]'))],
            ),
          ),
          const SizedBox(width: FasanSpace.s),
          Expanded(child: TextField(controller: qty, decoration: InputDecoration(labelText: t.quantity), keyboardType: TextInputType.number)),
        ]),
        if (it.suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: FasanSpace.s),
            child: Wrap(spacing: 6, children: [
              Text(t.suggestions(''), style: Theme.of(context).textTheme.bodySmall),
              for (final s in it.suggestions)
                ActionChip(label: Text(money(s, de: t.de)), onPressed: () => amount.text = money(s, de: t.de)),
            ]),
          ),
        const SizedBox(height: FasanSpace.l),
        Row(children: [
          if (onDelete != null)
            FasanButton(label: t.delete, kind: FasanButtonKind.quiet, icon: Icons.delete_outline, onPressed: () {
              onDelete();
              Navigator.pop(context, true);
            }),
          const Spacer(),
          FasanButton(label: t.save, onPressed: () => Navigator.pop(context, true)),
        ]),
      ]),
    ),
  );
  if (ok != true) return false;
  it.name = name.text.trim().isEmpty ? it.name : name.text.trim();
  final a = parseMoney(amount.text);
  if (a != null) it.amount = a;
  final q = int.tryParse(qty.text.trim());
  if (q != null && q >= 1) it.qty = q;
  it.sure = true;
  return true;
}
