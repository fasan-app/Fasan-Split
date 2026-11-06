// Fasan Split – shared widgets of the flow screens. MPL-2.0


import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import 'bill_notes.dart' show PinnedNotes;
import 'package:flutter/services.dart';

import '../l10n.dart';
import 'scope.dart';
import '../model/bill.dart';
import '../state/rates.dart';
import '../recognition/reader.dart' show nameAlternatives;
import 'marquee_text.dart';
import 'receipt_view.dart';
import '../state/images.dart';

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
    this.showStep = true,
  });

  final String title;
  final int step; // 1–4 (where a draft resumes)

  /// Show „n / 4“ above the title. The bill screen is one screen (Nutzer 05.11.) and does not.
  final bool showStep;

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
    final b = bill;
    if (b == null) return _build(context);
    return CurrencyScope(code: b.currency ?? StoreScope.read(context).homeCurrency, child: Builder(builder: _build));
  }

  Widget _build(BuildContext context) {
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
    // first step of a resumed draft sits at the bottom of a nested Navigator (ResumeFlow): back then closes the bill
    final nested = (ModalRoute.of(context)?.isFirst ?? false) && Navigator.of(context, rootNavigator: true).canPop();
    // rebuild when a shared photo arrives (the receipt button and the menus depend on it)
    context.dependOnInheritedWidgetOfExactType<CollabScope>();
    final scaffold = Scaffold(
      appBar: AppBar(
        leading: nested ? BackButton(onPressed: () => Navigator.of(context, rootNavigator: true).maybePop()) : null,
        title: showStep
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FasanLabel('$step / 4'),
                Text(title),
              ])
            // shrinks instead of „Rec…“ when the title is long and the bar is full (English „Receipt“ next to five buttons, Bildschirmvergleich 06.11.)
            : FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(title)),
        toolbarHeight: showStep ? 72 : null,
        actions: [
          // the receipt view always has the digital receipt; scan and original come with the photo (Nutzer 06.11.: in the
          // browser this button was missing for bills from the group)
          if (b != null && step != 3 && (imageExists(b.imagePath) || b.its.isNotEmpty))
            IconButton(
              tooltip: t.showReceipt,
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptScreen(bill: b))),
            ),
          ...?actions,
        ],
      ),
      body: Stack(children: [
        Positioned.fill(
          child: b != null && b.notes.any((n) => n.pinned)
              // pinned notes stay visible in every step (Nutzer 04.11.: a hint for everyone on this bill)
              ? Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, 0), child: PinnedNotes(bill: b)),
                  Expanded(child: body),
                ])
              : body,
        ),
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
                          // root navigator: a resumed draft runs in a nested one (ResumeFlow)
                          final messenger = ScaffoldMessenger.of(context);
                          closeBillFlow(context);
                          messenger.showSnackBar(SnackBar(content: Text(note)));
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

/// Currency shown by [Money] and the amount texts below it: the bill's currency on bill screens (StepScaffold,
/// ResultScreen, BillTile), else the home currency.
class CurrencyScope extends InheritedWidget {
  const CurrencyScope({super.key, required this.code, required super.child});

  final String code;

  static String codeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CurrencyScope>()?.code ?? StoreScope.of(context).homeCurrency;

  @override
  bool updateShouldNotify(CurrencyScope old) => old.code != code;
}

/// Sign of the current currency (€, $, £ or the code).
String signOf(BuildContext context) => currencySign(CurrencyScope.codeOf(context));

/// Sign of a bill's currency.
String billSign(BuildContext context, Bill b) => currencySign(b.currency ?? StoreScope.read(context).homeCurrency);

class Money extends StatelessWidget {
  const Money(this.cents, {super.key, this.style, this.sign = false});

