// SPDX-License-Identifier: MPL-2.0
// The screen an invitation link opens (Nutzer 05.11.): says who invites to what, what happens, what is wrong with a broken link, whether
// joining really worked, and puts the account safety in front. Test relay only. MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:fasan_split/collab/crypto.dart';
import 'package:fasan_split/collab/group.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/main.dart';
import 'package:fasan_split/state/store.dart';
import 'package:fasan_split/ui/join_screen.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Setup {
  _Setup(this.admin, this.friend, this.store, this.link, this.group);
  final CollabService admin, friend;
  final BillStore store;
  final String link;
  final CollabGroup group;
}

Future<_Setup> _setup(WidgetTester tester, {String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues({'collab.consent': true});
  late CollabService a, b;
  late CollabGroup g;
  late String link;
  final store = BillStore.memory()..language = lang;
  await tester.runAsync(() async {
    final hub = MemoryRelayHub();
    a = CollabService(store: BillStore.memory()..me = 'Pia', vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    g = await a.createGroup('Stadt 26');
    link = g.invitations!.create().link;
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // the ticket is out
    b = CollabService(store: store, vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
  });
  addTearDown(a.dispose);
  addTearDown(b.dispose);
  return _Setup(a, b, store, link, g);
}

Future<void> _pump(WidgetTester tester, _Setup s, String prefill) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox()); // a fresh screen state for every call
  await tester.pumpWidget(SplitApp(store: s.store, ui: FasanController(settings: const FasanSettings(reduceMotion: true)), collab: s.friend, home: JoinScreen(prefill: prefill)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Gültiger Link: sagt wer wohin einlädt, erklärt die Schritte, Beitritt klappt, Status „verbunden“, Konto-Sicherung vorn', (tester) async {
    final s = await _setup(tester);
    await _pump(tester, s, 'Hello! Here is the invitation:\n${s.link}\nSee you there!');
    expect(find.text('You are invited to “Stadt 26”'), findsOneWidget);
    expect(find.textContaining('Valid until'), findsOneWidget);
    expect(find.text('What happens next'), findsOneWidget);
    expect(find.textContaining('no email and no password'), findsOneWidget);
    expect(find.textContaining('end-to-end encrypted'), findsOneWidget);
    expect(find.byKey(const ValueKey('join-link')), findsNothing, reason: 'the long link is not in the way');
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'What should the others call you?'), 'Lena');
    await tester.tap(find.byKey(const ValueKey('join-button')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    expect(find.text('You are in!'), findsOneWidget);
    expect(find.text('You are now a member of “Stadt 26”.'), findsOneWidget);
    expect(find.text('Connected – the others can see you now.'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-safety')), findsOneWidget);
    expect(find.text('Secure your account now'), findsOneWidget);
    expect(find.textContaining('If you close the browser, everything stays'), findsOneWidget);
    expect(find.byKey(const ValueKey('safe-words')), findsOneWidget);
    expect(find.byKey(const ValueKey('safe-backup')), findsOneWidget);
    expect(s.admin.groupByLocalName('Stadt 26')!.session.memberKeys.contains(s.friend.identity!.pub), isTrue, reason: 'the admin sees her');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Abgeschnittener Link: erklärt was fehlt und wie es klappt, kein Beitreten-Knopf, Feld zum Einfügen da', (tester) async {
    final s = await _setup(tester);
    await _pump(tester, s, s.link.substring(0, s.link.length - 12));
    expect(find.textContaining('The link is incomplete'), findsOneWidget);
    expect(find.textContaining('tap the link in the message directly'), findsOneWidget);
    expect(find.byKey(const ValueKey('join-button')), findsNothing);
    expect(find.byKey(const ValueKey('join-link')), findsOneWidget);
    // fixing it: paste the whole link
    await tester.enterText(find.byKey(const ValueKey('join-link')), s.link);
    await tester.pumpAndSettle();
    expect(find.textContaining('The link is incomplete'), findsNothing);
    expect(find.byKey(const ValueKey('join-button')), findsOneWidget);
    expect(find.text('You are invited to “Stadt 26”'), findsOneWidget);
  });

  testWidgets('Kein Link, Müll, abgelaufen: je eine verständliche Meldung, nie ein totes Ende', (tester) async {
    final s = await _setup(tester);
    await _pump(tester, s, '');
    expect(find.textContaining('invitation link is still missing'), findsOneWidget);
    expect(find.byKey(const ValueKey('join-link')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('join-link')), 'https://example.org/hello');
    await tester.pumpAndSettle();
    expect(find.textContaining('not a Fasan Split invitation link'), findsOneWidget);
    final old = Invite(tag: 'a' * 32, secret: Uint8List(32), adminPub: 'b' * 64, relays: ['wss://x.example'], expires: DateTime(2020), name: 'Alt');
    await tester.enterText(find.byKey(const ValueKey('join-link')), old.link);
    await tester.pumpAndSettle();
    expect(find.textContaining('has expired'), findsOneWidget);
    expect(find.byKey(const ValueKey('join-button')), findsNothing);
  });

  testWidgets('Alter Link (v1) und schon Mitglied', (tester) async {
    final s = await _setup(tester);
    final inv = Invite.parse(s.link)!;
    final v1 = base64Url.encode(utf8.encode(jsonEncode({'v': 1, 't': inv.tag, 's': toHex(inv.secret), 'a': inv.adminPub, 'r': inv.relays, 'x': inv.expires.millisecondsSinceEpoch ~/ 1000, 'n': inv.name, 'o': 1, 'k': toHex(inv.groupKey!)}))).replaceAll('=', '');
    await _pump(tester, s, '${Invite.inviteBase}#$v1');
    expect(find.text('You are invited to “Stadt 26”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('join-button')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('You are in!'), findsOneWidget);
    // the same link again: not an error
    await _pump(tester, s, s.link);
    await tester.tap(find.byKey(const ValueKey('join-button')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('You are now a member'), findsOneWidget);
    expect(find.textContaining('Sending did not work'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Deutsch: alle Texte des Bildschirms sind deutsch', (tester) async {
    final s = await _setup(tester, lang: 'de');
    await _pump(tester, s, s.link);
    expect(find.text('Du bist eingeladen in „Stadt 26“'), findsOneWidget);
    expect(find.text('So geht es weiter'), findsOneWidget);
    expect(find.text('Beitreten'), findsWidgets);
    await _pump(tester, s, s.link.substring(0, s.link.length - 12));
    expect(find.textContaining('Der Link ist unvollständig'), findsOneWidget);
  });
}
