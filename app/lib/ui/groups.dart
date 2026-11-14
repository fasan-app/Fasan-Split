// SPDX-License-Identifier: MPL-2.0
// Fasan Split – Gruppen and Freunde, group page. A group is local until it is shared live (see collab_ui.dart); the
// invitation and the live part of a group live in collab_ui.dart. MPL-2.0
import 'person_avatar.dart';
import '../l10n/tr.dart';
import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';

import '../collab/group.dart';
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
import 'shape_tokens.dart';
export 'friends_page.dart';
export 'settle_dialogs.dart';
import 'settle_dialogs.dart' show giveFlow, markPaidIn;

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
                  onPressed: () => markPaidIn(context, name, label(from), label(to), c),
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
