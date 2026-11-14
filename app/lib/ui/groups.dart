// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Gruppen and Freunde, group page. A group is local until it is shared live (see collab_ui.dart); the
// invitation and the live part of a group live in collab_ui.dart. MPL-2.0
import 'person_avatar.dart';
import '../l10n/tr.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../collab/group.dart';
import '../collab/notes.dart' show ChatMessage;
import '../collab/service.dart';
import '../l10n.dart';
import '../l10n_collab.dart';
import '../l10n_groups.dart';
import 'package:fasan_core/settle.dart';
import 'scope.dart';
import 'package:fasan_core/bill.dart';
import '../flows/scan_queue.dart';
import 'bill_tile.dart';
import 'collab_ui.dart';
import 'common.dart';
import 'add_bill.dart';
import 'balance_breakdown.dart';
import 'category_ui.dart';
import 'group_header.dart';
import 'hints.dart';
import 'history.dart';
import 'my_balance.dart';
import 'pay_ui.dart';
import 'balance_state_ui.dart';
import 'person_profile.dart';
import 'marquee_text.dart';
import 'shape_tokens.dart';

/// All groups with their number of bills and sum; tap opens the group. Pending join requests are shown on top.
class GroupsPage extends StatelessWidget {
  const GroupsPage({super.key, required this.queue, this.onOpen});

  final ScanQueue queue;

  /// Picks the group in the start page (the same screen as the group picker, Nutzer 12.11.: the card opened a different screen); without it the group screen opens.
  final void Function(String group)? onOpen;

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
            final spend = bills.where((b) => !b.isTransfer).toList(); // settlement payments are no spending
            final sum = spend.fold<int>(0, (a, b) => a + b.effectiveTotal);
            final lg = CollabScope.of(context).groupByLocalName(g), live = lg != null;
            final unread = lg == null ? 0 : CollabScope.of(context).unread(lg);
            final last = lg == null ? null : CollabScope.of(context).lastMessage(lg);
            // the same count as the group header (Nutzer 12.11.: the members were missing here and the numbers differed)
            final nPeople = CollabScope.of(context).peopleOf(g).length;
            final members = trLang(t.de ? 'de' : 'en', nPeople == 1 ? 'groups.oneMember' : 'groups.nMembers', ['$nPeople']);
            return Material(
              color: l.surfaceAlt,
              borderRadius: BorderRadius.circular(l.rCard),
              child: InkWell(
                borderRadius: BorderRadius.circular(l.rCard),
                onTap: () => onOpen != null ? onOpen!(g) : Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(name: g, queue: queue))),
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
                                    ? '${t.billsCount(spend.length)} · $members · ${t.shared}'
                                    : '${t.billsCount(spend.length)} · $members',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall!.copyWith(fontWeight: unread > 0 ? FontWeight.w700 : null)),
                      ]),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Badge(isLabelVisible: unread > 0, label: Text('$unread'), offset: const Offset(10, -6), child: Text('${money(sum, de: t.de)} ${signOf(context)}', style: tt.titleMedium)),
                      // my balance in this group (green = I get, red = I owe)
                      if (myDebts(store.inGroup(g, done: true), myNames(context), isMePerson: myPerson(context)).values.fold(0, (a, x) => a + x) case final sure)
                        if (myProvisional(store.inGroup(g, done: false), myNames(context), isMePerson: myPerson(context)).values.fold(0, (a, x) => a + x) case final soft)
                          if (sure + soft != 0) ...[
                            Text('${money(sure + soft, de: t.de, sign: true)} ${signOf(context)}', style: tt.labelMedium!.copyWith(color: sure + soft > 0 ? Colors.green.shade600 : Colors.red.shade600, fontWeight: FontWeight.w700)),
                            if (soft != 0) Text(trLang(t.de ? 'de' : 'en', 'my_balance.provisionalShort', [money(soft, de: t.de, sign: true)]), style: tt.labelSmall!.copyWith(color: (soft > 0 ? Colors.green.shade600 : Colors.red.shade600).withValues(alpha: 0.65))),
                          ],
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

