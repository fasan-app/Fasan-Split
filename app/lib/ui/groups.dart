// Fasan Split – Gruppen and Freunde, group page. A group is local until it is shared live (see collab_ui.dart); the
// invitation and the live part of a group live in collab_ui.dart. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../collab/group.dart';
import '../collab/notes.dart' show ChatMessage;
import '../collab/service.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import '../l10n_groups.dart';
import '../model/settle.dart';
import '../main.dart';
import '../model/bill.dart';
import '../state/scan_queue.dart';
import 'bill_tile.dart';
import 'collab_ui.dart';
import 'common.dart';
import 'my_balance.dart';
import 'pay_ui.dart';
import 'swipe.dart';
import 'marquee_text.dart';

/// All groups with their number of bills and sum; tap opens the group. Pending join requests are shown on top.
class GroupsPage extends StatelessWidget {
  const GroupsPage({super.key, required this.queue});

  final ScanQueue queue;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context);
    final names = store.allGroups;
    final bottom = 150 + MediaQuery.paddingOf(context).bottom;
    if (names.isEmpty) {
      return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom), children: [
        const PendingJoinCards(),
        const SizedBox(height: 80),
        Icon(Icons.folder_copy_outlined, size: 56, color: l.textMuted),
        const SizedBox(height: FasanSpace.l),
        Text(t.groupsEmptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: FasanSpace.s),
        Text(t.groupsEmptyText, style: tt.bodyMedium!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
      ]);
    }
    return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, bottom), children: [
      const PendingJoinCards(),
      for (final g in names)
        Padding(
          padding: const EdgeInsets.only(bottom: FasanSpace.s),
          child: Builder(builder: (context) {
            final bills = store.inGroup(g);
            final sum = bills.fold<int>(0, (a, b) => a + b.effectiveTotal);
            final lg = CollabScope.of(context).groupByLocalName(g), live = lg != null;
            final unread = lg == null ? 0 : CollabScope.of(context).unread(lg);
            final last = lg == null ? null : CollabScope.of(context).lastMessage(lg);
            return Material(
              color: l.surfaceAlt,
              borderRadius: BorderRadius.circular(l.radius * 0.7),
              child: InkWell(
                borderRadius: BorderRadius.circular(l.radius * 0.7),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(name: g, queue: queue))),
                child: Padding(
                  padding: const EdgeInsets.all(FasanSpace.m),
                  child: Row(children: [
                    Icon(live ? Icons.wifi_tethering_rounded : Icons.folder_outlined, color: l.accent),
                    const SizedBox(width: FasanSpace.m),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g, style: tt.titleMedium!.copyWith(fontWeight: unread > 0 ? FontWeight.w800 : null)),
                        // the newest message, bold while unread (Nutzer 04.11.)
                        Text(
                            last != null && unread > 0
                                ? '${lg!.session.nameOf(last.from)}: ${last.text}'
                                : live
                                    ? '${t.billsCount(bills.length)} · ${t.shared}'
                                    : t.billsCount(bills.length),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall!.copyWith(fontWeight: unread > 0 ? FontWeight.w700 : null)),
                      ]),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Badge(isLabelVisible: unread > 0, label: Text('$unread'), offset: const Offset(10, -6), child: Text('${money(sum, de: t.de)} ${signOf(context)}', style: tt.titleMedium)),
                      // my balance in this group (green = I get, red = I owe)
                      if (myDebts(store.inGroup(g, done: true), myNames(context)).values.fold(0, (a, x) => a + x) case final v when v != 0)
                        Text('${money(v, de: t.de, sign: true)} ${signOf(context)}', style: tt.labelMedium!.copyWith(color: v > 0 ? Colors.green.shade600 : Colors.red.shade600, fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                ),
              ),
            );
          }),
        ),
    ]);
  }
}

