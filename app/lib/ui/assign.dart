// Fasan Split – step 3: assign items to people, in four switchable variants to compare (Plan „Rechnung“, Punkt 4):
// Fokus (one line large), Liste mit Zeilenbild, Bon (zoomed so every line is ≥ 48 dp), Karten (swipe).
// A multi-line item is one continuous shape; shared items show avatars, never colour stripes. MPL-2.0
import 'dart:io';
import 'dart:math' as math;

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../model/bill.dart';
import 'common.dart';
import 'flow.dart';

enum AssignMode { focus, list, receipt, cards }

class AssignScreen extends StatefulWidget {
  const AssignScreen({super.key, required this.bill, this.initialMode});

  final Bill bill;
  final AssignMode? initialMode;

  /// Last chosen variant (kept while the app runs).
  static AssignMode lastMode = AssignMode.focus;

  @override
  State<AssignScreen> createState() => _AssignScreenState();
}

class _AssignScreenState extends State<AssignScreen> {
  late AssignMode mode = widget.initialMode ?? AssignScreen.lastMode;
  Bill get b => widget.bill;

  void _changed() => setState(() {});

  /// Bulk action with a visible label and undo (0.1.2 had an unlabelled icon that silently overwrote everything).
  void _evenly() {
    final before = [for (final it in b.its) Map<int, double>.of(it.shares)];
    for (final it in b.its) {
      it.shares = {for (var i = 0; i < b.ps.length; i++) i: 1};
    }
    FasanHaptics.of(context).confirm();
    setState(() {});
    final t = S.of(context);
    showNote(context, t.splitEvenlyDone, actionLabel: t.undo, duration: const Duration(seconds: 6), onAction: () {
      if (!mounted) return;
      setState(() {
        for (var k = 0; k < b.its.length && k < before.length; k++) {
          b.its[k].shares = before[k];
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final hasImage = b.imagePath != null && File(b.imagePath!).existsSync();
    final modes = [AssignMode.focus, AssignMode.list, if (hasImage) AssignMode.receipt, AssignMode.cards];
    if (!modes.contains(mode)) mode = AssignMode.focus;
    final open = b.unassigned;
    final body = switch (mode) {
      AssignMode.focus => FocusAssign(bill: b, onChanged: _changed),
      AssignMode.list => ListAssign(bill: b, onChanged: _changed),
      AssignMode.receipt => ReceiptAssign(bill: b, onChanged: _changed),
      AssignMode.cards => CardsAssign(bill: b, onChanged: _changed),
    };
    return StepScaffold(
      title: t.assign,
      step: 3,
      bill: b,
      action: open == 0 ? t.next : t.open(open),
      onAction: () {
        StoreScope.read(context).upsert(b);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayScreen(bill: b)));
      },
      actions: [
        PopupMenuButton<int>(
          tooltip: t.more,
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (_) => _evenly(),
          itemBuilder: (_) => [PopupMenuItem(value: 0, child: ListTile(leading: const Icon(Icons.groups_2_outlined), title: Text(t.splitEvenly)))],
        ),
      ],
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s),
          child: FasanSegmented<AssignMode>(
            values: modes,
            selected: mode,
            label: (m) => switch (m) { AssignMode.focus => t.focus, AssignMode.list => t.list, AssignMode.receipt => t.receipt, AssignMode.cards => t.cards },
            onChanged: (m) => setState(() => mode = AssignScreen.lastMode = m),
          ),
        ),
        Expanded(child: AnimatedSwitcher(duration: FasanMotion.of(context).medium, child: KeyedSubtree(key: ValueKey(mode), child: body))),
      ]),
    );
  }
}

/// Person chips for one item; "Alle" toggles everyone. With quantity > 1: pieces per person.
class PeoplePicker extends StatelessWidget {
  const PeoplePicker({super.key, required this.bill, required this.item, required this.onChanged, this.onAll});

