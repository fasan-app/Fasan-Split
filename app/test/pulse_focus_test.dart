// SPDX-License-Identifier: MPL-2.0
// Fasan Split – PulseOnFocus (ui/pulse_focus.dart): the element is scrolled to the middle, pulses once and then costs nothing. MPL-2.0
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/pulse_focus.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wird in die Mitte gescrollt, pulsiert einmal und ist danach weg', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SplitApp(
      store: BillStore.memory()..onboarded = true,
      ui: FasanController(settings: const FasanSettings(reduceMotion: false)),
      home: Scaffold(
        body: ListView(children: [
          Column(children: [
            for (var i = 0; i < 40; i++) PulseOnFocus(key: ValueKey('p$i'), active: i == 30, child: SizedBox(height: 60, child: Text('Zeile $i'))),
          ]),
        ]),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // scroll done
    final box = tester.getRect(find.text('Zeile 30'));
    expect(box.center.dy, closeTo(400, 120), reason: 'in the middle of the 800 px high screen, not at an edge');
    expect(find.byType(DecoratedBox), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('p30')), matching: find.byType(AnimatedBuilder)), findsNothing, reason: 'nothing keeps running after the pulse');
  });
}