/// Invite, filter and menu (history, leave, delete) of one group: the app bar of the group screen and of the Gruppe tab with a
/// group picked. [onDeleted] runs after the group was deleted (screen: close it, tab: fall back to „Alle“).
List<Widget> groupActions(BuildContext context, String name, {required VoidCallback onDeleted, bool compact = false, VoidCallback? onSelect, bool selecting = false}) {
  final t = S.of(context);
  final lang = t.de ? 'de' : 'en';
  final store = StoreScope.of(context);
  final live = CollabScope.of(context).groupByLocalName(name);
  // always there (Nutzer 04.11.): a group only on this phone is shared first, then the link is ready
  Future<void> invite() async {
    final g = live ?? await shareLive(context, name);
    if (g != null && context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(group: g)));
  }

  // [compact]: in the Gruppe tab the app bar is full already; invite moves into the menu and the filter stays a chip on the list
  return [
          if (!compact) IconButton(tooltip: t.invite, icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: invite),
          if (!compact)
          IconButton(
            tooltip: trLang(lang, store.onlyOpen ? 'filter.allItems' : 'filter.onlyOpen'),
            isSelected: store.onlyOpen,
            icon: const Icon(Icons.filter_alt_outlined),
            selectedIcon: const Icon(Icons.filter_alt_rounded),
            onPressed: () => store.onlyOpen = !store.onlyOpen,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'select') {
                onSelect?.call();
                return;
              }
              if (v == 'invite') {
                await invite();
                return;
              }
              if (v == 'history') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen.group(groupTag: live?.secret.tag ?? '', groupName: name)));
                return;
              }
              if (v == 'leave' && live != null) {
                await leaveGroupFlow(context, live);
                return;
              }
              if (v == 'delete' && await confirmDialog(context, t.deleteGroup, name, t.deleteGroup) && context.mounted) {
                store.deleteGroup(name);
                onDeleted();
              }
            },
            itemBuilder: (_) => [
              // while selecting the entry ends the selection (Nutzer 12.11.: „Auswählen“ made no sense then)
              if (onSelect != null) PopupMenuItem(value: 'select', child: Text(selecting ? trLang(lang, 'select.end') : t.select)),
              if (compact) PopupMenuItem(value: 'invite', child: Text(t.invite)),
              PopupMenuItem(value: 'history', child: Text(trLang(lang, 'history.title'))),
              if (live != null) PopupMenuItem(value: 'leave', child: Text(t.leaveGroup)),
              if (live == null) PopupMenuItem(value: 'delete', child: Text(t.deleteGroup)),
            ],
          ),
  ];
}

