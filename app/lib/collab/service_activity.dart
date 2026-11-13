// SPDX-License-Identifier: MPL-2.0
// Fasan Split – CollabService, part: Activity (bell) and changed bills. Split out of service.dart (13.11., Umbau U3, behaviour unchanged): the fields
// and constants stay in the class, these are its methods as an extension in the same library. MPL-2.0
part of 'service.dart';

extension CollabServiceActivity on CollabService {

  List<Activity> get activity => _act ??= Activity.decode(prefs?.getString(CollabService._kActivity));

 // bill doc → item uid → note text seen

  /// New since the bell was opened.
  int get unseenActivity {
    final seen = prefs?.getInt(CollabService._kSeen) ?? 0;
    return activity.where((a) => a.at.millisecondsSinceEpoch > seen).length;
  }

  void markActivitySeen() {
    prefs?.setInt(CollabService._kSeen, DateTime.now().millisecondsSinceEpoch);
    _notify();
  }

  /// Bills someone else changed that I have not opened since (marked in the list).
  Set<String> get changedBills => {...?prefs?.getStringList(CollabService._kChanged)};

  int _openedAt(String id) => prefs?.getInt('${CollabService._kOpened}$id') ?? 0;

  /// Changes by others to [billId] since I opened it the time before (newest first).
  List<ChangeRecord> unseenChanges(String billId) {
    final since = _sinceOpen[billId] ?? _openedAt(billId);
    return [for (final r in changesOfBill(billId)) if (r.whoKey != identity?.pub && r.at.millisecondsSinceEpoch > since) r];
  }

  /// Number of single changes (lines) in [unseenChanges] – the counter on the bill's thumbnail in the list.
  int unseenCount(String billId) => unseenChanges(billId).fold(0, (a, r) => a + r.lines.length);

  void billSeen(String id) {
    _sinceOpen[id] = _openedAt(id);
    prefs?.setInt('${CollabService._kOpened}$id', DateTime.now().millisecondsSinceEpoch);
    final c = changedBills;
    if (c.remove(id)) {
      prefs?.setStringList(CollabService._kChanged, c.toList());
      _notify();
    }
  }


  bool notifies(ActivityKind k) => !(prefs?.getStringList(CollabService._kNotify) ?? const []).contains(k.name);

  void setNotifies(ActivityKind k, bool on) {
    final off = {...?prefs?.getStringList(CollabService._kNotify)};
    on ? off.remove(k.name) : off.add(k.name);
    prefs?.setStringList(CollabService._kNotify, off.toList());
    _notify();
  }

  void _note(Activity a) {
    if (!notifies(a.kind == ActivityKind.billChanged ? ActivityKind.billNew : a.kind)) return;
    final l = activity;
    // several snapshots of one edit: one line, not five
    if (a.ref != null && l.isNotEmpty && l.first.ref == a.ref && l.first.group == a.group && a.at.difference(l.first.at).abs() < const Duration(minutes: 2) &&
        (l.first.kind == a.kind || l.first.kind == ActivityKind.billNew && a.kind == ActivityKind.billChanged)) {
      if (l.first.kind == ActivityKind.billNew) return;
      l.removeAt(0);
    }
    l.insert(0, a);
    if (l.length > 150) l.removeRange(150, l.length);
    prefs?.setString(CollabService._kActivity, Activity.encode(l));
    onActivity?.call(a);
  }

  bool _quiet(CollabGroup g) => DateTime.now().difference(_activeSince[g.secret.tag] ?? DateTime(0)) < const Duration(seconds: 8);

  String _groupLabel(CollabGroup g) => g.secret.direct ? directName(g) : g.localName;

