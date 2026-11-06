// Fasan Split – the receipt as the work surface (REGELWERK-OBERFLAECHE §3/§4, Karte 3.8–3.19, Nutzer 02.11.). MPL-2.0
//
// - Always the whole receipt, fitted to the width; header and footer only paler (Regel 3.1).
// - Person bar on top with running sums: choose a person, then tap lines (Regel 4.1/4.3). Without a person a tap opens
//   the correction bar (line picture, name, people, edit) (Regel 3.6).
// - A tap next to a box snaps to the nearest line (Regel 3.5). Item rows span the full text width so the quantity
//   column belongs to the row (0.1.2 cut off the leading „1“).
// - Zoom: two fingers, double tap 1× ↔ 2.5×, plus/minus buttons as visible twin, „Ganze Breite“ only when zoomed
//   (Regel 3.7).
// - Three views: Scan (cleaned, with boxes), Original (photo exactly as taken), Digital (rebuilt by the app)
//   (Beschluss 02.11.).
import 'dart:math' as math;

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../l10n/tr.dart';
import '../main.dart';
import '../model/bill.dart';
import 'assign.dart' show PeoplePicker, addPersonDialog, personMenu;
import 'common.dart';
import '../state/images.dart';

enum ReceiptLayer { scan, original, digital }

class ReceiptAssign extends StatefulWidget {
  const ReceiptAssign({super.key, required this.bill, required this.onChanged, this.readOnly = false, this.initialLayer = ReceiptLayer.scan});

  final ReceiptLayer initialLayer;

  final Bill bill;
  final VoidCallback onChanged;

  /// Viewing only (opened from other steps): no person bar, taps only select.
  final bool readOnly;

  @override
  State<ReceiptAssign> createState() => _ReceiptAssignState();
}

class _ReceiptAssignState extends State<ReceiptAssign> {
  final _tc = TransformationController();
  int? person; // chosen person (person-first mode)
  int? sel; // selected item (correction bar)
  late ReceiptLayer layer = widget.initialLayer != ReceiptLayer.scan
      ? widget.initialLayer
      : (StoreScope.read(context).receiptLayer == 'original' && b.originalPath != null ? ReceiptLayer.original : ReceiptLayer.scan);
  (DateTime, Offset, int?)? _lastTap;

  // swiping between the views (Nutzer 02.11.): direction of the last change and the drag measured inside the viewer
  bool _back = false;
  double _dx = 0, _dy = 0;
  bool _multi = false;

  List<ReceiptLayer> _layers(bool hasScan, bool hasOriginal) => [if (hasScan) ReceiptLayer.scan, if (hasOriginal) ReceiptLayer.original, ReceiptLayer.digital];

  /// Goes to the next (+1) or previous (-1) view; no-op at the ends.
  void _swipeLayer(int dir) {
    final b = this.b;
    final list = _layers(imageExists(b.imagePath), imageExists(b.originalPath));
    final i = list.indexOf(layer) + dir;
    if (i < 0 || i >= list.length) return;
    FasanHaptics.of(context).tap();
    setState(() {
      _back = dir < 0;
      layer = list[i];
      _tc.value = Matrix4.identity();
    });
  }

  void _dragStart() {
    _dx = 0;
    _dy = 0;
    _multi = false;
  }

