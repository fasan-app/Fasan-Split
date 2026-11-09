// SPDX-License-Identifier: MPL-2.0
// Fasan Split – performance test (Nutzer 08.11.: „Ein Protokoll für die Browser-Performance kann ich dir nur mit Bon geben … ein
// Probe-Stresstest im Menü wäre viel effizienter, um absolut alles abzufragen und zu exportieren“).
// Runs by itself, about two minutes, with made-up data that is never stored: idle (refresh rate), scrolling the bill list with real
// BillTiles, scrolling item rows with the real item widgets, opening and closing sheets. Frame times come from a Ticker (the time
// between two frames as the screen shows them – works the same in the browser and on the phone; FrameTiming raster values are
// unreliable on the web) plus FrameStats build/raster. The report holds device, browser, graphics (WebGL or not), the numbers of
// every phase and the app's frame statistics; no names, no bills. MPL-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:fasan_core/bill.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../flows/scan_queue.dart';
import '../l10n.dart';
import '../l10n/tr.dart' show trLang;
import '../perf/frame_stats.dart';
import '../collab/crypto.dart' show KeyPair, cryptoStats, sha256, toHex;
import '../collab/curve.dart' show curveImplementation;
import '../collab/group.dart' show kindData;
import '../collab/nostr.dart' show NostrEvent;
import '../perf/timeline.dart';
import '../platform/web_platform.dart' show deviceFacts, readBatteryOnce;
import '../state/store.dart';
import 'bill_tile.dart';
import 'common.dart';
import 'diagnose.dart' show exportDocument;
import 'scope.dart';

/// Made-up bills for the list phase: long and short names, 2–7 people, every fill state, some with payer.
List<Bill> perfBills(int n, {List<String> thumbs = const []}) {
  // Only invented names (Nutzer 08.11.: never show or use names from real bills or groups in the test).
  const names = ['Café Muster', 'Taxi Beispiel', 'Bäckerei Probe', 'Eisdiele Test', 'Restaurant Beispielstadt mit sehr langem erfundenen Namen', 'Kneipe Nummer N', 'Koffer', 'Strandbar Erfunden'];
  const cats = ['restaurant', 'transport', 'lodging'];
  return [
    for (var i = 0; i < n; i++)
      Bill(
        id: 'perf$i',
        thumb: thumbs.isEmpty ? null : thumbs[i % thumbs.length],
        created: DateTime(2026, 10, 20 + i % 8),
        purpose: names[i % names.length],
        total: 2000 + i * 137,
        category: cats[i % cats.length],
        people: [for (var p = 0; p < 2 + i % 6; p++) Person(const ['Anna', 'Jo', 'Mia', 'Tom', 'Eva', 'Ben', 'Lea'][p], p)],
        items: [
          for (var k = 0; k < 6; k++) BillItem(name: 'Posten $k', amount: 300 + k * 50, shares: i % 3 == 0 ? {0: 1} : (i % 3 == 1 && k % 2 == 0 ? {0: 1, 1: 1} : {})),
        ],
      )
        ..checked = true
        ..payer = i % 4 == 0 ? null : 0,
  ];
}

Bill _itemsBill() => Bill(
      id: 'perfitems',
      created: DateTime(2026, 11, 8),
      purpose: 'Probe',
      total: 100000,
      people: [for (var p = 0; p < 6; p++) Person(const ['Anna', 'Jo', 'Mia', 'Tom', 'Eva', 'Ben'][p], p)],
      items: [
        for (var k = 0; k < 80; k++)
          BillItem(
            name: k % 3 == 0 ? 'Pfanne Phantasie mit Gemüse und Reis für zwei, dazu Soße $k' : 'Getränk Rot $k',
            amount: 450 + k * 30,
            qty: 1 + k % 3,
            shares: {for (var p = 0; p < (k % 6) + 1; p++) p: 1},
          ),
      ],
    );

/// Group-wide item view candidate (Umbau, option A): 25 bills x 20 items = 500 rows plus one heading per bill.
/// Measures whether a flat list of every item of every bill scrolls smoothly before anything is built for real.
List<(Bill, BillItem?)> _flatPosten() {
  final bills = perfBills(25);
  return [
    for (final b in bills) ...[
      (b, null),
      for (var k = 0; k < 20; k++)
        (b, BillItem(name: k % 4 == 0 ? 'Gericht Phantasie mit Beilage und Ei $k' : 'Wasser $k', amount: 250 + k * 40, shares: k % 3 == 0 ? {0: 1} : (k % 3 == 1 ? {0: 1, 1: 1} : {}))),
    ],
  ];
}

