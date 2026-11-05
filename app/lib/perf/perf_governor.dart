// Fasan Split – performance probe and effect governor. MPL-2.0
//
// Problem (Nutzer 05.11.): in the browser and on older phones the glass blur, the moving background and the long-text
// animations make the app slow. The app cannot know the device, so it measures it: every session starts with the
// effects the user chose, the first frames are timed (FrameTiming.totalSpan, api.flutter.dev/flutter/dart-ui/FrameTiming
// /totalSpan.html) and the effects are reduced at once when the frames are too slow. The result is remembered, so the
// next start begins with the right level and does not need to stutter first.
//
// Tiers (own thresholds, nicht gegen Studien geprüft; 60 Hz budget is 16.7 ms):
//   good      p75 of the frame time ≤ 24 ms  → everything as chosen
//   slow      p75 ≤ 45 ms                    → power level „save“ of fasan_ui: no blur, no grain, no moving background
//   veryslow  above                          → „save“ plus „less motion“ (no marquee, no springs, no hero effects)
// The measurement never raises the tier within a session (the effects are off, so there are no new frames to judge by);
// a stored tier expires after [tierTtl], then the next session probes with full effects again. The user can force a mode.
import 'dart:async';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PerfTier { good, slow, veryslow }

/// What the user chose in the settings: automatic (default), always full effects, always light.
enum PerfMode { auto, full, light }

/// Classifies frame times (microseconds, build + raster). Pure function, tested without a device.
PerfTier classifyFrames(List<int> micros) {
  if (micros.length < 12) return PerfTier.good; // too few frames to judge
  final s = [...micros]..sort();
  final p75 = s[((s.length - 1) * 0.75).round()] / 1000;
  if (p75 <= 24) return PerfTier.good;
  if (p75 <= 45) return PerfTier.slow;
  return PerfTier.veryslow;
}

/// The controller of the app: the same as [FasanController], plus a floor for the effect level and the motion that the
/// governor sets. Nothing of this is stored in the user's settings.
class SplitController extends FasanController {
  SplitController({super.settings, super.onChanged});

  PerfTier _tier = PerfTier.good;
  PerfTier get tier => _tier;

  set tier(PerfTier t) {
    if (t == _tier) return;
    _tier = t;
    notifyListeners();
  }

  @override
  FasanPowerLevel get level => _tier == PerfTier.good ? super.level : (super.level == FasanPowerLevel.maximum ? FasanPowerLevel.maximum : FasanPowerLevel.save);

  @override
  FasanSettings get settings => _tier == PerfTier.veryslow ? super.settings.copyWith(reduceMotion: true) : super.settings;

  /// The „less motion“ of the governor is a view only: when someone saves settings read from [settings], it must not be
  /// stored as the user's own choice.
  @override
  set settings(FasanSettings s) {
    super.settings = _tier == PerfTier.veryslow && s.reduceMotion ? s.copyWith(reduceMotion: super.settings.reduceMotion) : s;
  }
}

class PerfGovernor {
  PerfGovernor(this.ui, this.prefs, {this.warmup = 10, this.window = 40, this.minFrames = 20, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SplitController ui;
  final SharedPreferences prefs;
  /// Frames skipped at the start, frames kept (rolling), frames needed before judging. A slow device makes 6 frames per
  /// second, so [warmup] + [minFrames] frames must not take longer than a few seconds.
  final int warmup, window, minFrames;
  final DateTime Function() _now;

  static const tierTtl = Duration(days: 14);
  static const _kMode = 'perf.mode', _kTier = 'perf.tier', _kAt = 'perf.at';

  final List<int> _frames = [];
  int _seen = 0;
  bool _running = false;

  PerfMode get mode => PerfMode.values.firstWhere((m) => m.name == prefs.getString(_kMode), orElse: () => PerfMode.auto);

  Future<void> setMode(PerfMode m) async {
    await prefs.setString(_kMode, m.name);
    await prefs.remove(_kTier);
    await prefs.remove(_kAt);
    _frames.clear();
    _seen = 0;
    ui.tier = PerfTier.good;
    _apply();
  }

  /// Starts at app start: takes the remembered tier, and probes unless the user forced a mode.
  void start() {
    _apply();
  }

  void _apply() {
    switch (mode) {
      case PerfMode.full:
        ui.tier = PerfTier.good;
      case PerfMode.light:
        ui.tier = PerfTier.slow;
      case PerfMode.auto:
        final at = DateTime.tryParse(prefs.getString(_kAt) ?? '');
        final stored = PerfTier.values.firstWhere((t) => t.name == prefs.getString(_kTier), orElse: () => PerfTier.good);
        if (at != null && _now().difference(at) < tierTtl && stored != PerfTier.good) {
          ui.tier = stored; // known slow device: no probing with effects, it would stutter again
        } else {
          ui.tier = PerfTier.good;
          _listen();
        }
    }
  }

  void _listen() {
    if (_running) return;
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(onTimings);
  }

  void _stop() {
    if (!_running) return;
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
  }

  /// Public for tests: feed frame timings.
  void onTimings(List<FrameTiming> timings) => feed([for (final t in timings) t.totalSpan.inMicroseconds]);

  void feed(List<int> micros) {
    if (mode != PerfMode.auto) return _stop();
    for (final m in micros) {
      if (_seen++ < warmup) continue; // shader compile, first layout: not the device's speed
      _frames.add(m);
      if (_frames.length > window) _frames.removeAt(0);
    }
    if (_frames.length < minFrames) return;
    final t = classifyFrames(_frames);
    if (t.index > ui.tier.index) {
      ui.tier = t; // only ever worse within a session
      prefs.setString(_kTier, t.name);
      prefs.setString(_kAt, _now().toIso8601String());
      _frames.clear();
    } else if (_seen > warmup + window * 4) {
      _stop(); // four windows were fine: the device is fast enough, stop measuring
    }
  }

  void dispose() => _stop();
}
