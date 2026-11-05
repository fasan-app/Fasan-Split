// Chat between two devices: @mention notifies, mute silences everything except mentions, pins are shared. Test relay only. MPL-2.0
import 'package:fasan_split/collab/activity.dart';
import 'package:fasan_split/collab/keys.dart';
import 'package:fasan_split/collab/nostr.dart';
import 'package:fasan_split/collab/service.dart';
import 'package:fasan_split/state/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle([int ms = 1200]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Chat: Erwähnung kommt an, Stumm schweigt außer bei Erwähnung, Anpinnen ist geteilt', () async {
    final hub = MemoryRelayHub();
    final a = CollabService(store: BillStore.memory()..me = 'Chris', vault: MemoryVault(), relayFactory: (_) => MemoryRelay(hub));
    await a.init();
    await a.setName('Chris');
    final g = await a.createGroup('Lisboa 26');
    final link = g.invitations!.create().link;
    await settle(400);
    final b = CollabService(store: BillStore.memory()..me = 'Angi', vault: MemoryVault(), prefs: await SharedPreferences.getInstance(), relayFactory: (_) => MemoryRelay(hub));
    await b.init();
    await b.setName('Angi');
    await b.join(link, 'Angi');
    await settle(9000); // past the quiet start
    final gb = b.groups.values.single;
    final angi = b.identity!.pub;

    // 1. mention: Angi gets a „mention“, not a plain message
    a.sendMessage(g, '@Angi bringst du Brot mit?', mentions: [angi]);
    await settle(2000);
    expect(b.activity.where((x) => x.kind == ActivityKind.mention && x.text.contains('erwähnt')).length, 1);
    expect(b.activity.where((x) => x.kind == ActivityKind.message).length, 0, reason: 'no double notification');
    expect(b.messages(gb).single.mentions, [angi]);

    // a mention whose @name is not in the text, or of a non-member, is not stored
    a.sendMessage(g, 'ohne Namen', mentions: [angi, 'ffff']);
    await settle(1500);
    expect(b.messages(gb).last.mentions, isEmpty);

    // 2. mute: plain messages make no news, a mention still does
    final before = b.activity.length;
    b.setMuted(gb, true);
    expect(b.isMuted(gb), isTrue);
    a.sendMessage(g, 'Wer kommt mit zum Strand?');
    await settle(1500);
    expect(b.activity.length, before, reason: 'muted: no news for plain messages');
    expect(b.unread(gb), greaterThan(0), reason: 'the unread number stays');
    a.sendMessage(g, 'Hey @Angi, doch noch?', mentions: [angi]);
    await settle(1500);
    expect(b.activity.length, before + 1);
    b.setMuted(gb, false);
    expect(b.isMuted(gb), false);

    // 3. pin: set by one, seen by the other, and removed again
    final id = a.messages(g).first.id;
    a.pinMessage(g, id, true);
    await settle(1500);
    expect(b.messages(gb).where((m) => m.pinned).map((m) => m.id), [id]);
    b.pinMessage(gb, id, false);
    await settle(1500);
    expect(a.messages(g).any((m) => m.pinned), isFalse);
    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