/// One group: framed header (bills · price · people), switch Rechnungen | Posten, the live part (when shared) and the invitation (admin).
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.name, required this.queue});

  final String name;
  final ScanQueue queue;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  Set<ItemFill> _fills = {};
  bool _noPayer = false;
  String _q = ''; // search in the group (Nutzer 11.11.: Bier suchen) – same rules as on the start screen
  int _view = 0; // 0 bills, 1 all items of the group (Nutzer 08.11. 04:16)

  String get name => widget.name;
  ScanQueue get queue => widget.queue;

  /// The members, formerly folded at the end of the list: now behind the person symbol in the header (Nutzer 08.11. 04:09).
  void _showPeople(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.xl),
          children: [GroupPeople(name: name)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), tt = Theme.of(context).textTheme;
    final lang = t.de ? 'de' : 'en';
    final store = StoreScope.of(context);
    final all = store.inGroup(name);
    final q = _q.trim().toLowerCase();
    final bills = (store.onlyOpen ? all.where((b) => b.fill != ItemFill.complete).toList() : all).where((b) => billMatches(b, _fills, _noPayer) && (q.isEmpty || billSearchText(b, t.de).contains(q) || (hasPayerRow(b) && payerSearchMatch(context, b, q)))).toList();
    final live = CollabScope.of(context).groupByLocalName(name);
    final l = FasanLook.of(context);
    final people = CollabScope.of(context).peopleOf(name).length;
    final flat = _view == 1 ? flattenItems(bills, favorites: store.favorites, onlyOpen: store.onlyOpen, fills: _fills, itemMatch: q.isEmpty ? null : (b, i) => itemSearchMatch(b, i, q, t.de), payerMatch: q.isEmpty ? null : (b) => payerSearchMatch(context, b, q)) : const <(Bill, BillItem?)>[];
    return Scaffold(
      // the plus inside the group (Nutzer 07.11.): a bill started here is put into this group
      floatingActionButton: FasanDepth(
        radius: l.rCard,
        level: 2,
        child: FloatingActionButton(
          heroTag: 'group-plus-$name',
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          backgroundColor: l.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(l.rCard)),
          tooltip: t.newBill,
          onPressed: () => addBillSheet(context, queue, group: name, onQueued: (n) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.queuedN(n))));
          }),
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
      appBar: AppBar(
        title: Text(name),
        actions: [
          ...groupActions(context, name, onDeleted: () => Navigator.of(context).pop()),
        ],
      ),
      // lazy lists (SliverList): only the visible rows are built, also with hundreds of items (docs/recherche/2026-11-09-…)
      body: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              GroupHeader(
                bills: bills,
                people: people,
                onPrice: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupBreakdownScreen(name: name))),
                onPeople: () => _showPeople(context),
              ),
              GroupCountsLine(bills: all, fills: _fills, noPayer: _noPayer, onFills: (v) => setState(() => _fills = v), onNoPayer: (v) => setState(() => _noPayer = v)),
              const SizedBox(height: FasanSpace.s),
              TextField(
                key: const ValueKey('group-search'),
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: trLang(lang, 'search.hint'), isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: FasanSpace.s),
              FasanSegmented<int>(
                values: const [0, 1],
                selected: _view,
                label: (i) => trLang(lang, i == 0 ? 'grp.bills' : 'grp.items'),
                onChanged: (v) => setState(() => _view = v),
              ),
              const SizedBox(height: FasanSpace.m),
              HintCard(id: 'group_flow', text: trLang(lang, 'hint.groupFlow'), icon: Icons.route_outlined),
              if (live != null) HintCard(id: 'group_everyone', text: trLang(lang, 'hint.everyone'), icon: Icons.groups_2_outlined),
              if (live != null) CollabGroupPanel(group: live),
              if (live == null) _ShareButton(name: name),
              if (_view == 0 && bills.isEmpty) Text(t.groupEmpty, style: tt.bodyMedium),
              if (_view == 1 && flat.isEmpty) Text(trLang(lang, 'grp.noItems'), style: tt.bodyMedium),
            ]),
          ),
        ),
        if (_view == 0)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
            sliver: SliverList.builder(
              itemCount: bills.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: FasanSpace.s),
                child: BillTile(key: ValueKey(bills[i].id), bill: bills[i], queue: queue, selecting: false, selected: false, onToggle: () {}, onRetry: () {}),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
            sliver: SliverList.builder(
              itemCount: flat.length,
              itemBuilder: (_, i) {
                final (b, it) = flat[i];
                if (identical(it, kDifferenceRow)) return GroupRestRow(key: ValueKey('rest-${b.id}'), bill: b, onTap: () => openBill(context, b));
                if (identical(it, kPayerRow)) return GroupPayerRow(key: ValueKey('payer-${b.id}'), bill: b, onTap: () => openBill(context, b));
                return it == null
                    ? GroupBillHeading(key: ValueKey('h-${b.id}'), bill: b, onTap: () => openBill(context, b))
                    : GroupItemRow(key: ValueKey('${b.id}/${b.its.indexOf(it)}'), bill: b, item: it, onTap: () => openBill(context, b));
              },
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom)),
      ]),
    );
  }
}

