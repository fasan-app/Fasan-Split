// Fasan Split – start: saved bills, scan button in the thumb zone. MPL-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:fasan_ui/fasan_ui.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../main.dart';
import '../model/bill.dart';
import '../state/scan_queue.dart';
import '../state/store.dart';
import 'common.dart';
import 'assign.dart';
import 'flow.dart';
import 'onboarding.dart';
import 'update_ui.dart';
import '../update.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

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

  /// Reads several photos one after the other; lives as long as the start page (which stays under every other page).
  ScanQueue get queue => _queue ??= widget.queue ?? ScanQueue(StoreScope.read(context));

  /// At most once a day, only if enabled (Settings → Updates); silent without network.
  Future<void> _checkUpdate() async {
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
      if (!store.onboarded && store.bills.isEmpty) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      }
    });
  }

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

  /// Gallery: one or many photos. One photo opens the scan page; several are saved and read one after the other
  /// (Nutzer 02.11.: mehrere Bons auf einmal hochladen). Package source: `pickMultiImage` returns an empty list on cancel.
  /// Messages float above the glass bar at the bottom (otherwise it covers „Rückgängig“).
  SnackBar _msg(BuildContext context, String text, {SnackBarAction? action, Duration? duration}) => SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(FasanSpace.m, 0, FasanSpace.m, 150 + MediaQuery.paddingOf(context).bottom),
        action: action,
        // Flutter keeps a snack bar with an action on screen until it is dismissed (`persist` defaults to true then); the
        // delete message has to run out, or the bills would never be removed for good.
        persist: false,
        duration: duration ?? const Duration(seconds: 4),
      );

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
    if (context.mounted) msg.showSnackBar(_msg(context, t.queuedN(bytes.length)));
  }

  void _manual(BuildContext context) {
    final b = Bill(id: DateTime.now().microsecondsSinceEpoch.toString(), created: DateTime.now(), items: []);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(bill: b)));
  }

  // ---- selection, groups, delete ----

  void _toggle(String id) {
    FasanHaptics.of(context).tap();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _selecting = false;
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
    final existing = store.groups;
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

  /// Delete with „Rückgängig“: the bills disappear at once and are removed for good when the message runs out.
  void _delete(BuildContext context, List<Bill> list) {
    final store = StoreScope.read(context), t = S.of(context), msg = ScaffoldMessenger.of(context), q = queue;
    store.hide(list);
    msg.clearSnackBars();
    msg
        .showSnackBar(_msg(
          context,
          t.deletedN(list.length),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: t.undo, onPressed: () => store.restore(list)),
        ))
        .closed
        .then((reason) {
      if (reason == SnackBarClosedReason.action) return;
      for (final b in list) {
        q.forget(b.id);
      }
      store.commit(list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final store = StoreScope.of(context);
    final tt = Theme.of(context).textTheme;
    final all = [...store.inGroup(null), for (final g in store.groups) ...store.inGroup(g)];
    final selected = _picked(store);
    final selecting = _selecting && selected.isNotEmpty;
    return Scaffold(
      appBar: selecting
          ? AppBar(
              leading: IconButton(tooltip: t.cancel, icon: const Icon(Icons.close_rounded), onPressed: _exitSelect),
              title: Text(t.nSelected(selected.length)),
              actions: [
                IconButton(tooltip: t.groupTitle, icon: const Icon(Icons.folder_outlined), onPressed: () => _groupDialog(context, selected)),
                IconButton(
                  tooltip: selected.every((b) => b.done) ? t.markOpen : t.markDone,
                  icon: Icon(selected.every((b) => b.done) ? Icons.undo_rounded : Icons.task_alt_rounded),
                  onPressed: () {
                    store.setDone(selected, !selected.every((b) => b.done));
                    FasanHaptics.of(context).snap();
                    _exitSelect();
                  },
                ),
                IconButton(
                  tooltip: t.delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () {
                    final list = selected;
                    _exitSelect();
                    _delete(context, list);
                  },
                ),
              ],
            )
          : AppBar(
              title: Text(t.appName),
              actions: [
                if (all.isNotEmpty)
                  IconButton(tooltip: t.select, icon: const Icon(Icons.checklist_rounded), onPressed: () => setState(() => _selecting = true)),
                IconButton(
                  tooltip: t.settings,
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),
      body: Stack(children: [
        if (all.isEmpty && _update != null)
          Positioned(left: FasanSpace.l, right: FasanSpace.l, top: FasanSpace.s, child: UpdateBanner(info: _update!, onClose: () => setState(() => _update = null))),
        if (all.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(FasanSpace.xxl, 0, FasanSpace.xxl, 160),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_long_outlined, size: 56, color: FasanLook.of(context).textMuted),
                const SizedBox(height: FasanSpace.l),
                Text(t.emptyTitle, style: tt.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: FasanSpace.s),
                Text(t.emptyText, style: tt.bodyMedium!.copyWith(color: FasanLook.of(context).textMuted), textAlign: TextAlign.center),
              ]),
            ),
          )
        else
          ListenableBuilder(
            listenable: queue,
            builder: (context, _) => ListView(
              padding: EdgeInsets.fromLTRB(FasanSpace.l, FasanSpace.s, FasanSpace.l, 200 + MediaQuery.paddingOf(context).bottom),
              children: [
                if (_update != null) Padding(padding: const EdgeInsets.only(top: FasanSpace.s), child: UpdateBanner(info: _update!, onClose: () => setState(() => _update = null))),
                for (final g in store.groups) _section(context, store, g, g, store.inGroup(g)),
                _section(context, store, null, null, store.inGroup(null).where((b) => !b.done).toList(), title: t.drafts),
                _section(context, store, null, null, store.inGroup(null).where((b) => b.done).toList(), title: t.finished),
              ],
            ),
          ),
        Positioned(
          left: FasanSpace.m,
          right: FasanSpace.m,
          bottom: FasanSpace.m + MediaQuery.paddingOf(context).bottom,
          child: FasanGlass(
            padding: const EdgeInsets.all(6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: FasanButton(label: t.camera, icon: Icons.photo_camera_outlined, expand: true, onPressed: () => _pick(context, ImageSource.camera))),
                const SizedBox(width: 6),
                Expanded(child: FasanButton(label: t.gallery, icon: Icons.photo_library_outlined, kind: FasanButtonKind.secondary, expand: true, onPressed: () => _pickMany(context))),
              ]),
              TextButton(onPressed: () => _manual(context), child: Text(t.manual)),
            ]),
          ),
        ),
      ]),
    );
  }

  /// One block of the list. A group block (and the blocks without group) accepts bills that are dragged onto it.
  Widget _section(BuildContext context, BillStore store, String? group, String? groupName, List<Bill> list, {String? title}) {
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
          for (final b in list)
            Padding(
              padding: const EdgeInsets.only(bottom: FasanSpace.s),
              child: _row(context, store, b),
            ),
        ]),
      ),
    );
  }

  /// A bill: tap opens it (or selects), swipe right sets „Fertig“/„Offen“, swipe left deletes with „Rückgängig“,
  /// long press picks it up to drop it onto a group.
  Widget _row(BuildContext context, BillStore store, Bill b) {
    final t = S.of(context), l = FasanLook.of(context);
    final tile = _BillTile(
      bill: b,
      queue: queue,
      selecting: _selecting,
      selected: _selected.contains(b.id),
      onToggle: () => _toggle(b.id),
      onRetry: () => _retry(b),
    );
    if (_selecting) return tile;
    return Dismissible(
      key: ValueKey('bill-${b.id}'),
      direction: b.read == BillRead.ok ? DismissDirection.horizontal : DismissDirection.endToStart,
      background: _swipeBackground(l, b.done ? Icons.undo_rounded : Icons.task_alt_rounded, b.done ? t.markOpen : t.markDone, Alignment.centerLeft, l.accent),
      secondaryBackground: _swipeBackground(l, Icons.delete_outline_rounded, t.delete, Alignment.centerRight, Colors.red.shade700),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          store.setDone([b], !b.done);
          FasanHaptics.of(context).snap();
          return false; // the tile springs back, only its status changed
        }
        return true;
      },
      onDismissed: (_) => _delete(context, [b]),
      child: LongPressDraggable<Bill>(
        data: b,
        delay: const Duration(milliseconds: 350),
        onDragStarted: () => FasanHaptics.of(context).tap(),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: MediaQuery.sizeOf(context).width - 2 * FasanSpace.l, child: Opacity(opacity: 0.9, child: _BillTile(bill: b, queue: queue, selecting: false, selected: false, onToggle: () {}, onRetry: () {}))),
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
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, required this.queue, required this.selecting, required this.selected, required this.onToggle, required this.onRetry});

  final Bill bill;
  final ScanQueue queue;
  final bool selecting, selected;
  final VoidCallback onToggle, onRetry;

  @override
  Widget build(BuildContext context) {
    final l = FasanLook.of(context);
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final date = '${bill.date.day}.${bill.date.month}.${bill.date.year}';
    final r = l.radius * 0.7;
    final waiting = bill.read == BillRead.queued || bill.read == BillRead.reading;
    final failed = bill.read == BillRead.failed;
    final String sub;
    if (bill.read == BillRead.queued) {
      sub = t.waiting;
    } else if (bill.read == BillRead.reading) {
      sub = queue.currentId == bill.id && queue.progress > 0 ? '${t.readingNow} · ${(queue.progress * 100).round()} %' : t.readingNow;
    } else if (failed) {
      sub = t.readFailedShort;
    } else {
      sub = bill.done ? '$date · ${bill.ps.length} ${t.de ? 'Personen' : 'people'}' : '$date · ${t.stepOf(bill.step)}';
    }
    Widget body(VoidCallback? open) => InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: selecting ? onToggle : open,
          child: Container(
            constraints: BoxConstraints(minHeight: l.minTap + 16),
            padding: const EdgeInsets.all(FasanSpace.m),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              border: Border.all(color: selected ? l.accent : l.hairline, width: selected ? 2 : 1),
              color: selected ? l.accent.withValues(alpha: 0.08) : null,
            ),
            child: Row(children: [
              if (selecting) ...[
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? l.accent : l.textMuted),
                const SizedBox(width: FasanSpace.m),
              ],
              if (waiting)
                SizedBox(width: 40, height: 52, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, value: bill.read == BillRead.reading && queue.currentId == bill.id && queue.progress > 0 ? queue.progress : null))))
              else if (bill.imagePath != null && File(bill.imagePath!).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(bill.imagePath!), width: 40, height: 52, fit: BoxFit.cover, cacheWidth: 120),
                )
              else
                SizedBox(width: 40, height: 52, child: Icon(failed ? Icons.error_outline_rounded : Icons.receipt_outlined, color: l.textMuted)),
              const SizedBox(width: FasanSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bill.purpose.isEmpty ? (waiting || failed ? t.photoBill : t.appName) : bill.purpose, style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(sub, style: tt.bodySmall),
                ]),
              ),
              if (failed && !selecting)
                TextButton(onPressed: onRetry, child: Text(t.readAgain))
              else if (!waiting && !failed) ...[
                FasanAvatarStack(people: [for (final p in bill.ps) (p.name, p.color)], size: 24, max: 3),
                const SizedBox(width: FasanSpace.s),
                Money(bill.effectiveTotal),
              ],
            ]),
          ),
        );
    // Waiting, reading and failed photos have nothing to open yet.
    if (waiting || failed || selecting) return body(null);
    // Container transform: the card grows into the bill (fasan_ui GESTALTUNG.md §7). Unfinished bills continue where
    // the user left (Karte 3.9: Schließen verwirft nie).
    return FasanOpenContainer(
      radius: r,
      openBuilder: (_) => bill.done ? ResultScreen(bill: bill) : ResumeFlow(bill: bill),
      closedBuilder: (context, open) => body(open),
    );
  }
}

