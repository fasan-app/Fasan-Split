// SPDX-License-Identifier: MPL-2.0
// Fasan Split – build and raster time of every frame (Nutzer 08.11.: Rechnungsliste ruckelt in Firefox/Safari, Ursache offen).
// FrameTiming.buildDuration = Dart builds the widget tree, rasterDuration = the engine draws it (api.flutter.dev/flutter/
// dart-ui/FrameTiming-class.html). The two numbers tell whether a slow frame is „too much to build“ or „too much to draw“.
// Kept in memory only (last 600 frames), shown in the diagnosis log; nothing leaves the phone. In the browser `?perf=1` also
// prints one line per second to the console (measurement script tool/e2e/safari.js reads it). MPL-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

abstract final class FrameStats {
  static final List<int> _build = [], _raster = [], _span = [];
  static bool _started = false;

  /// [print] true: one console line per second (`FRAMESTAT {json}`) for the last second, then the window starts again.
  static void start({bool print = false}) {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback((ts) {
      for (final t in ts) {
        _build.add(t.buildDuration.inMicroseconds);
        _raster.add(t.rasterDuration.inMicroseconds);
        _span.add(t.totalSpan.inMicroseconds);
      }
      for (final l in [_build, _raster, _span]) {
        if (l.length > 600) l.removeRange(0, l.length - 600);
      }
    });
    if (print) {
      Timer.periodic(const Duration(seconds: 1), (_) {
        if (_span.isEmpty) return;
        debugPrint('FRAMESTAT ${jsonEncode(summary())}');
        _build.clear();
        _raster.clear();
        _span.clear();
      });
    }
  }

  static Map<String, Object> _q(List<int> l) {
    if (l.isEmpty) return const {};
    final s = [...l]..sort();
    double ms(int us) => (us / 100).round() / 10;
    return {'p50': ms(s[s.length ~/ 2]), 'p95': ms(s[(s.length * 0.95).floor().clamp(0, s.length - 1)]), 'max': ms(s.last), 'ueber16': l.where((x) => x > 16700).length};
  }

  /// Like [summary], then forgets the frames (the performance test measures one phase at a time).
  static Map<String, Object> take() {
    final r = summary();
    _build.clear();
    _raster.clear();
    _span.clear();
    return r;
  }

  /// Milliseconds of the last (up to 600) frames: build, raster, whole span.
  static Map<String, Object> summary() => {'n': _span.length, 'build': _q(_build), 'raster': _q(_raster), 'gesamt': _q(_span)};
}
