// SPDX-License-Identifier: MPL-2.0
// Fasan Split – start: three main tabs below (Rechnungen, Gruppen, Freunde), a floating plus for new bills, and on Rechnungen
// three views above (Offen, Archiv, Papierkorb). One horizontal pager carries all five pages, so swiping moves through
// them in order (Nutzer 02.11.). Research: fasan_ui docs/recherche/2026-11-02-navigation-layout-glas-ton.md. MPL-2.0
import '../l10n/tr.dart' show trLang;
import 'dart:async';

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
import 'common.dart';
import 'my_balance.dart';
import 'swipe.dart';
import 'tips.dart';
import 'groups.dart';
import 'balance_breakdown.dart' show GroupBreakdownScreen;
import 'group_header.dart';
import 'group_picker.dart';
import 'onboarding.dart';
import 'settings_screen.dart';
import 'update_ui.dart';
import '../state/images.dart';

/// Which list of bills a page shows.
enum BillList { open, archive, trash }

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
  final _pager = PageController();
  int _page = 0; // 0 open, 1 archive, 2 trash (tab Gruppe), 3 Abrechnung, 4 friends
  String _scope = kScopeAll; // what the group picker shows: Alle, Ohne Gruppe or one group (Option A, Nutzer 08.11.)
  bool _itemsView = false; // Gruppe tab: false = bills, true = all items of the scope

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
    if (m.enabled) {
      _pager.animateToPage(page, duration: m.medium, curve: FasanCurves.medium);
    } else {
      _pager.jumpToPage(page);
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

  Future<void> _addSheet(BuildContext context) => addBillSheet(context, queue, group: scopeGroup(_scopeOf(StoreScope.read(context))), onQueued: (n) {
        if (!mounted) return;
        if (_page != 0) _goTo(0);
        ScaffoldMessenger.of(this.context).showSnackBar(_msg(this.context, S.of(this.context).queuedN(n)));
      });

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
      });

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
    final any = selected.isNotEmpty;
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
        extendBody: true,
        appBar: selecting
            ? AppBar(
                leading: IconButton(tooltip: t.cancel, icon: const Icon(Icons.close_rounded), onPressed: _exitSelect),
                title: Text(_dragging ? (trLang(t.de ? 'de' : 'en', 'home.dragOntoATarget')) : any ? t.nSelected(selected.length) : t.selectHint),
                // while dragging only the targets below act (Nutzer 04.11.: two sets of archive/trash symbols)
                actions: _dragging ? const [] : [
                  if (inTrash) ...[
                    IconButton(tooltip: t.restore, icon: const Icon(Icons.restore_from_trash_rounded), onPressed: !any ? null : () {
                      store.untrash(selected);
                      _exitSelect();
                    }),
                    IconButton(tooltip: t.deleteForever, icon: const Icon(Icons.delete_forever_outlined), onPressed: !any ? null : () async {
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
                    IconButton(
                      tooltip: t.delete,
                      icon: const Icon(Icons.delete_outline_rounded),
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
                title: Text(_page <= 2 ? t.appName : (_page == 3 ? t.groupsTab : t.friendsTab)),
                actions: [
                  // my balance on every main page (Nutzer 04.11.)
                  const MyBalanceBadge(),
                  const ActivityBell(),
                  if (_page <= 2 && scopeIsGroup(_scopeOf(store))) ...groupActions(context, _scopeOf(store), compact: true, onDeleted: () => setState(() => _scope = kScopeAll)),
                  if (list != null && list != BillList.trash && _hasAny(store, list))
                    IconButton(
                      tooltip: trLang(t.de ? 'de' : 'en', 'home.sortAndFilter'),
                      icon: Badge(isLabelVisible: _catFilter != null || store.sortMode != BillSort.status, smallSize: 8, child: const Icon(Icons.sort_rounded)),
                      onPressed: () => sortSheet(context, filter: _catFilter, onFilter: (f) => setState(() => _catFilter = f)),
                    ),
                  if (list != null && _hasAny(store, list))
                    IconButton(tooltip: t.select, icon: const Icon(Icons.checklist_rounded), onPressed: () => setState(() => _selecting = true)),
                  IconButton(
                    tooltip: t.settings,
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
        body: Column(children: [
          // one short tip per start (Nutzer 07.11.), off in the settings
          const TipLine(),
          // the three views of Rechnungen: they appear and disappear smoothly when the page changes
          // stays while selecting (04.11.: hiding it made the list jump); while dragging its parts take the bills
          FasanReveal(
            show: _page <= 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s),
              child: Stack(children: [
                FasanSegmented<int>(
                  values: const [0, 1, 2],
                  selected: _page.clamp(0, 2),
                  label: (i) => [t.listOpen, t.listArchive, t.listTrash][i],
                  onChanged: _goTo,
                ),
              ]),
            ),
          ),
          // group picker (Option A): same row on Gruppe and Abrechnung; the chips take lifted bills
          FasanReveal(
            show: _page <= 3,
            child: Padding(
              padding: const EdgeInsets.only(bottom: FasanSpace.s),
              child: GroupPicker(
                groups: store0.allGroups,
                selected: _scopeOf(store0),
                onSelect: (v) => setState(() => _scope = v),
                onNew: () => _newGroup(context),
                onDrop: (bills, g) {
                  store0.setGroup(bills, g);
                  FasanHaptics.of(context).snap();
                  _exitSelect();
                },
              ),
            ),
          ),
          // bills | items of the scope (Nutzer 08.11. 04:16) and „only open items“ (Nutzer 07.11.) in ONE row: the screen of a phone
          // is short, every extra row costs list space (docs/recherche/2026-11-09-reale-und-gefuehlte-leistung.md, Daumenzone)
          FasanReveal(
            show: _page <= 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.s, FasanSpace.s),
              child: Row(children: [
                Expanded(
                  child: FasanSegmented<int>(
                    values: const [0, 1],
                    selected: _itemsView ? 1 : 0,
                    label: (i) => trLang(t.de ? 'de' : 'en', i == 0 ? 'grp.bills' : 'grp.items'),
                    onChanged: (v) => setState(() => _itemsView = v == 1),
                  ),
                ),
                if (_hasAny(store0, BillList.open))
                  IconButton(
                    tooltip: trLang(t.de ? 'de' : 'en', store0.onlyOpen ? 'filter.allItems' : 'filter.onlyOpen'),
                    isSelected: store0.onlyOpen,
                    icon: const Icon(Icons.filter_alt_outlined),
                    selectedIcon: const Icon(Icons.filter_alt_rounded),
                    onPressed: () => store0.onlyOpen = !store0.onlyOpen,
                  ),
              ]),
            ),
          ),
          Expanded(
            child: PageView(
          controller: _pager,
          onPageChanged: (p) {
            FasanHaptics.of(context).tap();
            setState(() {
              _page = p;
              _selecting = false;
              _selected.clear();
            });
          },
          children: [
            _listPage(context, BillList.open),
            _listPage(context, BillList.archive),
            _listPage(context, BillList.trash),
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
                  radius: FasanLook.of(context).radius * 0.7,
                  level: 2,
                  child: FloatingActionButton(
                    elevation: 0,
                    focusElevation: 0,
                    hoverElevation: 0,
                    highlightElevation: 0,
                    backgroundColor: FasanLook.of(context).accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FasanLook.of(context).radius * 0.7)),
                    tooltip: _page <= 2 ? t.newBill : (_page == 3 ? t.newGroup : t.newFriend),
                    onPressed: () => _plus(context),
                    child: const Icon(Icons.add_rounded, size: 28),
                  ),
                ),
              ),
        bottomNavigationBar: _dragging && list != null
            ? _DropDock(
                from: list,
                onList: (bills, target) => _dropOnList(context, store, bills, target),
                onGroup: (bills) => _groupDialog(context, bills),
              )
            : _NavBar(
          badges: [0, CollabScope.of(context).unreadGroups, CollabScope.of(context).unreadDirects],
          selected: _page <= 2 ? 0 : _page - 2,
          onSelect: (i) => _goTo(i == 0 ? (_page <= 2 ? _page : 0) : i + 2),
          // bills dropped on „Gruppen“: choose a group or name a new one (same dialog as the button)
          onDropGroup: null,
        ),
      ),
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
    final bottom = 200 + MediaQuery.paddingOf(context).bottom; // the last card scrolls fully above the plus button and the bar
    if (mode == BillList.trash) return _trashPage(context, store, bottom);
    final done = mode == BillList.archive;
    // sort and category filter (Nutzer 04.11.), category_ui.dart
    final sort = store.sortMode;
    final scope = _scopeOf(store);
    final groups = [
      for (final g in store.groups)
        if (scope == kScopeAll || scope == g) (g, arrange(store.inGroup(g, archived: done), sort, _catFilter, onlyOpen: store.onlyOpen))
    ].where((e) => e.$2.isNotEmpty).toList();
    final loose = scope == kScopeAll || scope == kScopeLoose ? arrange(store.inGroup(null, archived: done), sort, _catFilter, onlyOpen: store.onlyOpen) : <Bill>[];
    final shown = [for (final e in groups) ...e.$2, ...loose];
    final empty = groups.isEmpty && loose.isEmpty;
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
                if (!done) ...[const SizedBox(height: FasanSpace.s), const StorageWarningCard(), const OpenInviteCard(), const PendingJoinCards()],
                if (!done) Padding(padding: const EdgeInsets.only(top: FasanSpace.s), child: HintCard(id: 'swipe', text: t.hintSwipe, icon: Icons.swipe_rounded)),
                // the group's frame: bills, price, people; for Alle and Ohne Gruppe only the counts line
                if (scopeIsGroup(scope))
                  Padding(
                    padding: const EdgeInsets.only(top: FasanSpace.s),
                    child: GroupHeader(
                      bills: store.inGroup(scope),
                      people: CollabScope.of(context).peopleOf(scope).length,
                      onPrice: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupBreakdownScreen(name: scope))),
                      onPeople: () => _goTo(3),
                    ),
                  ),
                GroupCountsLine(bills: scopeIsGroup(scope) ? store.inGroup(scope) : shown, onOpenItems: () => setState(() => _itemsView = true)),
              ]),
            ),
          ),
          if (_itemsView)
            ..._itemSlivers(context, flattenItems(shown, onlyOpen: store.onlyOpen))
          else ...[
            for (final (g, bills) in groups) _section(context, store, mode, g, g, bills),
            _section(context, store, mode, null, null, loose, title: done ? t.finished : t.drafts),
          ],
          SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ),
    );
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
            return it == null
                ? GroupBillHeading(key: ValueKey('h-${b.id}'), bill: b, onTap: () => openBill(context, b))
                : GroupItemRow(key: ValueKey('${b.id}/${b.its.indexOf(it)}'), bill: b, item: it, onTap: () => openBill(context, b));
          },
        ),
      ),
    ];
  }

  /// Tab Abrechnung: with a group picked its people and settlement, otherwise the overview of all groups (balances).
  Widget _settlePage(BuildContext context) {
    final store = StoreScope.of(context);
    final scope = _scopeOf(store);
    if (!scopeIsGroup(scope)) return GroupsPage(queue: queue);
    final bottom = 150 + MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom),
      children: [GroupPeople(name: scope)],
    );
  }

  /// One block of the list as a sliver: the heading accepts bills that are dragged onto it (group blocks and the block without
  /// group); every bill row accepts them as well (moveBefore takes over the group of the row). The rows are built only when they are
  /// near the screen (SliverList.builder).
  Widget _section(BuildContext context, BillStore store, BillList mode, String? group, String? groupName, List<Bill> list, {String? title}) {
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
        SliverToBoxAdapter(child: header),
        SliverList.builder(
          itemCount: list.length,
          itemBuilder: (context, i) => Padding(padding: const EdgeInsets.only(bottom: FasanSpace.xs + 2), child: _row(context, store, mode, list[i])),
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
    final tile = BillTile(bill: b, queue: queue, selecting: _selecting, selected: _selected.contains(b.id), onToggle: () => _toggle(b.id), onRetry: () => _retry(b));
    final moving = _selecting && _selected.contains(b.id) ? _picked(store) : [b];
    final archive = mode == BillList.archive;
    return SwipeActions(
      key: ValueKey('bill-${mode.name}-${b.id}'),
      id: '${mode.name}-${b.id}',
      enabled: !_selecting,
      start: b.read == BillRead.ok ? SwipeSide(archive ? Icons.unarchive_outlined : Icons.task_alt_rounded, archive ? t.markOpen : t.markDone, archive ? l.accent : Colors.green.shade600) : null,
      end: SwipeSide(Icons.delete_outline_rounded, t.delete, Colors.red.shade700),
      // A swipe that would change nothing is refused before the card slides away: a card that was dismissed but stays in the list
      // is an error of the framework („A dismissed Dismissible widget is still part of the tree“). Unfinished bills cannot go
      // to the archive: the card springs back and says why.
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd && !archive && !b.done) {
          showNote(context, trLang(t.de ? 'de' : 'en', 'home.enterItFirstAll2'));
          return false;
        }
        return true;
      },
      onDismissed: (dir) {
        if (dir == DismissDirection.startToEnd) {
          _toArchive(context, [b], !archive);
        } else {
          _toTrash(context, [b]);
        }
        FasanHaptics.of(context).snap();
      },
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
            feedback: _DragFeedback(bills: moving),
            // above the finger: the target and its text stay readable
            dragAnchorStrategy: (draggable, context, position) => const Offset(44, 120),
            childWhenDragging: Opacity(opacity: 0.35, child: tile),
            child: tile,
          ),
        ),
      ),
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
              : SwipeActions(
                  key: ValueKey('trash-${b.id}'),
                  id: 'trash-${b.id}',
                  start: SwipeSide(Icons.restore_from_trash_rounded, t.restore, l.accent),
                  end: SwipeSide(Icons.delete_forever_outlined, t.deleteForever, Colors.red.shade700),
                  confirmDismiss: (dir) async => dir == DismissDirection.startToEnd || await _confirmForever(context, 1),
                  onDismissed: (dir) {
                    if (dir == DismissDirection.startToEnd) {
                      store.untrash([b]);
                    } else {
                      store.deleteForever([b]);
                    }
                    FasanHaptics.of(context).snap();
                  },
                  child: BillTile(bill: b, queue: queue, selecting: false, selected: false, onToggle: () {}, onRetry: () {}, subtitle: _trashSub(t, store, b), openable: false),
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

/// The three main places (Rechnungen, Gruppen, Freunde) as a glass bar at the bottom: icon and label, colour for the active
/// one (no check marks; Nutzer 02.11.). Material 3: a navigation bar holds three to five destinations.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.selected, required this.onSelect, this.onDropGroup, this.badges = const [0, 0, 0]});

  /// Unread messages per tab (Nutzer 04.11.: indicators for new messages).
  final List<int> badges;

  final int selected;
  final ValueChanged<int> onSelect;

  /// While bills are dragged: the Gruppen tab takes them.
  final void Function(List<Bill>)? onDropGroup;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context);
    final items = [
      (Icons.receipt_long_outlined, Icons.receipt_long_rounded, t.billsTab),
      (Icons.folder_copy_outlined, Icons.folder_copy_rounded, t.groupsTab),
      (Icons.people_outline_rounded, Icons.people_rounded, t.friendsTab),
    ];
    return Padding(
      // same side margin as the cards above (Nutzer 04.11.: surfaces of different width)
      padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s + MediaQuery.paddingOf(context).bottom),
      // fixed height: the glass fills the space it is given, and the Scaffold gives its bottom bar all the height there is
      child: SizedBox(
        height: l.minTap + 32,
        child: FasanGlass(
        padding: const EdgeInsets.all(4),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                selected: i == selected,
                button: true,
                label: items[i].$3,
                child: DragTarget<List<Bill>>(
                  onWillAcceptWithDetails: (_) => i == 1 && onDropGroup != null,
                  onAcceptWithDetails: (d) => onDropGroup?.call(d.data),
                  builder: (context, cand, _) => InkWell(
                  borderRadius: BorderRadius.circular(l.radius * 0.7),
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: FasanMotion.of(context).short,
                    curve: FasanCurves.short,
                    constraints: BoxConstraints(minHeight: l.minTap + 8),
                    decoration: BoxDecoration(
                        color: cand.isNotEmpty
                            ? l.accent.withValues(alpha: 0.3)
                            : i == selected || (i == 1 && onDropGroup != null)
                                ? l.accent.withValues(alpha: 0.14)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(l.radius * 0.7)),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Badge(
                        isLabelVisible: badges[i] > 0,
                        label: Text(badges[i] > 99 ? '99+' : '${badges[i]}'),
                        child: Icon(i == selected ? items[i].$2 : items[i].$1, color: i == selected ? l.accent : l.textMuted, size: 24),
                      ),
                      const SizedBox(height: 2),
                      Text(items[i].$3, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: i == selected ? l.accent : l.textMuted, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500)),
                    ]),
                  ),
                ),
                ),
              ),
            ),
        ]),
        ),
      ),
    );
  }
}

