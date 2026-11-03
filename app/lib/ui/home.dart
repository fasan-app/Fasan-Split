// Fasan Split – start: three main tabs below (Rechnungen, Gruppen, Freunde), a floating plus for new bills, and on Rechnungen
// three views above (Offen, Archiv, Papierkorb). One horizontal pager carries all five pages, so swiping moves through
// them in order (Nutzer 02.11.). Research: fasan_ui docs/recherche/2026-11-02-navigation-layout-glas-ton.md. MPL-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../main.dart';
import '../model/bill.dart';
import '../state/scan_queue.dart';
import '../state/store.dart';
import '../update.dart';
import 'bill_tile.dart';
import 'hints.dart';
import 'flow.dart';
import 'collab_ui.dart';
import 'groups.dart';
import 'onboarding.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'update_ui.dart';

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
  ScanQueue? _queue;
  bool _selecting = false;
  final Set<String> _selected = {};
  final _pager = PageController();
  int _page = 0; // 0 open, 1 archive, 2 trash, 3 groups, 4 friends

  /// Reads several photos one after the other; lives as long as the start page (which stays under every other page).
  ScanQueue get queue => _queue ??= widget.queue ?? ScanQueue(StoreScope.read(context));

  BillList? get _list => _page <= 2 ? BillList.values[_page] : null;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// At most once a day, only if enabled (Settings → Updates); silent without network.
  Future<void> _checkUpdate() async {
    if (kIsWeb) return;
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
      // Web: the introduction is about photographing receipts, which the browser cannot do; an invitation opens directly.
      if (!kIsWeb && !store.onboarded && store.bills.isEmpty) {
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

  Future<void> _pick(BuildContext context, ImageSource src) async {
    final nav = Navigator.of(context);
    XFile? f;
    try {
      // full resolution like the web app (it reads the whole photo); cap at 4000 px against memory spikes
      f = await ImagePicker().pickImage(source: src, maxWidth: 4000, maxHeight: 4000, imageQuality: 95);
    } catch (_) {
      f = null;
    }
    if (f == null) return;
    final bytes = await f.readAsBytes();
    nav.push(MaterialPageRoute(builder: (_) => ScanScreen(photo: bytes)));
  }

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

  /// Gallery: one or many photos. One photo opens the scan page; several are saved and read one after the other
  /// (Nutzer 02.11.: mehrere Bons auf einmal hochladen). Package source: `pickMultiImage` returns an empty list on cancel.
  Future<void> _pickMany(BuildContext context) async {
    final nav = Navigator.of(context), msg = ScaffoldMessenger.of(context), t = S.of(context), q = queue;
    List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(maxWidth: 4000, maxHeight: 4000, imageQuality: 95);
    } catch (_) {
      files = const [];
    }
    if (files.isEmpty) return;
    final bytes = <Uint8List>[for (final f in files) await f.readAsBytes()];
    if (bytes.length == 1) {
      nav.push(MaterialPageRoute(builder: (_) => ScanScreen(photo: bytes.first)));
      return;
    }
    await q.add(bytes);
    if (mounted) {
      if (_page != 0) _goTo(0);
      msg.showSnackBar(_msg(this.context, t.queuedN(bytes.length)));
    }
  }

  void _manual(BuildContext context) {
    final b = Bill(id: DateTime.now().microsecondsSinceEpoch.toString(), created: DateTime.now(), items: []);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(bill: b)));
  }

  /// The plus: the second step asks how (Kamera, Galerie/Datei, ohne Bon).
  Future<void> _addSheet(BuildContext context) async {
    final t = S.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!kIsWeb) ...[
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(t.camera), onTap: () => Navigator.pop(ctx, 'camera')),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(t.galleryOrFile), onTap: () => Navigator.pop(ctx, 'gallery')),
          ],
          ListTile(leading: const Icon(Icons.edit_note_rounded), title: Text(t.manual), onTap: () => Navigator.pop(ctx, 'manual')),
          const SizedBox(height: FasanSpace.s),
        ]),
      ),
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 'camera':
        await _pick(context, ImageSource.camera);
      case 'gallery':
        await _pickMany(context);
      case 'manual':
        _manual(context);
    }
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
    store.setGroup(list, r);
    if (mounted) {
      FasanHaptics.of(this.context).snap();
      _exitSelect();
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

  void _toArchive(BuildContext context, List<Bill> list, bool done) {
    final store = StoreScope.read(context), t = S.of(context);
    store.setDone(list, done);
    _undoable(context, done ? t.archivedN(list.length) : t.reopenedN(list.length), () => store.setDone(list, !done));
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
                title: Text(any ? t.nSelected(selected.length) : t.selectHint),
                actions: [
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
                      icon: Icon(inArchive ? Icons.unarchive_outlined : Icons.archive_outlined),
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
          // the three views of Rechnungen: they appear and disappear smoothly when the page changes
          FasanReveal(
            show: _page <= 2 && !selecting,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.l, 0, FasanSpace.l, FasanSpace.s),
              child: FasanSegmented<int>(
                values: const [0, 1, 2],
                selected: _page.clamp(0, 2),
                label: (i) => [t.listOpen, t.listArchive, t.listTrash][i],
                onChanged: _goTo,
              ),
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
            GroupsPage(queue: queue),
            const FriendsPage(),
          ],
            ),
          ),
        ]),
        floatingActionButton: selecting
            ? null
            : PulseRing(
                active: store0.bills.isEmpty && !store0.hintDone('plus'),
                child: FasanGlow(
                radius: 18,
                // the plus button floats: three-layer shadow with its own colour, turns with the tilt
                child: FasanDepth(
                  radius: 18,
                  level: 3,
                  tint: FasanLook.of(context).accent,
                  child: FloatingActionButton(
                    elevation: 0,
                    focusElevation: 0,
                    hoverElevation: 0,
                    highlightElevation: 0,
                    tooltip: _page <= 2 ? t.newBill : (_page == 3 ? t.newGroup : t.newFriend),
                    onPressed: () => _plus(context),
                    child: const Icon(Icons.add_rounded, size: 28),
                  ),
                ),
              )),
        bottomNavigationBar: _NavBar(
          selected: _page <= 2 ? 0 : _page - 2,
          onSelect: (i) => _goTo(i == 0 ? (_page <= 2 ? _page : 0) : i + 2),
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
    final bottom = 150 + MediaQuery.paddingOf(context).bottom;
    if (mode == BillList.trash) return _trashPage(context, store, bottom);
    final done = mode == BillList.archive;
    final groups = [for (final g in store.groups) (g, store.inGroup(g, done: done))].where((e) => e.$2.isNotEmpty).toList();
    final loose = store.inGroup(null, done: done);
    final empty = groups.isEmpty && loose.isEmpty;
    final banner = !done && _update != null ? UpdateBanner(info: _update!, onClose: () => setState(() => _update = null)) : null;
    if (empty) {
      return ListView(padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom), children: [
        ?banner,
        const SizedBox(height: 80),
        Icon(done ? Icons.inventory_2_outlined : Icons.receipt_long_outlined, size: 56, color: l.textMuted),
        const SizedBox(height: FasanSpace.l),
        Text(done ? t.archiveEmptyTitle : t.emptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: FasanSpace.s),
        Text(done ? t.archiveHow : t.emptyText, style: tt.bodyMedium!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
        if (!done) ...[
          const SizedBox(height: FasanSpace.xl),
          FasanButton(label: t.emptyCamera, icon: Icons.photo_camera_outlined, expand: true, onPressed: () => _pick(context, ImageSource.camera)),
          const SizedBox(height: FasanSpace.s),
          FasanButton(label: t.galleryOrFile, icon: Icons.photo_library_outlined, kind: FasanButtonKind.secondary, expand: true, onPressed: () => _pickMany(context)),
          const SizedBox(height: FasanSpace.s),
          FasanButton(label: t.manual, icon: Icons.edit_note_rounded, kind: FasanButtonKind.secondary, expand: true, onPressed: () => _manual(context)),
          const SizedBox(height: FasanSpace.l),
          Text(t.emptyOr, style: tt.bodySmall!.copyWith(color: l.textMuted), textAlign: TextAlign.center),
        ],
      ]);
    }
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) => ListView(
        padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, bottom),
        children: [
          if (banner != null) Padding(padding: const EdgeInsets.only(top: FasanSpace.s), child: banner),
          if (!done) Padding(padding: const EdgeInsets.only(top: FasanSpace.s), child: HintCard(id: 'swipe', text: t.hintSwipe, icon: Icons.swipe_rounded)),
          for (final (g, bills) in groups) _section(context, store, mode, g, g, bills),
          _section(context, store, mode, null, null, loose, title: done ? t.finished : t.drafts),
        ],
      ),
    );
  }

  /// One block of the list. A group block (and the block without group) accepts bills that are dragged onto it.
  Widget _section(BuildContext context, BillStore store, BillList mode, String? group, String? groupName, List<Bill> list, {String? title}) {
    if (list.isEmpty) return const SizedBox.shrink();
    final t = S.of(context), l = FasanLook.of(context);
    final heading = groupName ?? title ?? '';
    return DragTarget<Bill>(
      onWillAcceptWithDetails: (d) => d.data.group != group,
      onAcceptWithDetails: (d) {
        store.setGroup([d.data], group);
        FasanHaptics.of(context).snap();
      },
      builder: (context, candidate, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(l.radius),
          border: Border.all(color: candidate.isEmpty ? Colors.transparent : l.accent, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, FasanSpace.m, 4, FasanSpace.s),
            child: Row(children: [
              if (groupName != null) ...[Icon(Icons.folder_outlined, size: 16, color: l.textMuted), const SizedBox(width: 6)],
              Expanded(child: FasanLabel(heading)),
              if (groupName != null) Text('${list.length} · ${money(list.fold(0, (a, b) => a + b.effectiveTotal), de: t.de)} €', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          for (final b in list) Padding(padding: const EdgeInsets.only(bottom: FasanSpace.s), child: _row(context, store, mode, b)),
        ]),
      ),
    );
  }

  /// A bill: tap opens it (or selects), swipe right moves it to the archive (or back), swipe left to the trash with
  /// „Rückgängig“, long press picks it up to drop it onto a group.
  Widget _row(BuildContext context, BillStore store, BillList mode, Bill b) {
    final t = S.of(context), l = FasanLook.of(context);
    final tile = BillTile(bill: b, queue: queue, selecting: _selecting, selected: _selected.contains(b.id), onToggle: () => _toggle(b.id), onRetry: () => _retry(b));
    if (_selecting) return tile;
    final archive = mode == BillList.archive;
    return Dismissible(
      key: ValueKey('bill-${mode.name}-${b.id}'),
      direction: b.read == BillRead.ok ? DismissDirection.horizontal : DismissDirection.endToStart,
      background: _swipeBackground(l, archive ? Icons.unarchive_outlined : Icons.archive_outlined, archive ? t.markOpen : t.markDone, Alignment.centerLeft, l.accent),
      secondaryBackground: _swipeBackground(l, Icons.delete_outline_rounded, t.delete, Alignment.centerRight, Colors.red.shade700),
      onDismissed: (dir) {
        if (dir == DismissDirection.startToEnd) {
          _toArchive(context, [b], !archive);
        } else {
          _toTrash(context, [b]);
        }
        FasanHaptics.of(context).snap();
      },
      child: LongPressDraggable<Bill>(
        data: b,
        delay: const Duration(milliseconds: 350),
        onDragStarted: () => FasanHaptics.of(context).tap(),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: MediaQuery.sizeOf(context).width - 2 * FasanSpace.l, child: Opacity(opacity: 0.9, child: BillTile(bill: b, queue: queue, selecting: false, selected: false, onToggle: () {}, onRetry: () {}))),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: tile,
      ),
    );
  }

  Widget _swipeBackground(FasanLook l, IconData icon, String label, Alignment align, Color color) => Container(
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: FasanSpace.l),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(l.radius * 0.7)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color), const SizedBox(width: 8), Text(label, style: TextStyle(color: color))]),
      );

  Future<void> _retry(Bill b) async {
    final path = b.originalPath;
    if (path == null || !File(path).existsSync()) return;
    await queue.retry(b, await File(path).readAsBytes());
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
              : Dismissible(
                  key: ValueKey('trash-${b.id}'),
                  background: _swipeBackground(l, Icons.restore_from_trash_rounded, t.restore, Alignment.centerLeft, l.accent),
                  secondaryBackground: _swipeBackground(l, Icons.delete_forever_outlined, t.deleteForever, Alignment.centerRight, Colors.red.shade700),
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
  const _NavBar({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context), l = FasanLook.of(context);
    final items = [
      (Icons.receipt_long_outlined, Icons.receipt_long_rounded, t.billsTab),
      (Icons.folder_copy_outlined, Icons.folder_copy_rounded, t.groupsTab),
      (Icons.people_outline_rounded, Icons.people_rounded, t.friendsTab),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(FasanSpace.m, 0, FasanSpace.m, FasanSpace.s + MediaQuery.paddingOf(context).bottom),
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
                child: InkWell(
                  borderRadius: BorderRadius.circular(l.radius * 0.7),
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: FasanMotion.of(context).short,
                    curve: FasanCurves.short,
                    constraints: BoxConstraints(minHeight: l.minTap + 8),
                    decoration: BoxDecoration(color: i == selected ? l.accent.withValues(alpha: 0.14) : Colors.transparent, borderRadius: BorderRadius.circular(l.radius * 0.7)),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(i == selected ? items[i].$2 : items[i].$1, color: i == selected ? l.accent : l.textMuted, size: 24),
                      const SizedBox(height: 2),
                      Text(items[i].$3, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: i == selected ? l.accent : l.textMuted, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500)),
                    ]),
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
