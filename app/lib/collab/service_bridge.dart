// SPDX-License-Identifier: MPL-2.0
// Fasan Split – CollabService, part: Bridge to the bills, hidden bills. Split out of service.dart (13.11., Umbau U3, behaviour unchanged): the fields
// and constants stay in the class, these are its methods as an extension in the same library. MPL-2.0
part of 'service.dart';

extension CollabServiceBridge on CollabService {

  // ---- bridge to the bills ----

  void _onStoreChanged() => _pushAll();

  /// A small preview of the scan for the others (Nutzer 04.11.: no thumbnails in the browser). Once per bill, in the
  /// background; the bill goes out again with it.
  Future<void> _makeThumb(Bill b) async {
    final path = b.imagePath;
    if (path == null || !_thumbing.add(b.id)) return;
    try {
      final bytes = await readImage(path);
      if (bytes == null) return;
      final src = img.decodeImage(bytes);
      if (src == null) return;
      final small = img.copyResize(src, width: 120);
      b.thumb = base64.encode(img.encodeJpg(small, quality: 60));
      store.upsert(b, record: false);
    } catch (_) {
      // no preview: the bill is shared without it
    }
  }

  /// True if a shared bill was written by a newer build than this one (BillSync.schema): this build only reads.
  bool get outdated => groups.values.any((g) => g.session.docIds.any((id) => id.startsWith('bill:') && BillSync.schemaOf(g.session.doc(id)) > BillSync.schema));

  /// Earlier states of a shared bill, one per member (their last published state). Empty if the bill is not in a group.
  Future<List<BillSnapshot>> snapshotsOfBill(Bill b) async {
    final g = b.group == null ? null : groupByLocalName(b.group!);
    return g == null ? const [] : g.session.snapshotsOf(b.id);
  }

  /// Who published the snapshot [s] of [b] (own name for this phone).
  String snapshotWho(Bill b, BillSnapshot s) {
    if (s.author == identity?.pub) return identity?.name.trim().isNotEmpty == true ? identity!.name : store.me;
    final g = b.group == null ? null : groupByLocalName(b.group!);
    return g?.session.knownName(s.author) ?? 'Jemand';
  }

  /// Brings [b] back to the state of [s]: the values are applied to the bill and go out to the group as new changes (nothing
  /// is deleted; the log shows them). Locks of others still hold.
  void restoreSnapshot(Bill b, BillSnapshot s) {
    s.bill(b.id, into: b);
    store.upsert(b);
  }

  /// Takes a change back (Nutzer 12.11.: Saldo-Verlauf, „rückgängig machbar“): the values it replaced go into the bill document
  /// again, as a new change of this phone that everybody sees in the history. Keys that were changed again since, or that a
  /// padlock protects, stay as they are.
  UndoResult undoChange(ChangeRecord r) {
    final g = groups.values.where((x) => x.secret.tag == r.group).firstOrNull;
    if (g == null || r.undo.isEmpty) return UndoResult.nothing;
    final id = GroupSession.bill(r.billId), doc = g.session.doc(id), me = identity?.pub;
    final skipped = applyUndo(doc, r.undo, allow: me == null ? null : (k) => lockAllows(doc, k, me, adminPub: g.secret.adminPub));
    if (skipped.length >= r.undo.length) return UndoResult.nothing;
    g.session.touch(id);
    _saveDoc(g, id);
    final b = store.bills.where((x) => x.id == r.billId).firstOrNull;
    if (b != null) {
      BillSync.read(doc, id: b.id, into: b);
      store.upsert(b);
    }
    return skipped.isEmpty ? UndoResult.done : UndoResult.partly;
  }