  void _dragUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount == 1 && (d.scale - 1).abs() < 0.02) {
      _dx += d.focalPointDelta.dx;
      _dy += d.focalPointDelta.dy;
    } else {
      _multi = true;
    }
  }

  /// A clearly horizontal one-finger drag on the unzoomed receipt changes the view.
  void _dragEnd() {
    final swipe = !_multi && _scale <= 1.01 && _dx.abs() > 80 && _dx.abs() > 2.2 * _dy.abs();
    final dir = _dx < 0 ? 1 : -1;
    _dragStart();
    setState(() {});
    if (swipe) _swipeLayer(dir);
  }

  Bill get b => widget.bill;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  void _zoom(double to, {Offset? focus, Size? viewport}) {
    final f = focus ?? (viewport == null ? Offset.zero : Offset(viewport.width / 2, viewport.height / 2));
    final s = to.clamp(1.0, 4.0);
    // keep the point under the finger in place: translate so that f maps to itself after scaling
    final m = Matrix4.identity()
      ..translateByDouble(f.dx, f.dy, 0, 1)
      ..scaleByDouble(s / _scale, s / _scale, 1, 1)
      ..translateByDouble(-f.dx, -f.dy, 0, 1);
    setState(() => _tc.value = m * _tc.value);
  }

  void _fit() => setState(() => _tc.value = Matrix4.identity());

  /// Rows of all items in normalised coordinates, widened to the full text width (quantity column included).
  List<Rect> _rows() {
    final all = [for (final it in b.its) ...it.boxes];
    if (all.isEmpty) return const [];
    final x0 = all.map((x) => x.x0).reduce(math.min), x1 = all.map((x) => x.x1).reduce(math.max);
    final rows = [
      for (final it in b.its)
        it.boxes.isEmpty
            ? Rect.zero
            : Rect.fromLTRB(x0, it.boxes.map((x) => x.y0).reduce(math.min), x1, it.boxes.map((x) => x.y1).reduce(math.max)),
    ];
    // Neighbouring rows must not overlap (price lines reach into the next item): they share the border in the middle
    // of their overlap (Nutzer 02.11.: „unschön überlappende Kästen“). Taps then hit exactly one row.
    final order = [for (var k = 0; k < rows.length; k++) if (rows[k] != Rect.zero) k]..sort((a, c) => rows[a].top.compareTo(rows[c].top));
    for (var i = 0; i + 1 < order.length; i++) {
      final a = rows[order[i]], c = rows[order[i + 1]];
      if (a.bottom > c.top) {
        final mid = (a.bottom + c.top) / 2;
        rows[order[i]] = Rect.fromLTRB(a.left, a.top, a.right, mid);
        rows[order[i + 1]] = Rect.fromLTRB(c.left, mid, c.right, c.bottom);
      }
    }
    return rows;
  }

  /// Item at a normalised point: inside a row, else the nearest row within 1.5 row heights (snapping).
  int? _hit(Offset n, List<Rect> rows) {
    int? best;
    var bestD = double.infinity;
    for (var k = 0; k < rows.length; k++) {
      final r = rows[k];
      if (r == Rect.zero) continue;
      if (r.contains(n)) return k;
      final d = n.dy < r.top ? r.top - n.dy : (n.dy > r.bottom ? n.dy - r.bottom : 0.0);
      if (d < bestD && d < 1.5 * r.height) {
        bestD = d;
        best = k;
      }
    }
    return best;
  }

  void _tapItem(int k) {
    if (k < 0 || k >= b.its.length) return; // the list changed (undo, a change from the group) between drawing and tapping
    final it = b.its[k];
    final h = FasanHaptics.of(context);
    if (person != null && !widget.readOnly) {
      final p = person!;
      setState(() {
        if ((it.shares[p] ?? 0) > 0) {
          it.shares.remove(p);
        } else {
          it.shares[p] = 1;
        }
      });
      h.tap();
      widget.onChanged();
    } else {
      h.tap();
      setState(() => sel = sel == k ? null : k);
    }
  }

  int _sumOf(int p) {
    final per = b.perPerson();
    return per[p] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    context.dependOnInheritedWidgetOfExactType<CollabScope>(); // the shared photo may arrive while the view is open
    final hasOriginal = imageExists(b.originalPath);
    final hasScan = imageExists(b.imagePath);
    // fall back to what exists (bills from 0.1 have no original; „Bonfotos löschen“ removes both)
    if (layer == ReceiptLayer.original && !hasOriginal) layer = hasScan ? ReceiptLayer.scan : ReceiptLayer.digital;
    if (layer == ReceiptLayer.scan && !hasScan) layer = hasOriginal ? ReceiptLayer.original : ReceiptLayer.digital;
    final it = sel == null || sel! >= b.its.length ? null : b.its[sel!];
    return Column(children: [
      if (!widget.readOnly) _PersonBar(bill: b, selected: person, sumOf: _sumOf, onSelect: (p) => setState(() => person = person == p ? null : p), onChanged: () => setState(() {
        if (person != null && person! >= b.ps.length) person = null;
        widget.onChanged();
      })),
      Padding(
        padding: const EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.xs, FasanSpace.l, FasanSpace.xs),
        child: Row(children: [
          // viewing only: no hint, the switch takes the row (space for the receipt, Nutzer 02.11.)
          if (!widget.readOnly) ...[
            Expanded(
              child: Text(
                person == null ? t.receiptHintPick : t.receiptHintPerson(b.ps[person!].name),
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: l.textMuted),
                maxLines: 2,
              ),
            ),
            const SizedBox(width: FasanSpace.s),
          ],
          SizedBox(
            width: widget.readOnly ? MediaQuery.sizeOf(context).width - 2 * FasanSpace.l : 210,
            child: FasanSegmented<ReceiptLayer>(
              values: [if (hasScan) ReceiptLayer.scan, if (hasOriginal) ReceiptLayer.original, ReceiptLayer.digital],
              selected: layer,
              label: (v) => switch (v) { ReceiptLayer.scan => t.layerScan, ReceiptLayer.original => t.layerOriginal, ReceiptLayer.digital => t.layerDigital },
              onChanged: (v) => setState(() {
                final order = _layers(hasScan, hasOriginal);
                _back = order.indexOf(v) < order.indexOf(layer);
                layer = v;
                _tc.value = Matrix4.identity();
                _placed = false; // the scan starts at the items again (Nutzer 04.11.)
              }),
            ),
          ),
        ]),
      ),
      // without the photo only the digital receipt exists: say why scan and original are missing (Prüfliste G1/G3)
      if (!hasScan && !hasOriginal)
        Padding(
          padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.xs),
          child: Row(children: [
            Icon(photoComing(context, b) ? Icons.downloading_rounded : Icons.phone_android_rounded, size: 16, color: l.textMuted),
            const SizedBox(width: FasanSpace.xs),
            Expanded(
              child: Text(context.tr(photoComing(context, b) ? 'bill.photoComing' : 'bill.photoHere'),
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(color: l.textMuted)),
            ),
          ]),
        ),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final view = Size(c.maxWidth, c.maxHeight);
          final content = switch (layer) {
            ReceiptLayer.scan => _scan(view),
            ReceiptLayer.original => _original(view),
            ReceiptLayer.digital => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v.abs() > 450) _swipeLayer(v < 0 ? 1 : -1);
                },
                child: DigitalReceipt(bill: b, selected: sel, onTap: _tapItem),
              ),
          };
          return Stack(children: [
            // fade through between the three views of the same receipt (fasan_ui GESTALTUNG.md §7)
            Positioned.fill(child: FasanSlideSwitch(reverse: _back, child: KeyedSubtree(key: ValueKey(layer), child: content))),
            if (layer != ReceiptLayer.digital)
              Positioned(
                right: FasanSpace.m,
                bottom: (it == null ? 0 : 170) + bottomBarSpace(context) + FasanSpace.s,
                child: _ZoomButtons(
                  zoomed: _scale > 1.01,
                  onIn: () => _zoom(_scale * 1.6, viewport: view),
                  onOut: () => _zoom(_scale / 1.6, viewport: view),
                  onFit: _fit,
                  fitLabel: t.fullWidth,
                ),
              ),
            if (it != null)
              Positioned(
                left: FasanSpace.m,
                right: FasanSpace.m,
                bottom: bottomBarSpace(context) + FasanSpace.s,
                child: _CorrectionBar(
                  bill: b,
                  item: it,
                  readOnly: widget.readOnly,
                  onChanged: () {
                    setState(() {});
                    widget.onChanged();
                  },
                  onClose: () => setState(() => sel = null),
                ),
              ),
          ]);
        }),
      ),
    ]);
  }

  bool _placed = false;
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    // decode scan and original before the first switch, so a view change never shows an empty or black frame (04.11.)
    for (final p in [b.imagePath, b.originalPath]) {
      if (imageExists(p)) precacheImage(imageProvider(p!), context);
    }
  }

  Widget _scan(Size view) {
    final aspect = b.imageAspect ?? 0.4;
    // The receipt always fills the full width (Nutzer 02.11.: „muss immer auf die volle Breite gezogen werden“). The avatars
    // sit in the paper's right margin, right of the text, so they do not cover the amounts.
    final w = view.width, h = w / aspect;
    final rows = _rows();
    final textRight = rows.where((r) => r != Rect.zero).map((r) => r.right).fold<double>(0, math.max);
    final margin = ((1 - textRight) * w - 4).clamp(14.0, 40.0).toDouble();
    // start at the items, not at the shop header (the header stays reachable by scrolling up)
    if (!_placed) {
      _placed = true;
      final first = rows.where((r) => r != Rect.zero).map((r) => r.top).fold<double?>(null, (a, y) => a == null || y < a ? y : a);
      if (first != null) {
        final y = (first * h - 48).clamp(0.0, math.max(0.0, h - view.height)).toDouble();
        _tc.value = Matrix4.translationValues(0, -y, 0);
      }
    }
    return InteractiveViewer(
      transformationController: _tc,
      constrained: false,
      minScale: 1,
      maxScale: 4,
      boundaryMargin: EdgeInsets.only(bottom: bottomBarSpace(context) + 180),
      onInteractionStart: (_) => _dragStart(),
      onInteractionUpdate: _dragUpdate,
      onInteractionEnd: (_) => _dragEnd(),
      child: GestureDetector(
        // Taps act at once (no 300 ms double-tap wait). A second tap within 300 ms at the same spot is a double tap:
        // it undoes the first tap and toggles zoom 1× ↔ 2.5× (Regel 3.7/3.8).
        onTapUp: (d) {
          final now = DateTime.now();
          final last = _lastTap;
          if (last != null && now.difference(last.$1) < const Duration(milliseconds: 300) && (d.localPosition - last.$2).distance < 40) {
            _lastTap = null;
            if (last.$3 != null) _tapItem(last.$3!); // undo
            if (_scale > 1.01) {
              _fit();
            } else {
              _zoom(2.5, focus: MatrixUtils.transformPoint(_tc.value, d.localPosition));
            }
            return;
          }
          final k = _hit(Offset(d.localPosition.dx / w, d.localPosition.dy / h), rows);
          _lastTap = (now, d.localPosition, k);
          if (k != null) _tapItem(k);
        },
        child: SizedBox(
          width: view.width,
          height: h,
          child: Stack(children: [
            Positioned(left: 0, top: 0, width: w, height: h, child: Image(image: imageProvider(b.imagePath!), fit: BoxFit.fill, filterQuality: FilterQuality.medium, gaplessPlayback: true)),
            Positioned(
              left: 0,
              top: 0,
              width: w,
              height: h,
              child: CustomPaint(
                painter: _RowsPainter(
                  rows: rows,
                  bill: b,
                  selected: sel,
                  repaint: _tc,
                  visible: () {
                    // screen rect in receipt coordinates from the zoom/pan matrix
                    final m = _tc.value, s = m.getMaxScaleOnAxis(), tr = m.getTranslation();
                    return Rect.fromLTWH(-tr.x / s, -tr.y / s, view.width / s, view.height / s);
                  },
                  look: FasanLook.of(context),
                  error: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            for (var k = 0; k < rows.length; k++)
              if (rows[k] != Rect.zero && b.its[k].assigned)
                Positioned(
                  left: w - margin - 2,
                  width: margin,
                  top: rows[k].top * h + (rows[k].height * h - 18) / 2,
                  child: IgnorePointer(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: ShareAvatars(bill: b, item: b.its[k], size: 18))),
                ),
          ]),
        ),
      ),
    );
  }

  /// Normalised scan point (u, v) → normalised photo point, bilinear between the receipt corners (quad: TL, TR, BR, BL).
  static Offset _toPhoto(List<double> q, double u, double v) {
    double mix(int k) => (1 - v) * ((1 - u) * q[k] + u * q[2 + k]) + v * ((1 - u) * q[6 + k] + u * q[4 + k]);
    return Offset(mix(0), mix(1));
  }

  /// Largest rectangle with [aspect] centred in [view] (what `BoxFit.contain` shows).
  static Rect _fitRect(double aspect, Size view) {
    var w = view.width, h = w / aspect;
    if (h > view.height) {
      h = view.height;
      w = h * aspect;
    }
    return Rect.fromCenter(center: Offset(view.width / 2, view.height / 2), width: w, height: h);
  }

  /// The item rows as polygons in view pixels (original view); empty if the corners in the photo are unknown.
  List<Path?> _originalRows(Size view) {
    final q = b.originalQuad, ar = b.originalAspect;
    if (q == null || q.length != 8 || ar == null) return const [];
    final area = _fitRect(ar, view);
    return [
      for (final r in _rows())
        if (r == Rect.zero)
          null
        else
          (Path()
            ..addPolygon([
              for (final (u, v) in [(r.left, r.top), (r.right, r.top), (r.right, r.bottom), (r.left, r.bottom)])
                () {
                  final p = _toPhoto(q, u, v);
                  return Offset(area.left + p.dx * area.width, area.top + p.dy * area.height);
                }()
            ], true)),
    ];
  }

  Widget _original(Size view) {
    final t = S.of(context);
    final polys = _originalRows(view);
    return Stack(children: [
      Positioned.fill(
        child: InteractiveViewer(
          transformationController: _tc,
          minScale: 1,
          maxScale: 5,
          onInteractionStart: (_) => _dragStart(),
          onInteractionUpdate: _dragUpdate,
          onInteractionEnd: (_) => _dragEnd(),
          child: GestureDetector(
            onTapUp: polys.isEmpty
                ? null
                : (d) {
                    // inside a row polygon, else the nearest row within about 1.5 row heights (snapping like in the scan)
                    int? hit;
                    var best = double.infinity;
                    for (var k = 0; k < polys.length; k++) {
                      final p = polys[k];
                      if (p == null) continue;
                      if (p.contains(d.localPosition)) {
                        hit = k;
                        break;
                      }
                      final bb = p.getBounds();
                      final dist = d.localPosition.dy < bb.top ? bb.top - d.localPosition.dy : (d.localPosition.dy > bb.bottom ? d.localPosition.dy - bb.bottom : 0.0);
                      if (dist < best && dist < 1.5 * bb.height) {
                        best = dist;
                        hit = k;
                      }
                    }
                    if (hit != null) _tapItem(hit);
                  },
            child: SizedBox(
              width: view.width,
              height: view.height,
              child: Stack(children: [
                Positioned.fill(child: Image(image: imageProvider(b.originalPath!), fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true)),
                if (polys.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _PolyRowsPainter(polys: polys, bill: b, selected: sel, look: FasanLook.of(context), error: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
      Positioned(
        left: FasanSpace.l,
        top: FasanSpace.s,
        child: IgnorePointer(child: FasanGlass(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Text(t.originalNote, style: Theme.of(context).textTheme.bodySmall))),
      ),
    ]);
  }
}

/// Item rows: thin outline; assigned = colour of the first person as soft fill plus a bar on the left;
/// unassigned = dashed-looking thin outline in the error colour; header and footer of the receipt paler.
class _RowsPainter extends CustomPainter {
  _RowsPainter({required this.rows, required this.bill, required this.selected, required this.look, required this.error, this.visible, super.repaint});

  /// Part of the receipt on screen (child coordinates); the middle of it is always clear (Nutzer 04.11.).
  final Rect Function()? visible;

  final List<Rect> rows;
  final Bill bill;
  final int? selected;
  final FasanLook look;
  final Color error;

  @override
  void paint(Canvas canvas, Size size) {
    final real = [for (final r in rows) if (r != Rect.zero) r];
    if (real.isEmpty) return;
    var top = real.map((r) => r.top).reduce(math.min) * size.height - 6;
    var bottom = real.map((r) => r.bottom).reduce(math.max) * size.height + 6;
    // Regel 3.1: header/footer stay visible, only paler. The pale veil fades in softly (no hard edge) and gives way to
    // whatever is in the middle of the screen when the user scrolls to the header or the footer (Nutzer 04.11.).
    final v = visible?.call();
    if (v != null) {
      top = math.min(top, v.center.dy - v.height * 0.22);
      bottom = math.max(bottom, v.center.dy + v.height * 0.22);
    }
    const soft = 90.0;
    final c0 = look.background.withValues(alpha: 0.45), c1 = look.background.withValues(alpha: 0);
    if (top > 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, 0, size.width, top),
        Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c0, c0, c1], stops: [0, math.max(0, (top - soft) / top), 1]).createShader(Rect.fromLTRB(0, 0, size.width, top)),
      );
    }
    if (bottom < size.height) {
      final hgt = size.height - bottom;
      canvas.drawRect(
        Rect.fromLTRB(0, bottom, size.width, size.height),
        Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c1, c0, c0], stops: [0, math.min(1, soft / hgt), 1]).createShader(Rect.fromLTRB(0, bottom, size.width, size.height)),
      );
    }
    for (var k = 0; k < rows.length; k++) {
      final n = rows[k];
      if (n == Rect.zero) continue;
      // 1.5 px inside the shared border: a visible gap between neighbours, no overlap
      final r = Rect.fromLTRB(n.left * size.width - 4, n.top * size.height + 1.5, n.right * size.width + 4, n.bottom * size.height - 1.5);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
      final it = bill.its[k];
      if (it.assigned) {
        final first = it.shares.keys.where((p) => (it.shares[p] ?? 0) > 0).fold<int?>(null, (a, p) => a == null || p < a ? p : a)!;
        final c = FasanPeople.color(bill.ps[first].color, look.brightness);
        canvas.drawRRect(rr, Paint()..color = c.withValues(alpha: 0.16));
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(r.left, r.top, 4, r.height), topLeft: const Radius.circular(6), bottomLeft: const Radius.circular(6)),
          Paint()..color = c,
        );
      } else {
        canvas.drawRRect(rr, Paint()..color = error.withValues(alpha: 0.06));
        canvas.drawRRect(rr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = error.withValues(alpha: 0.55));
      }
      if (k == selected) {
        canvas.drawRRect(rr.inflate(2), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = look.accent);
      }
    }
  }

  @override
  bool shouldRepaint(_RowsPainter old) => true; // cheap; shares change in place
}

/// People as a bar with running sums; the chosen one is the only filled chip (Regel 4.3).
class _PersonBar extends StatelessWidget {
  const _PersonBar({required this.bill, required this.selected, required this.sumOf, required this.onSelect, required this.onChanged});

  final Bill bill;
  final int? selected;
  final int Function(int) sumOf;
  final ValueChanged<int> onSelect;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final de = S.of(context).de;
    return SizedBox(
      height: math.max(l.minTap, 48) + 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l, vertical: 8),
        itemCount: bill.ps.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: FasanSpace.s),
        itemBuilder: (context, p) {
          if (p == bill.ps.length) {
            // plus: add a person right here (Nutzer 03.11.)
            return Center(
              child: ActionChip(
                avatar: const Icon(Icons.add_rounded),
                label: Text(S.of(context).addPersonHere),
                onPressed: () async {
                  final idx = await addPersonDialog(context, bill);
                  if (idx != null) onChanged();
                },
              ),
            );
          }
          final on = selected == p;
          final c = FasanPeople.color(bill.ps[p].color, l.brightness);
          return Semantics(
            selected: on,
            button: true,
            child: Material(
              color: on ? c.withValues(alpha: 0.22) : l.surfaceAlt,
              shape: StadiumBorder(side: BorderSide(color: on ? c : l.hairline, width: on ? 2 : 1)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onSelect(p),
                onLongPress: () {
                  final box = context.findRenderObject() as RenderBox;
                  personMenu(context, bill, p, box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2)), changed: onChanged);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    FasanAvatar(name: bill.ps[p].name, index: bill.ps[p].color, size: 28),
                    const SizedBox(width: 8),
                    Text(bill.ps[p].name, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(width: 8),
                    Text('${money(sumOf(p), de: de)} ${signOf(context)}', style: Theme.of(context).textTheme.labelMedium),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.zoomed, required this.onIn, required this.onOut, required this.onFit, required this.fitLabel});

  final bool zoomed;
  final VoidCallback onIn, onOut, onFit;
  final String fitLabel;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    // solid surface: glass vanished over the white receipt (0.2 screenshots)
    return Material(
      color: l.surface,
      elevation: 3,
      shape: StadiumBorder(side: BorderSide(color: l.hairline)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (zoomed) TextButton(onPressed: onFit, child: Text(fitLabel)),
        IconButton(tooltip: '−', onPressed: zoomed ? onOut : null, icon: const Icon(Icons.remove_rounded)),
        IconButton(tooltip: '+', onPressed: onIn, icon: const Icon(Icons.add_rounded)),
      ]),
    );
  }
}

