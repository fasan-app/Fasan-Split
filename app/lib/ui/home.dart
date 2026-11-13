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
  SnackBar _msg(BuildContext context, String text, {SnackBarAction? action, Duration? duration}) => SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(FasanSpace.m, 0, FasanSpace.m, 150 + MediaQuery.paddingOf(context).bottom),
        action: action,
        // Flutter keeps a snack bar with an action on screen until it is dismissed (`persist` defaults to true then); it has
        // to run out, or „Rückgängig“ would never end.
        persist: false,
        duration: duration ?? const Duration(seconds: 4),
      );

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

  // ---- the three bill lists ----

  Widget _listPage(BuildContext context, BillList mode) {
    final t = S.of(context), l = FasanLook.of(context);
    final store = StoreScope.of(context);
    final tt = Theme.of(context).textTheme;
    final bottom = 96.0; // the last card scrolls fully above the plus button
    if (mode == BillList.trash) return _trashPage(context, store, bottom);
    final done = mode == BillList.archive;
    // sort and category filter (Nutzer 04.11.), category_ui.dart
    final sort = store.sortMode;
    final scope = _scopeOf(store);
    final q = _query.trim().toLowerCase();
    bool keep(Bill b) => billMatches(b, _fills, _noPayer) && (q.isEmpty || _searchText(b, t.de).contains(q) || (hasPayerRow(b) && payerSearchMatch(context, b, q)));
    final groups = [
      for (final g in store.groups)
        if (scope == kScopeAll || scope == g) (g, arrange(store.inGroup(g, archived: done), sort, _catFilter, onlyOpen: store.onlyOpen).where(keep).toList())
    ].where((e) => e.$2.isNotEmpty).toList();
    final loose = scope == kScopeAll || scope == kScopeLoose ? arrange(store.inGroup(null, archived: done), sort, _catFilter, onlyOpen: store.onlyOpen).where(keep).toList() : <Bill>[];
    final shown = [for (final e in groups) ...e.$2, ...loose];
    // nothing at all in this view (not: nothing that passes the buttons)
    final anyHere = [for (final g in store.groups) if (scope == kScopeAll || scope == g) ...store.inGroup(g, archived: done), if (scope == kScopeAll || scope == kScopeLoose) ...store.inGroup(null, archived: done)].isNotEmpty;
    final empty = !anyHere;
    // the whole scope for the frame and the counts, whatever the buttons say
    final scopeBills = scopeIsGroup(scope)
        ? store.inGroup(scope)
        : [if (scope == kScopeAll) for (final g in store.groups) ...store.inGroup(g), ...store.inGroup(null)];
    final flat = _itemsView ? flattenItems(shown, onlyOpen: store.onlyOpen, fills: _fills, itemMatch: q.isEmpty ? null : (b, i) => _itemMatches(b, i, q, t.de), payerMatch: q.isEmpty ? null : (b) => payerSearchMatch(context, b, q)) : const <(Bill, BillItem?)>[];
    _visibleItems = flat;
    // one way of counting everywhere (Nutzer 12.11.: „7 in allen Gruppen, 8 in der Gruppe“): a group counts its members and hand-added people
    // next to the names from its bills (peopleOf); „Alle“ is the union of that over the groups plus the names of bills without a group
    final collab = CollabScope.of(context);
    final peopleCount = scopeIsGroup(scope)
        ? collab.peopleOf(scope).length
        : {
            if (scope == kScopeAll) for (final g in store.allGroups) ...collab.peopleOf(g).map((n) => n.trim().toLowerCase()),
            for (final b in scopeBills) if (b.group == null) for (final p in b.ps) p.name.trim().toLowerCase(),
          }.length;
    // one banner at a time, most important first: update, backup due, home-screen tip (iPhone browser)
    final Widget? banner = done
        ? null
        : (_webUpdate || (kIsWeb && CollabScope.of(context).outdated)) // outdated: a shared bill is newer than this page, it only reads
            ? WebUpdateBanner(onClose: () => setState(() => _webUpdate = false))
            : _update != null
                ? UpdateBanner(info: _update!, onClose: () => setState(() => _update = null))
                : kIsWeb && webGlInfo() == 'none' && !store.hintDone('nogl')
                    ? HintCard(id: 'nogl', text: trLang(t.de ? 'de' : 'en', 'perf.noGl'), icon: Icons.speed_rounded)
                : (store.backupDue || _accountUnsaved(store)) // account in a group and never saved: Safari may delete the site data (Nutzer 08.11.)
                    ? const BackupReminder()
                    // a fresh account that was never saved: say how to keep it (friends asked „what if I close the browser?“)
                    : CollabScope.of(context).identity != null && store.lastBackup == null && !store.hintDone('accountSafe')
                        ? AccountSafetyCard(compact: true, onDone: () => store.hintDismiss('accountSafe'))
                        : kIsWeb && !store.hintDone('homescreen') && needsHomeScreenHint()
                        ? HomeScreenHint(onClose: () => store.hintDismiss('homescreen'))
                        : null;
    if (empty) {
      return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom), children: [
        ?banner,
        if (!done) ...[const StorageWarningCard(), const OpenInviteCard(), const PendingJoinCards()],
        const SizedBox(height: 80),
        Icon(done ? Icons.inventory_2_outlined : Icons.receipt_long_outlined, size: 56, color: l.textMuted),
        const SizedBox(height: FasanSpace.l),
        Text(done ? t.archiveEmptyTitle : t.emptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: FasanSpace.s),
        Text(done ? t.archiveHow : t.emptyText, style: tt.bodyMedium!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
        if (!done) ...[
          const SizedBox(height: FasanSpace.xl),
          FasanButton(label: t.emptyCamera, icon: Icons.photo_camera_outlined, expand: true, onPressed: () => pickBillPhoto(context, ImageSource.camera)),
          const SizedBox(height: FasanSpace.s),
          FasanButton(label: t.galleryOrFile, icon: Icons.photo_library_outlined, kind: FasanButtonKind.secondary, expand: true, onPressed: () => _pickMany(context)),
          const SizedBox(height: FasanSpace.s),
          FasanButton(label: t.manual, icon: Icons.edit_note_rounded, kind: FasanButtonKind.secondary, expand: true, onPressed: () => startManualBill(context)),
          const SizedBox(height: FasanSpace.l),
          Text(t.emptyOr, style: tt.bodySmall!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
        ],
      ]);
    }
    // Slivers instead of one ListView whose children are whole group blocks: a block of 15 bills was built and painted as ONE
    // child on every frame of a scroll (Firefox: ~130 ms per frame, Messung 08.11.). Now only the bills on the screen (and a little
    // around it) exist; the cost no longer grows with the number of bills.
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (banner != null) Padding(padding: const EdgeInsets.only(top: FasanSpace.s), child: banner),
                if (!done) ...[const StorageWarningCard(), const OpenInviteCard(), const PendingJoinCards()],
                // the frame: bills, price, people - for a group, Alle Gruppen and Ohne Gruppe alike (Nutzer 09.11.)
                Padding(
                  padding: const EdgeInsets.only(top: FasanSpace.s),
                  child: GroupHeader(
                    bills: scopeBills,
                    people: peopleCount,
                    onPrice: () => scopeIsGroup(scope) ? Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupBreakdownScreen(name: scope))) : _goTo(3),
                    onPeople: () => _goTo(3),
                  ),
                ),
                GroupCountsLine(
                  bills: scopeBills,
                  fills: _fills,
                  noPayer: _noPayer,
                  onFills: (v) => setState(() => _fills = v),
                  onNoPayer: (v) => setState(() => _noPayer = v),
                ),
                // always visible (Nutzer 09.11.): bills or items
                FasanSegmented<int>(
                  values: const [0, 1],
                  selected: _itemsView ? 1 : 0,
                  label: (i) => trLang(t.de ? 'de' : 'en', i == 0 ? 'grp.bills' : 'grp.items'),
                  onChanged: (v) => setState(() => _itemsView = v == 1),
                ),
                // Notizen, Chat and held changes of a live group: they only existed in the separate group screen, which the group card no longer opens (Nutzer 12.11.)
                if (scopeIsGroup(scope))
                  Builder(builder: (context) {
                    final live = CollabScope.of(context).groupByLocalName(scope);
                    return live == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: FasanSpace.s), child: CollabGroupPanel(group: live));
                  }),
                if (_searching && q.isEmpty && store.recentSearches.isNotEmpty)
                  _recentSearches(context, store)
                else if (shown.isEmpty || (_itemsView && flat.isEmpty))
                  _noHits(context, store, scopeBills, q),
              ]),
            ),
          ),
          if (_itemsView)
            ..._itemSlivers(context, flat)
          else ...[
            for (final (g, bills) in groups) _section(context, store, mode, g, g, bills, showHeading: !scopeIsGroup(scope)),
            _section(context, store, mode, null, null, loose, title: done ? t.finished : t.drafts),
          ],
          SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ),
    );
  }

  /// Edit an item right here, in the same sheet as in the bill (Nutzer 09.11. 18:44). A bill locked against me opens as the bill,
  /// which shows the lock.
  Future<void> _editItem(BuildContext context, Bill b, BillItem it) async {
    final store = StoreScope.read(context);
    if (CollabScope.read(context).lockedAgainstMe(b, b.lockBy)) return openBill(context, b);
    await showItemSheet(context, b, it, changed: () {
      b.checked = false;
      store.upsert(b);
    }, onDelete: () {
      final at = b.its.indexOf(it);
      if (at < 0) return;
      b.its.removeAt(at);
      b.checked = false;
      store.upsert(b);
      final lang = S.of(this.context).de ? 'de' : 'en';
      ScaffoldMessenger.of(this.context).showSnackBar(_msg(this.context, trLang(lang, 'bill.removed', [it.title]), action: SnackBarAction(label: trLang(lang, 'bill.undo'), onPressed: () {
        b.its.insert(at.clamp(0, b.its.length), it);
        store.upsert(b);
      })));
    });
  }

  /// Flat list of items (lazy), a heading per bill; a tap opens the bill.
  List<Widget> _itemSlivers(BuildContext context, List<(Bill, BillItem?)> flat) {
    final lang = S.of(context).de ? 'de' : 'en';
    if (flat.isEmpty) {
      return [SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(FasanSpace.l), child: Text(trLang(lang, 'grp.noItems'), style: Theme.of(context).textTheme.bodyMedium)))];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
        sliver: SliverList.builder(
          itemCount: flat.length,
          itemBuilder: (_, i) {
            final (b, it) = flat[i];
            if (it == null) return GroupBillHeading(key: ValueKey('h-${b.id}'), bill: b, onTap: () => openBill(context, b));
            if (identical(it, kPayerRow)) return GroupPayerRow(key: ValueKey('payer-${b.id}'), bill: b, onTap: () => openBill(context, b));
            if (identical(it, kDifferenceRow)) return GroupRestRow(key: ValueKey('rest-${b.id}'), bill: b, onTap: () => openBill(context, b));
            if (_selecting) {
              final on = _selItems.contains('${b.id}/${b.its.indexOf(it)}');
              return InkWell(
                key: ValueKey('sel-${b.id}/${b.its.indexOf(it)}'),
                onTap: () => _toggleItem(b, it),
                child: Row(children: [
                  Checkbox(value: on, onChanged: (_) => _toggleItem(b, it)),
                  Expanded(child: IgnorePointer(child: GroupItemRow(bill: b, item: it, onTap: () {}))),
                ]),
              );
            }
            return GroupItemRow(key: ValueKey('${b.id}/${b.its.indexOf(it)}'), bill: b, item: it, onTap: () => _editItem(context, b, it));
          },
        ),
      ),
    ];
  }

  /// Tab Abrechnung: with a group picked its people and settlement, otherwise the overview of all groups (balances).
  Widget _settlePage(BuildContext context) {
    final store = StoreScope.of(context);
    final scope = _scopeOf(store);
    if (!scopeIsGroup(scope)) return GroupsPage(queue: queue, onOpen: (g) => setState(() => _scope = g));
    final bottom = 150 + MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom),
      children: [GroupPeople(name: scope)],
    );
  }

  /// One block of the list as a sliver: the heading accepts bills that are dragged onto it (group blocks and the block without
  /// group); every bill row accepts them as well (moveBefore takes over the group of the row). The rows are built only when they are
  /// near the screen (SliverList.builder).
  Widget _section(BuildContext context, BillStore store, BillList mode, String? group, String? groupName, List<Bill> list, {String? title, bool showHeading = true}) {
    if (list.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final t = S.of(context), l = FasanLook.of(context);
    final heading = groupName ?? title ?? '';
    final header = DragTarget<List<Bill>>(
      onWillAcceptWithDetails: (d) => d.data.any((b) => b.group != group),
      onAcceptWithDetails: (d) {
        store.setGroup(d.data, group);
        FasanHaptics.of(context).snap();
        _exitSelect();
      },
      builder: (context, candidate, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(l.radius),
          border: Border.all(color: candidate.isEmpty ? Colors.transparent : l.accent, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, FasanSpace.s, 4, FasanSpace.s),
          child: Row(children: [
            if (groupName != null) ...[Icon(Icons.folder_outlined, size: 16, color: l.textMuted), const SizedBox(width: 6)],
            Expanded(child: FasanLabel(heading)),
            if (groupName != null) Text('${list.where((b) => !b.isTransfer).length} · ${money(list.where((b) => !b.isTransfer).fold(0, (a, b) => a + b.toHome(b.effectiveTotal)), de: t.de)} ${signOf(context)}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
      sliver: SliverMainAxisGroup(slivers: [
        if (showHeading) SliverToBoxAdapter(child: header),
        SliverList.builder(
          itemCount: list.length,
          itemBuilder: (context, i) => Padding(padding: const EdgeInsets.only(bottom: kRowGap), child: _row(context, store, mode, list[i])),
        ),
      ]),
    );
  }

  /// A bill: tap opens it (or selects), swipe right moves it to the archive (or back), swipe left to the trash with
  /// „Rückgängig“. Long press lifts it at once (Nutzer 04.11.: move without letting go) and selects it; while selecting it
  /// lifts all selected bills. Drop on a group, on a bill (goes right before it, store.moveBefore), on Offen/Archiv/
  /// Papierkorb above or on the Gruppen tab below. Letting go without moving keeps the selection. The widget tree is the
  /// same in both modes, so the drag survives the switch into the selection.
  Widget _row(BuildContext context, BillStore store, BillList mode, Bill b) {
    final t = S.of(context), l = FasanLook.of(context);
    final tile = BillTile(bill: b, queue: queue, selecting: _selecting, selected: _selected.contains(b.id), onToggle: () => _toggle(b.id), onRetry: () => _retry(b), focusItem: _searching ? _hitItem(b, _query.trim().toLowerCase(), t.de) : null, trailing: _selecting ? null : _rowMenu(context, store, mode, b));
    final moving = _selecting && _selected.contains(b.id) ? _picked(store) : [b];
    // no swipe on the rows (Nutzer 09.11. 18:44): a swipe on a row would block the swipe to Abrechnung; the actions are in the ⋮ menu
    return KeyedSubtree(
      key: ValueKey('bill-${mode.name}-${b.id}'),
      child: DragTarget<List<Bill>>(
        onWillAcceptWithDetails: (d) => !d.data.any((x) => x.id == b.id),
        onAcceptWithDetails: (d) {
          store.moveBefore(d.data, b);
          FasanHaptics.of(context).snap();
        },
        builder: (context, candidate, _) => Container(
          // drop line above the bill the dragged ones will go before; painted on top, so the row keeps the card's size
          // (a border in `decoration` made it 3 px taller: the swipe surface stood out, Nutzer 04.11.)
          foregroundDecoration: candidate.isEmpty ? null : BoxDecoration(border: Border(top: BorderSide(color: l.accent, width: 3))),
          child: LongPressDraggable<List<Bill>>(
            data: moving,
            delay: const Duration(milliseconds: 300),
            hapticFeedbackOnStart: false,
            onDragStarted: () {
              FasanHaptics.of(context).tap();
              if (!_selected.contains(b.id)) {
                setState(() {
                  _selecting = true;
                  _selected.add(b.id);
                });
              }
              setState(() => _dragging = true);
            },
            onDragEnd: (_) {
              if (mounted) setState(() => _dragging = false);
            },
            // small stack of receipts under the finger (Nutzer 04.11.): the targets below stay visible
            feedback: HomeDragFeedback(bills: moving),
            // above the finger: the target and its text stay readable
            dragAnchorStrategy: (draggable, context, position) => const Offset(44, 120),
            childWhenDragging: Opacity(opacity: 0.35, child: tile),
            child: tile,
          ),
        ),
      ),
    );
  }

  /// The ⋮ of a bill row: what the swipes did (to the archive and back, to the trash) plus „Auswählen“. What cannot be done now is
  /// shown grey with its reason, not hidden (research: hidden entries make people search).
  Widget _rowMenu(BuildContext context, BillStore store, BillList mode, Bill b) {
    final t = S.of(context), lang = t.de ? 'de' : 'en', archive = mode == BillList.archive;
    final canArchive = b.read == BillRead.ok && (archive || b.done);
    return PopupMenuButton<String>(
      key: ValueKey('more-${b.id}'),
      padding: EdgeInsets.zero,
      iconSize: 22,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) {
        FasanHaptics.of(context).tap();
        switch (v) {
          case 'archive':
            _toArchive(context, [b], !archive);
          case 'select':
            setState(() {
              _selecting = true;
              _selected.add(b.id);
            });
          case 'note':
            _editNotes(context, b);
          case 'delete':
            _toTrash(context, [b]);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'archive',
          enabled: canArchive,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(archive ? Icons.unarchive_outlined : Icons.task_alt_rounded),
            title: Text(archive ? t.markOpen : t.markDone),
            subtitle: canArchive ? null : Text(trLang(lang, 'home.enterItFirstAll2')),
          ),
        ),
        // note on the bill, from the list (Nutzer 09.11. 19:08): the same notes as in the bill, with „pin“ for the line under the title
        PopupMenuItem(value: 'note', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.sticky_note_2_outlined), title: Text(trLang(lang, 'home.noteEdit')))),
        PopupMenuItem(value: 'select', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.checklist_rounded), title: Text(t.select))),
        PopupMenuItem(value: 'delete', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700), title: Text(t.delete))),
      ],
    );
  }

  /// The notes of [b] in a sheet over the list: read, write, pin. The tile shows the pinned one at once.
  Future<void> _editNotes(BuildContext context, Bill b) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, MediaQuery.of(ctx).viewInsets.bottom + FasanSpace.l),
        child: SingleChildScrollView(child: BillNotes(bill: b)),
      ),
    );
  }

  /// Trash row: bring it back, or delete it for good (asks first).
  Widget _trashMenu(BuildContext context, BillStore store, Bill b) {
    final t = S.of(context);
    return PopupMenuButton<String>(
      key: ValueKey('more-${b.id}'),
      padding: EdgeInsets.zero,
      iconSize: 22,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) async {
        if (v == 'restore') {
          store.untrash([b]);
        } else if (await _confirmForever(context, 1) && context.mounted) {
          store.deleteForever([b]);
        }
        if (context.mounted) FasanHaptics.of(context).snap();
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'restore', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.restore_from_trash_rounded), title: Text(t.restore))),
        PopupMenuItem(value: 'forever', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_forever_outlined, color: Colors.red.shade700), title: Text(t.deleteForever))),
      ],
    );
  }

  Future<void> _retry(Bill b) async {
    final path = b.originalPath;
    final bytes = path == null ? null : await readImage(path);
    if (bytes == null) return;
    await queue.retry(b, bytes);
  }

  // ---- trash ----

  Widget _trashPage(BuildContext context, BillStore store, double bottom) {
    final t = S.of(context), l = FasanLook.of(context), tt = Theme.of(context).textTheme;
    final items = store.trashed;
    final days = store.trashDays;
    if (items.isEmpty) {
      return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom), children: [
        const SizedBox(height: 80),
        Icon(Icons.delete_outline_rounded, size: 56, color: l.textMuted),
        const SizedBox(height: FasanSpace.l),
        Text(t.trashEmptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: FasanSpace.s),
        Text(days == 0 ? t.trashEmptyManual : t.trashEmptyText(days), style: tt.bodyMedium!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
      ]);
    }
    return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom), children: [
      Row(children: [
        Expanded(child: Text(days == 0 ? t.trashInfoManual : t.trashInfo(days), style: tt.bodySmall)),
        TextButton(
          onPressed: () async {
            if (await _confirmForever(context, items.length) && context.mounted) store.emptyTrash();
          },
          child: Text(t.emptyTrash),
        ),
      ]),
      for (final b in items)
        Padding(
          padding: const EdgeInsets.only(bottom: FasanSpace.s),
          child: _selecting
              ? BillTile(bill: b, queue: queue, selecting: true, selected: _selected.contains(b.id), onToggle: () => _toggle(b.id), onRetry: () {}, subtitle: _trashSub(t, store, b))
              : KeyedSubtree(
                  key: ValueKey('trash-${b.id}'),
                  child: BillTile(bill: b, queue: queue, selecting: false, selected: false, onToggle: () {}, onRetry: () {}, subtitle: _trashSub(t, store, b), openable: false, trailing: _trashMenu(context, store, b)),
                ),
        ),
    ]);
  }

  String _trashSub(S t, BillStore store, Bill b) {
    final left = store.daysLeft(b);
    final d = b.trashedAt!;
    final when = '${d.day}.${d.month}.${d.year}';
    return left == null ? t.trashedOn(when) : '${t.trashedOn(when)} · ${t.daysLeft(left)}';
  }
}