/// Names in the balance of a group: in a live group every name linked to one member counts as „@pub“ ([keyOf]); [label] turns a key
/// back into the name to show. Shared by the people list and the breakdown („wer wem wie viel“), so both always agree.
({String Function(String) keyOf, String Function(String) label}) groupNaming(BuildContext context, String name) {
  final live = CollabScope.read(context).groupByLocalName(name);
  String keyOf(String p) => switch (live?.session.memberOfPerson(p)) { final m? => '@$m', _ => p };
  String label(String k) => k.startsWith('@') && live != null ? (live.session.personOf(k.substring(1)) ?? live.session.nameOf(k.substring(1))) : k;
  return (keyOf: keyOf, label: label);
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
    final (:keyOf, :label) = groupNaming(context, name);
    final bal = store.groupBalance(name, key: keyOf);
    final gaps = store.groupGaps(name, key: keyOf);
    final moves = settle(bal);
    final anyDone = store.inGroup(name, done: true).isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (anyDone)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.calculate_outlined),
            label: Text(trLang(t.de ? 'de' : 'en', 'breakdown.groupTitle')),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupBreakdownScreen(name: name))),
          ),
        ),
      if (people.isEmpty) Text(t.groupNoPeople, style: tt.bodyMedium!.copyWith(color: l.textMuted)),
      for (final (i, p) in people.indexed)
        Container(
          constraints: BoxConstraints(minHeight: l.minTap),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: l.hairline))),
          child: Row(children: [
            Expanded(
              // the profile of the person (Nutzer 12.11.): status, balance, groups, changes, and the actions that used to be in a sheet;
              // a sibling of the balance button, not its parent, so both stay buttons for screen readers
              child: InkWell(
                onTap: () => openProfile(context, groupName: name, person: p),
                child: Row(children: [
                  PersonAvatar(name: p, index: i, size: 32),
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
                        null => t.nameOnlyText,
                        final m when label('@$m') != p => '${t.linkedAccountText} · ${t.countsWith(label('@$m'))}',
                        _ => t.linkedAccountText,
                      },
                      style: tt.bodySmall!.copyWith(color: l.textMuted),
                    ),
                  ),
              ]),
                  ),
                ]),
              ),
            ),
            // 0 € and „ungewiss“ are shown too, not only a non-zero amount (Nutzer 12.11.)
            if (label(keyOf(p)) == p)
              PersonBalance(cents: bal[keyOf(p)] ?? 0, gap: gaps[keyOf(p)], onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupBreakdownScreen(name: name, person: keyOf(p))))),
            if (store.isHandMember(name, p))
              IconButton(tooltip: t.cancel, icon: const Icon(Icons.close_rounded), onPressed: () => store.removeGroupMember(name, p)),
          ]),
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
      // interim payment or lent money (Nutzer 07.11.): any time, between any two people; the balance moves at once
      if (people.length >= 2)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.swap_horiz_rounded),
            label: Text(trLang(t.de ? 'de' : 'en', 'groups.give')),
            onPressed: () => giveFlow(context, name, people),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.owes(label(from), label(to), '${money(c, de: t.de)} ${signOf(context)}'), style: tt.bodyMedium),
              // the actions under the sentence, each with a label (Prüfliste: no bare icons): my debt → pay with one tap (pay_ui.dart);
              // anyone → „bezahlt“ books this one payment (Beschluss 06.11.)
              Wrap(spacing: FasanSpace.s, children: [
                if (myNames(context)(label(from)) || from == '@${CollabScope.read(context).identity?.pub}')
                  TextButton.icon(
                    icon: const Icon(Icons.payments_outlined),
                    onPressed: () => payFlow(context,
                        name: label(to), pub: to.startsWith('@') ? to.substring(1) : live?.session.memberOfPerson(to), cents: c, currency: StoreScope.read(context).homeCurrency, purpose: name),
                    label: Text(trLang(t.de ? 'de' : 'en', 'groups.pay')),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  onPressed: () => _markPaidIn(context, name, label(from), label(to), c),
                  label: Text(trLang(t.de ? 'de' : 'en', 'groups.markPaidLong')),
                ),
              ]),
            ]),
          ),
        if (moves.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FasanSpace.s),
            child: FasanButton(
              label: trLang(t.de ? 'de' : 'en', 'groups.everyonePaidSettle'),
              icon: Icons.task_alt_rounded,
              kind: FasanButtonKind.secondary,
              expand: true,
              onPressed: () async {
                final list = store.inGroup(name, done: true, archived: false);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: Text(trLang(t.de ? 'de' : 'en', 'groups.markAllEnteredReceipts', [list.length])),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(trLang(t.de ? 'de' : 'en', 'groups.settle'))),
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
            padding: const EdgeInsets.symmetric(horizontal: FasanSpace.m, vertical: FasanSpace.s + 2),
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

/// The payment flows are used inside the people sheet of the group: after booking, the sheet closes so the note with „Rückgängig“
/// below it can be tapped (a modal sheet would cover it).
void _closeSheet(BuildContext context) {
  if (context.mounted && ModalRoute.of(context) is PopupRoute) Navigator.of(context).pop();
}

/// Interim payment or lent money: asks who gave whom how much and books it like a settlement payment (store.recordPayment).
Future<void> giveFlow(BuildContext context, String group, List<String> people) async {
  final lang = S.of(context).de ? 'de' : 'en';
  final r = await showDialog<({bool loan, String from, String to, int cents, String subject})>(context: context, builder: (_) => _GiveDialog(lang: lang, people: people));
  if (r == null || !context.mounted) return;
  final store = StoreScope.read(context);
  final shown = '${money(r.cents, de: lang == 'de')} ${signOf(context)}';
  final b = store.recordPayment(group, r.from, r.to, r.cents,
      purpose: r.subject.isNotEmpty ? r.subject : trLang(lang, r.loan ? 'groups.loanPurpose' : 'groups.paymentPurpose', [r.from, r.to]), item: trLang(lang, r.loan ? 'groups.loanItem' : 'groups.paymentItem'));
  showNote(context, trLang(lang, r.loan ? 'groups.loanDone' : 'groups.markPaidDone', [r.from, r.to, shown]), actionLabel: context.tr('bill.undo'), onAction: () => store.remove(b));
  _closeSheet(context);
}

class _GiveDialog extends StatefulWidget {
  const _GiveDialog({required this.lang, required this.people});

  final String lang;
  final List<String> people;

  @override
  State<_GiveDialog> createState() => _GiveDialogState();
}

class _GiveDialogState extends State<_GiveDialog> {
  final _field = TextEditingController();
  final _subject = TextEditingController();
  bool _loan = false;
  String? _from, _to;

  @override
  void dispose() {
    _field.dispose();
    _subject.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), lang = widget.lang;
    final v = parseMoney(_field.text);
    final valid = _from != null && _to != null && _from != _to && v != null && v > 0;
    DropdownButtonFormField<String> pick(String label, String? value, ValueChanged<String?> on) => DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [for (final p in widget.people) DropdownMenuItem(value: p, child: Text(p))],
          onChanged: on,
        );
    return AlertDialog(
      title: Text(trLang(lang, 'groups.give')),
      // fixed width: the dropdowns cannot give intrinsic sizes, which AlertDialog asks for
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(trLang(lang, 'groups.giveHint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: FasanSpace.m),
          FasanSegmented<bool>(values: const [false, true], selected: _loan, label: (x) => trLang(lang, x ? 'groups.giveLoan' : 'groups.givePay'), onChanged: (x) => setState(() => _loan = x)),
          const SizedBox(height: FasanSpace.m),
          pick(trLang(lang, 'groups.giveFrom'), _from, (x) => setState(() => _from = x)),
          const SizedBox(height: FasanSpace.s),
          pick(trLang(lang, 'groups.giveTo'), _to, (x) => setState(() => _to = x)),
          const SizedBox(height: FasanSpace.s),
          TextField(
            controller: _field,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: trLang(lang, 'groups.markPaidAmount'), suffixText: signOf(context)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: FasanSpace.s),
          TextField(
            key: const ValueKey('give-subject'),
            controller: _subject,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: trLang(lang, 'groups.giveSubject')),
          ),
        ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: valid ? () => Navigator.pop(context, (loan: _loan, from: _from!, to: _to!, cents: v, subject: _subject.text.trim())) : null, child: Text(t.ok)),
      ],
    );
  }
}

