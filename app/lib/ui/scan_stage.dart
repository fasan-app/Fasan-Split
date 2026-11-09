// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the scan animation as a widget: lines light up as verified boxes, then the kinked receipt straightens
// along the dewarp mesh. Used big on the scan page and small in the list tiles. MPL-2.0
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../recognition/service.dart';
import '../state/scan_live.dart';

/// Shows what [live] collects: [placeholder] until the first preview, then the preview with its boxes, at the end the
/// straightening. Without motion ("Animationen entfernen") the final state appears at once.
class ScanStage extends StatefulWidget {
  const ScanStage({super.key, required this.live, required this.placeholder, this.brackets = false});

  final ScanLive live;
  final Widget placeholder;

  /// Corner brackets and sweep of the cinematic styles (big view only).
  final bool brackets;

  @override
  State<ScanStage> createState() => _ScanStageState();
}

class _ScanStageState extends State<ScanStage> with TickerProviderStateMixin {
  late final AnimationController _light = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _straighten = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  ui.Image? _warpImage;
  int _seenPreview = -1, _seenWarp = -1;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      widget.live.addListener(_changed);
    }
    _changed();
  }

  @override
  void didUpdateWidget(ScanStage old) {
    super.didUpdateWidget(old);
    if (old.live != widget.live) {
      old.live.removeListener(_changed);
      widget.live.addListener(_changed);
      _seenPreview = -1;
      _seenWarp = -1;
      _changed();
    }
  }

  void _changed() {
    if (!mounted) return;
    final l = widget.live, m = FasanMotion.of(context);
    if (l.previewSerial != _seenPreview && l.preview != null) {
      _seenPreview = l.previewSerial;
      // lines light up one after the other (Bewegung erklärt Veränderung); instantly without motion
      _light.duration = m.enabled ? const Duration(milliseconds: 900) : Duration.zero;
      _light.forward(from: 0);
    }
    if (l.warp != null && l.warpSerial != _seenWarp) {
      _seenWarp = l.warpSerial;
      l.playing = _play(l.warp!);
    }
    setState(() {});
  }

  /// Shows the kinked receipt with the verified line boxes, then straightens it. Instant without motion.
  Future<void> _play(ScanWarp w) async {
    try {
      final img = await decodeImageFromList(w.jpeg);
      if (!mounted) return;
      final m = FasanMotion.of(context);
      setState(() => _warpImage = img);
      if (!m.enabled) {
        _straighten.value = 1;
        _light.value = 1;
        return;
      }
      _straighten.value = 0;
      await _light.forward(from: 0).orCancel;
      if (!mounted) return;
      await _straighten.animateTo(1, curve: Curves.easeInOutCubic).orCancel;
    } catch (_) {
      // animation only; the result is shown anyway
    }
  }

  @override
  void dispose() {
    widget.live.removeListener(_changed);
    _light.dispose();
    _straighten.dispose();
    _warpImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context), live = widget.live;
    final cine = widget.brackets && l.style.cinematic;
    Widget child;
    if (_warpImage != null && live.warp != null) {
      child = LayoutBuilder(
        key: const ValueKey('warp'),
        builder: (context, c) => ScanWarpView(image: _warpImage!, warp: live.warp!, light: _light, straighten: _straighten, color: l.accent, size: Size(c.maxWidth, c.maxHeight), brackets: cine),
      );
    } else if (live.preview != null) {
      child = LayoutBuilder(
        key: ValueKey(live.previewSerial),
        builder: (context, c) => ScanPreviewBoxes(jpeg: live.preview!, boxes: live.boxes, light: _light, color: l.accent, brackets: cine, straight: live.straight),
      );
    } else {
      child = KeyedSubtree(key: const ValueKey('placeholder'), child: widget.placeholder);
    }
    return AnimatedSwitcher(duration: FasanMotion.of(context).long, child: child);
  }
}

/// The preview image with the verified line boxes on top.
class ScanPreviewBoxes extends StatelessWidget {
  const ScanPreviewBoxes({super.key, required this.jpeg, required this.boxes, required this.light, required this.color, required this.brackets, required this.straight});

  final Uint8List jpeg;
  final List<List<double>> boxes;
  final Animation<double> light;
  final Color color;
  final bool brackets, straight;

  @override
  Widget build(BuildContext context) {
    final img = Image.memory(jpeg, gaplessPlayback: true, fit: BoxFit.contain);
    Widget w = AnimatedBuilder(
      animation: light,
      builder: (context, child) => CustomPaint(foregroundPainter: ScanBoxPainter(boxes, light.value, color), child: child),
      child: img,
    );
    if (brackets) w = FasanBrackets(label: straight ? 'SCAN · GERADE' : 'ANALYSE', child: Stack(children: [w, const Positioned.fill(child: FasanSweep(active: true))]));
    return w;
  }
}

/// Rotated boxes along the verified lines (8 numbers per box; 4 numbers = upright rectangle), revealed top to bottom.
class ScanBoxPainter extends CustomPainter {
  ScanBoxPainter(List<List<double>> boxes, this.t, this.color) : boxes = _sorted(boxes);

