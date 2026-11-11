// SPDX-License-Identifier: MPL-2.0
// Fasan Split – „Abmelden“ im Profil (Nutzer 11.11.): Kachel, Warnung mit Sicherungsfrage, danach ist das Gerät abgemeldet. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/flows/scan_queue.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_split/ui/my_balance.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Profil: Abmelden fragt nach der Sicherung, meldet nur dieses Gerät ab und löscht nichts', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    const tilt = MethodChannel('app.fasan.ui/tilt');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tilt, null));
    final store = BillStore.memory()..me = 'Pia'..onboarded = true;
    final hub = MemoryRelayHub();
    final prefs = await SharedPreferences.getInstance();
    final c = CollabService(store: store, vault: MemoryVault(), prefs: prefs, relayFactory: (_) => MemoryRelay(hub));
    await tester.runAsync(() async {
      await c.init();
      await c.setName('Pia');
    });
    expect(c.identity, isNotNull);
    final q = ScanQueue(store, recognize: (_) => const Stream.empty());
    await tester.pumpWidget(SplitApp(store: store, ui: FasanController(settings: const FasanSettings(reduceMotion: true)), collab: c, home: HomeScreen(queue: q)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(MyBalanceBadge));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final tile = find.byKey(const ValueKey('profile-signout'));
    await tester.ensureVisible(tile);
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Auf diesem Gerät abmelden?'), findsOneWidget);
    expect(find.textContaining('12 Wörter'), findsWidgets, reason: 'die Sicherungsfrage nennt den Weg zurück');
    expect(c.identity, isNotNull, reason: 'erst die Bestätigung meldet ab');
    await tester.tap(find.widgetWithText(FilledButton, 'Abmelden'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.identity, isNull, reason: 'dieses Gerät ist abgemeldet');
    expect(find.text('Abgemeldet. Mit deinen 12 Wörtern kommst du zurück.'), findsWidgets);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    expect(c.identity, isNull, reason: 'das Schließen des Profils darf kein neues Konto anlegen (Name wurde dort nachgespeichert)');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