/// What follows the finger while bills are dragged: a small stack of the receipts with their number (Nutzer 04.11.:
/// the full-width card covered where it would land).
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.bills});

  final List<Bill> bills;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final shown = bills.take(3).toList();
    Widget card(Bill b) => Container(
          width: 56,
          height: 72,
          decoration: BoxDecoration(
            color: l.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: l.accent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          clipBehavior: Clip.antiAlias,
          child: imageExists(b.imagePath)
              ? Image(image: ResizeImage(imageProvider(b.imagePath!), width: 120), fit: BoxFit.cover, gaplessPlayback: true)
              : Icon(Icons.receipt_long_rounded, color: l.textMuted),
        );
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 88,
        height: 96,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(left: 6.0 * i, top: 4.0 * i, child: Transform.rotate(angle: (i - 1) * 0.06, child: card(shown[i]))),
          if (bills.length > 1)
            Positioned(
              right: 0,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: l.accent, borderRadius: BorderRadius.circular(12)),
                child: Text('${bills.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// While bills are dragged the bottom bar becomes the drop targets (Nutzer 04.11.: „beim Verschieben auf den darunter
/// liegenden Papierkorb muss er deutlich animiert zeigen, dass beim Loslassen gelöscht wird – systemweit die Regel“).
/// The target under the finger grows, takes its colour and says what happens on release.
class _DropDock extends StatelessWidget {
  const _DropDock({required this.from, required this.onList, required this.onGroup});

  final BillList from;
  final void Function(List<Bill>, BillList) onList;
  final void Function(List<Bill>) onGroup;

  @override
  Widget build(BuildContext context) {
    final de = S.of(context).de, l = FasanLook.of(context);
    final targets = <(IconData, String, String, Color, void Function(List<Bill>))>[
      if (from != BillList.open) (Icons.inbox_rounded, trLang(de ? 'de' : 'en', 'home.open'), trLang(de ? 'de' : 'en', 'home.releaseOpenAgain'), l.accent, (b) => onList(b, BillList.open)),
      (Icons.folder_rounded, trLang(de ? 'de' : 'en', 'home.group'), trLang(de ? 'de' : 'en', 'home.releaseChooseAGroup'), l.accent, onGroup),
      if (from != BillList.archive) (Icons.task_alt_rounded, trLang(de ? 'de' : 'en', 'home.settle'), trLang(de ? 'de' : 'en', 'home.releasePaidToThe'), Colors.green.shade600, (b) => onList(b, BillList.archive)),
      if (from != BillList.trash) (Icons.delete_rounded, trLang(de ? 'de' : 'en', 'home.trash'), trLang(de ? 'de' : 'en', 'home.releaseToTheTrash'), Colors.red.shade600, (b) => onList(b, BillList.trash)),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s + MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: l.minTap + 56,
        child: Row(children: [
          for (final (icon, label, action, color, drop) in targets)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: DragTarget<List<Bill>>(
                  onWillAcceptWithDetails: (_) {
                    FasanHaptics.of(context).tap(); // entering a target is felt
                    return true;
                  },
                  onAcceptWithDetails: (d) => drop(d.data),
                  builder: (context, cand, _) {
                    final over = cand.isNotEmpty;
                    final motion = FasanMotion.of(context);
                    return AnimatedScale(
                      duration: motion.short,
                      curve: Curves.easeOutBack,
                      scale: over ? 1.08 : 1,
                      child: AnimatedContainer(
                        duration: motion.short,
                        curve: FasanCurves.short,
                        decoration: BoxDecoration(
                          color: over ? color : color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(l.radius * 0.7),
                          border: Border.all(color: color.withValues(alpha: over ? 1 : 0.5), width: 1.5),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedScale(duration: motion.short, scale: over ? 1.25 : 1, child: Icon(icon, color: over ? Colors.white : color, size: 26)),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(over ? action : label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: Theme.of(context).textTheme.labelSmall!.copyWith(color: over ? Colors.white : color, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