  void _trackActivity(CollabGroup g, String id) {
    final me = identity?.pub;
    final s = g.session;
    if (id == GroupSession.members) {
      final now = s.memberKeys;
      final before = _knownMembers[g.secret.tag];
      _knownMembers[g.secret.tag] = now;
      if (before == null || _quiet(g) || g.secret.direct) return;
      for (final k in now.difference(before)) {
        if (k == me) continue;
        // the name may arrive after the key: use it when known, otherwise „Jemand Neues“, never an empty or key-like name
        final n = s.knownName(k);
        _note(Activity(ActivityKind.joined, DateTime.now(), g.secret.tag, '${n ?? 'Jemand Neues'} ist „${g.localName}“ beigetreten', en: '${n ?? 'Someone new'} joined “${g.localName}”'));
      }
    } else if (id == GroupSession.chat) {
      final msgs = messages(g);
      final known = _knownMessages[g.secret.tag];
      _knownMessages[g.secret.tag] = {for (final m in msgs) m.id};
      if (_quiet(g)) return;
      for (final m in msgs) {
        if (known != null && known.contains(m.id) || m.from == me || m.deleted) continue;
        // first batch of this chat on this device: old messages are history (the unread number shows them), but a message sent
        // just now is news – before, the very first message of a new group never made a notification
        if (known == null && DateTime.now().difference(m.at) > const Duration(seconds: 30)) continue;
        if (me != null && m.mentions.contains(me)) {
          // mentions get through even when the chat is muted
          _note(Activity(ActivityKind.mention, m.at, g.secret.tag, '${s.nameOf(m.from)} hat dich in „${_groupLabel(g)}“ erwähnt: ${m.text}', ref: m.id, en: '${s.nameOf(m.from)} mentioned you in “${_groupLabel(g)}”: ${m.text}'));
        } else if (!isMuted(g)) {
          _note(Activity(ActivityKind.message, m.at, g.secret.tag, '${s.nameOf(m.from)} in „${_groupLabel(g)}“: ${m.text}', ref: m.id, en: '${s.nameOf(m.from)} in “${_groupLabel(g)}”: ${m.text}'));
        }
      }
    } else if (id.startsWith('bill:')) {
      final doc = s.doc(id);
      Entry? last;
      for (final e in doc.entries) {
        if (last == null || e.beats(last)) last = e;
      }
      final billId = id.substring(5);
      // notes that mention me (Nutzer 04.11.: @user in a bill note notifies them)
      final noteIds = doc.keys('n/').toSet();
      final knownN = _knownNotes[id];
      _knownNotes[id] = noteIds;
      if (knownN != null && !_quiet(g)) {
        final myName = (identity?.name ?? store.me).trim().toLowerCase();
        for (final k in noteIds.difference(knownN)) {
          final v = doc.get(k);
          if (v is! Map || v['f'] == (identity?.name ?? '')) continue;
          final ms = [for (final m in (v['m'] as List?) ?? const []) '$m'.toLowerCase()];
          if (ms.contains(me) || myName.isNotEmpty && ms.contains(myName)) {
            final p = doc.get('meta/purpose');
            _note(Activity(ActivityKind.mention, DateTime.now(), g.secret.tag, '${v['f']} hat dich in „${p is String && p.isNotEmpty ? p : 'Bon'}“ erwähnt: ${v['x']}', ref: billId,
                en: '${v['f']} mentioned you in “${p is String && p.isNotEmpty ? p : 'Receipt'}”: ${v['x']}'));
          }
        }
      }
      // @mention of me in the note of an item (Nutzer 09.11.): the writer of the item entry is the one who mentioned
      final itemNotes = <String, String>{
        for (final k in doc.keys('i/'))
          if (doc.get(k) case final Map v when v['note'] is String && (v['note'] as String).trim().isNotEmpty) k.substring(2): v['note'] as String
      };
      final knownI = _knownItemNotes[id];
      _knownItemNotes[id] = itemNotes;
      if (knownI != null && !_quiet(g)) {
        final myName = (identity?.name ?? store.me).trim().toLowerCase();
        for (final n in itemNotes.entries) {
          if (knownI[n.key] == n.value || myName.isEmpty || !n.value.toLowerCase().contains('@$myName')) continue;
          Entry? w;
          for (final e in doc.entries) {
            if (e.key == 'i/${n.key}' && (w == null || e.beats(w))) w = e;
          }
          if (w == null || w.author == identity?.pub) continue;
          final item = doc.get('i/${n.key}');
          final it = item is Map ? '${item['name']}' : '';
          final who = s.nameOf(w.author);
          _note(Activity(ActivityKind.mention, DateTime.now(), g.secret.tag, '$who hat dich bei „$it“ erwähnt: ${n.value}', ref: '$billId#${n.key}',
              en: '$who mentioned you at “$it”: ${n.value}'));
        }
      }
      // tentative „vllt“ proposals for me (sv/<item>/<person>): the person is me when the name matches mine
      final svKeys = doc.keys('sv/').toSet();
      final knownS = _knownMaybe[id];
      _knownMaybe[id] = svKeys;
      if (knownS != null && !_quiet(g)) {
        final myName = (identity?.name ?? store.me).trim().toLowerCase();
        for (final k in svKeys.difference(knownS)) {
          final by = doc.get(k), parts = k.split('/');
          if (by is! String || by == identity?.pub || parts.length < 3 || myName.isEmpty) continue;
          final person = doc.get('p/${parts.last}');
          if (person is! Map || '${person['name']}'.trim().toLowerCase() != myName) continue;
          final item = doc.get('i/${parts[1]}');
          final it = item is Map ? '${item['name']}' : '';
          final who = s.nameOf(by);
          _note(Activity(ActivityKind.proposal, DateTime.now(), g.secret.tag, '$who schlägt vor, dass „$it“ zu dir gehört (vielleicht)', ref: '$billId#${parts[1]}',
              en: '$who suggests “$it” is yours (maybe)'));
        }
      }
      if (last == null || last.author == me || _quiet(g)) return;
      final isNew = !store.bills.any((b) => b.id == billId);
      final purpose = doc.get('meta/purpose');
      final title = purpose is String && purpose.isNotEmpty ? purpose : 'Bon';
      final who = s.nameOf(last.author);
      // a change of an existing bill is announced with its content by the change log (_flushBurst)
      if (isNew) {
        _note(Activity(ActivityKind.billNew, DateTime.now(), g.secret.tag, '$who hat „$title“ in „${g.localName}“ eingetragen', ref: billId,
            en: '$who added “${title == 'Bon' ? 'Receipt' : title}” to “${g.localName}”'));
      }
      final c = changedBills..add(billId);
      prefs?.setStringList(CollabService._kChanged, c.toList());
    }
  }

