// Fasan Split – reading the receipt: the straightened receipt appears, lines light up as they are read. MPL-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../model/bill.dart';
import '../recognition_service.dart';
import '../state/store.dart';
import 'flow.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.photo, this.events});

  final Uint8List photo;

  /// For tests: a prepared event stream instead of the real recognition.
  final Stream<ScanEvent>? events;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  StreamSubscription<ScanEvent>? _sub;
  String _stage = '';
  double _progress = 0;
  Uint8List? _preview;
  List<List<double>> _boxes = const [];
  bool _straight = false;
  String? _error;
  late final AnimationController _light = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

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
      case ScanDone():
        _finish(e.result);
      case ScanError():
        setState(() => _error = e.message);
    }
  }

  Future<void> _finish(ScanResultData r) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final img = await BillStore.saveFile('$id.jpg', r.display);
    // utf8, not codeUnits (UTF-16 units broke every character outside Latin-1 in 0.1.2)
    final log = await BillStore.saveFile('$id.log.json', Uint8List.fromList(utf8.encode(r.log)));
    // the photo exactly as taken (Beschluss 02.11.: Original immer sichtbar, für alle)
    final orig = await BillStore.saveFile('$id.orig.jpg', widget.photo);
    final bill = Bill(
      id: id,
      created: DateTime.now(),
      purpose: r.shop.isNotEmpty ? _title(r.shop) : r.kind,
      total: r.total,
      items: r.items,
      imagePath: img,
      imageAspect: r.width / r.height,
      checked: r.checked && !r.contradiction,
      advance: r.advance,
      logPath: log,
      originalPath: orig,
    );
    if (!mounted) return;
    FasanHaptics.of(context).confirm();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReviewScreen(bill: bill, scan: r)));
  }

  static String _title(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  void dispose() {
    _sub?.cancel();
    _light.dispose();
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
                        child: _preview == null
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

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.boxes, this.t, this.color);

  final List<List<double>> boxes;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = boxes.length;
    for (var i = 0; i < n; i++) {
      // staggered: box i appears at i/n of the animation; sorted top to bottom like reading
      final a = ((t * (n + 4) - i) / 4).clamp(0.0, 1.0);
      if (a <= 0) continue;
      final b = boxes[i];
      final r = Rect.fromLTRB(b[0] * size.width, b[1] * size.height, b[2] * size.width, b[3] * size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), Paint()..color = color.withValues(alpha: 0.18 * a));
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        Paint()
          ..color = color.withValues(alpha: 0.65 * a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_BoxPainter o) => o.t != t || o.boxes != boxes;
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
