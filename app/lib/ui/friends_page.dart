// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the friends list and what can be done with a friend (moved out of groups.dart, Umbau 14.11.). MPL-2.0
import 'person_avatar.dart';
import '../l10n/tr.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import '../collab/notes.dart' show ChatMessage;
import '../l10n.dart';
import 'scope.dart';
import '../flows/scan_queue.dart';
import 'bill_tile.dart';
import 'collab_ui.dart';
import 'common.dart';
import 'marquee_text.dart';
import 'shape_tokens.dart';

/// People from the bills plus the ones added by hand, with their number of bills and what they consumed.
class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  /// A friend link (Nutzer 04.11.: invite friends without a group or bill, to chat and try the app together).
  static Future<void> inviteFriend(BuildContext context) async {
    final c = CollabScope.read(context);
    if (!await ensureConsent(context, c) || !context.mounted) return;
    final g = await c.createDirect();
    if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: g)));
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context), collab = CollabScope.of(context);
    final de = t.de;
    final bottom = 150 + MediaQuery.paddingOf(context).bottom;
    // one list (Nutzer 04.11.): people from bills, everyone from my groups, direct connections – merged by name
    final rows = <String, _Friend>{};
    _Friend at(String name) => rows.putIfAbsent(name.toLowerCase(), () => _Friend(name));
    for (final f in store.friends) {
      at(f.name)
        ..color = f.color
        ..bills = f.bills
        ..sum = f.sum
        ..fromBills = true;
    }
    for (final e in collab.memberFriends.entries) {
      at(e.value).pub ??= e.key;
    }
    // deleted accounts stay visible as such until removed (Nutzer 04.11.)
    for (final e in collab.deletedFriends.entries) {
      at(e.value)
        ..pub ??= e.key
        ..deleted = true;
    }
    // gone from all my groups (left or removed) but not deleted (Nutzer 11.11.): shown as such, not as a current friend
    for (final e in collab.leftFriends.entries) {
      at(e.value)
        ..pub ??= e.key
        ..left = true;
    }
    // not myself, under any name I ever had (Nutzer 11.11.: „Chris“ stayed behind as a friend after renaming) and not my own key
    final mine = collab.ownNames;
    rows.removeWhere((k, f) => mine.contains(k) || (f.pub != null && f.pub == collab.identity?.pub));
    final waiting = <CollabGroup>[];
    for (final g in collab.directs) {
      final n = collab.directName(g);
      if (n.isEmpty) {
        waiting.add(g);
        continue;
      }
      at(n)
        ..direct = g
        ..pub ??= collab.directPeer(g);
    }
    for (final f in rows.values) {
      if (f.direct != null) {
        f.last = collab.lastMessage(f.direct!);
        f.unread = collab.unread(f.direct!);
      }
    }
    final list = rows.values.toList()
      ..sort((a, b) {
        if ((a.unread > 0) != (b.unread > 0)) return a.unread > 0 ? -1 : 1;
        final ta = a.last?.at, tb = b.last?.at;
        if (ta != null || tb != null) return (tb ?? DateTime(0)).compareTo(ta ?? DateTime(0));
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final inviteButton = FasanButton(label: trLang(de ? 'de' : 'en', 'groups.inviteAFriend'), icon: Icons.person_add_alt_1_rounded, expand: true, onPressed: () => inviteFriend(context));

    Future<void> openChat(_Friend f) async {
      final c = CollabScope.read(context);
      final g = f.direct ?? (f.pub != null ? await c.directWith(f.pub!, f.name) : null);
      if (g != null && context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(group: g)));
    }

    if (list.isEmpty && waiting.isEmpty) {
      return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom), children: [
        const SizedBox(height: 80),
        Icon(Icons.people_outline_rounded, size: 56, color: l.textMuted),
        const SizedBox(height: FasanSpace.l),
        Text(t.friendsEmptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: FasanSpace.s),
        Text(t.friendsEmptyText, style: tt.bodyMedium!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
        const SizedBox(height: FasanSpace.l),
        inviteButton,
      ]);
    }
    String when(DateTime d) {
      final now = DateTime.now();
      if (d.year == now.year && d.month == now.month && d.day == now.day) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      return '${d.day}.${d.month}.';
    }

    Widget row(_Friend f) {
      final hasChat = !f.deleted && !f.left && (f.pub != null || f.direct != null);
      final bold = f.unread > 0;
      final sub = f.deleted
          ? (trLang(de ? 'de' : 'en', 'groups.accountDeleted'))
          : f.left
          ? trLang(de ? 'de' : 'en', 'groups.accountLeft')
          : f.last != null
          ? (f.last!.from == collab.identity?.pub ? (trLang(de ? 'de' : 'en', 'groups.you')) : '') + f.last!.text
          : [
              if (f.bills > 0) t.billsCount(f.bills),
              if (f.pub != null && collab.isOnline(f.pub!))
                'online'
              else if (f.pub != null && collab.lastSeen(f.pub!) != null)
                (trLang(de ? 'de' : 'en', 'groups.lastSeen', [when(collab.lastSeen(f.pub!)!)]))
              else if (hasChat)
                trLang(de ? 'de' : 'en', 'groups.inTheApp2')
              else
                trLang(de ? 'de' : 'en', 'groups.onlyInReceipts'),
            ].join(' · ');
      final card = Material(
        color: l.surfaceAlt,
        borderRadius: BorderRadius.circular(l.rCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(l.rCard),
          // with the app: tap writes (like a messenger), long press shows everything else; only in bills: the actions;
          // a deleted account: offer to remove it from the list
          onTap: f.deleted ? () => _removeDeleted(context, f.name, f.pub!) : (hasChat ? () => openChat(f) : () => friendActions(context, f.name)),
          onLongPress: () => friendActions(context, f.name),
          child: Padding(
            padding: const EdgeInsets.only(left: FasanSpace.m, right: 0, top: FasanSpace.s + 2, bottom: FasanSpace.s + 2),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                PersonAvatar(name: f.name, index: f.color, size: 44),
                // online now (Nutzer 04.11.; off in Einstellungen → Privatsphäre)
                if (f.pub != null && collab.isOnline(f.pub!))
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(width: 13, height: 13, decoration: BoxDecoration(color: Colors.green.shade500, shape: BoxShape.circle, border: Border.all(color: l.surfaceAlt, width: 2))),
                  ),
              ]),
              const SizedBox(width: FasanSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, style: tt.titleMedium!.copyWith(fontWeight: bold ? FontWeight.w800 : null)),
                  MarqueeText(sub, style: tt.bodySmall!.copyWith(fontWeight: bold ? FontWeight.w700 : null, color: bold ? tt.bodyLarge!.color : null)),
                ]),
              ),
              const SizedBox(width: FasanSpace.s),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (f.last != null) Text(when(f.last!.at), style: tt.labelSmall!.copyWith(color: bold ? l.accent : l.textMuted, fontWeight: bold ? FontWeight.w700 : null)),
                if (bold)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: l.accent, borderRadius: BorderRadius.circular(10)),
                    child: Text(f.unread > 99 ? '99+' : '${f.unread}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  )
                // no bare amount here (Nutzer 09.11.: debt or credit was not clear); the balance lives in Abrechnung and the profile
              ]),
              if (hasChat && !bold && f.last == null) ...[const SizedBox(width: 4), Icon(Icons.chat_bubble_outline_rounded, size: 20, color: l.accent)],
              // the visible twin of the long press (Regel: jede Geste hat einen sichtbaren Zwilling)
              IconButton(
                key: ValueKey('friend-more-${f.name}'),
                tooltip: context.tr('s.more'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => friendActions(context, f.name),
              ),
            ]),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: FasanSpace.s),
        // no swipe (Nutzer 09.11.): „Aus Vorschlägen entfernen“ is in the menu (long press)
        child: card,
      );
    }

    return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, bottom), children: [
      inviteButton,
      const SizedBox(height: FasanSpace.m),
      for (final f in list) row(f),
      for (final g in waiting)
        Padding(
          padding: const EdgeInsets.only(bottom: FasanSpace.s),
          child: ListTile(
            leading: Icon(Icons.schedule_send_rounded, color: l.textMuted),
            title: Text(trLang(de ? 'de' : 'en', 'groups.invitationOpen')),
            subtitle: Text(trLang(de ? 'de' : 'en', 'groups.nobodyOpenedTheLink')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: g))),
          ),
        ),
    ]);
  }
}