  BalanceLedger get ledger => _ledger ??= BalanceLedger.decode(prefs?.getString(CollabService._kLedger));

  /// Who counts as me on a bill (Nutzer 11.11.: „Alles muss überall mit dem echten User verknüpft sein“). Names alone
  /// were the weak point: a renamed person or a second „Chris“ broke the link. A person is me when its stable uid is
  /// known as mine ([_ownUids], learned from every person that carries one of my names, see [learnOwnUids]); the names
  /// ([ownNames]) stay only as the way in for bills that no uid was learned from yet.
  bool Function(String) get isMeName {
    final names = ownNames;
    return (n) => names.contains(n.trim().toLowerCase());
  }

  Set<String> get ownUids => {...?prefs?.getStringList(CollabService._kUids)};

  bool Function(Person) get isMePerson {
    final names = ownNames, uids = ownUids;
    return (p) => uids.contains(p.uid) || names.contains(p.name.trim().toLowerCase());
  }

  /// Pins the uid of every person on my bills that carries one of my names: from then on a rename of that person (or a
  /// new person with the same name) cannot change who is me. Returns true when something was added.
  /// My person uids into my profile in every group (others use them, see [CollabGroup] billReaders).
  void publishOwnUids() {
    final u = ownUids;
    for (final g in groups.values) {
      g.session.setMyUids(u);
    }
  }

  bool learnOwnUids() {
    if (identity == null) return false;
    final names = ownNames, uids = ownUids;
    final before = uids.length;
    for (final b in store.bills) {
      for (final p in b.ps) {
        if (names.contains(p.name.trim().toLowerCase())) uids.add(p.uid);
      }
    }
    if (uids.length == before) return false;
    prefs?.setStringList(CollabService._kUids, uids.toList());
    unawaited(syncAccount());
    publishOwnUids();
    return true;
  }