  final Bill bill;
  final BillItem item;
  final VoidCallback onChanged;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final all = bill.ps.isNotEmpty && List.generate(bill.ps.length, (i) => (item.shares[i] ?? 0) > 0).every((x) => x);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < bill.ps.length; i++)
          FasanPersonChip(
            name: bill.ps[i].name,
            index: bill.ps[i].color,
            selected: (item.shares[i] ?? 0) > 0,
            onTap: () {
              if ((item.shares[i] ?? 0) > 0) {
                item.shares.remove(i);
              } else {
                item.shares[i] = 1;
              }
              onChanged();
            },
          ),
        ChoiceChip(
          label: Text(t.everyone),
          selected: all,
          onSelected: (_) {
            item.shares = all ? {} : {for (var i = 0; i < bill.ps.length; i++) i: 1};
            FasanHaptics.of(context).tap();
            onChanged();
            if (!all) onAll?.call();
          },
        ),
      ]),
      if (item.qty > 1 && item.shares.values.any((w) => w > 0)) ...[
        const SizedBox(height: FasanSpace.m),
        FasanLabel(t.pieces),
        for (final e in item.shares.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          if (e.key < bill.ps.length)
            Row(children: [
              Expanded(child: Text(bill.ps[e.key].name)),
              IconButton(
                tooltip: '−',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: e.value <= 1
                    ? null
                    : () {
                        item.shares[e.key] = e.value - 1;
                        onChanged();
                      },
              ),
              SizedBox(width: 28, child: Text(_n(e.value), textAlign: TextAlign.center)),
              IconButton(
                tooltip: '+',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  item.shares[e.key] = e.value + 1;
                  onChanged();
                },
              ),
            ]),
      ],
    ]);
  }

  static String _n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
}

// ---------------------------------------------------------------------------------------------------------------------
// Fokus: one line large, tap people, the next line slides in

class FocusAssign extends StatefulWidget {
  const FocusAssign({super.key, required this.bill, required this.onChanged});

  final Bill bill;
  final VoidCallback onChanged;

  @override
  State<FocusAssign> createState() => _FocusAssignState();
}

class _FocusAssignState extends State<FocusAssign> {
  int i = 0;
  int dir = 1;

  @override
  void initState() {
    super.initState();
    final first = widget.bill.its.indexWhere((p) => !p.assigned);
    i = first < 0 ? 0 : first;
  }