class PerfTestScreen extends StatefulWidget {
  const PerfTestScreen({super.key});

  @override
  State<PerfTestScreen> createState() => _PerfTestScreenState();
}

class _PerfTestScreenState extends State<PerfTestScreen> with SingleTickerProviderStateMixin {
  // floor / shadow / nothumb are counter-samples of the list phase: bare rows, rows with only the card shadows, the real tile without picture.
  // Their difference to 'list' shows what costs the time (measure, do not guess).
  static const _phases = ['idle', 'list', 'floor', 'shadow', 'nothumb', 'items', 'posten', 'sync', 'sheet', 'ruhe'];
  late final Ticker _tick = createTicker(_onTick);
  final List<double> _deltas = [];
  Duration? _last;
  final ScrollController _sc = ScrollController();
  final List<Map<String, Object?>> _results = [];
  int _phase = -1; // -1 not started, 0.._phases.length-1 running, _phases.length done
  bool _cancelled = false;
  BillStore _mem = BillStore.memory(perfBills(60));
  final BillStore _memNoThumb = BillStore.memory(perfBills(60));
  List<NostrEvent> _events = const [];
  bool _preparing = false;
  /// Display rate guessed from the idle phase (median frame time), snapped to common rates. Scroll phases are judged against its frame budget:
  /// on a 120 Hz screen 60 frames/s with 33 ms peaks is visibly worse than other apps (Nutzer 08.11., Adreno 650: idle 8.3 ms, scrolling 16.7 ms).
  double _hz = 60;
  int _prepFrom = 0, _prepTo = 0, _testTo = 0;
  final Map<String, double> _settleMax = {};
  static const _scrollPhases = {'list', 'floor', 'shadow', 'nothumb', 'items', 'posten', 'sync'};
  late final Bill _itemsDoc = _itemsBill();
  late final List<(Bill, BillItem?)> _flat = _flatPosten();

  void _onTick(Duration t) {
    if (_last != null) _deltas.add((t - _last!).inMicroseconds / 1000);
    _last = t;
  }

  @override
  void dispose() {
    _cancelled = true;
    _tick.dispose();
    _sc.dispose();
    super.dispose();
  }