  // after the bill documents were read into the store and the change log has its line (burst timer 800 ms)
  void _ledgerSoon() {
    if (_disposed) return;
    _ledgerTimer?.cancel();
    _ledgerTimer = Timer(const Duration(milliseconds: 1500), _bookLedger);
  }

  void _bookLedger() {
    if (_disposed) return;
    final l = ledger;
    learnOwnUids();
    final changed = l.update(store.bills, isMeName, isMePerson: isMePerson, why: (id, before, after) {
      // every record of this bill that reached this phone since the last look (not „within 5 minutes by the writer's clock“:
      // somebody who was offline writes hours late, and then the history had no reason at all, Nutzer 12.11.)
      final mine = [for (final r in changeLog) if (r.billId == id && r.rcvAt.isAfter(_lastBooked)) r];
      if (mine.isNotEmpty) {
        final r = mine.first;
        final more = mine.length > 1 ? ' (+${mine.length - 1})' : '';
        final de = '${r.who}: ${r.lines.take(2).map((x) => x.de).join('; ')}$more', en = '${r.who}: ${r.lines.take(2).map((x) => x.en).join('; ')}$more';
        return (de, en, r.at.millisecondsSinceEpoch, r.whoKey);
      }
      if (before == 0) return ('Bon hinzugekommen', 'Receipt added', null, null);
      if (after == 0) return ('Bon abgeschlossen oder entfernt', 'Receipt closed or removed', null, null);
      return null;
    });
    _lastBooked = DateTime.now();
    prefs?.setInt(CollabService._kLedgerAt, _lastBooked.millisecondsSinceEpoch);
    if (changed) {
      prefs?.setString(CollabService._kLedger, l.encode());
      _publishHistoryAll();
      _notify();
    }
  }

  /// Newest first; every change of every bill in every group, from this phone's point of view (own changes too).
  List<ChangeRecord> get changeLog => _changeLog ??= ChangeRecord.decode(prefs?.getString(CollabService._kChangeLog));

  List<ChangeRecord> changesOfBill(String billId) => [for (final r in changeLog) if (r.billId == billId) r];

  List<ChangeRecord> changesOfGroup(String tag) => [for (final r in changeLog) if (r.group == tag) r];

  void _onEntry(CollabGroup g, String docId, Entry? old, Entry now) {
    final key = '${g.secret.tag}|$docId';
    var b = _bursts[key];
    if (b == null) {
      // how much the document held before this burst: a document that was empty is being created (or loaded for the
      // first time) – no change, nothing to list
      final live = g.session.doc(docId).keys('').length;
      final self = old?.value == null && now.value != null ? 1 : (old?.value != null && now.value == null ? -1 : 0);
      b = _bursts[key] = _Burst(g, docId, live - self);
    }
    b.pairs.add((old, now));
    b.timer?.cancel();
    b.timer = Timer(const Duration(milliseconds: 800), () => _flushBurst(key));
  }

