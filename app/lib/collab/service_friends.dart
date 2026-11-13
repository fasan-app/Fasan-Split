// SPDX-License-Identifier: MPL-2.0
// Fasan Split – CollabService, part: Friends: direct connections, joining, inviting from a bill. Split out of service.dart (13.11., Umbau U3, behaviour unchanged): the fields
// and constants stay in the class, these are its methods as an extension in the same library. MPL-2.0
part of 'service.dart';

extension CollabServiceFriends on CollabService {

  /// My direct connections (also those still waiting for the friend to open the link).
  List<CollabGroup> get directs => [for (final g in groups.values) if (g.secret.direct) g];

  /// The other person of a direct connection, or null while nobody opened the link.
  String? directPeer(CollabGroup g) {
    final me = identity?.pub;
    for (final k in g.session.memberKeys) {
      if (k != me) return k;
    }
    return null;
  }

  /// Name to show for a direct connection: the friend's name (the inviter's name is in the secret).
  String directName(CollabGroup g) {
    final p = directPeer(g);
    if (p == null) return '';
    // the members list may not be here yet: the inviter's name is in the secret
    final m = g.session.doc(GroupSession.members).get('m/$p');
    if (m is Map && m['name'] is String && (m['name'] as String).isNotEmpty) return m['name'] as String;
    return p == g.secret.adminPub ? g.secret.name : g.session.nameOf(p);
  }

  /// Friends = everyone I share a group with (Nutzer 04.11.: like contacts in a messenger), by member key.
  Map<String, String> get memberFriends {
    final me = identity?.pub;
    final out = <String, String>{};
    for (final g in groups.values) {
      final hidden = hiddenFriends;
      for (final k in g.session.memberKeys) {
        if (k == me || hidden.contains(k)) continue;
        final n = g.secret.direct ? directName(g) : g.session.nameOf(k);
        if (n.trim().isNotEmpty && n != '—') out.putIfAbsent(k, () => n);
      }
    }
    return out;
  }

  /// The direct connection with [pub], if there is one.
  CollabGroup? directWithPub(String pub) {
    for (final g in directs) {
      if (directPeer(g) == pub) return g;
    }
    return null;
  }

  /// Writing to a member without a second link (Nutzer 04.11.): a direct connection is made here and offered to the
  /// other person (its key NIP-44 encrypted to them, event `fs:direct`); their phone takes it when it comes from someone
  /// they share a group with.
  Future<CollabGroup> directWith(String pub, String name) async {
    final have = directWithPub(pub);
    if (have != null) return have;
    final me = await ensureIdentity();
    final secret = GroupSecret(key: randomBytes(32), adminPub: me.pub, name: me.name.isEmpty ? '—' : me.name, relays: defaultRelays, direct: true);
    final g = await _activate(secret, CollabService.directLocalName(secret));
    g.session.addMember(me.pub, me.name.isEmpty ? '—' : me.name);
    g.session.addMember(pub, name);
    await g.session.flush();
    final ev = NostrEvent.create(me.key,
        kind: kindData,
        tags: [['d', 'fs:direct:${secret.tag}'], ['t', 'fs:direct'], ['p', pub]],
        content: nip44Encrypt(jsonEncode(secret.toJson()), nip44ConversationKey(me.key.priv, pub)));
    await _relayFactory(_accountRelays).publish(ev);
    await _persistGroups();
    _notify();
    return g;
  }

  void _watchDirectOffers() {
    final me = identity;
    if (me == null || _directWatch != null) return;
    _directWatch = _relayFactory(_accountRelays).subscribe(Filter(kinds: const [kindData], tags: {'t': ['fs:direct'], 'p': [me.pub]})).listen(_onDirectOffer);
  }

 // offers from people whose membership has not arrived yet

