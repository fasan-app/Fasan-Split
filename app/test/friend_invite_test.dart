// SPDX-License-Identifier: MPL-2.0
// Invite a friend to a group straight from a bill: goes to the friend's direct chat as an open link, can be taken back before and
// after they joined. Test relay only (nothing leaves the machine). MPL-2.0
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

final _link = RegExp(r'(fasansplit://join#\S+|https://\S+/join\S*#\S+)');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pia (admin) has two groups; Lena is only in the first. Returns both services and the groups on Pia' side.
  Future<(CollabService, CollabService, CollabGroup, CollabGroup)> setup() async {
    final hub = MemoryRelayHub();
    final a = CollabService(store: BillStore.memory()..me = 'Pia', vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Pia');
    final g1 = await a.createGroup('Stadt 26');
    final g2 = await a.createGroup('Hütte');
    final link = g1.invitations!.create().link;
    await settle(400);
    final b = CollabService(store: BillStore.memory()..me = 'Lena', vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Lena');
    await b.join(link, 'Lena');
    await settle(3000);
    return (a, b, g1, g2);
  }

  test('Freund einladen: Link kommt im Direktchat an, Beitritt ohne Bestätigung, Rückgängig nach Beitritt entfernt wieder', () async {
    final (a, b, g1, g2) = await setup();
    final lena = b.identity!.pub;
    expect(a.memberFriends.keys, contains(lena), reason: 'Lena is a friend through the first group');
    expect(g2.session.memberKeys.contains(lena), isFalse);

    final inv = await a.inviteFriendToGroup(g2, lena, 'Lena', message: 'Einladung in die Gruppe „Hütte“');
    expect(inv, isNotNull);
    expect(inv!.messageId, isNotNull);
    await settle(2500);
    // Lena finds the invitation in the direct chat with Pia
    final direct = b.directs.firstWhere((d) => b.directName(d) == 'Pia');
    final msgs = b.messages(direct);
    expect(msgs.length, 1);
    final link = _link.firstMatch(msgs.single.text)?.group(0);
    expect(link, isNotNull, reason: 'the message carries the join link');
    expect(msgs.single.text, contains('Hütte'));

    // „Beitreten“ = the join flow with that link: no admin has to confirm
    await b.join(link!, 'Lena');
    await settle(3500);
    expect(g2.session.memberKeys.contains(lena), isTrue, reason: 'joined without confirmation');

    // taking it back after the join removes Lena again and the message is gone
    await a.undoFriendInvite(inv);
    await settle(2500);
    final g2After = a.groupByLocalName('Hütte')!;
    expect(g2After.session.memberKeys.contains(lena), isFalse);
    expect(b.messages(direct).any((m) => !m.deleted && m.text.contains('join')), isFalse);
    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Rückgängig vor dem Beitritt: Nachricht weg, Link wirkungslos, Eingeladene sind nicht in der Gruppe', () async {
    final (a, b, g1, g2) = await setup();
    final lena = b.identity!.pub;
    final inv = await a.inviteFriendToGroup(g2, lena, 'Lena', message: 'Einladung');
    await a.undoFriendInvite(inv!);
    await settle(2500);
    final direct = b.directs.firstWhere((d) => b.directName(d) == 'Pia');
    expect(b.messages(direct).where((m) => !m.deleted).isEmpty, isTrue, reason: 'the invitation message is deleted for Lena');
    expect(g2.invitations!.open.any((i) => i.person == 'Lena'), isFalse, reason: 'the invitation is withdrawn');
    expect(a.groupByLocalName('Hütte')!.session.memberKeys.contains(lena), isFalse);
    // inviting someone who is already in the group, or into a friend chat, does nothing
    expect(await a.inviteFriendToGroup(g1, lena, 'Lena', message: 'x'), isNull);
    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Zurückgezogener Link: wer ihn trotzdem benutzt, kommt nicht in die Gruppe', () async {
    final (a, b, g1, g2) = await setup();
    final lena = b.identity!.pub;
    final inv = await a.inviteFriendToGroup(g2, lena, 'Lena', message: 'Einladung');
    final link = inv!.invite.link; // Lena may have read it before the invitation was taken back
    await a.undoFriendInvite(inv);
    await settle(2000);
    final err = await b.join(link, 'Lena');
    await settle(3500);
    final member = a.groupByLocalName('Hütte')!.session.memberKeys.contains(lena);
    // ignore: avoid_print
    print('JOIN AFTER UNDO: error=$err member=$member');
    expect(member, isFalse, reason: 'a withdrawn invitation must not let anyone in');
    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}