  void _flushBurst(String key) {
    final b = _bursts.remove(key);
    if (b == null || b.liveBefore <= 0) return;
    final g = b.g, s = g.session, doc = s.doc(b.docId);
    final billId = b.docId.substring(5);
    final purpose = doc.get('meta/purpose');
    final title = purpose is String && purpose.isNotEmpty ? purpose : 'Bon';
    final me = identity?.pub;
    final byAuthor = <String, List<EntryChange>>{};
    for (final p in b.pairs) {
      (byAuthor[p.$2.author] ??= []).add(p);
    }
    for (final e in byAuthor.entries) {
      final lines = describeChanges(doc, e.value);
      if (lines.isEmpty) continue;
      final who = e.key == me ? (identity?.name.trim().isNotEmpty == true ? identity!.name : store.me) : (s.knownName(e.key) ?? 'Jemand');
      // when the writer made the change (their device clock, never later than now), not when it reached this phone
      final now = DateTime.now();
      final walls = [for (final p in e.value) if (p.$2.wall != null) p.$2.wall!];
      final at = walls.isEmpty ? now : DateTime.fromMillisecondsSinceEpoch(walls.reduce((a, c) => a > c ? a : c).clamp(0, now.millisecondsSinceEpoch));
      final app = [for (final p in e.value) if (p.$2.app != null) p.$2.app!].firstOrNull;
      // the replaced values, so the change can be taken back from the balance history (not for photos, and not for huge changes)
      final first = <String, Object?>{}, last = <String, Object?>{};
      for (final p in e.value) {
        if (!undoable(p.$2.key)) continue;
        first.putIfAbsent(p.$2.key, () => p.$1?.value); // the oldest value of a key that changed twice in one go
        last[p.$2.key] = p.$2.value;
      }
      final ops = [for (final k in first.keys) if (jsonEncode(first[k]) != jsonEncode(last[k])) UndoOp(k, first[k], last[k])];
      final rec = ChangeRecord(at: at, group: g.secret.tag, billId: billId, title: title, who: who, whoKey: e.key, lines: lines, app: app, undo: ops.length <= 60 ? ops : const []);
      final l = changeLog;
      l.insert(0, rec);
      if (l.length > 600) l.removeRange(600, l.length);
      prefs?.setString(CollabService._kChangeLog, ChangeRecord.encode(l));
      if (e.key != me && !_quiet(g)) {
        final more = lines.length > 3 ? ' (+${lines.length - 3})' : '';
        final de = '$who hat „$title“ geändert: ${lines.take(3).map((x) => x.de).join('; ')}$more';
        final en = '$who changed “${title == 'Bon' ? 'Receipt' : title}”: ${lines.take(3).map((x) => x.en).join('; ')}$more';
        _note(Activity(ActivityKind.billChanged, rec.at, g.secret.tag, de, ref: billId, en: en));
      }
    }
    _notify();
  }

  void _onDocChanged(CollabGroup g, String id) {
    _scheduleSave();
    if (identity != null && id == GroupSession.profile(identity!.pub)) _unpublishPay(g); // older versions published my details here
    if (_adoptPending && (id.startsWith('profile:') || id == GroupSession.members)) unawaited(_adoptNameFromGroups());
    _trackActivity(g, id);
    if (id == GroupSession.members || id == GroupSession.chat || id == GroupSession.notes || id.startsWith('profile:')) {
      if (id == GroupSession.members) {
        _ensureInvitations(g); // someone made me admin
        if (_laterOffers.isNotEmpty) {
          final again = _laterOffers.toList();
          _laterOffers.clear();
          again.forEach(_onDirectOffer);
        }
      }
      _notify();
      return;
    }
    if (id.startsWith('sum:')) {
      _adoptSummary(g, id);
      return;
    }
    if (!id.startsWith('bill:')) return;
    final billId = id.substring(5);
    final doc = g.session.doc(id);
    if (!BillSync.hasBill(doc)) return;
    Bill? existing;
    for (final b in store.bills) {
      if (b.id == billId) existing = b;
    }
    final bill = BillSync.read(doc, id: billId, into: existing);
    bill.group = g.localName;
    store.upsert(bill, record: false); // notifies; the write back finds nothing to change (not a step of the user's undo)
    _wantPhotos(g, bill);
  }

  /// A summary of a hidden bill with visible amounts arrived: without the bill's key this phone gets a copy with one line per
  /// person (what they owe), so balances are right. With the key, the full bill is the truth.
  void _adoptSummary(CollabGroup g, String id) {
    final billId = id.substring(4);
    final doc = g.session.doc(id);
    if (!BillSync.hasSummary(doc) || g.session.hasBillKey(billId)) return;
    Bill? existing;
    for (final b in store.bills) {
      if (b.id == billId) existing = b;
    }
    if (existing != null && !existing.sumOnly) return;
    final bill = BillSync.readSummary(doc, id: billId, into: existing)..purpose = '•••';
    bill.group = g.localName;
    store.upsert(bill, record: false);
  }
}
