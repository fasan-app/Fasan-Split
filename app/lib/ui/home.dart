// SPDX-License-Identifier: MPL-2.0
// Fasan Split – start: three main tabs below (Rechnungen, Gruppen, Freunde), a floating plus for new bills, and on Rechnungen
// three views above (Offen, Archiv, Papierkorb). One horizontal pager carries all five pages, so swiping moves through
// them in order (Nutzer 02.11.). Research: fasan_ui docs/recherche/2026-11-02-navigation-layout-glas-ton.md. MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'dart:async';
import 'home_bars.dart';
export 'home_bars.dart' show BillList;

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../platform/web_platform.dart';
import 'scope.dart';
import 'package:fasan_core/bill.dart';
import '../flows/scan_queue.dart';
import '../state/store.dart';
import '../flows/update.dart';
import 'add_bill.dart';
import 'bill_tile.dart';
import 'hints.dart';
import 'collab_ui.dart';
import 'backup_ui.dart';
import 'category_ui.dart';
import 'bill_notes.dart' show BillNotes;
import 'common.dart';
import 'my_balance.dart';
import 'brand_mark.dart';
import 'scope_sheet.dart';
import 'groups.dart';
import 'balance_breakdown.dart' show GroupBreakdownScreen;
import 'item_sheet.dart' show showItemSheet;
import 'group_header.dart';
import 'group_picker.dart';
import 'onboarding.dart';
import 'update_ui.dart';
import '../state/images.dart';
import 'search_suggest.dart';
import 'send_items.dart';
import 'shape_tokens.dart';

