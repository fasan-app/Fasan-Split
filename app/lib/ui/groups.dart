// Fasan Split – Gruppen and Freunde, group page. A group is local until it is shared live (see collab_ui.dart); the
// invitation and the live part of a group live in collab_ui.dart. MPL-2.0
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../collab/group.dart';
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
import 'swipe.dart';

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
            final live = CollabScope.of(context).groupByLocalName(g) != null;
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
                        Text(g, style: tt.titleMedium),
                        Text(live ? '${t.billsCount(bills.length)} · ${t.shared}' : t.billsCount(bills.length), style: tt.bodySmall),
                      ]),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${money(sum, de: t.de)} ${signOf(context)}', style: tt.titleMedium),
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
          if (live != null && live.isAdmin)
            IconButton(tooltip: t.invite, icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: live)))),
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
        GroupPeople(name: name),
        const SizedBox(height: FasanSpace.l),
        if (live == null) _ShareButton(name: name),
        if (bills.isEmpty) Text(t.groupEmpty, style: tt.bodyMedium),
        for (final b in bills)
          Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: BillTile(bill: b, queue: queue, selecting: false, selected: false, onToggle: () {}, onRetry: () {})),
      ]),
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
    final people = store.groupMembers(name);
    final live = CollabScope.of(context).groupByLocalName(name);
    // Live group: balance per member, not per spelling (Nutzer 03.11.). Every name linked to a member counts as „@pub“;
    // the member's first name stands for all of them.
    String keyOf(String p) => switch (live?.session.memberOfPerson(p)) { final m? => '@$m', _ => p };
    String label(String k) => k.startsWith('@') ? (live!.session.personOf(k.substring(1)) ?? live.session.nameOf(k.substring(1))) : k;
    final bal = store.groupBalance(name, key: keyOf);
    final moves = settle(bal);
    final anyDone = store.inGroup(name, done: true).isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FasanLabel(t.groupPeople),
      const SizedBox(height: FasanSpace.s),
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
                        final m? when label('@$m') != p => '${t.linkedTo(live.session.nameOf(m))} · ${t.countsWith(label('@$m'))}',
                        final m? => t.linkedTo(live.session.nameOf(m)),
                        _ => t.notLinked,
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
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(t.owes(label(from), label(to), '${money(c, de: t.de)} ${signOf(context)}'), style: tt.bodyMedium)),
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
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'invite') {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: g, person: person)));
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

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final store = StoreScope.of(context);
    final friends = store.friends;
    final bottom = 150 + MediaQuery.paddingOf(context).bottom;
    if (friends.isEmpty) {
      return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom), children: [
        const SizedBox(height: 80),
        Icon(Icons.people_outline_rounded, size: 56, color: l.textMuted),
        const SizedBox(height: FasanSpace.l),
        Text(t.friendsEmptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: FasanSpace.s),
        Text(t.friendsEmptyText, style: tt.bodyMedium!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
      ]);
    }
    return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.m, FasanSpace.l, bottom), children: [
      for (final f in friends)
        Padding(
          padding: const EdgeInsets.only(bottom: FasanSpace.s),
          child: SwipeActions(
            key: ValueKey('friend-${f.name}'),
            id: 'friend-${f.name}',
            end: SwipeSide(Icons.person_remove_outlined, t.forget, Colors.red.shade700),
            onDismissed: (_) => store.forgetFriend(f.name),
            child: Material(
              color: l.surfaceAlt,
              borderRadius: BorderRadius.circular(l.radius * 0.7),
              child: InkWell(
              borderRadius: BorderRadius.circular(l.radius * 0.7),
              // a person can be tapped (Nutzer 04.11.): add to a group, invite, write, see the bills
              onTap: () => friendActions(context, f.name),
              child: Padding(
              padding: const EdgeInsets.all(FasanSpace.m),
              child: Row(children: [
                FasanAvatar(name: f.name, index: f.color, size: 40),
                const SizedBox(width: FasanSpace.m),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f.name, style: tt.titleMedium), Text(t.billsCount(f.bills), style: tt.bodySmall)])),
                if (f.bills > 0) Text('${money(f.sum, de: t.de)} ${signOf(context)}', style: tt.titleMedium),
                Icon(Icons.chevron_right_rounded, color: l.textMuted),
              ]),
            ),
            ),
            ),
          ),
        ),
    ]);
  }
}


/// Everything one can do with a person (Nutzer 04.11.: „alles überall verfügbar, was der Benutzer erwarten könnte“).
Future<void> friendActions(BuildContext context, String name) async {
  final t = S.of(context), store = StoreScope.read(context), collab = CollabScope.read(context);
  final de = t.de;
  final groups = store.allGroups;
  final live = [for (final g in groups) ?collab.groupByLocalName(g)];
  // shared groups where this person is linked to a member: chat there
  final chats = [for (final g in live) if (g.session.memberOfPerson(name) != null) g];
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(leading: FasanAvatar(name: name, index: 0, size: 32), title: Text(name, style: Theme.of(ctx).textTheme.titleMedium)),
        ListTile(leading: const Icon(Icons.group_add_outlined), title: Text(de ? 'Zu einer Gruppe hinzufügen' : 'Add to a group'), onTap: () => Navigator.pop(ctx, 'add')),
        if (live.any((g) => g.isAdmin && g.session.memberOfPerson(name) == null))
          ListTile(leading: const Icon(Icons.person_add_alt_1_outlined), title: Text(de ? 'In eine geteilte Gruppe einladen' : 'Invite to a shared group'), onTap: () => Navigator.pop(ctx, 'invite')),
        for (final g in chats)
          ListTile(leading: const Icon(Icons.chat_bubble_outline_rounded), title: Text(de ? 'Nachricht in „${g.localName}“' : 'Message in “${g.localName}”'), onTap: () => Navigator.pop(ctx, 'chat:${g.secret.tag}')),
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
            for (final g in names) ListTile(leading: const Icon(Icons.folder_outlined), title: Text(g), onTap: () => Navigator.pop(ctx, g)),
            ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: Text(t.newGroup), onTap: () => Navigator.pop(ctx, '+')),
          ]),
        ),
      );
  switch (choice) {
    case 'add':
      var g = await pickGroup(groups);
      if (g == '+' && context.mounted) {
        g = await askText(context, t.newGroup, t.groupName);
        if (g != null) store.addGroup(g);
      }
      if (g == null || g.trim().isEmpty) return;
      store.addGroupMember(g.trim(), name);
      if (context.mounted) showNote(context, de ? '$name ist in „${g.trim()}“.' : '$name is in “${g.trim()}”.');
    case 'invite':
      final names = [for (final g in live) if (g.isAdmin && g.session.memberOfPerson(name) == null) g.localName];
      final g = await pickGroup(names);
      final c = g == null ? null : collab.groupByLocalName(g);
      if (c == null || !context.mounted) return;
      store.addGroupMember(c.localName, name);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: c, person: name)));
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
