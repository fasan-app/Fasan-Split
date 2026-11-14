// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the three bill lists of the start page (Offen, Archiv, Papierkorb), their rows, menus and the item view
// (moved out of home.dart, Umbau 14.11.; only moved). MPL-2.0
part of 'home.dart';

extension _HomeLists on _HomeScreenState {
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
        if (scope == kScopeAll || scope == g) (g, arrange(store.inGroup(g, archived: done), sort, _catFilter, onlyOpen: store.onlyOpen, favorites: store.favorites).where(keep).toList())
    ].where((e) => e.$2.isNotEmpty).toList();
    final loose = scope == kScopeAll || scope == kScopeLoose ? arrange(store.inGroup(null, archived: done), sort, _catFilter, onlyOpen: store.onlyOpen, favorites: store.favorites).where(keep).toList() : <Bill>[];
    final shown = [for (final e in groups) ...e.$2, ...loose];
    // nothing at all in this view (not: nothing that passes the buttons)
    final anyHere = [for (final g in store.groups) if (scope == kScopeAll || scope == g) ...store.inGroup(g, archived: done), if (scope == kScopeAll || scope == kScopeLoose) ...store.inGroup(null, archived: done)].isNotEmpty;
    final empty = !anyHere;
    // the whole scope for the frame and the counts, whatever the buttons say
    final scopeBills = scopeIsGroup(scope)
        ? store.inGroup(scope)
        : [if (scope == kScopeAll) for (final g in store.groups) ...store.inGroup(g), ...store.inGroup(null)];
    final flat = _itemsView ? flattenItems(shown, favorites: store.favorites, onlyOpen: store.onlyOpen, fills: _fills, itemMatch: q.isEmpty ? null : (b, i) => _itemMatches(b, i, q, t.de), payerMatch: q.isEmpty ? null : (b) => payerSearchMatch(context, b, q)) : const <(Bill, BillItem?)>[];
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
            ? WebUpdateBanner(onClose: () => _set(() => _webUpdate = false))
            : _update != null
                ? UpdateBanner(info: _update!, onClose: () => _set(() => _update = null))
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
                  onFills: (v) => _set(() => _fills = v),
                  onNoPayer: (v) => _set(() => _noPayer = v),
                ),
                // always visible (Nutzer 09.11.): bills or items
                FasanSegmented<int>(
                  values: const [0, 1],
                  selected: _itemsView ? 1 : 0,
                  label: (i) => trLang(t.de ? 'de' : 'en', i == 0 ? 'grp.bills' : 'grp.items'),
                  onChanged: (v) => _set(() => _itemsView = v == 1),
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
    if (!scopeIsGroup(scope)) return GroupsPage(queue: queue, onOpen: (g) => _set(() => _scope = g));
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
                _set(() {
                  _selecting = true;
                  _selected.add(b.id);
                });
              }
              _set(() => _dragging = true);
            },
            onDragEnd: (_) {
              if (mounted) _set(() => _dragging = false);
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
            _set(() {
              _selecting = true;
              _selected.add(b.id);
            });
          case 'fav':
            store.toggleFavorite(b.id);
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
        PopupMenuItem(
          key: ValueKey('fav-${b.id}'),
          value: 'fav',
          child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(store.isFavorite(b.id) ? Icons.push_pin : Icons.push_pin_outlined), title: Text(trLang(lang, store.isFavorite(b.id) ? 'fav.unpin' : 'fav.pin'))),
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
