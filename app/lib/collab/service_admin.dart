// SPDX-License-Identifier: MPL-2.0
// Fasan Split – CollabService, part: Admin, trust, how others can pay me back, deleting the account. Split out of service.dart (13.11., Umbau U3, behaviour unchanged): the fields
// and constants stay in the class, these are its methods as an extension in the same library. MPL-2.0
part of 'service.dart';

extension CollabServiceAdmin on CollabService {

  // ---- admin ----

  Future<void> approve(CollabGroup g, JoinRequest r) async {
    final inv = g.invitations;
    if (inv == null) return;
    // not yet a member, or in through an open link only: the admin writes the entry itself (then it stays when the
    // link is withdrawn)
    if (!g.session.memberKeys.contains(r.pub) || g.session.isSelfJoined(r.pub)) {
      final n = r.name.isEmpty ? r.pub.substring(0, 8) : r.name;
      g.session.addMember(r.pub, n, person: r.person ?? g.session.personOf(r.pub) ?? n);
      // open links: everyone in the group may invite too (Nutzer 04.11.: like messenger groups where all can add people)
      if (r.auto && !g.secret.direct) g.session.setAdmin(r.pub, true);
    }
    await g.session.flush(); // members first, then the key
    await inv.welcome(r.pub);
    _notify();
  }

  /// Withdraws one link: nobody new gets in with it (its ticket is deleted). Whoever already joined stays. The group key
  /// stays too – for „nobody who ever had a link can read on“ there is [revokeInvites].
  void revokeInvite(CollabGroup g, Invite i) {
    if (i.groupKey != null && g.session.isAdmin) g.session.setTicket(i, open: false);
    g.invitations?.revoke(i);
    _notify();
  }

  /// Admin: withdraws all invitation links of this phone. Open links carry the group key, so the group gets a new one
  /// (rotateKey): old links lead nowhere. Members who came in through a link and were not adopted yet are adopted first.
  Future<CollabGroup> revokeInvites(CollabGroup g) async {
    final inv = g.invitations;
    final s = g.session;
    for (final pub in s.memberKeys.where(s.isSelfJoined).toList()) {
      s.addMember(pub, s.nameOf(pub), person: s.personOf(pub));
    }
    final hadOpen = inv?.open.any((i) => i.groupKey != null) ?? false;
    for (final i in inv?.open ?? const <Invite>[]) {
      if (i.groupKey != null) s.setTicket(i, open: false);
    }
    inv?.revokeAll();
    await s.flush();
    final ng = hadOpen ? await rotateKey(g) : g;
    _notify();
    return ng;
  }

  void decline(CollabGroup g, JoinRequest r) {
    g.invitations?.decline(r.pub);
    _notify();
  }

  /// Admin: links a member to a person of the group's bills, or unlinks (person null).
  void linkPerson(CollabGroup g, String pub, String? person) {
    g.session.linkPerson(pub, person);
    _notify();
  }

  void unlinkPerson(CollabGroup g, String pub, String person) {
    g.session.unlinkPerson(pub, person);
    _notify();
  }

  /// Removes a member and gives everyone else a new group key, so the removed one cannot read anything new (04.11.).
  Future<CollabGroup> removeMember(CollabGroup g, String pub) async {
    g.session.removeMember(pub);
    await g.session.flush();
    final ng = await rotateKey(g);
    _notify();
    return ng;
  }

  /// Admin: makes a member admin too (or takes it back). Then the group keeps an admin when the founder leaves.
  void setAdmin(CollabGroup g, String pub, bool admin) {
    g.session.setAdmin(pub, admin);
    _notify();
  }

  /// Founder: „everybody is admin“ on or off (Paket 5).
  void setAllAdmins(CollabGroup g, bool on) {
    g.session.setAllAdmins(on);
    _notify();
  }