/// After a tap: line picture, name, amount, people, edit (Regel 3.6).
class _CorrectionBar extends StatelessWidget {
  const _CorrectionBar({required this.bill, required this.item, required this.onChanged, required this.onClose, required this.readOnly});

  final Bill bill;
  final BillItem item;
  final VoidCallback onChanged, onClose;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return FasanGlass(
      padding: const EdgeInsets.fromLTRB(FasanSpace.m, FasanSpace.s, FasanSpace.s, FasanSpace.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: ItemTitle(item, style: Theme.of(context).textTheme.titleMedium, maxLines: 1)),
          Money(item.amount),
          IconButton(
            tooltip: t.edit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              if (await editItem(context, item, onDelete: () => bill.its.remove(item))) onChanged();
              if (!bill.its.contains(item)) onClose();
            },
          ),
          IconButton(tooltip: t.close, icon: const Icon(Icons.close_rounded), onPressed: onClose),
        ]),
        if (item.snippet != null) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: Snippet(item.snippet, height: 30)),
        if (!readOnly) PeoplePicker(bill: bill, item: item, onChanged: onChanged),
      ]),
    );
  }
}

/// The receipt rebuilt by the app: shop, date, items with plain names, total and check (Beschluss 02.11.).
class DigitalReceipt extends StatelessWidget {
  const DigitalReceipt({super.key, required this.bill, this.selected, this.onTap});