/// Asks, then books „[from] gave [to] [cents]“ in the group [group] of the surrounding page (store.recordPayment), with undo.
Future<void> _markPaidIn(BuildContext context, String group, String from, String to, int cents) async {
  final t = S.of(context);
  final lang = t.de ? 'de' : 'en';
  final amount = '${money(cents, de: t.de)} ${signOf(context)}';
  // the amount can be changed: a part paid now, the rest later (only between 0 and the open amount)
  final paid = await showDialog<int>(context: context, builder: (_) => _PaidDialog(lang: lang, de: t.de, cents: cents, ask: trLang(lang, 'groups.markPaidAsk', [from, to, amount]), amount: amount));
  if (paid == null || !context.mounted) return;
  final store = StoreScope.read(context);
  final shown = '${money(paid, de: t.de)} ${signOf(context)}';
  final b = store.recordPayment(group, from, to, paid, purpose: trLang(lang, 'groups.paymentPurpose', [from, to]), item: trLang(lang, 'groups.paymentItem'));
  showNote(context, trLang(lang, 'groups.markPaidDone', [from, to, shown]), actionLabel: context.tr('bill.undo'), onAction: () => store.remove(b));
  _closeSheet(context);
}

/// Amount for „paid“: the open amount, editable down to a part. Owns its text controller and frees it with the dialog (06.11.: before,
/// a controller made outside the dialog could only be left to the garbage collector, because the dialog still builds while it fades out).
class _PaidDialog extends StatefulWidget {
  const _PaidDialog({required this.lang, required this.de, required this.cents, required this.ask, required this.amount});

  final String lang, ask, amount;
  final bool de;
  final int cents;

  @override
  State<_PaidDialog> createState() => _PaidDialogState();
}

class _PaidDialogState extends State<_PaidDialog> {
  late final _field = TextEditingController(text: money(widget.cents, de: widget.de));

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final v = parseMoney(_field.text);
    final valid = v != null && v > 0 && v <= widget.cents;
    return AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.ask),
        const SizedBox(height: FasanSpace.m),
        TextField(
          controller: _field,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: trLang(widget.lang, 'groups.markPaidAmount'),
            suffixText: signOf(context),
            errorText: _field.text.isEmpty || valid ? null : trLang(widget.lang, 'groups.markPaidTooMuch', [widget.amount]),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: valid ? () => Navigator.pop(context, v) : null, child: Text(trLang(widget.lang, 'groups.markPaid'))),
      ],
    );
  }
}