  /// Admin: new group key for everyone in the members list except me; they get it as a NIP-44 message bound to the old
  /// group, then all documents move to the new key. Returns the group under its new key.
  Future<CollabGroup> rotateKey(CollabGroup g) async {
    final me = await ensureIdentity();
    if (!g.isAdmin) throw StateError('only an admin rotates the key');
    final s = g.secret;
    final ns = GroupSecret(key: randomBytes(32), adminPub: s.adminPub, name: s.name, relays: s.relays, direct: s.direct);
    final body = jsonEncode({'key': toHex(ns.key), 'name': ns.name, 'admin': ns.adminPub, 'relays': ns.relays});
    for (final pub in g.session.memberKeys) {
      if (pub == me.pub) continue;
      final ev = NostrEvent.create(me.key, kind: kindData, tags: [['d', 'fs:${s.tag}:rekey:$pub'], ['t', '${s.tag}:rekey'], ['p', pub]], content: nip44Encrypt(body, nip44ConversationKey(me.key.priv, pub)));
      await g.session.relay.publish(ev);
    }
    return _switchKey(g, ns);
  }

  void _onRekey(CollabGroup g, NostrEvent e) {
    final me = identity;
    if (me == null || !e.valid || !g.session.admins.contains(e.pubkey) || e.tag('d') != 'fs:${g.secret.tag}:rekey:${me.pub}') return;
    try {
      final j = jsonDecode(nip44Decrypt(e.content, nip44ConversationKey(me.key.priv, e.pubkey))) as Map<String, dynamic>;
      final ns = GroupSecret(key: fromHex(j['key'] as String), adminPub: j['admin'] as String? ?? g.secret.adminPub, name: j['name'] as String? ?? g.secret.name, relays: [for (final r in j['relays'] as List) '$r'], direct: g.secret.direct);
      if (ns.adminPub != g.secret.adminPub || groups.containsKey(ns.tag)) return; // other group or already there
      _switchKey(g, ns);
    } catch (_) {
      // not for us or damaged
    }
  }

  /// Moves a group to a new key: new session, all documents copied (and published again), old session closed.
  Future<CollabGroup> _switchKey(CollabGroup g, GroupSecret ns) async {
    final ng = await _activate(ns, g.localName);
    for (final id in g.session.docIds.toList()) {
      ng.session.doc(id).merge(g.session.doc(id).entries);
      ng.session.touch(id);
    }
    await g.rekeySub?.cancel();
    await _subs.remove(g.secret.tag)?.cancel();
    await g.session.close();
    await g.invitations?.close();
    groups.remove(g.secret.tag);
    held.removeWhere((h) => h.group == g);
    await _persistGroups();
    saveDocs();
    _notify();
    return ng;
  }

  void _ensureInvitations(CollabGroup g) {
    if (!g.session.isAdmin || g.invitations != null) return;
    final me = identity;
    if (me == null) return;
    final inv = Invitations(secret: g.secret, me: me.key, relay: g.session.relay);
    g.invitations = inv;
    final key = 'fasan.invites.${g.secret.tag}';
    inv.onIssued = (l) {
      unawaited(vault.write(key, jsonEncode([for (final i in l) i.encode()])));
      // open links: the ticket goes into the members document at once (group.dart step 4b)
      if (!g.session.isAdmin) return;
      var added = false;
      for (final i in l) {
        if (i.groupKey != null && g.session.doc(GroupSession.members).get('i/${i.ticketId}') == null) {
          g.session.setTicket(i);
          added = true;
        }
      }
      if (added) unawaited(g.session.flush());
    };
    inv.changes.stream.listen((_) {
      _autoApprove(g);
      _notify();
    });
    () async {
      // invitations of earlier runs first, then read the requests (also those sent while this phone was off)
      try {
        final raw = await vault.read(key);
        if (raw != null) inv.restore([for (final c in jsonDecode(raw) as List) ?Invite.parse(c as String)]);
      } catch (_) {}
      inv.listen();
    }();
  }

  /// Requests through an invitation with „let in at once“, and repeated requests of members (e.g. after a reinstall
  /// that lost the welcome), are approved without asking.
  void _autoApprove(CollabGroup g) {
    final inv = g.invitations;
    if (inv == null) return;
    for (final r in inv.pending.values.toList()) {
      if (r.auto || g.session.memberKeys.contains(r.pub)) unawaited(approve(g, r));
    }
  }

  Map<String, Object?> get _trust => (jsonDecode(prefs?.getString(CollabService._kTrust) ?? '{}') as Map).cast<String, Object?>();

  /// Changes by anyone else that touch my shares, my person or the payer wait for me.
  bool get confirmAll => _trust['all'] == true;

  set confirmAll(bool v) {
    prefs?.setString(CollabService._kTrust, jsonEncode({..._trust, 'all': v}));
    _notify();
  }

