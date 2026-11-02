// Fasan Split – shared widgets of the flow screens. MPL-2.0

import 'dart:io';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../main.dart';
import '../model/bill.dart';
import 'receipt_view.dart';

/// Screen of the bill flow: title, step, content; the main action sits in a glass bar in the thumb zone
/// (Bergstrom-Lehtovirta & Oulasvirta 2014, GRUNDSAETZE.md).
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.title,
    required this.step,
    required this.body,
    this.bill,
    this.action,
    this.onAction,
    this.secondary,
    this.actions,
    this.bottomExtra,
  });

  final String title;
  final int step; // 1–4

  /// The bill being edited: saved after every rebuild (= every change) and via „Speichern und schließen“.
  final Bill? bill;
  final Widget body;
  final String? action;
  final VoidCallback? onAction;
  final Widget? secondary;
  final List<Widget>? actions;
  final Widget? bottomExtra;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final b = bill;
    if (b != null) {
      final store = StoreScope.read(context);
      // every setState of a flow screen rebuilds this scaffold: save then (debounced in the store)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!b.done) b.step = step;
        store.touch(b);
      });
    }
    final t = S.of(context);
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FasanLabel('$step / 4'),
          Text(title),
        ]),
        toolbarHeight: 72,
        actions: [
          if (b != null && step != 3 && b.imagePath != null && File(b.imagePath!).existsSync())
            IconButton(
              tooltip: t.showReceipt,
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptScreen(bill: b))),
            ),
          ...?actions,
        ],
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
                ?bottomExtra,
                if (action != null)
                  Row(children: [
                    if (secondary != null) ...[secondary!, const SizedBox(width: 6)],
                    // Karte 3.13: großer Speichern-Knopf in jedem Schritt, in der Daumenzone neben der Hauptaktion
                    if (secondary == null && b != null) ...[
                      FasanButton(
                        label: t.saveClose,
                        icon: Icons.check_rounded,
                        kind: FasanButtonKind.secondary,
                        onPressed: () {
                          if (!b.done) b.step = step;
                          StoreScope.read(context).upsert(b);
                          FasanHaptics.of(context).confirm();
                          final note = b.done ? t.saved : t.savedDraft;
                          Navigator.of(context).popUntil((r) => r.isFirst);
                          showNote(context, note);
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(child: FasanButton(label: action!, onPressed: onAction, expand: true)),
                  ]),
              ]),
            ),
          ),
      ]),
    );
    if (b == null) return scaffold;
    // leaving a step (back gesture, arrow) saves and lets the start page update its lists
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) StoreScope.read(context).upsert(b);
      },
      child: scaffold,
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

/// Message above the bottom bar, never over the main action (0.1.2 snack bars covered „Weiter“).
void showNote(BuildContext context, String text, {String? actionLabel, VoidCallback? onAction, Duration duration = const Duration(seconds: 4)}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(FasanSpace.m, 0, FasanSpace.m, bottomBarSpace(context) + FasanSpace.s),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ));
}

/// Item name: plain German name with symbol (or cleaned receipt name), receipt name small below (Karte 3.8).
class ItemTitle extends StatelessWidget {
  const ItemTitle(this.item, {super.key, this.style, this.maxLines = 2});

  final BillItem item;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final sub = item.subtitle;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(item.title, style: style ?? tt.bodyLarge, maxLines: maxLines, overflow: TextOverflow.ellipsis),
      if (sub != null) Text(sub, style: tt.bodySmall!.copyWith(color: FasanLook.of(context).textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]);
  }
}
