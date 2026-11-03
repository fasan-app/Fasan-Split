// Widget tests of the collaboration screens. They use MemoryRelay only: no public relay is contacted. MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/collab_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryRelayHub hub;
  late BillStore store;
  late CollabService svc;

  setUp(() {
    hub = MemoryRelayHub();
    store = BillStore.memory();
    svc = CollabService(store: store, vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
  });

  tearDown(() => svc.dispose());

  /// The screen inside the same scopes as in main.dart.
  Widget host(Widget child) => CollabScope(service: svc, child: StoreScope(store: store, child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      )));

  testWidgets('Konto zeigt ohne Schlüssel den Hinweis und speichert den Namen', (tester) async {
    await tester.pumpWidget(host(const AccountScreen()));
    expect(find.text('Noch kein Konto. Es entsteht, sobald du eine Gruppe teilst oder beitrittst.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Anna');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(svc.identity?.name, 'Anna');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Einladung erzeugt einen Link mit QR-Code, nur für den Admin', (tester) async {
    final g = await svc.createGroup('Hütte');
    await tester.pumpWidget(host(InviteScreen(group: g)));
    expect(find.text('Einladung erstellen'), findsOneWidget);
    await tester.tap(find.text('Einladung erstellen'));
    await tester.pump();
    expect(find.textContaining('fasansplit://join#'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Notiz anlegen, schreiben, und sie steht in der Gruppe', (tester) async {
    final g = await svc.createGroup('Hütte');
    await tester.pumpWidget(host(NotesScreen(group: g)));
    await tester.tap(find.text('Neue Notiz'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Einkauf');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // now in the editor: the second TextField is the body
    await tester.enterText(find.byType(TextField).last, 'Brot und Butter');
    await tester.pump(const Duration(milliseconds: 500)); // debounce of the editor
    final notes = svc.notes(g);
    expect(notes.length, 1);
    expect(notes.first.title, 'Einkauf');
    expect(notes.first.text, contains('Brot und Butter'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Chat: Nachricht senden erscheint in der Liste', (tester) async {
    final g = await svc.createGroup('Hütte');
    await tester.pumpWidget(host(ChatScreen(group: g)));
    expect(find.text('Noch keine Nachricht. Schreib die erste.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hallo');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(find.text('Hallo'), findsOneWidget);
    expect(svc.messages(g).single.text, 'Hallo');
    await tester.pump(const Duration(seconds: 1));
  });
}