  void _go(int d) {
    final n = widget.bill.its.length;
    if (n == 0) return;
    setState(() {
      dir = d;
      i = (i + d).clamp(0, n - 1);
    });
    FasanHaptics.of(context).tap();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final t = S.of(context);
    final l = FasanLook.of(context);
    final m = FasanMotion.of(context);
    if (b.its.isEmpty) return const SizedBox();
    final it = b.its[i];
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      // gesture twin: buttons "Zurück"/"Weiter" below
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) _go(1);
        if (v > 200) _go(-1);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, bottomBarSpace(context)),
        children: [
          FasanLabel('${i + 1} / ${b.its.length}'),
          const SizedBox(height: FasanSpace.s),
          AnimatedSwitcher(
            duration: m.medium,
            switchInCurve: FasanCurves.medium,
            transitionBuilder: (child, a) => SlideTransition(
              position: Tween(begin: Offset(0.25 * dir, 0), end: Offset.zero).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: Container(
              key: ValueKey(i),
              padding: const EdgeInsets.all(FasanSpace.l),
              decoration: BoxDecoration(color: l.surface, borderRadius: BorderRadius.circular(l.radius), border: Border.all(color: l.hairline)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (it.snippet != null) Snippet(it.snippet, height: 52),
                const SizedBox(height: FasanSpace.m),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(it.qty > 1 ? '${it.qty} × ${it.name}' : it.name, style: tt.headlineSmall)),
                  Money(it.amount, style: tt.headlineSmall),
                ]),
                if (it.note != null) Text(it.note!, style: tt.bodySmall),
                const SizedBox(height: FasanSpace.l),
                Text(t.whoHad, style: tt.labelMedium),
                const SizedBox(height: FasanSpace.s),
                PeoplePicker(bill: b, item: it, onChanged: () {
                  widget.onChanged();
                  setState(() {});
                }, onAll: () => Future.delayed(m.short, () => mounted ? _go(1) : null)),
              ]),
            ),
          ),
          const SizedBox(height: FasanSpace.l),
          Row(children: [
            Expanded(child: FasanButton(label: t.back, icon: Icons.chevron_left, kind: FasanButtonKind.secondary, expand: true, onPressed: i > 0 ? () => _go(-1) : null)),
            const SizedBox(width: FasanSpace.s),
            Expanded(child: FasanButton(label: t.next, icon: Icons.chevron_right, kind: FasanButtonKind.secondary, expand: true, onPressed: i < b.its.length - 1 ? () => _go(1) : null)),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Liste mit Zeilenbild

class ListAssign extends StatelessWidget {
  const ListAssign({super.key, required this.bill, required this.onChanged});

  final Bill bill;
  final VoidCallback onChanged;

  Future<void> _pick(BuildContext context, BillItem it) => showModalBottomSheet<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, set) => Padding(
            padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.xl),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (it.snippet != null) Snippet(it.snippet, height: 40),
              const SizedBox(height: FasanSpace.s),
              Row(children: [Expanded(child: Text(it.name, style: Theme.of(context).textTheme.titleMedium)), Money(it.amount)]),
              const SizedBox(height: FasanSpace.l),
              PeoplePicker(bill: bill, item: it, onChanged: () {
                onChanged();
                set(() {});
              }),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context)),
      itemCount: bill.its.length,
      itemBuilder: (context, i) {
        final it = bill.its[i];
        return InkWell(
          onTap: () => _pick(context, it),
          child: Container(
            constraints: BoxConstraints(minHeight: l.minTap + 8),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: l.hairline))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (it.snippet != null) Snippet(it.snippet, height: 26) else Text(it.name, style: tt.bodyLarge),
                  if (it.snippet != null) Text(it.qty > 1 ? '${it.qty} × ${it.name}' : it.name, style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: FasanSpace.s),
              ShareAvatars(bill: bill, item: it),
              const SizedBox(width: FasanSpace.m),
              Money(it.amount),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Bon direkt: zoomed so that every item line is at least 48 dp high; tap the continuous item shape

class ReceiptAssign extends StatefulWidget {
  const ReceiptAssign({super.key, required this.bill, required this.onChanged});

  final Bill bill;
  final VoidCallback onChanged;

  @override
  State<ReceiptAssign> createState() => _ReceiptAssignState();
}

/// Zoom of the receipt view (Plan: „Bon direkt, automatisch gezoomt, sodass jede Zeile mindestens 48 dp hoch ist“).
abstract final class ReceiptAssignZoom {
  /// Display width so that every item line box is ≥ [minLine] dp high: box_dp = h_norm × width / aspect.
  /// Boxes under half the median height are treated as detection noise and do not drive the zoom.
  static double width(Bill b, double screenW, double minLine) {
    final hs = [for (final it in b.its) for (final x in it.boxes) x.y1 - x.y0]..sort();
    if (hs.isEmpty) return screenW;
    final h = math.max(hs.first, 0.5 * hs[hs.length >> 1]), aspect = b.imageAspect ?? 0.4;
    return math.max(screenW, minLine * aspect / math.max(h, 0.002));
  }
}

class _ReceiptAssignState extends State<ReceiptAssign> {
  int? sel;
  final _tc = TransformationController();
  bool _placed = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final l = FasanLook.of(context);
    final t = S.of(context);
    return LayoutBuilder(builder: (context, c) {
      final W = ReceiptAssignZoom.width(b, c.maxWidth, l.minTap);
      final H = W / (b.imageAspect ?? 0.4);
      if (!_placed && b.its.isNotEmpty && b.its.first.boxes.isNotEmpty) {
        // start at the first item, left edge
        final y0 = b.its.first.boxes.first.y0 * H - 24;
        final x0 = math.max(0.0, b.its.first.boxes.first.x0 * W - 12);
        _tc.value = Matrix4.translationValues(-x0, -math.max(0.0, y0), 0);
        _placed = true;
      }
      final it = sel == null ? null : b.its[sel!];
      return Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _tc,
            constrained: false,
            minScale: math.min(1.0, c.maxWidth / W),
            maxScale: 3,
            boundaryMargin: EdgeInsets.only(bottom: bottomBarSpace(context, extra: true)),
            child: SizedBox(
              width: W,
              height: H,
              child: Stack(children: [
                Positioned.fill(child: Image.file(File(b.imagePath!), fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
                for (var k = 0; k < b.its.length; k++)
                  if (b.its[k].boxes.isNotEmpty) _ItemShape(bill: b, index: k, size: Size(W, H), selected: sel == k, onTap: () => setState(() => sel = sel == k ? null : k)),
              ]),
            ),
          ),
        ),
        Positioned(
          left: FasanSpace.m,
          right: FasanSpace.m,
          bottom: 84 + MediaQuery.paddingOf(context).bottom,
          child: FasanGlass(
            child: it == null
                ? Text(t.tapItem, style: Theme.of(context).textTheme.bodyMedium)
                : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [Expanded(child: Text(it.name, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)), Money(it.amount)]),
                    const SizedBox(height: FasanSpace.s),
                    PeoplePicker(bill: b, item: it, onChanged: () {
                      widget.onChanged();
                      setState(() {});
                    }),
                  ]),
          ),
        ),
      ]);
    });
  }
}

/// One item drawn as a continuous shape over all its lines (gaps between its lines are filled).
class _ItemShape extends StatelessWidget {
  const _ItemShape({required this.bill, required this.index, required this.size, required this.selected, required this.onTap});

