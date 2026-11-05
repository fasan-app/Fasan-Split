// Language switch (Settings → Sprache · Language): in English no German text may be left on the main screens, and in German no
// English leftovers of the simple kind. Collects every visible Text, field label/hint, tooltip. Test relay only. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/model/bill.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/assign.dart';
import 'package:fasan_split/ui/collab_ui.dart';
import 'package:fasan_split/ui/flow.dart';
import 'package:fasan_split/ui/home.dart';
import 'package:fasan_split/ui/my_balance.dart';
import 'package:fasan_split/ui/onboarding.dart';
import 'package:fasan_split/ui/settings_screen.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// German words and letters that must not appear in English mode.
final _german = RegExp(
    r'[äöüßÄÖÜ]|\b(und|nicht|oder|für|mit|von|wird|werden|dein|deine|deinen|keine|noch|ohne|einen|eine|einer|alle|jede|Bon|Bons|Rechnung|Rechnungen|Gruppe|Gruppen|Summe|Posten|Freunde|Freund|bezahlt|Einstellungen|Weiter|Zurück|Abbrechen|Löschen|Neue|Wer|Wie|Wo|Aussehen|Nachricht|Notiz|Notizen|Mitglieder|Einladen|Einladung|Speichern|Fertig|Übersicht|Ergebnis|schreib|Tippe|tippe|heute|gestern)\b');

List<String> _texts(WidgetTester tester) {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final s = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (s.trim().isNotEmpty) out.add(s);
  }
  for (final e in find.byType(TextField).evaluate()) {
    final d = (e.widget as TextField).decoration;
    for (final s in [d?.labelText, d?.hintText, d?.helperText, d?.errorText]) {
      if (s != null && s.trim().isNotEmpty) out.add(s);
    }
  }
  for (final e in find.byType(Tooltip).evaluate()) {
    final m = (e.widget as Tooltip).message;
    if (m != null && m.trim().isNotEmpty) out.add(m);
  }
  return out;
}

Bill _demo() => Bill(id: 'd', created: DateTime(2026, 11, 5), purpose: 'Dinner', total: 3000, checked: true, items: [
      BillItem(name: 'Pizza', amount: 1800),
      BillItem(name: 'Wine', amount: 1200),
    ], people: [Person('Ann', 0), Person('Bo', 1)])
  ..payer = 0;

void main() {
  final screens = <String, Widget Function(Bill)>{
    'onboarding': (_) => const OnboardingScreen(),
    'home': (_) => const HomeScreen(),
    'review': (b) => ReviewScreen(bill: b),
    'assign-focus': (b) => AssignScreen(bill: b, initialMode: AssignMode.focus),
    'assign-list': (b) => AssignScreen(bill: b, initialMode: AssignMode.list),
    'pay': (b) => PayScreen(bill: b),
    'result': (b) => ResultScreen(bill: b),
    'settings': (_) => const SettingsScreen(),
  };
  for (final e in screens.entries) {
    testWidgets('Englisch: ${e.key} ohne deutsche Reste', (tester) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final store = BillStore.memory([_demo()])
        ..onboarded = e.key != 'onboarding'
        ..language = 'en';
      final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
      await tester.pumpWidget(SplitApp(store: store, ui: ui, home: e.value(_demo())));
      await tester.pumpAndSettle();
      final all = _texts(tester);
      expect(all.length, greaterThan(3), reason: 'the test must really see texts on ${e.key}');
      final bad = [for (final s in all) if (_german.hasMatch(s)) s];
      expect(bad, isEmpty, reason: 'German text in English mode on ${e.key}');
    });
  }

  testWidgets('Umschalter: Einstellung wirkt sofort, auch gegen die Systemsprache', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final store = BillStore.memory()..onboarded = true;
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ui, home: const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Einstellungen'), findsOneWidget, reason: 'system language is German');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(store.language, 'en');
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Einstellungen'), findsNothing);
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(find.text('Einstellungen'), findsOneWidget);
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(store.language, 'system');
  });

  testWidgets('Englisch: Chat, Notizen, Mitglieder, Konto ohne deutsche Reste', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final hub = MemoryRelayHub();
    final store = BillStore.memory()
      ..onboarded = true
      ..language = 'en';
    final svc = CollabService(store: store, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    addTearDown(svc.dispose);
    final g = await svc.createGroup('Trip');
    svc.sendMessage(g, 'Hello');
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    final pages = <String, Widget>{
      'chat': ChatScreen(group: g),
      'notes': NotesScreen(group: g),
      'members': MembersScreen(group: g),
      'invite': InviteScreen(group: g),
      'account': const AccountScreen(),
      'profile': const ProfileScreen(),
    };
    for (final p in pages.entries) {
      await tester.pumpWidget(SplitApp(store: store, ui: ui, collab: svc, home: p.value));
      await tester.pumpAndSettle();
      final all = _texts(tester);
      expect(all.length, greaterThan(2), reason: 'the test must really see texts on ${p.key}');
      final bad = [for (final s in all) if (_german.hasMatch(s)) s];
      expect(bad, isEmpty, reason: 'German text in English mode on ${p.key}');
    }
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Gegenprobe: im deutschen Modus findet der Detektor deutschen Text (der Test ist nicht blind)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = BillStore.memory([_demo()])
      ..onboarded = true
      ..language = 'de';
    final ui = FasanController(settings: const FasanSettings(reduceMotion: true));
    await tester.pumpWidget(SplitApp(store: store, ui: ui, home: const SettingsScreen()));
    await tester.pumpAndSettle();
    expect([for (final s in _texts(tester)) if (_german.hasMatch(s)) s].length, greaterThan(3));
  });
}
