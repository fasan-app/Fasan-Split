import 'package:fasan_split/perf/perf_governor.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> _ms(int n, double ms) => List.filled(n, (ms * 1000).round());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('classifyFrames: Schwellen und zu wenige Bilder', () {
    expect(classifyFrames(_ms(100, 8)), PerfTier.good);
    expect(classifyFrames(_ms(100, 24)), PerfTier.good);
    expect(classifyFrames(_ms(100, 30)), PerfTier.slow);
    expect(classifyFrames(_ms(100, 45)), PerfTier.slow);
    expect(classifyFrames(_ms(100, 80)), PerfTier.veryslow);
    expect(classifyFrames(_ms(5, 200)), PerfTier.good, reason: 'too few frames');
    // a few hitches do not count (p75), a mostly slow run does
    expect(classifyFrames([..._ms(90, 10), ..._ms(10, 200)]), PerfTier.good);
    expect(classifyFrames([..._ms(40, 10), ..._ms(60, 60)]), PerfTier.veryslow);
  });

  test('Governor: Aufwärmen zählt nicht, langsam senkt Stufe, wird gemerkt, nie besser in der Sitzung', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime(2026, 11, 5);
    final ui = SplitController();
    final g = PerfGovernor(ui, prefs, now: () => now)..start();
    expect(ui.level, FasanPowerLevel.full);
    g.feed(_ms(10, 300)); // warm-up: ignored
    expect(ui.tier, PerfTier.good);
    g.feed(_ms(19, 30));
    expect(ui.tier, PerfTier.good, reason: 'too few frames yet');
    g.feed(_ms(1, 30));
    expect(ui.tier, PerfTier.slow);
    expect(ui.level, FasanPowerLevel.save, reason: 'blur, grain and moving background off');
    g.feed(_ms(90, 5)); // fast now (effects are off): the tier stays
    expect(ui.tier, PerfTier.slow);
    g.dispose();

    // next start: remembered, no probing needed
    final ui2 = SplitController();
    final g2 = PerfGovernor(ui2, prefs, now: () => now)..start();
    expect(ui2.tier, PerfTier.slow);
    g2.dispose();

    // after the time-to-live: probe again with full effects
    now = now.add(const Duration(days: 15));
    final ui3 = SplitController();
    final g3 = PerfGovernor(ui3, prefs, now: () => now)..start();
    expect(ui3.tier, PerfTier.good);
    g3.feed(_ms(10 + 20, 70));
    expect(ui3.tier, PerfTier.veryslow);
    expect(ui3.settings.reduceMotion, isTrue);
    g3.dispose();
  });

  test('Modus: „voll“ und „leicht“ erzwingen, Wechsel löscht das Gemerkte', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final ui = SplitController();
    final g = PerfGovernor(ui, prefs)..start();
    await g.setMode(PerfMode.light);
    expect(ui.tier, PerfTier.slow);
    g.feed(_ms(200, 5));
    expect(ui.tier, PerfTier.slow, reason: 'forced');
    await g.setMode(PerfMode.full);
    expect(ui.tier, PerfTier.good);
    g.feed(_ms(200, 90));
    expect(ui.tier, PerfTier.good, reason: 'forced full effects, no measuring');
    await g.setMode(PerfMode.auto);
    g.feed(_ms(40, 90));
    expect(ui.tier, PerfTier.veryslow);
    g.dispose();
  });

  test('„Weniger Bewegung“ des Reglers wird nie als Wahl des Nutzers gespeichert', () {
    FasanSettings? saved;
    final ui = SplitController(onChanged: (s) => saved = s);
    ui.tier = PerfTier.veryslow;
    ui.settings = ui.settings.copyWith(haptics: false); // e.g. a toggle in the settings
    expect(saved!.reduceMotion, isFalse);
    expect(saved!.haptics, isFalse);
    expect(ui.settings.reduceMotion, isTrue, reason: 'still reduced in the view');
  });
}