  Future<void> _onDirectOffer(NostrEvent e) async {
      final me = identity;
      if (me == null || !e.valid || e.pubkey == me.pub) return;
      // only from people I share a group with (no strangers writing to me); maybe the members list comes later
      if (!groups.values.any((g) => g.session.memberKeys.contains(e.pubkey))) {
        if (_laterOffers.length < 50 && !_laterOffers.any((x) => x.id == e.id)) _laterOffers.add(e);
        return;
      }
      try {
        final s = GroupSecret.fromJson((jsonDecode(nip44Decrypt(e.content, nip44ConversationKey(me.key.priv, e.pubkey))) as Map).cast<String, dynamic>());
        if (!s.direct || s.adminPub != e.pubkey || groups.containsKey(s.tag) || directWithPub(e.pubkey) != null) return;
        await _activate(s, CollabService.directLocalName(s));
        await _persistGroups();
        _notify();
      } catch (_) {}
  }

  /// A new friend link: a direct connection with only me in it; the link lets the friend in at once (open link).
  Future<CollabGroup> createDirect({List<String>? relays}) async {
    final me = await ensureIdentity();
    final secret = GroupSecret(key: randomBytes(32), adminPub: me.pub, name: me.name.isEmpty ? '—' : me.name, relays: relays ?? defaultRelays, direct: true);
    final g = await _activate(secret, CollabService.directLocalName(secret));
    g.session.addMember(me.pub, me.name.isEmpty ? '—' : me.name);
    await _persistGroups();
    _notify();
    return g;
  }

  /// Makes an existing local group live (we become its admin).
  Future<CollabGroup> shareLocalGroup(String localName) async {
    final me = await ensureIdentity();
    final secret = GroupSecret(key: randomBytes(32), adminPub: me.pub, name: localName, relays: defaultRelays);
    final g = await _activate(secret, localName);
    g.session.addMember(me.pub, me.name.isEmpty ? '—' : me.name);
    await _persistGroups();
    _pushAll();
    _notify();
    return g;
  }

  Future<CollabGroup> _activate(GroupSecret secret, String local, {bool restoreDocs = false}) async {
    final me = await ensureIdentity();
    scheduleMicrotask(_watchDirectOffers);
    _activeSince[secret.tag] = DateTime.now();
    final relay = _relayFactory(secret.relays);
    final session = GroupSession(secret: secret, me: me.key, relay: relay);
    final g = CollabGroup(secret, local, session, null);
    session.acceptEntry = (docId, e) => _accept(g, docId, e);
    groups[secret.tag] = g;
    if (restoreDocs) {
      _restoreDocs(g);
      _adoptDocs(g);
      session.republishAll(); // relays that missed something get it now (04.11.)
    }
    // wired after the restore: what comes from the disk is the starting point, not a change
    session.onEntry = (id, o, n) => _onEntry(g, id, o, n);
    _subs[secret.tag] = session.changes.listen((id) => _onDocChanged(g, id));
    session.start();
    _ensureInvitations(g);
    final myName = identity?.name.trim() ?? '';
    if (myName.isNotEmpty && session.doc(GroupSession.profile(me.pub)).get('name') == null) session.setMyName(myName);
    _unpublishPay(g);
    // a new group key from an admin after someone was removed (rotateKey)
    g.rekeySub = relay
        .subscribe(Filter(kinds: const [kindData], tags: {'t': ['${secret.tag}:rekey'], 'p': [me.pub]}))
        .listen((e) => _onRekey(g, e));
    if (!_storeListening) {
      _storeListening = true;
      store.addListener(_onStoreChanged);
    }
    return g;
  }

  // ---- joining ----

  Invite? parseInvite(String text) => Invite.parse(text);

  /// Opens an invitation: asks the admin to let us in. Returns an error text or null.
  Future<String?> join(String text, String myName) async {
    final inv = Invite.parse(text);
    if (inv == null) return 'invalid';
    if (inv.expired) return 'expired';
    if (groups.containsKey(inv.tag)) return 'member';
    final me = await ensureIdentity();
    if (myName.trim().isNotEmpty && me.name != myName.trim()) await setName(myName);
    final p = PendingJoin(inv, me.name.isEmpty ? myName : me.name, DateTime.now());
    if (inv.groupKey != null) return _joinOpen(inv, p.name, me);
    joins.add(p);
    _saveJoins();
    final relay = _relayFactory(inv.relays);
    final flow = JoinFlow(invite: inv, me: me.key, relay: relay, name: p.name);
    final ok = await flow.sendRequest();
    if (!ok) {
      p.error = 'send';
      _notify();
    }
    _waitForWelcome(p, flow: flow);
    _notify();
    return ok ? null : 'send';
  }