/// A friend deleted their account: remove them from the list (and leave the direct chat). Their names in old bills stay.
Future<void> _removeDeleted(BuildContext context, String name, String pub) async {
  final de = S.of(context).de;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(trLang(de ? 'de' : 'en', 'groups.deletedTheAccount', [name])),
      content: Text(trLang(de ? 'de' : 'en', 'groups.removeFromYourFriends')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(trLang(de ? 'de' : 'en', 'groups.keep'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(trLang(de ? 'de' : 'en', 'groups.remove'))),
      ],
    ),
  );
  if (ok == true && context.mounted) await CollabScope.read(context).forgetFriendPub(pub);
}

/// One row of the friends list (built from bills, groups and direct connections).
class _Friend {
  _Friend(this.name);
  final String name;
  int color = 0, bills = 0, sum = 0, unread = 0;
  bool fromBills = false, deleted = false, left = false;
  String? pub;
  CollabGroup? direct;
  ChatMessage? last;
}

/// Everything one can do with a person (Nutzer 04.11.: „alles überall verfügbar, was der Benutzer erwarten könnte“).
/// One „In Gruppe aufnehmen“ for all groups (Nutzer 04.11.: two group entries were confusing); in a shared group where
/// I am admin the invitation link opens right away.
Future<void> friendActions(BuildContext context, String name) async {
  final t = S.of(context), store = StoreScope.read(context), collab = CollabScope.read(context);
  final de = t.de;
  final groups = store.allGroups;
  final live = [for (final g in groups) ?collab.groupByLocalName(g)];
  CollabGroup? direct;
  for (final g in collab.directs) {
    if (collab.directName(g).toLowerCase() == name.toLowerCase()) direct = g;
  }
  // a member of one of my groups: writing works without any link (directWith)
  String? pub;
  for (final e in collab.memberFriends.entries) {
    if (e.value.toLowerCase() == name.toLowerCase()) pub = e.key;
  }
  // shared groups where this person is linked to a member: chat there too
  final chats = [for (final g in live) if (g.session.memberOfPerson(name) != null) g];
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(leading: PersonAvatar(name: name, index: 0, size: 32), title: Text(name, style: Theme.of(ctx).textTheme.titleMedium)),
        if (direct != null || pub != null)
          ListTile(leading: const Icon(Icons.chat_bubble_outline_rounded), title: Text(trLang(de ? 'de' : 'en', 'groups.writeAMessage')), onTap: () => Navigator.pop(ctx, 'direct'))
        else
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: Text(trLang(de ? 'de' : 'en', 'groups.connectWith', [name])),
            subtitle: Text(trLang(de ? 'de' : 'en', 'groups.sendALinkChat')),
            onTap: () => Navigator.pop(ctx, 'connect'),
          ),
        ListTile(
          leading: const Icon(Icons.group_add_outlined),
          title: Text(trLang(de ? 'de' : 'en', 'groups.addToAGroup')),
          subtitle: Text(trLang(de ? 'de' : 'en', 'groups.sharedGroupsAnInvitation')),
          onTap: () => Navigator.pop(ctx, 'add'),
        ),
        for (final g in chats)
          ListTile(leading: const Icon(Icons.forum_outlined), title: Text(trLang(de ? 'de' : 'en', 'groups.messageIn', [g.localName])), onTap: () => Navigator.pop(ctx, 'chat:${g.secret.tag}')),
        ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text(trLang(de ? 'de' : 'en', 'groups.receiptsWith', [name])), onTap: () => Navigator.pop(ctx, 'bills')),
        ListTile(leading: Icon(Icons.person_remove_outlined, color: Colors.red.shade700), title: Text(trLang(de ? 'de' : 'en', 'groups.removeFromSuggestions')), onTap: () => Navigator.pop(ctx, 'forget')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  Future<String?> pickGroup(List<String> names) => showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            for (final g in names)
              ListTile(
                leading: Icon(collab.groupByLocalName(g) != null ? Icons.sensors_rounded : Icons.folder_outlined),
                title: Text(g),
                subtitle: collab.groupByLocalName(g) != null ? Text(trLang(de ? 'de' : 'en', 'groups.shared')) : null,
                onTap: () => Navigator.pop(ctx, g),
              ),
            ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: Text(t.newGroup), onTap: () => Navigator.pop(ctx, '+')),
          ]),
        ),
      );
  switch (choice) {
    case 'direct':
      final d = direct ?? await collab.directWith(pub!, name);
      if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(group: d)));
    case 'connect':
      await FriendsPage.inviteFriend(context);
    case 'add':
      var g = await pickGroup(groups);
      if (g == '+' && context.mounted) {
        g = await askText(context, t.newGroup, t.groupName);
        if (g != null) store.addGroup(g);
      }
      if (g == null || g.trim().isEmpty || !context.mounted) return;
      store.addGroupMember(g.trim(), name);
      final c = collab.groupByLocalName(g.trim());
      if (c != null && c.isAdmin && c.session.memberOfPerson(name) == null) {
        // shared: the person still has to get in – the link for them opens at once
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: c, person: name)));
      } else {
        showNote(context, trLang(de ? 'de' : 'en', 'groups.isIn', [name, g.trim()]));
      }
    case 'bills':
      final list = store.bills.where((b) => b.trashedAt == null && b.ps.any((p) => p.name == name)).toList()..sort((a, b) => b.date.compareTo(a.date));
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(trLang(de ? 'de' : 'en', 'groups.receiptsWith2', [name]))),
          body: ListView(padding: const EdgeInsets.all(FasanSpace.l), children: [
            for (final b in list)
              Padding(
                padding: const EdgeInsets.only(bottom: FasanSpace.xs + 2),
                child: BillTile(bill: b, queue: ScanQueue.current ?? ScanQueue(store), selecting: false, selected: false, onToggle: () {}, onRetry: () {}),
              ),
          ]),
        ),
      ));
    case 'forget':
      store.forgetFriend(name);
    default:
      if (choice.startsWith('chat:')) {
        final c = collab.groups[choice.substring(5)];
        if (c != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(group: c)));
      }
  }
}