/// One group: its bills (open and finished), the sum, the live part (when shared) and the invitation (admin).
class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.name, required this.queue});

  final String name;
  final ScanQueue queue;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context);
    final bills = store.inGroup(name);
    final sum = bills.fold<int>(0, (a, b) => a + b.effectiveTotal);
    final live = CollabScope.of(context).groupByLocalName(name);
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          // always there (Nutzer 04.11.): a group only on this phone is shared first, then the link is ready
          IconButton(
            tooltip: t.invite,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () async {
              final g = live ?? await shareLive(context, name);
              if (g != null && context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: g)));
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'leave' && live != null) {
                await leaveGroupFlow(context, live);
                return;
              }
              if (v == 'delete' && await confirmDialog(context, t.deleteGroup, name, t.deleteGroup) && context.mounted) {
                store.deleteGroup(name);
                Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => [
              if (live != null) PopupMenuItem(value: 'leave', child: Text(t.leaveGroup)),
              if (live == null) PopupMenuItem(value: 'delete', child: Text(t.deleteGroup)),
            ],
          ),
        ],
      ),
      body: ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 40 + MediaQuery.paddingOf(context).bottom), children: [
        Padding(padding: const EdgeInsets.only(bottom: FasanSpace.m), child: Text('${t.billsCount(bills.length)} · ${money(sum, de: t.de)} ${signOf(context)}', style: tt.bodyMedium)),
        if (live != null) CollabGroupPanel(group: live),
        if (live == null) _ShareButton(name: name),
        // receipts first (Nutzer 06.11.: the people block pushed the receipts off the screen), people in one folded section below
        if (bills.isEmpty) Text(t.groupEmpty, style: tt.bodyMedium),
        for (final b in bills)
          Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: BillTile(bill: b, queue: queue, selecting: false, selected: false, onToggle: () {}, onRetry: () {})),
        const SizedBox(height: FasanSpace.m),
        _PeopleSection(name: name),
      ]),
    );
  }
}

/// „Personen“ – the one place for everyone in the group (in the app or not), folded by default; balances and settling inside.
class _PeopleSection extends StatelessWidget {
  const _PeopleSection({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final n = CollabScope.of(context).peopleOf(name).length;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.6)),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(Icons.group_outlined, color: l.accent),
          title: Text('${t.groupPeople} · $n', style: tt.titleMedium),
          childrenPadding: const EdgeInsets.fromLTRB(FasanSpace.m, 0, FasanSpace.m, FasanSpace.m),
          children: [GroupPeople(name: name)],
        ),
      ),
    );
  }
}

/// Members of a group with their balance, and the transfers that settle the group. People added by hand can be
/// removed again; people from bills stay (their costs are in the bills).
class GroupPeople extends StatelessWidget {
  const GroupPeople({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context);
    final live = CollabScope.of(context).groupByLocalName(name);
    // everyone who joined is a person of the group (Nutzer 04.11.), next to the names from the bills
    final people = CollabScope.of(context).peopleOf(name);
    // Live group: balance per member, not per spelling (Nutzer 03.11.). Every name linked to a member counts as „@pub“;
    // the member's first name stands for all of them.
    String keyOf(String p) => switch (live?.session.memberOfPerson(p)) { final m? => '@$m', _ => p };
    String label(String k) => k.startsWith('@') ? (live!.session.personOf(k.substring(1)) ?? live.session.nameOf(k.substring(1))) : k;
    final bal = store.groupBalance(name, key: keyOf);
    final moves = settle(bal);
    final anyDone = store.inGroup(name, done: true).isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (people.isEmpty) Text(t.groupNoPeople, style: tt.bodyMedium!.copyWith(color: l.textMuted)),
      for (final (i, p) in people.indexed)
        InkWell(
          // Live group: who of the bills is which member (Nutzer 03.11.: invite people from a bill, link, unlink).
          onTap: live == null ? null : () => _personActions(context, live, p),
          child: Container(
          constraints: BoxConstraints(minHeight: l.minTap),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: l.hairline))),
          child: Row(children: [
            FasanAvatar(name: p, index: i, size: 32),
            const SizedBox(width: FasanSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p, style: tt.bodyLarge),
                if (live != null)
                  GroupChangeBuilder(
                    group: live,
                    docId: GroupSession.members,
                    builder: (context) => Text(
                      switch (live.session.memberOfPerson(p)) {
                        final m? when label('@$m') != p => '${t.inTheApp} · ${t.countsWith(label('@$m'))}',
                        _?  => t.inTheApp,
                        _ => t.withoutApp,
                      },
                      style: tt.bodySmall!.copyWith(color: l.textMuted),
                    ),
                  ),
              ]),
            ),
            if (label(keyOf(p)) == p && bal[keyOf(p)] != null && bal[keyOf(p)] != 0)
              Text('${money(bal[keyOf(p)]!, de: t.de, sign: true)} ${signOf(context)}', style: tt.titleMedium!.copyWith(color: bal[keyOf(p)]! > 0 ? l.accent : null)),
            if (store.isHandMember(name, p))
              IconButton(tooltip: t.cancel, icon: const Icon(Icons.close_rounded), onPressed: () => store.removeGroupMember(name, p)),
          ]),
        ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.person_add_alt_rounded),
          label: Text(t.groupAddPerson),
          onPressed: () async {
            final n = await askText(context, t.groupAddPerson, t.friendName);
            if (n != null) store.addGroupMember(name, n);
          },
        ),
      ),
      if (anyDone) ...[
        const SizedBox(height: FasanSpace.m),
        FasanLabel(t.groupSettle),
        const SizedBox(height: FasanSpace.s),
        if (moves.isEmpty) Text(t.groupSettled, style: tt.bodyMedium),
        for (final (from, to, c) in moves)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(t.owes(label(from), label(to), '${money(c, de: t.de)} ${signOf(context)}'), style: tt.bodyMedium)),
              // my debt in this group: pay with one tap (pay_ui.dart)
              if (myNames(context)(label(from)) || from == '@${CollabScope.read(context).identity?.pub}')
                TextButton(
                  onPressed: () => payFlow(context,
                      name: label(to), pub: to.startsWith('@') ? to.substring(1) : live?.session.memberOfPerson(to), cents: c, currency: StoreScope.read(context).homeCurrency, purpose: name),
                  child: Text(t.de ? 'Bezahlen' : 'Pay'),
                ),
            ]),
          ),
        if (moves.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FasanSpace.s),
            child: FasanButton(
              label: t.de ? 'Alle haben bezahlt – ausgleichen' : 'Everyone paid – settle',
              icon: Icons.task_alt_rounded,
              kind: FasanButtonKind.secondary,
              expand: true,
              onPressed: () async {
                final list = store.inGroup(name, done: true, archived: false);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: Text(t.de
                        ? 'Alle ${list.length} eingetragenen Bons als bezahlt markieren? Sie kommen ins Archiv und zählen nicht mehr im Saldo.'
                        : 'Mark all ${list.length} entered receipts as paid? They go to the archive and no longer count in the balances.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.de ? 'Ausgleichen' : 'Settle')),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  final changed = store.setSettled(list, true);
                  showNote(context, t.archivedN(changed.length));
                }
              },
            ),
          ),
        Text(t.groupBalanceHint, style: tt.bodySmall!.copyWith(color: l.textMuted)),
      ],
    ]);
  }
}