  final List<List<double>> boxes;
  final double t;
  final Color color;

  static List<List<double>> _sorted(List<List<double>> b) {
    final out = [
      for (final q in b)
        if (q.length == 8) q else if (q.length == 4) [q[0], q[1], q[2], q[1], q[2], q[3], q[0], q[3]],
    ];
    out.sort((a, c) => (a[1] + a[5]).compareTo(c[1] + c[5]));
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = boxes.length;
    for (var i = 0; i < n; i++) {
      // staggered: box i appears at i/n of the animation; sorted top to bottom like reading
      final a = ((t * (n + 4) - i) / 4).clamp(0.0, 1.0);
      if (a <= 0) continue;
      final b = boxes[i];
      drawScanQuad(canvas, [for (var k = 0; k < 8; k += 2) Offset(b[k] * size.width, b[k + 1] * size.height)], color, a);
    }
  }

  @override
  bool shouldRepaint(ScanBoxPainter o) => o.t != t || o.boxes != boxes;
}

void drawScanQuad(Canvas canvas, List<Offset> p, Color color, double a) {
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  for (var k = 1; k < p.length; k++) {
    path.lineTo(p[k].dx, p[k].dy);
  }
  path.close();
  canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18 * a));
  canvas.drawPath(
    path,
    Paint()
      ..color = color.withValues(alpha: 0.65 * a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round,
  );
}

/// The kinked receipt straightens: the photo is drawn on a mesh whose nodes move from their place in the photo to a
/// regular grid; the verified line boxes move with the mesh corners (scan_preview.dart).
class ScanWarpView extends StatelessWidget {
  const ScanWarpView({
    super.key,
    required this.image,
    required this.warp,
    required this.light,
    required this.straighten,
    required this.color,
    required this.size,
    required this.brackets,
  });

  final ui.Image image;
  final ScanWarp warp;
  final Animation<double> light, straighten;
  final Color color;
  final Size size;
  final bool brackets;

  @override
  Widget build(BuildContext context) {
    Widget w = SizedBox(width: size.width, height: size.height, child: CustomPaint(painter: ScanWarpPainter(image, warp, light, straighten, color)));
    if (brackets) w = FasanBrackets(label: 'SCAN · GERADE', child: w);
    return w;
  }
}

class ScanWarpPainter extends CustomPainter {
  ScanWarpPainter(this.image, this.warp, this.light, this.straighten, this.color) : super(repaint: Listenable.merge([light, straighten]));

  final ui.Image image;
  final ScanWarp warp;
  final Animation<double> light, straighten;
  final Color color;

  /// Largest rectangle with [aspect] (width / height) centred in [s].
  static Rect _fit(double aspect, Size s) {
    var w = s.width, h = w / aspect;
    if (h > s.height) {
      h = s.height;
      w = h * aspect;
    }
    return Rect.fromCenter(center: Offset(s.width / 2, s.height / 2), width: w, height: h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = straighten.value, pre = _fit(warp.preAspect, size), scan = _fit(warp.scanAspect, size);
    Offset at(Offset n, Offset d) =>
        Offset.lerp(pre.topLeft + Offset(n.dx * pre.width, n.dy * pre.height), scan.topLeft + Offset(d.dx * scan.width, d.dy * scan.height), t)!;
    final cols = warp.cols, rows = warp.rows, iw = image.width.toDouble(), ih = image.height.toDouble();
    final pos = <Offset>[], tex = <Offset>[];
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final k = (j * cols + i) * 2, n = Offset(warp.src[k], warp.src[k + 1]);
        pos.add(at(n, Offset(i / (cols - 1), j / (rows - 1))));
        tex.add(Offset(n.dx.clamp(0.0, 1.0) * iw, n.dy.clamp(0.0, 1.0) * ih));
      }
    }
    final idx = <int>[];
    for (var j = 0; j + 1 < rows; j++) {
      for (var i = 0; i + 1 < cols; i++) {
        final a = j * cols + i, b = a + 1, c = a + cols, d = c + 1;
        idx.addAll([a, b, c, b, d, c]);
      }
    }
    final shader = ui.ImageShader(image, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage, filterQuality: FilterQuality.medium);
    final vertices = ui.Vertices(ui.VertexMode.triangles, pos, textureCoordinates: tex, indices: idx);
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint()..shader = shader);
    vertices.dispose();
    shader.dispose();
    // verified line boxes: corners move with the mesh, revealed top to bottom while the receipt is still kinked
    final quads = [...warp.quads]..sort((a, b) => (a[1] + a[5]).compareTo(b[1] + b[5]));
    final n = quads.length;
    for (var i = 0; i < n; i++) {
      final a = ((light.value * (n + 4) - i) / 4).clamp(0.0, 1.0);
      if (a <= 0) continue;
      final q = quads[i];
      drawScanQuad(canvas, [for (var k = 0; k < 4; k++) at(Offset(q[8 + 2 * k], q[9 + 2 * k]), Offset(q[2 * k], q[2 * k + 1]))], color, a);
    }
  }

  @override
  bool shouldRepaint(ScanWarpPainter o) => o.image != image || o.warp != warp;
}