  void _pushAll() {
    if (writesPaused) return;
    for (final b in store.bills) {
      if (b.thumb == null && b.imagePath != null && b.group != null && groupByLocalName(b.group!) != null) unawaited(_makeThumb(b));
      if (b.group != null && groupByLocalName(b.group!) != null) _preparePhotos(b);
    }
    _sendPhotos();
    for (final g in groups.values) {
      for (final b in store.bills) {
        // trashed bills go out too: the others move them to their trash (04.11.: they stayed there)
        if (b.group != g.localName || b.read != BillRead.ok) continue;
        // group default „new bills only for the people on them“: bills I started are hidden before the first write
        if (!b.hidden && hidesNewBills(g) && canHide(b) && _startedByMe(g, b)) hideBill(b);
        // a hidden bill is never written without its own key (it would go out under the group key and everybody could read it);
        // with the key, newly eligible readers (a person added to the bill) get it too
        if (b.hidden) {
          if (!g.session.hasBillKey(b.id)) continue;
          g.session.shareBillKey(b.id, billReaders(g, b));
          // „nur Beträge“: the summary (no item names, photos, notes) goes out under the group key for everybody
          if (b.sums) {
            final sid = 'sum:${b.id}', sd = g.session.doc(sid);
            if (BillSync.writeSummary(sd, b)) {
              g.session.touch(sid);
              _saveDoc(g, sid);
            }
          }
        }
        final id = GroupSession.bill(b.id);
        final doc = g.session.doc(id);
        final me = identity?.pub;
        var blocked = false;
        // padlocks: what somebody else locked is not written; it comes back from the document below
        final changed = BillSync.write(doc, b,
            allow: me == null ? null : (k) => lockAllows(doc, k, me, adminPub: g.secret.adminPub), onBlocked: () => blocked = true);
        if (changed) {
          g.session.touch(id);
          _saveDoc(g, id); // at once, not 600 ms later: the document must never be older than the stored bill (see _adoptDocs)
        }
        if (blocked) BillSync.read(doc, id: b.id, into: b);
      }
    }
  }

  // ---- hidden bills (Sichtbarkeit je Rechnung, docs/KONZEPT-SICHTBARKEIT.md) ----

  /// Members who may read a hidden bill: me and every member whose name or linked person is on the bill. Admins get no
  /// automatic right: everybody who joined by an open link is an admin (setAdmin in the join path), so „all admins“ would
  /// be „everybody“ and the hiding would do nothing.
  Set<String> billReaders(CollabGroup g, Bill b) {
    final s = g.session;
    final names = {for (final p in b.ps) p.name.trim().toLowerCase()}..remove('');
    final uids = {for (final p in b.ps) p.uid};
    return {
      s.me.pub,
      for (final pub in s.memberKeys)
        // by the member's own published person uid first (a renamed person stays linked), names as the way in
        if (s.uidsOf(pub).any(uids.contains) || {s.nameOf(pub), ...s.personsOf(pub)}.any((n) => names.contains(n.trim().toLowerCase()))) pub,
    };
  }

  /// Names of the people who can read [b] (me first), for the question before hiding it.
  List<String> hiddenReaderNames(Bill b) {
    final g = b.group == null ? null : groupByLocalName(b.group!);
    if (g == null) return const [];
    final me = g.session.me.pub;
    final readers = billReaders(g, b);
    return [for (final pub in [me, ...readers.where((k) => k != me)]) g.session.nameOf(pub)];
  }

  /// Group tags in which new bills I start are hidden at once (Standardstufe je Gruppe, Anforderung 18). Local to this phone.
  Set<String> get _hideNew => {...?prefs?.getStringList(CollabService._kHideNew)};

  bool hidesNewBills(CollabGroup g) => _hideNew.contains(g.secret.tag);

  void setHideNewBills(CollabGroup g, bool on) {
    final s = _hideNew;
    on ? s.add(g.secret.tag) : s.remove(g.secret.tag);
    prefs?.setStringList(CollabService._kHideNew, s.toList());
    if (on) _pushAll();
    _notify();
  }

  /// Did I start [b] (nobody else wrote into its document yet)? Only those are hidden by the group default.
  bool _startedByMe(CollabGroup g, Bill b) {
    final me = g.session.me.pub;
    return g.session.doc(GroupSession.bill(b.id)).entries.every((e) => e.author == me);
  }

  /// Bills of [g] that could still be hidden (not yet hidden, readable, not in the trash).
  List<Bill> hideableBills(CollabGroup g) => [
        for (final b in store.bills)
          if (b.group == g.localName && !b.hidden && b.read == BillRead.ok && canHide(b)) b
      ];

  /// Hides every bill of [g] that is not hidden yet (before inviting somebody who should not see the old ones). Returns how many.
  int hideAllBills(CollabGroup g) {
    var n = 0;
    for (final b in hideableBills(g)) {
      if (hideBill(b)) n++;
    }
    return n;
  }

  /// Can [b] be made readable for its people only: in a live group, not yet hidden, and I hold the group's identity.
  bool canHide(Bill b) => identity != null && !b.hidden && b.group != null && groupByLocalName(b.group!) != null;

  /// Makes [b] a hidden bill: own key for it, given to [billReaders]; from now on its document and photos are encrypted with
  /// it. What other members already hold from before stays with them (the dialog says so). False if it cannot be done.
  bool hideBill(Bill b, {bool sums = false}) {
    if (!canHide(b)) return false;
    b.sums = sums;
    final g = groupByLocalName(b.group!)!;
    g.session.shareBillKey(b.id, billReaders(g, b));
    b.hidden = true;
    store.upsert(b);
    _notify();
    return true;
  }
}