/// Invite this person, link them to a member who is already in, or unlink. Only the admin changes the members document;
/// the others see who is linked.
Future<void> _personActions(BuildContext context, CollabGroup g, String person) async {
  final t = S.of(context), s = CollabScope.read(context);
  final linked = g.session.memberOfPerson(person);
  if (!g.isAdmin) {
    showNote(context, t.onlyAdminLinks);
    return;
  }
  final members = g.session.memberKeys.toList();
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(person, style: Theme.of(ctx).textTheme.titleMedium)),
        if (linked == null) ListTile(leading: const Icon(Icons.person_add_alt_1_outlined), title: Text(t.inviteFor(person)), onTap: () => Navigator.pop(ctx, 'invite')),
        if (linked == null)
          for (final k in members)
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: Text(g.session.nameOf(k)),
              subtitle: Text([t.linkMember, ...g.session.personsOf(k)].join(' · ')),
              onTap: () => Navigator.pop(ctx, 'link:$k'),
            ),
        if (linked != null) ListTile(leading: const Icon(Icons.link_off_rounded), title: Text(t.unlink), subtitle: Text(t.linkedTo(g.session.nameOf(linked))), onTap: () => Navigator.pop(ctx, 'unlink')),
        // rights and removal live in the person's sheet too (Nutzer 06.11.: one concept „Personen“)
        if (linked != null) ListTile(leading: const Icon(Icons.admin_panel_settings_outlined), title: Text(t.personRights), onTap: () => Navigator.pop(ctx, 'rights')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'invite') {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: g, person: person)));
  } else if (choice == 'rights') {
    await memberActions(context, g, linked!);
  } else if (choice == 'unlink') {
    s.unlinkPerson(g, linked!, person);
  } else if (choice.startsWith('link:')) {
    s.linkPerson(g, choice.substring(5), person);
  }
}