/// Screen of the step a draft was left on.
Widget resumeScreen(Bill b) => _stepScreen(b, b.step);

Widget _stepScreen(Bill b, int s) => switch (s) {
      2 => PeopleScreen(bill: b),
      3 => AssignScreen(bill: b),
      4 => PayScreen(bill: b),
      _ => ReviewScreen(bill: b),
    };

/// A resumed draft opens on its last step, but with the earlier steps underneath, so „zurück“ leads to the previous
/// step and not straight home (Nutzer 02.11.: angefangene Bons ließen sich teilweise nicht zurück bearbeiten – cause:
/// only the last step was pushed). A nested Navigator holds steps 1…n; when it has nothing left, back closes the bill.
class ResumeFlow extends StatefulWidget {
  const ResumeFlow({super.key, required this.bill});

  final Bill bill;

  @override
  State<ResumeFlow> createState() => _ResumeFlowState();
}

class _ResumeFlowState extends State<ResumeFlow> {
  final _nav = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final step = b.step.clamp(1, 4);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final n = _nav.currentState;
        if (n != null && n.canPop()) {
          n.pop();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Navigator(
        key: _nav,
        onGenerateInitialRoutes: (_, _) => [
          for (var s = 1; s <= step; s++) MaterialPageRoute<void>(builder: (_) => _stepScreen(b, s)),
        ],
        onGenerateRoute: (_) => null,
      ),
    );
  }

}