part 'home_lists.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.queue});

  /// Test hook: a prepared queue instead of the real recognition.
  final ScanQueue? queue;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UpdateInfo? _update;
  bool _webUpdate = false;
  Timer? _webTimer; // browser: looks for a newer build again and again (Nutzer 08.11.: nobody knows when to reload)
  ScanQueue? _queue;
  bool _selecting = false;
  String? _catFilter; // category filter of the lists, null = all
  bool _dragging = false; // bills are lifted: drop targets light up (segments above, Gruppen tab)
  final Set<String> _selected = {};
  /// Selected items of the Posten view, as „billId/position“ (Nutzer 12.11.: select in Posten too).
  final Set<String> _selItems = {};
  final _pager = PageController();
  int _page = 0; // 0 open, 1 archive, 2 trash (tab Gruppe), 3 Abrechnung, 4 friends
  // Which of the three bill lists the Gruppe page shows. Archive and trash are views of that ONE page, not pages of the pager:
  // swiping only moves between Gruppe, Abrechnung and Freunde (Nutzer 09.11. 18:44: pages of the hidden lists scrolled by).
  int _view = 0;
  String _scope = kScopeAll; // what the group picker shows: Alle, Ohne Gruppe or one group (Option A, Nutzer 08.11.)
  Set<ItemFill> _fills = {}; // status buttons under the frame (Nutzer 09.11.): which items to show
  bool _noPayer = false; // only bills nobody paid yet
  bool _searching = false; // search field in the context row (Nutzer 09.11.)
  String _query = '';
  final _searchCtl = TextEditingController(); // set from a recent search or a suggestion
  bool _itemsView = false; // Gruppe tab: false = bills, true = all items of the scope
  List<(Bill, BillItem?)> _visibleItems = const []; // the items the Posten view shows right now (filters and search applied); „sichtbare Posten schicken“

  /// The picked scope; „Alle“ when the picked group is gone (deleted, left).
  String _scopeOf(BillStore s) => scopeIsGroup(_scope) && !s.allGroups.contains(_scope) ? kScopeAll : _scope;

  /// A group made through the „+“ of the picker: the new name is the one that was not there before, and it is picked.
  Future<void> _newGroup(BuildContext context) async {
    final store = StoreScope.read(context);
    final before = store.allGroups.toSet();
    await groupPlusAction(context, queue: queue);
    if (!mounted) return;
    final added = store.allGroups.where((g) => !before.contains(g));
    if (added.isNotEmpty) setState(() => _scope = added.first);
  }

  /// Reads several photos one after the other; lives as long as the start page (which stays under every other page).
  ScanQueue get queue => ScanQueue.current = _queue ??= widget.queue ?? ScanQueue(StoreScope.read(context));

  BillList? get _list => _page <= 2 ? BillList.values[_page] : null;

  @override
  void dispose() {
    _webTimer?.cancel();
    _searchCtl.dispose();
    _pager.dispose();
    super.dispose();
  }

  /// A shared account that was never saved to a file: the hint comes at once (not only after 3 bills and 10 changes); „Später“ holds it
  /// back for 3 days like the normal hint.
  bool _accountUnsaved(BillStore store) {
    if (!CollabScope.of(context).hasGroups || store.lastBackup != null) return false;
    final s = store.backupHintSnoozed;
    return s == null || DateTime.now().difference(s).inDays >= 3;
  }

  /// Browser: a stale tab must not keep writing old data into shared bills. A newer build reloads the page by itself as soon as
  /// nothing is being read; while a bill is being read the banner shows (and comes back after every check).
  Future<void> _checkWebBuild() async {
    if (!await webUpdateAvailable() || !mounted) return;
    final busy = ScanQueue.current?.open ?? 0;
    if (busy == 0) {
      StoreScope.read(context).flush(); // everything typed so far is saved before the page goes
      reloadPage();
      return;
    }
    CollabScope.read(context).writesPaused = true; // stale page: no more writes into shared bills until it has reloaded
    setState(() => _webUpdate = true);
  }

  /// At most once a day, only if enabled (Settings → Updates); silent without network.
  Future<void> _checkUpdate() async {
    if (kIsWeb) {
      unawaited(askPersistentStorage()); // keep IndexedDB/localStorage (browser decides)
      // Browser: no APK, only "load the page again" when the server has a newer build (web_platform_web.dart).
      await _checkWebBuild();
      _webTimer ??= Timer.periodic(const Duration(minutes: 10), (_) => _checkWebBuild());
      return;
    }
    final store = StoreScope.read(context);
    final last = store.lastUpdateCheck;
    if (!store.autoUpdate || (last != null && DateTime.now().difference(last) < const Duration(hours: 20))) return;
    store.lastUpdateCheck = DateTime.now();
    final u = await Updates.available();
    if (mounted && u != null) setState(() => _update = u);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
    // first start: introduction (skippable, Beschluss 02.11.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = StoreScope.read(context);
      // Opened through an invitation: the join screen comes first, the introduction would cover it.
      if (!startedWithInvite && !store.onboarded && store.bills.isEmpty) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      }
    });
  }

  // ---- paging ----

  void _goTo(int page) {
    if (page == _page) return;
    FasanHaptics.of(context).tap();
    if (_selecting) _exitSelect();
    final m = FasanMotion.of(context);
    final target = page <= 2 ? 0 : page - 2; // pager index
    if (page <= 2) {
      setState(() {
        _view = page;
        _page = page;
      });
    }
    if (!_pager.hasClients || (_pager.page ?? 0).round() == target) return;
    if (m.enabled) {
      _pager.animateToPage(target, duration: m.medium, curve: FasanCurves.medium);
    } else {
      _pager.jumpToPage(target);
    }
  }

  // ---- adding bills ----

  /// Messages float above the glass bar at the bottom (otherwise it covers „Rückgängig“).
  SnackBar _msg(BuildContext context, String text, {SnackBarAction? action, Duration? duration}) =>
      noteBar(text, action: action, duration: duration ?? const Duration(seconds: 4), margin: EdgeInsets.fromLTRB(FasanSpace.m, 0, FasanSpace.m, 150 + MediaQuery.paddingOf(context).bottom));

  Future<void> _pickMany(BuildContext context) => pickBillPhotos(context, queue, onQueued: (n) {
        if (!mounted) return;
        if (_page != 0) _goTo(0);
        ScaffoldMessenger.of(this.context).showSnackBar(_msg(this.context, S.of(this.context).queuedN(n)));
      });

  Future<void> _addSheet(BuildContext context) {
    final scope = _scopeOf(StoreScope.read(context));
    final g = scopeGroup(scope);
    return addBillSheet(context, queue,
        group: g,
        people: g == null ? const [] : CollabScope.read(context).peopleOf(g),
        groupMenu: g == null,
        onQueued: _queuedMsg);
  }

  void _queuedMsg(int n) {
    if (!mounted) return;
    if (_page != 0) _goTo(0);
    ScaffoldMessenger.of(context).showSnackBar(_msg(context, S.of(context).queuedN(n)));
  }

  Future<void> _plus(BuildContext context) async {
    StoreScope.read(context).hintDismiss('plus');
    if (_page <= 2) return _addSheet(context);
    if (_page == 3) return groupPlusAction(context, queue: queue);
    final t = S.of(context);
    final store = StoreScope.read(context);
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_page == 3 ? t.newGroup : t.newFriend),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: _page == 3 ? t.groupName : t.friendName), onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)), TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(t.ok))],
      ),
    );
    c.dispose();
    if (name == null || name.trim().isEmpty) return;
    if (_page == 3) {
      store.addGroup(name);
    } else {
      store.addFriend(name);
    }
  }

  // ---- selection, groups, delete ----

  void _toggle(String id) {
    FasanHaptics.of(context).tap();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _exitSelect() => setState(() {
        _selecting = false;
        _selected.clear();
        _selItems.clear();
      });

  void _toggleItem(Bill b, BillItem it) {
    FasanHaptics.of(context).tap();
    final k = '${b.id}/${b.its.indexOf(it)}';
    setState(() {
      if (!_selItems.remove(k)) _selItems.add(k);
    });
  }

  /// What the selection holds, as bill → item positions (bills: all their items), for sending.
  Map<Bill, Set<int>> _sendable(BillStore s) {
    final out = <Bill, Set<int>>{};
    if (_itemsView) {
      for (final k in _selItems) {
        final at = k.lastIndexOf('/');
        final b = s.bills.where((x) => x.id == k.substring(0, at)).firstOrNull;
        if (b != null) (out[b] ??= {}).add(int.parse(k.substring(at + 1)));
      }
    } else {
      for (final b in _picked(s)) {
        out[b] = {for (var i = 0; i < b.its.length; i++) i};
      }
    }
    return out;
  }

  List<Bill> _picked(BillStore s) => [for (final b in s.bills) if (_selected.contains(b.id)) b];

  Future<void> _groupDialog(BuildContext context, List<Bill> list) async {
    final store = StoreScope.read(context), t = S.of(context);
    final c = TextEditingController(text: list.length == 1 ? list.first.group ?? '' : '');
    final existing = store.allGroups;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.groupTitle),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: t.groupName), textCapitalization: TextCapitalization.sentences, onSubmitted: (v) => Navigator.of(ctx).pop(v)),
          if (existing.isNotEmpty) ...[
            const SizedBox(height: FasanSpace.m),
            Wrap(spacing: FasanSpace.s, runSpacing: FasanSpace.s, children: [
              for (final g in existing) ActionChip(label: Text(g), onPressed: () => Navigator.of(ctx).pop(g)),
            ]),
          ],
        ]),
        actions: [
          if (list.any((b) => b.group != null)) TextButton(onPressed: () => Navigator.of(ctx).pop(''), child: Text(t.ungroup)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: Text(t.ok)),
        ],
      ),
    );
    c.dispose();
    if (r == null) return;
    final same = existing.where((g) => g.toLowerCase() == r.trim().toLowerCase());
    store.setGroup(list, same.isEmpty ? r : same.first); // no second „WG“ next to „wg“
    if (same.isEmpty && r.trim().isNotEmpty && mounted) showNote(this.context, trLang(S.of(this.context).de ? 'de' : 'en', 'home.newGroup', [r.trim()]));
    if (mounted) {
      FasanHaptics.of(this.context).snap();
      _exitSelect();
    }
  }

  /// Bills dropped on Offen, Archiv or Papierkorb.
  void _dropOnList(BuildContext context, BillStore store, List<Bill> list, BillList target) {
    FasanHaptics.of(context).snap();
    _exitSelect();
    switch (target) {
      case BillList.trash:
        _toTrash(context, list);
      case BillList.archive:
        store.untrash(list.where((b) => b.trashedAt != null).toList());
        _toArchive(context, list, true);
      case BillList.open:
        store.untrash(list.where((b) => b.trashedAt != null).toList());
        _toArchive(context, list, false);
    }
  }

  /// A message with „Rückgängig“ for a change that moved bills.
  void _undoable(BuildContext context, String text, VoidCallback undo) {
    final msg = ScaffoldMessenger.of(context);
    msg.clearSnackBars();
    msg.showSnackBar(_msg(context, text, duration: const Duration(seconds: 5), action: SnackBarAction(label: S.of(context).undo, onPressed: undo)));
  }

  /// To the trash (nothing is lost: 7 or 30 days, or until emptied by hand).
  void _toTrash(BuildContext context, List<Bill> list) {
    final store = StoreScope.read(context), t = S.of(context);
    for (final b in list) {
      queue.forget(b.id);
    }
    store.trash(list);
    _undoable(context, t.trashedN(list.length), () => store.untrash(list));
  }

  /// Archive = settled (paid back), Nutzer 04.11.; bills not entered yet stay under Offen with a note.
  void _toArchive(BuildContext context, List<Bill> list, bool settled) {
    final store = StoreScope.read(context), t = S.of(context);
    final changed = store.setSettled(list, settled);
    final skipped = list.length - changed.length;
    if (changed.isEmpty) {
      if (settled && skipped > 0) showNote(context, trLang(t.de ? 'de' : 'en', 'home.enterItFirstAll'));
      return;
    }
    _undoable(context, settled ? t.archivedN(changed.length) : t.reopenedN(changed.length), () => store.setSettled(changed, !settled));
  }

  Future<bool> _confirmForever(BuildContext context, int n) async {
    final t = S.of(context);
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteForeverTitle),
        content: Text(t.deleteForeverBody(n)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.deleteForever))],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final store0 = StoreScope.of(context);
    final t = S.of(context);
    final store = StoreScope.of(context);
    final selected = _picked(store);
    final list = _list;
    // The selection mode stays until it is left again: with the X, with the same icon, or with „Zurück“ (Nutzer 02.11.).
    final selecting = _selecting && list != null;
    final count = _itemsView && _page <= 2 && scopeIsGroup(_scopeOf(store)) ? _selItems.length : selected.length;
    final any = count > 0;
    final inTrash = list == BillList.trash;
    final inArchive = list == BillList.archive;
    return PopScope(
      canPop: !selecting && _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          _exitSelect();
        } else {
          _goTo(0);
        }
      },
      child: Scaffold(
        extendBody: false, // the list ends above the bar: no frames biting each other (Nutzer 09.11.)
        appBar: selecting
            ? AppBar(
                leading: IconButton(tooltip: t.cancel, icon: const Icon(Icons.close_rounded), onPressed: _exitSelect),
                title: Text(_dragging ? (trLang(t.de ? 'de' : 'en', 'home.dragOntoATarget')) : any ? t.nSelected(count) : t.selectHint),
                // while dragging only the targets below act (Nutzer 04.11.: two sets of archive/trash symbols)
                actions: _dragging ? const [] : [
                  if (inTrash) ...[
                    IconButton(tooltip: t.restore, icon: const Icon(Icons.restore_from_trash_rounded), onPressed: !any ? null : () {
                      store.untrash(selected);
                      _exitSelect();
                    }),
                    const SizedBox(width: FasanSpace.l),
                    IconButton(tooltip: t.deleteForever, style: IconButton.styleFrom(foregroundColor: Colors.red.shade600), icon: Icon(Icons.delete_forever_outlined, color: Colors.red.shade600), onPressed: !any ? null : () async {
                      final l = selected;
                      if (await _confirmForever(context, l.length)) {
                        store.deleteForever(l);
                        _exitSelect();
                      }
                    }),
                  ] else ...[
                    IconButton(tooltip: t.groupTitle, icon: const Icon(Icons.folder_outlined), onPressed: any ? () => _groupDialog(context, selected) : null),
                    IconButton(
                      tooltip: inArchive ? t.markOpen : t.markDone,
                      icon: Icon(inArchive ? Icons.unarchive_outlined : Icons.task_alt_rounded),
                      onPressed: !any ? null : () {
                        final l = selected;
                        _exitSelect();
                        _toArchive(context, l, !inArchive);
                      },
                    ),
                    // red and set apart (Nutzer 12.11.): nobody deletes by accident while reaching for „Schicken“
                    const SizedBox(width: FasanSpace.l),
                    IconButton(
                      tooltip: t.delete,
                      style: IconButton.styleFrom(foregroundColor: Colors.red.shade600), // the theme's icon button style would override `color`
                      icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade600),
                      onPressed: !any ? null : () {
                        final l = selected;
                        _exitSelect();
                        _toTrash(context, l);
                      },
                    ),
                  ],
                ],
              )
            : AppBar(
                // the same on every main page (Nutzer 09.11.): Fasan symbol left, news and my profile right; nothing else up here
                leadingWidth: 56,
                leading: const Padding(padding: EdgeInsets.only(left: FasanSpace.l), child: Center(child: FasanMark())),
                title: const SizedBox.shrink(),
                actions: const [ActivityBell(), MyBalanceBadge(), SizedBox(width: FasanSpace.s)],
              ),
        body: Column(children: [
          // context row, the same height on every main page so nothing jumps (Nutzer 09.11.): the group switch on the left,
          // filter and the more menu on the right; room for the search to come (docs/KONZEPT-STARTBILDSCHIRM.md)
          Padding(
            padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.s, 0),
            child: SizedBox(
              height: FasanLook.of(context).minTap,
              child: Row(children: [
                Expanded(child: _contextLeft(context, store0, t)),
                if (_page <= 2 && !_searching)
                  IconButton(tooltip: trLang(t.de ? 'de' : 'en', 'search.tip'), icon: Icon(Icons.search_rounded, color: _query.isEmpty ? null : FasanLook.of(context).accent), onPressed: () => setState(() => _searching = true)),
                if (_page <= 2) _viewMenu(context),
                if (list != null && list != BillList.trash && _hasAny(store, list))
                  IconButton(
                    tooltip: trLang(t.de ? 'de' : 'en', 'home.sortAndFilter'),
                    icon: Badge(isLabelVisible: _catFilter != null || store.sortMode != BillSort.status || store.onlyOpen, smallSize: 8, child: const Icon(Icons.filter_list_rounded)),
                    onPressed: () => sortSheet(context, filter: _catFilter, onFilter: (f) => setState(() => _catFilter = f)),
                  ),
                _moreMenu(context, store, list),
              ]),
            ),
          ),
          Expanded(
            child: PageView(
          controller: _pager,
          // the neighbour page is built before the swipe starts: its top does not pop in afterwards (Nutzer 09.11.)
          allowImplicitScrolling: true,
          onPageChanged: (p) {
            FasanHaptics.of(context).tap();
            setState(() {
              _page = p == 0 ? _view : p + 2;
              _selecting = false;
              _selected.clear();
            });
          },
          children: [
            KeyedSubtree(key: ValueKey('list-$_view'), child: _listPage(context, BillList.values[_view])),
            _settlePage(context),
            const FriendsPage(),
          ],
            ),
          ),
        ]),
        floatingActionButton: selecting
            ? null
            : PulseRing(
                active: store0.bills.isEmpty && !store0.hintDone('plus'),
                // same radius and shadow as the cards, solid accent (04.11.: glow and tinted halo looked off)
                child: FasanDepth(
                  radius: FasanLook.of(context).rCard,
                  level: 2,
                  child: FloatingActionButton(
                    elevation: 0,
                    focusElevation: 0,
                    hoverElevation: 0,
                    highlightElevation: 0,
                    backgroundColor: FasanLook.of(context).accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FasanLook.of(context).rCard)),
                    tooltip: _page <= 2 ? t.newBill : (_page == 3 ? t.newGroup : t.newFriend),
                    onPressed: () => _plus(context),
                    child: const Icon(Icons.add_rounded, size: 28),
                  ),
                ),
              ),
        bottomNavigationBar: selecting && !_dragging && !inTrash
            ? HomeSelectBar(
                count: count,
                onSend: !any ? null : () async {
                  final map = _sendable(store);
                  await sendItemsOfBills(context, map);
                  if (mounted) _exitSelect();
                },
              )
            : _dragging && list != null
            ? HomeDropDock(
                from: list,
                onList: (bills, target) => _dropOnList(context, store, bills, target),
                onGroup: (bills) => _groupDialog(context, bills),
              )
            : HomeNavBar(
          badges: [0, CollabScope.of(context).unreadGroups, CollabScope.of(context).unreadDirects],
          selected: _page <= 2 ? 0 : _page - 2,
          onSelect: (i) => _goTo(i == 0 ? (_page <= 2 ? _page : _view) : i + 2),
          // bills dropped on „Gruppen“: choose a group or name a new one (same dialog as the button)
          onDropGroup: null,
        ),
      ),
    );
  }

  /// The ⋮ menu of the context row (Nutzer 09.11.): select (formerly its own icon), and the group actions when a group is chosen.
  /// Entries stay and are greyed out when they cannot act (docs/recherche: never hide menu entries).
  Widget _moreMenu(BuildContext context, BillStore store, BillList? list) {
    final t = S.of(context);
    final canSelect = _selecting || (list != null && (_itemsView ? _hasVisibleItems : _hasAny(store, list)));
    void toggleSelect() => _selecting ? _exitSelect() : setState(() => _selecting = true);
    if (_page <= 2 && scopeIsGroup(_scopeOf(store))) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        if (_itemsView && _hasVisibleItems) IconButton(key: const ValueKey('send-visible'), tooltip: trLang(t.de ? 'de' : 'en', 'send.filtered'), icon: const Icon(Icons.forward_to_inbox_outlined), onPressed: () => _sendVisible(context)),
        ...groupActions(context, _scopeOf(store), compact: true, onDeleted: () => setState(() => _scope = kScopeAll), onSelect: canSelect ? toggleSelect : null, selecting: _selecting),
      ]);
    }
    if (_page > 2) {
      return PopupMenuButton<String>(
        tooltip: t.settings,
        onSelected: (_) => FriendsPage.inviteFriend(context),
        itemBuilder: (_) => [PopupMenuItem(value: 'invite', child: Text(trLang(t.de ? 'de' : 'en', 'groups.inviteAFriend')))],
      );
    }
    return PopupMenuButton<String>(
      key: const ValueKey('more-menu'),
      onSelected: (v) => v == 'send' ? _sendVisible(context) : toggleSelect(),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'select', enabled: canSelect, child: Text(_selecting ? trLang(t.de ? 'de' : 'en', 'select.end') : t.select)),
        if (_itemsView) PopupMenuItem(value: 'send', enabled: _hasVisibleItems, child: Text(trLang(t.de ? 'de' : 'en', 'send.filtered'))),
      ],
    );
  }

  bool get _hasVisibleItems => _visibleItems.any((e) => e.$2 != null);

  /// Sends the items the Posten view shows (filters and search applied) as cards into the chats of their groups.
  Future<void> _sendVisible(BuildContext context) {
    final byBill = <Bill, Set<int>>{};
    for (final (b, it) in _visibleItems) {
      if (it == null) continue;
      final i = b.its.indexOf(it);
      if (i >= 0) (byBill[b] ??= {}).add(i);
    }
    return sendItemsOfBills(context, byBill);
  }

  /// What a search looks at: purpose, place, people, item names and the amount as written (Karte-Recherche: Suche über Zweck, Zahler und Betrag).
  String _searchText(Bill b, bool de) => billSearchText(b, de);

  /// Last searches under the search field: tap one to search it again, the x removes it alone.
  Widget _recentSearches(BuildContext context, BillStore store) {
    final l = FasanLook.of(context), lang = S.of(context).de ? 'de' : 'en';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, key: const ValueKey('recent-searches'), children: [
      Padding(padding: const EdgeInsets.fromLTRB(4, FasanSpace.s, 4, 0), child: FasanLabel(trLang(lang, 'search.recent'))),
      for (final r in store.recentSearches)
        SizedBox(
          height: l.minTap,
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  _searchCtl.text = r;
                  _searchCtl.selection = TextSelection.collapsed(offset: r.length);
                  setState(() => _query = r);
                },
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history_rounded, size: 20, color: l.textMuted),
                    const SizedBox(width: FasanSpace.s),
                    Flexible(child: Text(r, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
            ),
            IconButton(key: ValueKey('forget-$r'), tooltip: trLang(lang, 'search.forget'), icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => store.forgetSearch(r)),
          ]),
        ),
    ]);
  }

  /// „Keine Treffer“, with „Meintest du …?“ when a word looks like a typo of a word in these bills.
  Widget _noHits(BuildContext context, BillStore store, List<Bill> scopeBills, String q) {
    final lang = S.of(context).de ? 'de' : 'en', tt = Theme.of(context).textTheme, l = FasanLook.of(context);
    final fix = q.isEmpty
        ? null
        : didYouMean(q, [
            for (final b in scopeBills) ...[b.purpose, for (final p in b.ps) p.name, for (final i in b.its) i.name]
          ]);
    return Column(children: [
      Padding(padding: const EdgeInsets.all(FasanSpace.l), child: Text(trLang(lang, 'filter.none'), style: tt.bodyMedium, textAlign: TextAlign.center)),
      if (fix != null)
        TextButton(
          key: const ValueKey('did-you-mean'),
          style: TextButton.styleFrom(minimumSize: Size(l.minTap, l.minTap)),
          onPressed: () {
            _searchCtl.text = fix;
            _searchCtl.selection = TextSelection.collapsed(offset: fix.length);
            store.rememberSearch(fix);
            setState(() => _query = fix);
          },
          child: Text(trLang(lang, 'search.didYouMean', [fix])),
        ),
    ]);
  }

  /// The first item of [b] that the search words hit, or null (the name of the bill or a person matched, or nothing is searched).
  int? _hitItem(Bill b, String q, bool de) {
    if (q.isEmpty) return null;
    final i = b.its.indexWhere((it) => it.name.toLowerCase().contains(q) || (it.note ?? '').toLowerCase().contains(q) || money(it.amount, de: de).contains(q));
    return i < 0 ? null : i;
  }

  /// Search in the items view: the bill head (name, people) matching shows all its items; otherwise only items whose name or
  /// amount match.
  bool _itemMatches(Bill b, BillItem i, String q, bool de) => itemSearchMatch(b, i, q, de);

  Widget _contextLeft(BuildContext context, BillStore store0, S t) {
    if (_page <= 2 && _searching) {
      return TextField(
        key: const ValueKey('search-field'),
        controller: _searchCtl,
        autofocus: true,
        textInputAction: TextInputAction.search,
        // the keyboard's own suggestions and autocorrect hold back text while composing (Android): the list must follow each letter
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          hintText: trLang(t.de ? 'de' : 'en', 'search.hint'),
          prefixIcon: const Icon(Icons.search_rounded),
          border: InputBorder.none,
          suffixIcon: IconButton(tooltip: t.cancel, icon: const Icon(Icons.close_rounded), onPressed: () {
            if (_query.trim().length >= 3) store0.rememberSearch(_query);
            _searchCtl.clear();
            setState(() {
              _searching = false;
              _query = '';
            });
          }),
        ),
        onChanged: (v) => setState(() => _query = v),
        onSubmitted: (v) => store0.rememberSearch(v),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: _page <= 3
          ? ScopeSwitch(
              groups: store0.allGroups,
              selected: _scopeOf(store0),
              onSelect: (v) => setState(() => _scope = v),
              onNew: () => _newGroup(context),
            )
          : Padding(padding: const EdgeInsets.only(left: FasanSpace.s), child: Text(t.friendsTab, style: Theme.of(context).textTheme.titleMedium)),
    );
  }

  /// Offen / Archiv / Papierkorb as a pull-down in the context row (Nutzer 09.11.): the symbol shows the current view; a tint marks
  /// that it is not „Offen“. The views are not swipe pages.
  Widget _viewMenu(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context);
    final names = [t.listOpen, t.listArchive, t.listTrash];
    const icons = [Icons.inbox_outlined, Icons.inventory_2_outlined, Icons.delete_outline_rounded];
    final cur = _page.clamp(0, 2);
    return PopupMenuButton<int>(
      key: const ValueKey('view-menu'),
      tooltip: names[cur],
      initialValue: cur,
      onSelected: _goTo,
      icon: Icon(icons[cur], color: cur == 0 ? null : l.accent),
      itemBuilder: (_) => [
        for (var i = 0; i < 3; i++) CheckedPopupMenuItem<int>(value: i, checked: i == cur, child: Text(names[i])),
      ],
    );
  }

  bool _hasAny(BillStore s, BillList l) => switch (l) {
        BillList.open => s.drafts.isNotEmpty,
        BillList.archive => s.finished.isNotEmpty,
        BillList.trash => s.trashed.isNotEmpty,
      };

  // ---- the three bill lists: home_lists.dart ----

  /// setState for the parts of this screen in other files (extensions may not call the protected setState)
  void _set(VoidCallback f) => setState(f);
}