/// Starts the live sharing of a group that is still local. Asks for the consent first.
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FasanSpace.m),
      child: FilledButton.tonalIcon(
        icon: const Icon(Icons.wifi_tethering_rounded),
        label: Text(t.collabShare),
        onPressed: () async {
          await shareLive(context, name);
        },
      ),
    );
  }
}

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
    final inviteButton = FasanButton(label: de ? 'Freund einladen' : 'Invite a friend', icon: Icons.person_add_alt_1_rounded, expand: true, onPressed: () => inviteFriend(context));

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
      final hasChat = !f.deleted && (f.pub != null || f.direct != null);
      final bold = f.unread > 0;
      final sub = f.deleted
          ? (de ? 'Konto gelöscht' : 'Account deleted')
          : f.last != null
          ? (f.last!.from == collab.identity?.pub ? (de ? 'Du: ' : 'You: ') : '') + f.last!.text
          : [
              if (f.bills > 0) t.billsCount(f.bills),
              if (f.pub != null && collab.isOnline(f.pub!))
                'online'
              else if (f.pub != null && collab.lastSeen(f.pub!) != null)
                (de ? 'zuletzt ${when(collab.lastSeen(f.pub!)!)}' : 'last seen ${when(collab.lastSeen(f.pub!)!)}')
              else if (hasChat)
                de ? 'in der App' : 'in the app'
              else
                de ? 'nur in Bons' : 'only in receipts',
            ].join(' · ');
      final card = Material(
        color: l.surfaceAlt,
        borderRadius: BorderRadius.circular(l.radius * 0.7),
        child: InkWell(
          borderRadius: BorderRadius.circular(l.radius * 0.7),
          // with the app: tap writes (like a messenger), long press shows everything else; only in bills: the actions;
          // a deleted account: offer to remove it from the list
          onTap: f.deleted ? () => _removeDeleted(context, f.name, f.pub!) : (hasChat ? () => openChat(f) : () => friendActions(context, f.name)),
          onLongPress: () => friendActions(context, f.name),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s + 2),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                FasanAvatar(name: f.name, index: f.color, size: 44),
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
                else if (f.bills > 0 && f.last == null)
                  Text('${money(f.sum, de: de)} ${signOf(context)}', style: tt.titleSmall),
              ]),
              if (hasChat && !bold && f.last == null) ...[const SizedBox(width: 4), Icon(Icons.chat_bubble_outline_rounded, size: 20, color: l.accent)],
            ]),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: FasanSpace.s),
        child: f.fromBills && f.pub == null
            ? SwipeActions(
                key: ValueKey('friend-${f.name}'),
                id: 'friend-${f.name}',
                end: SwipeSide(Icons.person_remove_outlined, t.forget, Colors.red.shade700),
                onDismissed: (_) => store.forgetFriend(f.name),
                child: card,
              )
            : card,
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
            title: Text(de ? 'Einladung offen' : 'Invitation open'),
            subtitle: Text(de ? 'Noch hat niemand den Link geöffnet. Tippen: erneut schicken' : 'Nobody opened the link yet. Tap: send again'),
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
      title: Text(de ? '$name hat das Konto gelöscht' : '$name deleted the account'),
      content: Text(de ? 'Aus der Freundesliste entfernen? Die Beträge in alten Bons bleiben, wie sie sind.' : 'Remove from your friends? Amounts in old receipts stay as they are.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(de ? 'Behalten' : 'Keep')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(de ? 'Entfernen' : 'Remove')),
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
  bool fromBills = false, deleted = false;
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
        ListTile(leading: FasanAvatar(name: name, index: 0, size: 32), title: Text(name, style: Theme.of(ctx).textTheme.titleMedium)),
        if (direct != null || pub != null)
          ListTile(leading: const Icon(Icons.chat_bubble_outline_rounded), title: Text(de ? 'Nachricht schreiben' : 'Write a message'), onTap: () => Navigator.pop(ctx, 'direct'))
        else
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: Text(de ? 'Mit $name verbinden' : 'Connect with $name'),
            subtitle: Text(de ? 'Link schicken: chatten und die App testen, ohne Gruppe' : 'Send a link: chat and try the app, no group needed'),
            onTap: () => Navigator.pop(ctx, 'connect'),
          ),
        ListTile(
          leading: const Icon(Icons.group_add_outlined),
          title: Text(de ? 'In Gruppe aufnehmen' : 'Add to a group'),
          subtitle: Text(de ? 'Bei geteilten Gruppen geht ein Einladungslink mit' : 'Shared groups: an invitation link comes with it'),
          onTap: () => Navigator.pop(ctx, 'add'),
        ),
        for (final g in chats)
          ListTile(leading: const Icon(Icons.forum_outlined), title: Text(de ? 'Nachricht in „${g.localName}“' : 'Message in “${g.localName}”'), onTap: () => Navigator.pop(ctx, 'chat:${g.secret.tag}')),
        ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text(de ? 'Bons mit $name' : 'Receipts with $name'), onTap: () => Navigator.pop(ctx, 'bills')),
        ListTile(leading: Icon(Icons.person_remove_outlined, color: Colors.red.shade700), title: Text(de ? 'Aus den Vorschlägen entfernen' : 'Remove from suggestions'), onTap: () => Navigator.pop(ctx, 'forget')),
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
                subtitle: collab.groupByLocalName(g) != null ? Text(de ? 'geteilt' : 'shared') : null,
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
        showNote(context, de ? '$name ist in „${g.trim()}“.' : '$name is in “${g.trim()}”.');
      }
    case 'bills':
      final list = store.bills.where((b) => b.trashedAt == null && b.ps.any((p) => p.name == name)).toList()..sort((a, b) => b.date.compareTo(a.date));
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(de ? 'Bons mit $name' : 'Receipts with $name')),
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