  final Bill bill;
  final int? selected;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final mono = tt.bodyMedium!.copyWith(fontFamily: l.monoFamily == null ? null : 'packages/${l.fontPackage}/${l.monoFamily}', fontFeatures: const [FontFeature.tabularFigures()]);
    final date = '${bill.date.day.toString().padLeft(2, '0')}.${bill.date.month.toString().padLeft(2, '0')}.${bill.date.year}';
    return ListView(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottomBarSpace(context) + 190),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: l.surface, borderRadius: BorderRadius.circular(l.radius * 0.6), border: Border.all(color: l.hairline)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FasanSpace.m, FasanSpace.m, FasanSpace.m, FasanSpace.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // small head: the items are what matters (Nutzer 02.11.)
              Text(bill.purpose.isEmpty ? t.appName : bill.purpose, style: tt.titleMedium, textAlign: TextAlign.center),
              Text([date, ?bill.placeAddress].join(' · '), style: tt.bodySmall!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
              const SizedBox(height: FasanSpace.m),
              Divider(color: l.hairline),
              for (var k = 0; k < bill.its.length; k++)
                InkWell(
                  onTap: onTap == null ? null : () => onTap!(k),
                  child: Container(
                    constraints: BoxConstraints(minHeight: l.minTap),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    // same border on every row (transparent unless selected): Container adds the border width to the
                    // padding, so a border only on the selected row shifted its text (Nutzer 02.11.)
                    decoration: BoxDecoration(border: Border.all(color: k == selected ? l.accent : Colors.transparent, width: 2), borderRadius: BorderRadius.circular(6)),
                    child: Row(children: [
                      Expanded(child: ItemTitle(bill.its[k])),
                      if (bill.its[k].assigned) Padding(padding: const EdgeInsets.only(right: 8), child: ShareAvatars(bill: bill, item: bill.its[k], size: 18)),
                      Text('${money(bill.its[k].amount, de: t.de)} ${signOf(context)}', style: mono),
                    ]),
                  ),
                ),
              Divider(color: l.hairline),
              Row(children: [
                Expanded(child: Text(t.total, style: tt.titleMedium)),
                Text('${money(bill.effectiveTotal, de: t.de)} ${signOf(context)}', style: mono.copyWith(fontWeight: FontWeight.w700, fontSize: 18)),
              ]),
              if (bill.difference != 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(t.diff('${money(bill.difference.abs(), de: t.de)} ${signOf(context)}'), style: tt.bodySmall!.copyWith(color: Theme.of(context).colorScheme.error)),
                ),
              if (bill.checked && bill.difference == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [Icon(Icons.verified_outlined, size: 16, color: l.accent), const SizedBox(width: 6), Text(t.checked, style: tt.bodySmall)]),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Full-screen receipt from any step (Regel 3.2): scan, original, digital.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.bill, this.initialLayer = ReceiptLayer.scan});

  final Bill bill;
  final ReceiptLayer initialLayer;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.bill.purpose.isEmpty ? t.showReceipt : widget.bill.purpose)),
      body: ReceiptAssign(bill: widget.bill, readOnly: true, initialLayer: widget.initialLayer, onChanged: () => setState(() {})),
    );
  }
}

