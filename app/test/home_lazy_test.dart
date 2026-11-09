// SPDX-License-Identifier: MPL-2.0
// Messung 08.11. (Firefox): die Liste baute einen ganzen Gruppenblock als EIN Kind und malte alle Kacheln in jedem Bild. Jetzt entstehen nur
// die Kacheln in Bildschirmnähe; die Kosten wachsen nicht mit der Zahl der Rechnungen. MPL-2.0
import 'package:fasan_core/bill.dart';
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/bill_tile.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Rechnungsliste baut nur Kacheln in Bildschirmnähe, Scrollen holt weitere', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    const tilt = MethodChannel('app.fasan.ui/tilt');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, null));
    final store = BillStore.memory([
      for (var i = 0; i < 60; i++)
        Bill(id: 'b$i', created: DateTime(2026, 11, 2), purpose: 'Bon Nr. $i', total: 1000, items: [BillItem(name: 'Posten', amount: 1000)], group: 'Beispielstadt')..order = i.toDouble(),
    ])
      ..onboarded = true;
    final q = ScanQueue(store, recognize: (_) => const Stream.empty());
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ui, home: HomeScreen(queue: q)));
    await tester.pump(const Duration(milliseconds: 300));
    List<String> names() => tester.widgetList<BillTile>(find.byType(BillTile)).map((t) => t.bill.purpose).toList();
    final first = names();
    expect(first.length, greaterThan(3), reason: 'sichtbare Kacheln sind da');
    expect(first.length, lessThan(30), reason: 'nicht alle 60: nur die in Bildschirmnähe (${first.length} gebaut)');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -20000));
    await tester.pump(const Duration(milliseconds: 300));
    final later = names();
    expect(later.length, lessThan(30));
    expect(later.where((n) => !first.contains(n)).length, greaterThan(3), reason: 'Scrollen holt andere Kacheln: $first → $later');
  });
}
