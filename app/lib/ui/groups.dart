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
                    Text('${money(sum, de: t.de)} €', style: tt.titleMedium),
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
        Padding(padding: const EdgeInsets.only(bottom: FasanSpace.m), child: Text('${t.billsCount(bills.length)} · ${money(sum, de: t.de)} €', style: tt.bodyMedium)),
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
              Text('${money(bal[keyOf(p)]!, de: t.de, sign: true)} €', style: tt.titleMedium!.copyWith(color: bal[keyOf(p)]! > 0 ? l.accent : null)),
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
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(t.owes(label(from), label(to), '${money(c, de: t.de)} €'), style: tt.bodyMedium)),
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
            child: Container(
              padding: const EdgeInsets.all(FasanSpace.m),
              decoration: BoxDecoration(color: l.surfaceAlt, borderRadius: BorderRadius.circular(l.radius * 0.7)),
              child: Row(children: [
                FasanAvatar(name: f.name, index: f.color, size: 40),
                const SizedBox(width: FasanSpace.m),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f.name, style: tt.titleMedium), Text(t.billsCount(f.bills), style: tt.bodySmall)])),
                if (f.bills > 0) Text('${money(f.sum, de: t.de)} €', style: tt.titleMedium),
              ]),
            ),
          ),
        ),
    ]);
  }
}
