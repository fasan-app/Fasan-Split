// MarqueeText: a long single line fades out, scrolls once sideways and springs back; with reduced motion it stays still. MPL-2.0
import 'package:fasan_split/ui/marquee_text.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduce = false}) => FasanScope(
      controller: FasanController(settings: FasanSettings(reduceMotion: reduce)),
      child: MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 120, child: child)))),
    );

double _dx(WidgetTester tester) {
  final t = tester.widget<Transform>(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform)).first);
  return -t.transform.getTranslation().x;
}

void main() {
  const long = 'Gin Tonico Martini Bianco mit Zitrone und viel Eis';

  testWidgets('passt der Text, bleibt es ein normaler Text ohne Überblendung', (tester) async {
    await tester.pumpWidget(_host(const MarqueeText('Pizza')));
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('Pizza'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('langer Text: blendet am Rand aus, läuft einmal langsam zur Seite und federt zurück', (tester) async {
    await tester.pumpWidget(_host(const MarqueeText(long)));
    expect(find.byType(ShaderMask), findsOneWidget, reason: 'fades out at the edge');
    expect(_dx(tester), 0);
    await tester.pump(const Duration(milliseconds: 3100)); // waits (1.4 s plus a small stagger), then starts
    await tester.pump(const Duration(milliseconds: 800));
    final mid = _dx(tester);
    expect(mid, greaterThan(5), reason: 'moving sideways');
    await tester.pump(const Duration(milliseconds: 3000)); // arrived
    final end = _dx(tester);
    expect(end, greaterThan(mid));
    await tester.pump(const Duration(milliseconds: 700)); // hold
    // spring back: passes through 0 (may overshoot a little) and comes to rest at 0
    var minSeen = double.infinity;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      minSeen = minSeen < _dx(tester) ? minSeen : _dx(tester);
    }
    expect(_dx(tester).abs(), lessThan(0.6), reason: 'back at the start');
    expect(minSeen, lessThan(0.5), reason: 'the spring reaches the start');
    expect(tester.takeException(), isNull);
  });

  testWidgets('mit „Animationen entfernen“ läuft nichts von selbst, auch nicht beim Antippen', (tester) async {
    await tester.pumpWidget(_host(const MarqueeText(long), reduce: true));
    expect(find.byType(ShaderMask), findsOneWidget, reason: 'still fades out (static)');
    await tester.pump(const Duration(seconds: 4));
    expect(_dx(tester), 0);
    await tester.tap(find.byType(MarqueeText));
    await tester.pump(const Duration(seconds: 2));
    expect(_dx(tester), 0);
  });

  testWidgets('Gesten gehören der Zeile: Antippen und Wischen auf einem langen Namen erreichen den Eltern-Widget; Volltext in der Semantik', (tester) async {
    var taps = 0, drags = 0;
    await tester.pumpWidget(_host(GestureDetector(
      onTap: () => taps++,
      onHorizontalDragUpdate: (_) => drags++,
      child: const MarqueeText(long),
    )));
    await tester.tap(find.byType(MarqueeText));
    expect(taps, 1, reason: 'a tap on a long name is the row\'s tap');
    await tester.drag(find.byType(MarqueeText), const Offset(-80, 0));
    expect(drags, greaterThan(0), reason: 'a swipe on a long name is the row\'s swipe');
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel(long), findsOneWidget, reason: 'screen readers get the whole text');
    handle.dispose();
    await tester.pumpWidget(const SizedBox()); // leave no timer behind
    await tester.pump();
  });

  testWidgets('Zeichenfolgen mit Extremen brechen nichts: leer, sehr lang, Emoji, rechts nach links', (tester) async {
    for (final t in ['', 'x' * 400, '😀' * 80, 'اختبار نص طويل جدا جدا جدا جدا جدا جدا جدا']) {
      await tester.pumpWidget(_host(MarqueeText(t)));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(tester.takeException(), isNull, reason: 'text of ${t.length} characters');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