  Future<void> _pause(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  /// Six flings at finger speed (down fast, up slower), each left to run out: the scroll physics of a real swipe, not a smooth animation.
  Future<void> _scrollThere() async {
    const speeds = [4200.0, -2600.0, 3000.0, -4500.0, 3600.0, -3200.0];
    for (final v in speeds) {
      if (_cancelled || !_sc.hasClients) return;
      (_sc.position as ScrollPositionWithSingleContext).goBallistic(v);
      await _pause(1600);
    }
  }

  /// What a group does to the screen thread: every message that arrives is checked (signature) before it is used. Distinct, never seen
  /// events, one every 450 ms while the list is scrolled (the check is the same code the app runs for relay messages).
  Future<void> _verifyEvents() async {
    for (final e in _events) {
      await _pause(450);
      if (_cancelled) return;
      e.valid;
    }
  }

  /// A receipt-like picture (160 x 240, rows of text bars) as base64 PNG, the size class of the real thumbnails.
  Future<String?> _fakeThumb(int k) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 160, 240), Paint()..color = const Color(0xFFF4F1EA));
    final paint = Paint()..color = const Color(0xFF55504A);
    for (var row = 0; row < 24; row++) {
      c.drawRect(Rect.fromLTWH(12, 10.0 + row * 9, 40.0 + ((row * 37 + k * 11) % 90), 4), paint);
    }
    final img = await rec.endRecording().toImage(160, 240);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes == null ? null : base64Encode(bytes.buffer.asUint8List());
  }

  /// Test data made of real-sized parts: 60 bills with picture thumbnails, 6 made-up members, 12 signed events. Nothing from the person's
  /// own bills or groups is read or written (Nutzer 08.11.: not with the original data).
  Future<void> _prepare() async {
    setState(() => _preparing = true);
    await _pause(50);
    final thumbs = <String>[];
    for (var k = 0; k < 3; k++) {
      try {
        final t = await _fakeThumb(k).timeout(const Duration(seconds: 4));
        if (t != null) thumbs.add(t);
      } catch (_) {
        // no picture encoder (tests): the bills simply have no thumbnail
      }
    }
    _mem = BillStore.memory(perfBills(60, thumbs: thumbs));
    final keys = [for (var m = 0; m < 6; m++) KeyPair.fromPrivate(toHex(sha256(utf8.encode('perf-member-$m'))))];
    _events = [
      for (var i = 0; i < 12; i++) NostrEvent.create(keys[i % keys.length], kind: kindData, tags: [['d', 'fs:perf:doc$i']], content: 'x' * 4000, createdAt: 1700000000 + i),
    ];
    if (mounted) setState(() => _preparing = false);
  }

  Future<void> _run() async {
    readBatteryOnce(); // browser: battery level for the report (arrives asynchronously, long before the end)
    _results.clear();
    _cancelled = false;
    setState(() => _phase = 0);
    _prepFrom = StartTimeline.seconds;
    await _prepare();
    _prepTo = StartTimeline.seconds;
    _last = null;
    _tick.start();
    for (var i = 0; i < _phases.length && !_cancelled; i++) {
      setState(() => _phase = i);
      await _pause(600); // let the new content build before measuring
      // The switch to a new screen is real UI work the person sees: keep its longest frame apart from the measured phase.
      _settleMax[_phases[i]] = _deltas.isEmpty ? 0 : _deltas.reduce((a, b) => a > b ? a : b);
      _deltas.clear();
      FrameStats.take();
      final sw = Stopwatch()..start();
      switch (_phases[i]) {
        case 'idle':
          await _pause(2500);
        case 'ruhe':
          await _pause(30000);
        case 'sync':
          final v = _verifyEvents();
          await _scrollThere();
          await v;
        case 'sheet':
          for (var k = 0; k < 4 && !_cancelled && mounted; k++) {
            // ignore: use_build_context_synchronously
            unawaited(showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [for (var j = 0; j < 4; j++) ListTile(leading: const Icon(Icons.person_outline), title: Text('Eintrag $j'), subtitle: const Text('Probe'))]))));
            await _pause(900);
            // ignore: use_build_context_synchronously
            if (mounted) Navigator.of(context).pop();
            await _pause(500);
          }
        default:
          await _scrollThere();
      }
      sw.stop();
      if (_phases[i] == 'idle' && _deltas.length > 20) {
        final d = [..._deltas]..sort();
        final hz = 1000 / d[d.length ~/ 2];
        _hz = const [60.0, 72.0, 90.0, 120.0, 144.0].reduce((a, b) => (a - hz).abs() < (b - hz).abs() ? a : b);
      }
      _results.add({..._summarise(_phases[i], sw.elapsedMilliseconds), 'app': FrameStats.take(), if (_phases[i] == 'sync') 'krypto': cryptoStats.summary()});
    }
    _tick.stop();
    _testTo = StartTimeline.seconds;
    if (mounted && !_cancelled) setState(() => _phase = _phases.length);
  }

  Map<String, Object?> _summarise(String name, int ms) {
    final d = [..._deltas]..sort();
    if (d.isEmpty) return {'phase': name, 'ms': ms, 'bilder': 0};
    double q(double p) => d[(d.length * p).floor().clamp(0, d.length - 1)];
    final mean = d.reduce((a, b) => a + b) / d.length;
    double r(double v) => (v * 10).round() / 10;
    final over100 = d.where((x) => x > 100).length;
    final p95 = q(0.95);
    // Verdict (Nutzer 08.11.: the test said „good“ while the app stuttered): a frame over 100 ms is never good.
    // Scroll phases use the frame budget of the display (8.3 ms at 120 Hz); the other phases stay at 60 Hz (the system lowers the rate for light animation).
    final budget = _scrollPhases.contains(name) ? 1000 / _hz : 1000 / 60;
    final verdict = over100 == 0 && p95 <= budget * 1.2 ? 'good' : (over100 <= 2 && p95 <= budget * 2.05 ? 'mid' : 'bad');
    return {
      'phase': name,
      'urteil': verdict,
      'ms': ms,
      'bilder': d.length,
      'fps': r(1000 / mean),
      'median': r(q(0.5)),
      'p95': r(q(0.95)),
      'laengster': r(d.last),
      'ueber33': d.where((x) => x > 33.4).length,
      'ueber100': d.where((x) => x > 100).length,
    };
  }

  /// What Flutter itself knows, same on phone and browser (api.flutter.dev: FlutterView.display, PlatformDispatcher.accessibilityFeatures).
  /// Build mode matters: debug/profile builds are far slower than release and must never be compared with it.
  Map<String, Object?> _flutterFacts() {
    final view = View.of(context);
    final disp = view.display;
    final pd = WidgetsBinding.instance.platformDispatcher;
    final a = pd.accessibilityFeatures;
    return {
      'modus': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'wasm': const bool.fromEnvironment('dart.tool.dart2wasm'),
      'anzeige': {'hz': disp.refreshRate, 'groessePx': '${disp.size.width.round()}×${disp.size.height.round()}', 'dpr': disp.devicePixelRatio},
      'sprache': pd.locale.toLanguageTag(),
      'helligkeit': pd.platformBrightness.name,
      'textSkala': pd.textScaleFactor,
      'bedienhilfen': {'animationenAus': a.disableAnimations, 'kontrastHoch': a.highContrast, 'fettText': a.boldText, 'bildschirmleser': a.accessibleNavigation},
    };
  }

  Map<String, Object?> _report() => {
        'app': 'app.fasan.split',
        'art': 'leistungstest',
        'zeit': DateTime.now().toIso8601String(),
        'geraet': deviceFacts(),
        'flutter': _flutterFacts(),
        'bildschirm': {'dpr': MediaQuery.of(context).devicePixelRatio, 'groesse': '${MediaQuery.of(context).size.width.round()}×${MediaQuery.of(context).size.height.round()}'},
        'urteil': _verdictAll(),
        'sekundenSeitStart': StartTimeline.seconds,
        'anzeigeHz': _hz,
        // Power level and effect switches the app ran with (low battery lowers them): runs are only comparable with the same values.
        'effekte': {'stufe': FasanLook.of(context).level.name, 'an': FasanLook.of(context).effects.enabled, 'schatten': FasanLook.of(context).effects.shadows},
        'vorbereitung': {'vonS': _prepFrom, 'bisS': _prepTo, 'testEndeS': _testTo, 'hinweis': 'Abschnitte dieser Zeit zählen nicht ins Start-Urteil: die Phasen werden einzeln beurteilt'},
        'aufbauLaengsterMs': _settleMax,
        'krypto': {...cryptoStats.summary(), 'rechnung': curveImplementation},
        'startVerlauf': StartTimeline.windows(),
        'phasen': _results,
      };

  /// Worst verdict of the phases; the start record counts too (a stalled window after the first minute is „mid“, more than two „bad“).
  /// Windows that do not overlap the test itself (its own preparation and phase switches are measured and judged on their own).
  List<Map<String, Object>> _outsideTest(List<Map<String, Object>> win) {
    if (_testTo == 0) return win;
    return win.where((w) {
      final a = w['ab_s']! as int;
      return a + 5 <= _prepFrom || a > _testTo;
    }).toList();
  }

  String _verdictAll() {
    const order = ['good', 'mid', 'bad'];
    var worst = 0;
    for (final r in _results) {
      final i = order.indexOf(r['urteil'] as String? ?? 'good');
      if (i > worst) worst = i;
    }
    final late = _outsideTest(StartTimeline.windows()).where((w) => (w['ab_s']! as int) >= 60 && ((w['timerUeber100']! as int) > 0 || (w['ueber100']! as int) > 0)).length;
    final i = late == 0 ? 0 : (late <= 2 ? 1 : 2);
    return order[i > worst ? i : worst];
  }

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de;
    String tr(String k, [List<Object> a = const []]) => trLang(de ? 'de' : 'en', k, a);
    final l = FasanLook.of(context);
    final done = _phase == _phases.length;
    final running = _phase >= 0 && !done;
    return PopScope(
      canPop: !running,
      child: Scaffold(
        appBar: AppBar(title: Text(tr('perf.test'))),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(FasanSpace.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_preparing ? tr('perf.prepare') : running ? tr('perf.running', [tr('perf.phase.${_phases[_phase]}'), '${_phase + 1}', '${_phases.length}']) : tr(done ? 'perf.done' : 'perf.intro')),
              const SizedBox(height: FasanSpace.m),
              if (running) const LinearProgressIndicator(),
              if (!running)
                Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [
                  FilledButton.icon(onPressed: _run, icon: const Icon(Icons.speed_rounded), label: Text(tr(done ? 'perf.again' : 'perf.start'))),
                  if (done) OutlinedButton.icon(onPressed: () => exportDocument(context, _report(), prefix: 'leistungstest', share: false), icon: const Icon(Icons.save_alt_rounded), label: Text(S.of(context).saveFile)),
                  if (done) OutlinedButton.icon(onPressed: () => exportDocument(context, _report(), prefix: 'leistungstest', share: true), icon: const Icon(Icons.ios_share_rounded), label: Text(S.of(context).share)),
                ]),
            ]),
          ),
          Expanded(child: running ? _stage(context) : _resultsView(context, tr, l)),
        ]),
      ),
    );
  }

  Widget _resultsView(BuildContext context, String Function(String, [List<Object>]) tr, FasanLook l) {
    final win = StartTimeline.windows();
    final stalled = _outsideTest(win).where((w) => (w['timerUeber100']! as int) > 0 || (w['ueber100']! as int) > 0).toList();
    return ListView(padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l), children: [
        if (_results.isNotEmpty)
          Card(child: ListTile(title: Text(tr('perf.verdict.${_verdictAll()}')), subtitle: Text(tr('perf.startLine', ['${stalled.length}', '${win.length}', '${stalled.isEmpty ? 0 : stalled.last['ab_s']}', '${StartTimeline.seconds}'])))),
        for (final r in _results)
          Card(
            child: ListTile(
              leading: Icon(r['urteil'] == 'good' ? Icons.check_circle_outline_rounded : (r['urteil'] == 'mid' ? Icons.error_outline_rounded : Icons.cancel_outlined)),
              title: Text(tr('perf.phase.${r['phase']}')),
              subtitle: Text(tr('perf.line', ['${r['fps']}', '${r['median']}', '${r['p95']}', '${r['laengster']}', '${r['ueber100']}'])),
            ),
          ),
        if (_results.isNotEmpty) Padding(padding: const EdgeInsets.all(FasanSpace.m), child: Text(tr('perf.note'), style: Theme.of(context).textTheme.bodySmall)),
      ]);
  }

  Widget _stage(BuildContext context) {
    switch (_phases[_phase]) {
      case 'list':
      case 'sync':
        final q = ScanQueue.current ?? ScanQueue(StoreScope.read(context));
        return StoreScope(
          store: _mem,
          child: ListView.builder(
            key: const ValueKey('perf-list'),
            controller: _sc,
            padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
            itemCount: _mem.bills.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: BillTile(bill: _mem.bills[i], queue: q, selecting: false, selected: false, onToggle: () {}, onRetry: () {}, openable: false),
            ),
          ),
        );
      case 'floor':
      case 'shadow':
        final dark = FasanLook.of(context).brightness == Brightness.dark;
        final shadow = _phases[_phase] == 'shadow';
        final fill = FasanLook.of(context).surfaceAlt;
        return ListView.builder(
          key: ValueKey('perf-${_phases[_phase]}'),
          controller: _sc,
          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
          itemCount: 60,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(10), boxShadow: shadow ? FasanShadows.of(2, dark: dark) : null),
              child: SizedBox(height: 62, child: Center(child: Text('Zeile $i'))),
            ),
          ),
        );
      case 'nothumb':
        final q = ScanQueue.current ?? ScanQueue(StoreScope.read(context));
        return StoreScope(
          store: _memNoThumb,
          child: ListView.builder(
            key: const ValueKey('perf-nothumb'),
            controller: _sc,
            padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
            itemCount: _memNoThumb.bills.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: BillTile(bill: _memNoThumb.bills[i], queue: q, selecting: false, selected: false, onToggle: () {}, onRetry: () {}, openable: false),
            ),
          ),
        );
      case 'items':
        final b = _itemsDoc;
        return ListView.builder(
          key: const ValueKey('perf-items'),
          controller: _sc,
          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
          itemCount: b.its.length,
          itemBuilder: (_, i) {
            return _itemRow(context, b, b.its[i]);
          },
        );
      case 'posten':
        return ListView.builder(
          key: const ValueKey('perf-posten'),
          controller: _sc,
          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
          itemCount: _flat.length,
          itemBuilder: (_, i) {
            final (b, it) = _flat[i];
            if (it != null) return _itemRow(context, b, it);
            return SizedBox(
              height: 40,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${b.purpose} · ${b.date}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall)),
              ),
            );
          },
        );
      default:
        return const Center(child: Icon(Icons.speed_rounded, size: 64));
    }
  }

  Widget _itemRow(BuildContext context, Bill b, BillItem it) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(FasanLook.of(context).radius * 0.5), border: Border.fromBorderSide(fillSide(context, it.fill))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: ItemTitle(it, maxLines: 1)), const SizedBox(width: FasanSpace.m), Money(it.amount)]),
            Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [Icon(fillIcon(it.fill), size: 16, color: fillColor(context, it.fill)), const SizedBox(width: 6), ShareAvatars(bill: b, item: it)])),
          ]),
        ),
      );
}