  /// Members whose changes about me wait for me.
  Set<String> get distrusted => {...?(_trust['people'] as List?)?.cast<String>()};

  void setTrusted(String pub, bool trusted) {
    final p = distrusted;
    trusted ? p.remove(pub) : p.add(pub);
    prefs?.setString(CollabService._kTrust, jsonEncode({..._trust, 'people': p.toList()}));
    _notify();
  }

  /// Members who may not enter anything about me at all (level „nein“ of the stand-in levels, Nutzer 09.11.): their changes
  /// about my person are dropped on this phone. Local, like the held changes. Wins over [confirmAll] and [distrusted].
  Set<String> get blocked => {...?(_trust['block'] as List?)?.cast<String>()};

  /// full = their entries about me apply at once; confirm = they wait for me; block = they are dropped.
  TrustLevel trustOf(String pub) => blocked.contains(pub) ? TrustLevel.block : (distrusted.contains(pub) ? TrustLevel.confirm : TrustLevel.full);

  void setTrust(String pub, TrustLevel level) {
    final d = distrusted, b = blocked;
    d.remove(pub);
    b.remove(pub);
    if (level == TrustLevel.confirm) d.add(pub);
    if (level == TrustLevel.block) b.add(pub);
    prefs?.setString(CollabService._kTrust, jsonEncode({..._trust, 'people': d.toList(), 'block': b.toList()}));
    _notify();
  }

  bool _accept(CollabGroup g, String docId, Entry e) {
    // padlocks (lock_rules.dart): a locked bill or item takes changes only from whoever locked it and from the group admin
    if (docId.startsWith('bill:') && !lockAllows(g.session.doc(docId), e.key, e.author, adminPub: g.secret.adminPub)) return false;
    final me = identity;
    if (me == null || e.author == me.pub || !docId.startsWith('bill:')) return true;
    if (!confirmAll && !distrusted.contains(e.author) && !blocked.contains(e.author)) return true;
    // which persons of this bill are me: my name or names linked to my key
    final names = {store.me.trim().toLowerCase(), ...g.session.personsOf(me.pub).map((n) => n.toLowerCase())}..remove('');
    final doc = g.session.doc(docId);
    final mine = <String>{
      for (final k in doc.keys('p/'))
        if (doc.get(k) case final Map p when names.contains('${p['name']}'.trim().toLowerCase())) k.substring(2),
    };
    if (mine.isEmpty) return true;
    final concerns = e.key == 'meta/payer' || mine.any((u) => e.key == 'p/$u' || ((e.key.startsWith('s/') || e.key.startsWith('f/')) && e.key.endsWith('/$u')));
    if (!concerns) return true;
    if (blocked.contains(e.author)) return false; // level „nein“: dropped, not even held
    // a share added for me is only a suggestion: it shows faded at the item until I accept it (Nutzer 09.11.: „vllt“)
    final addsMe = e.key.startsWith('s/') && e.value is num && (e.value as num) > 0 && (doc.get(e.key) is! num || (doc.get(e.key) as num) <= 0);
    if (addsMe && mine.any((u) => e.key.endsWith('/$u'))) {
      final parts = e.key.split('/');
      scheduleMicrotask(() {
        final bill = store.bills.where((b) => b.id == docId.substring(5)).firstOrNull;
        final item = bill?.its.where((x) => x.uid == parts[1]).firstOrNull;
        final idx = bill?.ps.indexWhere((p) => p.uid == parts[2]) ?? -1;
        if (bill != null && item != null && idx >= 0) {
          if ((item.shares[idx] ?? 0) <= 0) {
            item.maybe[idx] = e.author;
            store.upsert(bill);
          }
        } else if (!held.any((h) => h.docId == docId && h.entry.key == e.key && h.entry.ts == e.ts)) {
          held.add(HeldChange(g, docId, e)); // bill, item or person not here yet: wait in the list of held changes instead
          _notify();
        }
      });
      return false;
    }
    if (!held.any((h) => h.docId == docId && h.entry.key == e.key && h.entry.ts == e.ts && h.entry.author == e.author)) {
      held.add(HeldChange(g, docId, e));
      scheduleMicrotask(notifyListeners);
    }
    return false;
  }

