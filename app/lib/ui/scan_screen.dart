// Fasan Split – reading the receipt: the straightened receipt appears, lines light up as they are read. MPL-2.0
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../model/bill.dart';
import '../model/scan_bill.dart';
import '../recognition_service.dart';
import 'flow.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.photo, this.events});

  final Uint8List photo;

  /// For tests: a prepared event stream instead of the real recognition.
  final Stream<ScanEvent>? events;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with TickerProviderStateMixin {
  StreamSubscription<ScanEvent>? _sub;
  String _stage = '';
  double _progress = 0;
  Uint8List? _preview;
  List<List<double>> _boxes = const [];
  bool _straight = false;
  String? _error;
  late final AnimationController _light = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  // end of the scan: the kinked receipt straightens along the dewarp mesh (0 = as photographed, 1 = straight)
  late final AnimationController _straighten = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  ScanWarp? _warp;
  ui.Image? _warpImage;
  Future<void>? _warpDone;

  @override
  void initState() {
    super.initState();
    _sub = (widget.events ?? RecognitionService.instance.recognize(widget.photo)).listen(_on);
  }

  void _on(ScanEvent e) {
    if (!mounted) return;
    switch (e) {
      case ScanProgress():
        setState(() {
          _stage = e.stage;
          _progress = e.progress;
        });
      case ScanPreview():
        setState(() {
          _preview = e.jpeg;
          _boxes = e.boxes;
          _straight = e.straight;
        });
        // lines light up one after the other (Bewegung erklärt Veränderung); instantly without motion
        final m = FasanMotion.of(context);
        _light.duration = m.enabled ? const Duration(milliseconds: 900) : Duration.zero;
        _light.forward(from: 0);
      case ScanWarp():
        _warpDone = _playWarp(e);
      case ScanDone():
        _finish(e.result);
      case ScanError():
        setState(() => _error = e.message);
    }
  }

  /// Shows the kinked receipt with the verified line boxes, then straightens it. Instant without motion.
  Future<void> _playWarp(ScanWarp w) async {
    try {
      final img = await decodeImageFromList(w.jpeg);
      if (!mounted) return;
      final m = FasanMotion.of(context);
      setState(() {
        _warp = w;
        _warpImage = img;
      });
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

  Future<void> _finish(ScanResultData r) async {
    final playing = _warpDone;
    if (playing != null) await playing.timeout(const Duration(seconds: 5), onTimeout: () {});
    if (!mounted) return;
    final bill = await billFromScan(r, widget.photo);
    if (!mounted) return;
    FasanHaptics.of(context).confirm();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReviewScreen(bill: bill, scan: r)));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _light.dispose();
    _straighten.dispose();
    _warpImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final l = FasanLook.of(context);
    final tt = Theme.of(context).textTheme;
    final cine = l.style.cinematic;
    return Scaffold(
      appBar: AppBar(title: Text(t.reading)),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(FasanSpace.l),
              child: Center(
                child: _error != null
                    ? _Failed(message: _error!)
                    : AnimatedSwitcher(
                        duration: FasanMotion.of(context).long,
                        child: _warp != null && _warpImage != null
                            ? LayoutBuilder(
                                key: const ValueKey('warp'),
                                builder: (context, c) => _WarpView(
                                  image: _warpImage!,
                                  warp: _warp!,
                                  light: _light,
                                  straighten: _straighten,
                                  color: l.accent,
                                  size: Size(c.maxWidth, c.maxHeight),
                                  brackets: cine,
                                ),
                              )
                            : _preview == null
                            ? Image.memory(widget.photo, key: const ValueKey('foto'), fit: BoxFit.contain, cacheWidth: 900, opacity: const AlwaysStoppedAnimation(0.5))
                            : LayoutBuilder(
                                key: ValueKey(_preview.hashCode),
                                builder: (context, c) => _PreviewWithBoxes(jpeg: _preview!, boxes: _boxes, light: _light, color: l.accent, brackets: cine, straight: _straight),
                              ),
                      ),
              ),
            ),
          ),
          if (_error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_stage, style: cine ? l.mono(12, color: l.text) : tt.bodyMedium),
                const SizedBox(height: FasanSpace.s),
                FasanProgress(value: _progress <= 0 ? null : _progress),
                const SizedBox(height: FasanSpace.s),
                Text(t.photoStays, style: tt.bodySmall),
                const SizedBox(height: FasanSpace.s),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(t.cancel))),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _PreviewWithBoxes extends StatelessWidget {
  const _PreviewWithBoxes({required this.jpeg, required this.boxes, required this.light, required this.color, required this.brackets, required this.straight});

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
      builder: (context, child) => CustomPaint(foregroundPainter: _BoxPainter(boxes, light.value, color), child: child),
      child: img,
    );
    if (brackets) w = FasanBrackets(label: straight ? 'SCAN · GERADE' : 'ANALYSE', child: Stack(children: [w, const Positioned.fill(child: FasanSweep(active: true))]));
    return w;
  }
}

/// Rotated boxes along the verified lines (8 numbers per box; 4 numbers = upright rectangle), revealed top to bottom.
class _BoxPainter extends CustomPainter {
  _BoxPainter(List<List<double>> boxes, this.t, this.color) : boxes = _sorted(boxes);

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
      _drawQuad(canvas, [for (var k = 0; k < 8; k += 2) Offset(b[k] * size.width, b[k + 1] * size.height)], color, a);
    }
  }

  @override
  bool shouldRepaint(_BoxPainter o) => o.t != t || o.boxes != boxes;
}

void _drawQuad(Canvas canvas, List<Offset> p, Color color, double a) {
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
class _WarpView extends StatelessWidget {
  const _WarpView({
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
    Widget w = SizedBox(width: size.width, height: size.height, child: CustomPaint(painter: _WarpPainter(image, warp, light, straighten, color)));
    if (brackets) w = FasanBrackets(label: 'SCAN · GERADE', child: w);
    return w;
  }
}

class _WarpPainter extends CustomPainter {
  _WarpPainter(this.image, this.warp, this.light, this.straighten, this.color) : super(repaint: Listenable.merge([light, straighten]));

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
      _drawQuad(canvas, [for (var k = 0; k < 4; k++) at(Offset(q[8 + 2 * k], q[9 + 2 * k]), Offset(q[2 * k], q[2 * k + 1]))], color, a);
    }
  }

  @override
  bool shouldRepaint(_WarpPainter o) => o.image != image || o.warp != warp;
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline, size: 40, color: FasanLook.of(context).textMuted),
      const SizedBox(height: FasanSpace.m),
      Text(t.readFailed, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
      const SizedBox(height: FasanSpace.s),
      Text(message.split('\n').first, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      const SizedBox(height: FasanSpace.l),
      FasanButton(
        label: t.enterByHand,
        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ReviewScreen(bill: Bill(id: DateTime.now().microsecondsSinceEpoch.toString(), created: DateTime.now(), items: [])),
        )),
      ),
    ]);
  }
}