  /// Open link (group.dart step 4b): in at once with the key from the link, no admin needed. The join request still
  /// goes out, so an admin adopts the member when its phone runs.
  Future<String?> _joinOpen(Invite inv, String name, Identity me) async {
    final secret = GroupSecret(key: inv.groupKey!, adminPub: inv.adminPub, name: inv.name, relays: inv.relays, direct: inv.direct);
    if (secret.tag != inv.tag) return 'invalid'; // damaged link
    final local = secret.direct ? CollabService.directLocalName(secret) : uniqueLocalName(secret.name);
    if (!secret.direct) store.addGroup(local);
    final g = await _activate(secret, local);
    g.session.joinWithTicket(inv, name);
    // saved at once, not 600 ms later: closing the browser or the app right after joining (iPhone: switching to the messenger)
    // must not lose the entry – it is sent when the app is opened again (_activate → republishAll)
    saveDocs();
    await _persistGroups();
    await g.session.flush();
    unawaited(JoinFlow(invite: inv, me: me.key, relay: _relayFactory(inv.relays), name: name).sendRequest());
    _notify();
    return null;
  }

  void _waitForWelcome(PendingJoin p, {JoinFlow? flow}) {
    final me = identity;
    () async {
      final id = me ?? await ensureIdentity();
      final f = flow ?? JoinFlow(invite: p.invite, me: id.key, relay: _relayFactory(p.invite.relays), name: p.name);
      try {
        final secret = await f.waitForWelcome(timeout: p.invite.expires.add(const Duration(days: 1)).difference(DateTime.now()));
        joins.remove(p);
        _saveJoins();
        final local = secret.direct ? CollabService.directLocalName(secret) : uniqueLocalName(secret.name);
        if (!secret.direct) store.addGroup(local);
        await _activate(secret, local);
        await _persistGroups();
      } catch (_) {
        p.error = 'timeout';
      }
      _notify();
    }();
  }

  void cancelJoin(PendingJoin p) {
    joins.remove(p);
    _saveJoins();
    _notify();
  }

  // ---- invite a friend to a group straight from a bill (Nutzer 05.11.) ----

  /// Sends [friend] (a member key from [memberFriends]) an invitation to [g]: an open link (they join at once, nobody has to
  /// confirm) in our direct chat. Null when this phone cannot invite to the group (only admins and people who came in over an
  /// open link can). [message] is the text before the link, in the language of the app.
  Future<FriendInvite?> inviteFriendToGroup(CollabGroup g, String friend, String name, {required String message}) async {
    final inv = g.invitations;
    if (inv == null || g.secret.direct || g.session.memberKeys.contains(friend)) return null;
    final invite = inv.create(valid: const Duration(days: 7), person: name);
    final d = await directWith(friend, name);
    final id = sendMessage(d, '$message\n${invite.link}');
    _notify();
    return FriendInvite(g, d, invite, id, friend, name);
  }

  /// Takes an invitation back: its link stops working, the message disappears for the friend, and if they already joined they are
  /// removed again (the group gets a new key, so they read nothing new).
  Future<void> undoFriendInvite(FriendInvite f) async {
    revokeInvite(f.group, f.invite);
    final id = f.messageId;
    if (id != null) deleteMessage(f.direct, id);
    if (f.group.session.memberKeys.contains(f.friend)) await removeMember(f.group, f.friend);
  }

  void pinMessage(CollabGroup g, String id, bool pin) {
    Notes.pinMessage(g.session.doc(GroupSession.chat), id, pin);
    g.session.touch(GroupSession.chat);
  }
}
