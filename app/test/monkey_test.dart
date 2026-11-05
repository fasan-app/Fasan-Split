// Stress test of the operation: random taps, text, long presses and swipes on the bill screen (and wherever they lead) in six
// window sizes and both languages. Any exception – also a layout overflow – fails with the seed and the step, so it can be replayed.
// Test relay only. MPL-2.0
import 'dart:math';

import 'package:fasan_split/main.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/flow.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Bill _bill() => Bill(
      id: 'm',
      created: DateTime(2026, 11, 5),
      purpose: 'Abendessen im Restaurant mit sehr langem Namen, damit Zeilen umbrechen müssen',
      total: 5480,
      items: [
        for (final (i, n) in ['Flammkuchen', 'Apfelschorle 0,4 l mit einem wirklich sehr langen Namen', 'Weizen', 'Salat', 'Espresso', 'Tiramisu'].indexed)
          BillItem(name: n, amount: 500 + i * 230, qty: i == 4 ? 2 : 1, sure: i != 3),
      ],
      people: [Person('Anna', 0), Person('Jo', 1), Person('Mia', 2)],
    );

final _texts = ['', '0', '12,50', '-198', 'abc', '1e9', '999999999999', 'Ä' * 40, '😀', ' ', '1,5,5', '0,001', '−7'];

/// One random action; returns a description for the failure message.
Future<String> _act(WidgetTester tester, Random r) async {
  final taps = find.byWidgetPredicate((w) => (w is InkWell && w.onTap != null) || w is IconButton || w is TextButton || w is FilledButton || w is ActionChip || w is InputChip || w is FasanPersonChip).hitTestable();
  final fields = find.byType(TextField).hitTestable();
  final roll = r.nextInt(100);
  if (roll < 58 && taps.evaluate().isNotEmpty) {
    final n = taps.evaluate().length, i = r.nextInt(n);
    final w = taps.at(i).evaluate().first.widget;
    await tester.tap(taps.at(i), warnIfMissed: false);
    return 'tap #$i of $n (${w.runtimeType})';
  }
  if (roll < 78 && fields.evaluate().isNotEmpty) {
    final n = fields.evaluate().length, i = r.nextInt(n), t = _texts[r.nextInt(_texts.length)];
    await tester.enterText(fields.at(i), t);
    return 'text "$t" in field #$i of $n';
  }
  if (roll < 86 && taps.evaluate().isNotEmpty) {
    final i = r.nextInt(taps.evaluate().length);
    await tester.longPress(taps.at(i), warnIfMissed: false);
    return 'long press #$i';
  }
  if (roll < 94) {
    final items = find.byType(Dismissible).hitTestable();
    if (items.evaluate().isNotEmpty) {
      final i = r.nextInt(items.evaluate().length);
      await tester.drag(items.at(i), Offset(r.nextBool() ? -500 : 500, 0), warnIfMissed: false);
      return 'swipe item #$i';
    }
  }
  if (roll < 98) {
    await tester.fling(find.byType(Scrollable).first, Offset(0, r.nextBool() ? -300 : 300), 800, warnIfMissed: false);
    return 'scroll';
  }
  await tester.binding.handlePopRoute(); // system back: closes a sheet or leaves the screen
  return 'back';
}

void main() {
  const sizes = <String, Size>{
    'phone-small': Size(360, 640),
    'phone': Size(412, 915),
    'phone-landscape': Size(915, 412),
    'tablet': Size(800, 1280),
    'desktop': Size(1280, 800),
    'desktop-wide': Size(1920, 1080),
  };
  for (final lang in ['en', 'de']) {
    for (final e in sizes.entries) {
      testWidgets('Zufallsbedienung ${e.key} $lang (3 Läufe à 90 Schritte)', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = e.value * 2.0;
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        // keep the full error reports (the exception alone does not say which widget overflowed)
        final seen = <FlutterErrorDetails>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          seen.add(d);
          prev?.call(d);
        };
        addTearDown(() => FlutterError.onError = prev);
        for (var seed = 1; seed <= 3; seed++) {
          final r = Random(seed * 31 + e.key.length + (lang == 'de' ? 7 : 0));
          final b = _bill();
          final store = BillStore.memory()
            ..onboarded = true
            ..language = lang;
          store.upsert(b);
          await tester.pumpWidget(SplitApp(store: store, ui: FasanController(settings: const FasanSettings(reduceMotion: true)), home: ReviewScreen(bill: b)));
          await tester.pumpAndSettle();
          for (var step = 0; step < 90; step++) {
            final what = await _act(tester, r);
            await tester.pump(const Duration(milliseconds: 60));
            await tester.pump(const Duration(milliseconds: 400));
            final ex = tester.takeException();
            if (ex != null) {
              final detail = seen.isEmpty ? '$ex' : seen.last.toDiagnosticsNode().toStringDeep().split('\n').where((l) => l.contains('.dart') || l.contains('overflowed') || l.contains('creator') || l.contains('relevant')).take(12).join('\n');
              fail('${e.key} $lang seed $seed step $step: $what\n$detail');
            }
            // the model stays consistent whatever was tapped
            for (final it in b.its) {
              for (final k in it.shares.keys) {
                expect(k >= 0 && k < b.ps.length, isTrue, reason: '${e.key} $lang seed $seed step $step ($what): share of a person that is not there');
              }
              expect(it.amount.abs() < 1 << 50, isTrue);
              expect(it.qty >= 1, isTrue, reason: '${e.key} $lang seed $seed step $step ($what): quantity ${it.qty}');
            }
            for (final k in b.paid.keys) {
              expect(k >= 0 && k < b.ps.length, isTrue, reason: '${e.key} $lang seed $seed step $step ($what): payer index $k');
            }
            if (b.payer != null) expect(b.payer! < b.ps.length, isTrue, reason: '${e.key} $lang seed $seed step $step ($what): payer ${b.payer}');
          }
          // leave everything open: pop all the way back so the next run starts clean
          for (var i = 0; i < 6; i++) {
            await tester.binding.handlePopRoute();
            await tester.pump(const Duration(milliseconds: 300));
          }
          tester.takeException();
        }
      }, timeout: const Timeout(Duration(minutes: 6)));
    }
  }
}