/// The same item rows as [_RowsPainter], but as polygons (the receipt is not upright in the original photo).
class _PolyRowsPainter extends CustomPainter {
  _PolyRowsPainter({required this.polys, required this.bill, required this.selected, required this.look, required this.error});

  final List<Path?> polys;
  final Bill bill;
  final int? selected;
  final FasanLook look;
  final Color error;

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = 0; k < polys.length; k++) {
      final p = polys[k];
      if (p == null || k >= bill.its.length) continue;
      final it = bill.its[k];
      if (it.assigned) {
        final first = it.shares.keys.where((x) => (it.shares[x] ?? 0) > 0).fold<int?>(null, (a, x) => a == null || x < a ? x : a)!;
        final c = FasanPeople.color(bill.ps[first].color, look.brightness);
        canvas.drawPath(p, Paint()..color = c.withValues(alpha: 0.2));
        canvas.drawPath(p, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = c.withValues(alpha: 0.8));
      } else {
        canvas.drawPath(p, Paint()..color = error.withValues(alpha: 0.06));
        canvas.drawPath(p, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = error.withValues(alpha: 0.55));
      }
      if (k == selected) {
        canvas.drawPath(p, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = look.accent);
      }
    }
  }

  @override
  bool shouldRepaint(_PolyRowsPainter old) => true;
}