  /// Takes a held change (it is applied as if it had come in now) or drops it.
  void decideHeld(HeldChange h, bool take) {
    held.remove(h);
    if (take && h.group.session.doc(h.docId).apply(h.entry)) _onDocChanged(h.group, h.docId);
    _notify();
  }

  /// My payment details, on this device; shared only in my groups' profiles (encrypted, members only).
  PayInfo get myPay => PayInfo.fromJson((jsonDecode(prefs?.getString(CollabService._kPay) ?? '{}') as Map).cast<String, Object?>());

  set myPay(PayInfo p) {
    prefs?.setString(CollabService._kPay, jsonEncode(p.toJson()));
    for (final g in groups.values) {
      _publishPay(g, p);
    }
    _notify();
  }

  void _publishPay(CollabGroup g, PayInfo p) {
    final id = GroupSession.profile(g.session.me.pub);
    g.session.doc(id).set('pay', p.isEmpty ? null : p.toJson());
    g.session.touch(id);
  }

  /// What [pub] shared to be paid (newest group that has it), or null.
  PayInfo? payOf(String pub) {
    for (final g in groups.values) {
      final v = g.session.doc(GroupSession.profile(pub)).get('pay');
      if (v is Map) return PayInfo.fromJson(v.cast<String, Object?>());
    }
    return null;
  }

  // ---- deleting the account (Nutzer 04.11.) ----

  /// Deletes my account: every group and friend first learns „Konto gelöscht“ (my profile there), I leave the members
  /// lists, a NIP-09 deletion request (kind 5, `a` tags for my addressable events) asks relays to drop what I published
  /// – honoured by many, not guaranteed – and key, words, group list and collaboration data go from this device.
  /// [alsoBills] also empties the bills on this device.
  Future<void> deleteAccount({bool alsoBills = false}) async {
    _markLeft();
    final me = identity;
    if (me == null) return;
    final refs = <String>{'$kindData:${me.pub}:${CollabService._accountD}'};
    for (final g in groups.values.toList()) {
      final s = g.session;
      s.doc(GroupSession.profile(me.pub))
        ..set('deleted', true)
        ..set('seen', null);
      s.touch(GroupSession.profile(me.pub));
      _announceLeaving(g);
      await s.flush();
      for (final id in s.docIds) {
        if (!id.startsWith('profile:')) refs.add('$kindData:${me.pub}:fs:${g.secret.tag}:$id');
      }
    }
    // an empty account list, then the deletion request for everything else
    try {
      final empty = NostrEvent.create(me.key, kind: kindData, tags: [['d', CollabService._accountD], ['t', 'fs:account']], content: nip44Encrypt(jsonEncode({'groups': []}), nip44ConversationKey(me.key.priv, me.pub)));
      final del = NostrEvent.create(me.key, kind: 5, tags: [for (final a in refs) ['a', a], ['k', '$kindData']], content: 'Fasan Split: Konto gelöscht');
      final relay = _relayFactory(_accountRelays);
      await relay.publish(empty);
      await relay.publish(del);
    } catch (_) {}
    for (final g in groups.values.toList()) {
      await leave(g);
    }
    for (final k in ['fasan.identity.priv', 'fasan.identity.name', 'fasan.identity.words', CollabService._kGroups]) {
      await vault.delete(k);
    }
    for (final k in prefs?.getKeys().where((k) => k.startsWith('collab.')).toList() ?? <String>[]) {
      await prefs?.remove(k);
    }
    _act = null;
    _readCache = null;
    joins.clear();
    identity = null;
    if (alsoBills) {
      store.trash(store.bills.where((b) => b.trashedAt == null).toList());
      store.deleteForever(store.bills.toList());
      store.me = '';
    }
    _notify();
  }

  /// People who are no longer in any of my groups although I know them (they left or were removed): pub → name. A member
  /// leaves a tombstone in the members list (`m/<pub>` empty); the name comes from the profile that stays. Not the deleted
  /// accounts (see [deletedFriends]) and not the people who are still in some group.
  Map<String, String> get leftFriends {
    final out = <String, String>{}, hidden = hiddenFriends, me = identity?.pub;
    final current = {for (final g in groups.values) ...g.session.memberKeys};
    for (final g in groups.values) {
      if (g.secret.direct) continue;
      for (final e in g.session.doc(GroupSession.members).entries) {
        if (e.value != null || !e.key.startsWith('m/')) continue;
        final pub = e.key.substring(2);
        if (pub == me || hidden.contains(pub) || current.contains(pub) || isDeleted(pub)) continue;
        final n = g.session.nameOf(pub);
        if (n.trim().isNotEmpty && n != '—') out.putIfAbsent(pub, () => n);
      }
    }
    return out;
  }