  final Bill bill;
  final int index;
  final Size size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final it = bill.its[index];
    final l = FasanLook.of(context);
    final rects = [for (final x in it.boxes) Rect.fromLTRB(x.x0 * size.width, x.y0 * size.height, x.x1 * size.width, x.y1 * size.height)]..sort((a, b) => a.top.compareTo(b.top));
    final bounds = rects.reduce((a, b) => a.expandToInclude(b));
    final color = it.assigned ? l.accent : Theme.of(context).colorScheme.error;
    return Positioned.fromRect(
      rect: bounds.inflate(4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          FasanHaptics.of(context).tap();
          onTap();
        },
        child: CustomPaint(
          painter: _ShapePainter([for (final r in rects) r.shift(-bounds.topLeft + const Offset(4, 4))], color, selected),
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(padding: const EdgeInsets.all(2), child: it.assigned ? ShareAvatars(bill: bill, item: it, size: math.min(24, bounds.height)) : const SizedBox()),
          ),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.rects, this.color, this.selected);

  final List<Rect> rects;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    // each line rect is stretched down to the next one, then all are united → one outline, no separate boxes
    var path = Path();
    for (var i = 0; i < rects.length; i++) {
      var r = rects[i];
      if (i + 1 < rects.length) r = Rect.fromLTRB(r.left, r.top, r.right, math.max(r.bottom, rects[i + 1].top + 1));
      path = Path.combine(PathOperation.union, path, Path()..addRRect(RRect.fromRectAndRadius(r.inflate(2), const Radius.circular(6))));
    }
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: selected ? 0.22 : 0.08));
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: selected ? 0.9 : 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : 1,
    );
  }

  @override
  bool shouldRepaint(_ShapePainter o) => o.selected != selected || o.color != color || o.rects != rects;
}

// ---------------------------------------------------------------------------------------------------------------------
// Karten wischen

class CardsAssign extends StatefulWidget {
  const CardsAssign({super.key, required this.bill, required this.onChanged});

  final Bill bill;
  final VoidCallback onChanged;

  @override
  State<CardsAssign> createState() => _CardsAssignState();
}

class _CardsAssignState extends State<CardsAssign> {
  late final _pc = PageController(viewportFraction: 0.88);
  int page = 0;

  void _go(int d) {
    final m = FasanMotion.of(context);
    final to = (page + d).clamp(0, widget.bill.its.length - 1);
    if (m.enabled) {
      _pc.animateToPage(to, duration: m.medium, curve: FasanCurves.medium);
    } else {
      _pc.jumpToPage(to);
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final t = S.of(context);
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    return Column(children: [
      Expanded(
        child: PageView.builder(
          controller: _pc,
          itemCount: b.its.length,
          onPageChanged: (p) {
            setState(() => page = p);
            FasanHaptics.of(context).tap();
          },
          itemBuilder: (context, i) {
            final it = b.its[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: FasanSpace.s),
              child: Container(
                padding: const EdgeInsets.all(FasanSpace.l),
                decoration: BoxDecoration(color: l.surface, borderRadius: BorderRadius.circular(l.radius), border: Border.all(color: it.assigned ? l.accent.withValues(alpha: 0.5) : l.hairline)),
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FasanLabel('${i + 1} / ${b.its.length}'),
                    const SizedBox(height: FasanSpace.s),
                    if (it.snippet != null) Snippet(it.snippet, height: 44),
                    const SizedBox(height: FasanSpace.m),
                    Text(it.qty > 1 ? '${it.qty} × ${it.name}' : it.name, style: tt.titleLarge),
                    Money(it.amount, style: tt.titleLarge),
                    const SizedBox(height: FasanSpace.l),
                    PeoplePicker(bill: b, item: it, onChanged: () {
                      widget.onChanged();
                      setState(() {});
                    }, onAll: () => Future.delayed(FasanMotion.of(context).short, () => mounted ? _go(1) : null)),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      Padding(
        // full bar height plus a gap: with -24 the row slid under the bar (0.1.2)
        padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, bottomBarSpace(context) + FasanSpace.s),
        child: Row(children: [
          Expanded(child: FasanButton(label: t.back, icon: Icons.chevron_left, kind: FasanButtonKind.secondary, expand: true, onPressed: page > 0 ? () => _go(-1) : null)),
          const SizedBox(width: FasanSpace.s),
          Expanded(child: FasanButton(label: t.next, icon: Icons.chevron_right, kind: FasanButtonKind.secondary, expand: true, onPressed: page < b.its.length - 1 ? () => _go(1) : null)),
        ]),
      ),
    ]);
  }
}
