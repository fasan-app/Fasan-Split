// SPDX-License-Identifier: MPL-2.0
// Fasan Split – what the first minutes after the start looked like (Nutzer 08.11.: „ruckelt, legt sich erst langsam nach längerer Zeit“).
// The performance test measures a warm, idle app; this recorder runs from the start of the app and writes one record per 5 seconds
// for the first 10 minutes: frames, slow frames, the longest frame, how late a 50 ms timer fired (a blocked screen thread shows
// there even when no frame is drawn) and what the expensive crypto calls cost in that window (CryptoStats). In memory only, shown in
// the performance report; nothing leaves the phone. FrameTiming: api.flutter.dev/flutter/dart-ui/FrameTiming-class.html. MPL-2.0
import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../collab/crypto.dart' show cryptoStats;

abstract final class StartTimeline {
  static const _windowMs = 5000, _maxWindows = 120;
  static final Stopwatch _clock = Stopwatch();
  static final List<Map<String, Object>> _done = [];
  static bool _started = false;
  static Timer? _timer;
  static int _index = 0, _frames = 0, _over33 = 0, _over100 = 0, _longestFrameUs = 0, _lateMaxMs = 0, _late100 = 0;
  static int _lastExpected = 0, _verifies = 0, _verifyUs = 0, _signs = 0, _signUs = 0, _ecdhs = 0, _ecdhUs = 0;

  static void start() {
    if (_started) return;
    _started = true;
    _clock.start();
    _lastExpected = 50;
    SchedulerBinding.instance.addTimingsCallback((ts) {
      for (final t in ts) {
        _roll();
        final us = t.totalSpan.inMicroseconds;
        _frames++;
        if (us > 33400) _over33++;
        if (us > 100000) _over100++;
        if (us > _longestFrameUs) _longestFrameUs = us;
      }
    });
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _roll();
      final now = _clock.elapsedMilliseconds;
      final late = now - _lastExpected; // how much later than planned this tick ran
      _lastExpected = now + 50;
      if (late > _lateMaxMs) _lateMaxMs = late;
      if (late > 100) _late100++;
      if (_done.length >= _maxWindows) {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  /// Closes the finished 5-second windows (also empty ones).
  static void _roll() {
    final idx = _clock.elapsedMilliseconds ~/ _windowMs;
    while (_index < idx && _done.length < _maxWindows) {
      double ms(int us) => (us / 100).round() / 10;
      _done.add({
        'ab_s': _index * _windowMs ~/ 1000,
        'bilder': _frames,
        'ueber33': _over33,
        'ueber100': _over100,
        'laengstesBildMs': ms(_longestFrameUs),
        'timerVerspaetungMaxMs': _lateMaxMs,
        'timerUeber100': _late100,
        'pruefungen': cryptoStats.verifies - _verifies,
        'pruefungMs': ms(cryptoStats.verifyUs - _verifyUs),
        'signaturen': cryptoStats.signs - _signs,
        'signaturMs': ms(cryptoStats.signUs - _signUs),
        'schluesseltausch': cryptoStats.ecdhs - _ecdhs,
        'schluesseltauschMs': ms(cryptoStats.ecdhUs - _ecdhUs),
      });
      _verifies = cryptoStats.verifies;
      _verifyUs = cryptoStats.verifyUs;
      _signs = cryptoStats.signs;
      _signUs = cryptoStats.signUs;
      _ecdhs = cryptoStats.ecdhs;
      _ecdhUs = cryptoStats.ecdhUs;
      _frames = _over33 = _over100 = _longestFrameUs = _lateMaxMs = _late100 = 0;
      _index++;
    }
  }

  /// Seconds since the app started.
  static int get seconds => _clock.elapsedMilliseconds ~/ 1000;

  /// The finished windows, oldest first.
  static List<Map<String, Object>> windows() {
    _roll();
    return List.unmodifiable(_done);
  }

  /// One line per window with at least one stall (timer over 100 ms or a frame over 100 ms), for the short view.
  static int get stalledWindows => windows().where((w) => (w['timerUeber100']! as int) > 0 || (w['ueber100']! as int) > 0).length;
}