  /// People who deleted their account, from their profiles in my groups (they left the member lists): pub → name.
  Map<String, String> get deletedFriends {
    final out = <String, String>{}, hidden = hiddenFriends, me = identity?.pub;
    for (final g in groups.values) {
      for (final id in g.session.docIds) {
        if (!id.startsWith('profile:')) continue;
        final pub = id.substring('profile:'.length);
        final d = g.session.doc(id);
        if (pub == me || hidden.contains(pub) || d.get('deleted') != true) continue;
        out.putIfAbsent(pub, () => d.get('name') is String ? d.get('name') as String : g.session.nameOf(pub));
      }
    }
    return out;
  }

  /// [pub] deleted their account (their profile in a shared group says so).
  bool isDeleted(String pub) => groups.values.any((g) => g.session.doc(GroupSession.profile(pub)).get('deleted') == true);

  /// Friends removed from the list (e.g. after they deleted their account).
  Set<String> get hiddenFriends => {...?prefs?.getStringList(CollabService._kHidden)};

  /// Removes [pub] from my friends: hidden in the list, our direct chat is left.
  Future<void> forgetFriendPub(String pub) async {
    await prefs?.setStringList(CollabService._kHidden, {...hiddenFriends, pub}.toList());
    final d = directWithPub(pub);
    if (d != null) await leave(d);
    _notify();
  }

  /// Takes my entry out of the members list, so the others see that I am gone (Nutzer 11.11.: a deleted account stayed a
  /// member). The founder stays (the group secret names it); a member who came in over a link is an admin in the list and
  /// writes the tombstone as such, others as „self entry“ (group.dart _validSelfEntry). Nothing happens without an entry.
  void _announceLeaving(CollabGroup g) {
    final me = identity;
    if (me == null || me.pub == g.secret.adminPub) return;
    final s = g.session, md = s.doc(GroupSession.members);
    if (md.get('m/${me.pub}') == null) return;
    md.set('m/${me.pub}', null);
    s.touch(GroupSession.members);
  }

  /// Leaves a group on this phone (the others keep it). Bills stay, without the shared link. [announce]: the others see me
  /// gone from the members list (a deliberate leaving); false for the technical cases (key change, sign-out).
  Future<void> leave(CollabGroup g, {bool announce = false}) async {
    if (announce) {
      _announceLeaving(g);
      await g.session.flush();
    }
    await _subs.remove(g.secret.tag)?.cancel();
    await g.session.close();
    await g.invitations?.close();
    groups.remove(g.secret.tag);
    for (final k in prefs?.getKeys().where((k) => k.startsWith('${CollabService._kDocs}${g.secret.tag}.')).toList() ?? <String>[]) {
      await prefs?.remove(k);
    }
    await _persistGroups();
    _notify();
  }

  /// Signs out of this device (Nutzer 11.11.): the account stays as it is – for the groups nothing changes, nothing is
  /// written to the relays, no deletion mark. Key, words, group list and collaboration data leave this device; the 12 words
  /// (or a backup, or a second device) bring everything back. [alsoBills] also empties the bills here (shared computer).
  Future<void> signOut({bool alsoBills = false}) async {
    _markLeft();
    for (final g in groups.values.toList()) {
      await leave(g);
    }
    for (final k in ['fasan.identity.priv', 'fasan.identity.name', 'fasan.identity.words', CollabService._kGroups]) {
      await vault.delete(k);
    }
    for (final k in prefs?.getKeys().where((k) => k.startsWith('collab.')).toList() ?? <String>[]) {
      await prefs?.remove(k);
    }
    _accountWatch?.cancel();
    _accountWatch = null;
    _directWatch?.cancel();
    _directWatch = null;
    _act = null;
    _readCache = null;
    joins.clear();
    identity = null;
    if (alsoBills) {
      store.trash(store.bills.where((b) => b.trashedAt == null).toList());
      store.deleteForever(store.bills.toList());
    }
    store.me = '';
    _notify();
  }
}