  final int cents;
  final TextStyle? style;
  final bool sign;

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de;
    final s = style ?? Theme.of(context).textTheme.bodyLarge!;
    return Text('${money(cents, de: de, sign: sign)} ${signOf(context)}', style: s.copyWith(fontFeatures: const [FontFeature.tabularFigures()], fontWeight: s.fontWeight ?? FontWeight.w600));
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
        // reading confidence and other readings: errors are caught here, before they do harm (Nutzer 02.11.)
        Builder(builder: (context) {
          final pct = it.certainty ?? (it.sure ? null : 50);
          final alts = nameAlternatives(it.name);
          if (pct == null && alts.isEmpty) return const SizedBox.shrink();
          final l = FasanLook.of(context);
          final unsure = !it.sure || (pct != null && pct < 70);
          return Padding(
            padding: const EdgeInsets.only(top: FasanSpace.s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (pct != null)
                Row(children: [
                  Icon(unsure ? Icons.help_outline : Icons.check_circle_outline, size: 16, color: unsure ? Theme.of(context).colorScheme.error : l.textMuted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(unsure ? '${t.confidence(pct)} · ${t.checkThis}' : t.confidence(pct), style: Theme.of(context).textTheme.bodySmall)),
                ]),
              if (alts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(t.otherNames, style: Theme.of(context).textTheme.bodySmall),
                    for (final a in alts) ActionChip(label: Text(a), onPressed: () => name.text = a),
                  ]),
                ),
            ]),
          );
        }),
        const SizedBox(height: FasanSpace.s),
        Row(children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: amount,
              decoration: InputDecoration(labelText: t.amount, suffixText: signOf(context)),
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
        // side by side when they fit, else stacked (monkey test 06.11.: German on a small phone overflowed by 40 px)
        OverflowBar(alignment: MainAxisAlignment.spaceBetween, overflowAlignment: OverflowBarAlignment.end, spacing: FasanSpace.s, overflowSpacing: FasanSpace.s, children: [
          if (onDelete != null)
            FasanButton(label: t.delete, kind: FasanButtonKind.quiet, icon: Icons.delete_outline, onPressed: () {
              onDelete();
              Navigator.pop(context, true);
            }),
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
    // one line: a long name fades out and scrolls slowly sideways (marquee_text.dart) instead of being cut off with „…“
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      maxLines == 1
          ? MarqueeText(item.title, style: style ?? tt.bodyLarge)
          : Text(item.title, style: style ?? tt.bodyLarge, maxLines: maxLines, overflow: TextOverflow.ellipsis),
      if (sub != null) MarqueeText(sub, style: tt.bodySmall!.copyWith(color: FasanLook.of(context).textMuted)),
    ]);
  }
}


/// Title with a small „?“ that opens the explanation (Nutzer 04.11.: hint texts behind a question mark, as usual in
/// apps; Apple HIG keeps only short footers in lists and puts longer help behind an info button). Values that change
/// (a name, a version) stay visible as subtitle; only explanations move here.
class TitleHelp extends StatelessWidget {
  const TitleHelp(this.title, this.help, {super.key});

  final String title, help;

  @override
  Widget build(BuildContext context) => Row(children: [
        Flexible(child: Text(title)),
        IconButton(
          tooltip: S.of(context).de ? 'Erklärung' : 'Explanation',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.help_outline_rounded, size: 18, color: FasanLook.of(context).textMuted),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, FasanSpace.l),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: FasanSpace.s),
                  Text(help, style: Theme.of(ctx).textTheme.bodyMedium),
                ]),
              ),
            ),
          ),
        ),
      ]);
}


/// The page a bill was opened from (overview, a group, a chat). Closing the bill returns there – before 04.11. it always
/// went back to the start and left the group (Nutzer: „ergibt überhaupt keinen Sinn“).
Route<dynamic>? billOrigin;

/// Call where a bill is opened or a new one is started.
void markBillOrigin(BuildContext context) => billOrigin = ModalRoute.of(context);

/// True for the route a closed bill returns to.
/// The photo of a shared bill is on its way from the group (collab/photo_sync.dart); false without a group or CollabScope.
bool photoComing(BuildContext context, Bill b) => context.getInheritedWidgetOfExactType<CollabScope>()?.notifier?.photoComing(b) ?? false;

bool isBillOrigin(Route<dynamic> r) => r.isFirst || (billOrigin != null && identical(r, billOrigin) && billOrigin!.isActive);

/// Leaves the bill flow (all its steps, a nested ResumeFlow too) back to where it was opened.
void closeBillFlow(BuildContext context) => Navigator.of(context, rootNavigator: true).popUntil(isBillOrigin);
