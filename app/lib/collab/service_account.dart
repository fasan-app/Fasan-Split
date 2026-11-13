// SPDX-License-Identifier: MPL-2.0
// Fasan Split – CollabService, part: My names, linking a second device, account across devices. Split out of service.dart (13.11., Umbau U3, behaviour unchanged): the fields
// and constants stay in the class, these are its methods as an extension in the same library. MPL-2.0
part of 'service.dart';

extension CollabServiceAccount on CollabService {

  void _rememberOwnName(String old) {
    final o = old.trim();
    if (o.isEmpty || o == '—' || (identity != null && o == identity!.pub.substring(0, 8))) return;
    final had = prefs?.getStringList(CollabService._kOldNames) ?? const <String>[];
    if (had.contains(o)) return;
    prefs?.setStringList(CollabService._kOldNames, [...had, o]);
    if (identity != null) unawaited(syncAccount());
  }

  /// Every name that means me (lower case): the account name, „Ich bin“ in the bills, earlier names and linked persons.
  Set<String> get ownNames {
    final me = identity;
    return {
      (me?.name ?? '').trim().toLowerCase(),
      store.me.trim().toLowerCase(),
      for (final n in prefs?.getStringList(CollabService._kOldNames) ?? const <String>[]) n.trim().toLowerCase(),
      if (me != null)
        for (final g in groups.values) ...g.session.personsOf(me.pub).map((n) => n.trim().toLowerCase()),
    }..remove('');
  }

  // ---- linking a second device (pairing.dart) ----

  /// New device: one-time offer to show as QR code, and the result once the old device answered (number of groups).
  (PairOffer, Future<int>) startPairing() {
    final eph = KeyPair.generate();
    final offer = PairOffer(eph.pub, defaultRelays);
    final done = () async {
      final a = await waitForAccount(_relayFactory(offer.relays), eph);
      return restoreIdentity(a.words, name: a.name);
    }();
    return (offer, done);
  }

  /// Old device: sends this account (12 words, name) to the device that shows [offer]. False without words (an account
  /// restored from an old backup without them) or without network.
  Future<bool> sendPairing(PairOffer offer) async {
    final me = await ensureIdentity();
    final words = me.mnemonic;
    if (words == null || words.isEmpty) return false;
    return sendAccount(_relayFactory(offer.relays), me.key, offer, words: words, name: me.name);
  }

  /// One account event from another device: groups missing here are joined.
  Future<void> _mergeAccountEvent(NostrEvent e) async {
    final me = identity;
    if (me == null || !e.valid || e.pubkey != me.pub || e.tag('d') != CollabService._accountD) return;
    try {
      final j = jsonDecode(nip44Decrypt(e.content, nip44ConversationKey(me.key.priv, me.pub))) as Map<String, dynamic>;
      var added = 0;
      for (final g in (j['groups'] as List? ?? const [])) {
        final m = (g as Map).cast<String, dynamic>();
        final s = GroupSecret.fromJson((m['secret'] as Map).cast<String, dynamic>());
        if (groups.containsKey(s.tag)) continue;
        final want = m['local'] as String? ?? s.name;
        final local = groupByLocalName(want) == null ? want : uniqueLocalName(s.name);
        if (!s.direct) store.addGroup(local);
        await _activate(s, local);
        added++;
      }
      if (added > 0) {
        await vault.write(CollabService._kGroups, jsonEncode([for (final g in groups.values) {'secret': g.secret.toJson(), 'local': g.localName}]));
        _notify();
      }
    } catch (_) {}
  }

  List<String> get _accountRelays => {...defaultRelays, for (final g in groups.values) ...g.secret.relays}.toList();

  /// Publishes the group list of this account (after create, join, key change, leave).
  Future<void> syncAccount() async {
    final me = identity;
    if (me == null || groups.isEmpty) return;
    final body = jsonEncode({
      'v': 1,
      'groups': [for (final g in groups.values) {'secret': g.secret.toJson(), 'local': g.localName}],
      // who I am on the bills (Nutzer 11.11.: „alles mit dem echten User verknüpft“): earlier names and the uids of my
      // persons travel with the account to every device (encrypted to myself like the rest)
      'names': prefs?.getStringList(CollabService._kOldNames) ?? const <String>[],
      'uids': ownUids.toList(),
    });
    final ev = NostrEvent.create(me.key, kind: kindData, tags: [['d', CollabService._accountD], ['t', 'fs:account']], content: nip44Encrypt(body, nip44ConversationKey(me.key.priv, me.pub)));
    try {
      await _relayFactory(_accountRelays).publish(ev);
    } catch (_) {
      // offline: next change publishes again
    }
  }

  /// Reads the account list from the relays and joins every group that is not on this device yet. Waits up to
  /// [wait] for the relays. Returns the number of groups added.
  Future<int> recoverGroups({Duration wait = const Duration(seconds: 6)}) async {
    final me = await ensureIdentity();
    final relay = _relayFactory(defaultRelays);
    final seen = <String, Map<String, dynamic>>{};
    final oldNames = <String>{}, uids = <String>{};
    final sub = relay.subscribe(Filter(kinds: const [kindData], authors: [me.pub], tags: {'t': ['fs:account']})).listen((e) {
      if (!e.valid || e.pubkey != me.pub || e.tag('d') != CollabService._accountD) return;
      try {
        final j = jsonDecode(nip44Decrypt(e.content, nip44ConversationKey(me.key.priv, me.pub))) as Map<String, dynamic>;
        oldNames.addAll([for (final n in (j['names'] as List? ?? const [])) '$n']);
        uids.addAll([for (final u in (j['uids'] as List? ?? const [])) '$u']);
        for (final g in (j['groups'] as List? ?? const [])) {
          final m = (g as Map).cast<String, dynamic>();
          final s = GroupSecret.fromJson((m['secret'] as Map).cast<String, dynamic>());
          seen[s.tag] = m;
        }
      } catch (_) {}
    });
    await Future<void>.delayed(wait);
    await sub.cancel();
    oldNames.forEach(_rememberOwnName);
    if (uids.isNotEmpty) prefs?.setStringList(CollabService._kUids, {...ownUids, ...uids}.toList());
    var added = 0;
    for (final m in seen.values) {
      final s = GroupSecret.fromJson((m['secret'] as Map).cast<String, dynamic>());
      if (groups.containsKey(s.tag)) continue;
      final local = groupByLocalName(m['local'] as String? ?? s.name) == null ? (m['local'] as String? ?? s.name) : uniqueLocalName(s.name);
      if (!s.direct) store.addGroup(local);
      await _activate(s, local);
      added++;
    }
    if (added > 0) {
      await _persistGroups();
      _notify();
    }
    return added;
  }

  String uniqueLocalName(String wanted) {
    var n = wanted.trim().isEmpty ? '—' : wanted.trim();
    var i = 2;
    final base = n;
    while (store.allGroups.contains(n) && groupByLocalName(n) == null) {
      n = '$base ($i)';
      i++;
    }
    return n;
  }

  /// Creates a shared group: we are the admin. The local group of the same name is created if needed.
  Future<CollabGroup> createGroup(String name, {List<String>? relays}) async {
    final me = await ensureIdentity();
    final secret = GroupSecret(key: randomBytes(32), adminPub: me.pub, name: name.trim(), relays: relays ?? defaultRelays);
    final local = uniqueLocalName(name);
    store.addGroup(local);
    final g = await _activate(secret, local);
    g.session.addMember(me.pub, me.name.isEmpty ? '—' : me.name);
    await _persistGroups();
    _notify();
    return g;
  }

  /// Everyone of a group: the names from its bills and added by hand, and every member who joined (as the person they
  /// are linked to, or their own name). Nutzer 04.11.: joined people were missing from the group.
  List<String> peopleOf(String localName) {
    final people = [...store.groupMembers(localName)];
    final live = groupByLocalName(localName);
    if (live != null) {
      final have = {for (final p in people) p.toLowerCase()};
      for (final k in live.session.memberKeys) {
        final p = live.session.personOf(k) ?? live.session.nameOf(k);
        if (p.trim().isNotEmpty && p != '—' && have.add(p.toLowerCase())) people.add(p);
      }
    }
    return people;
  }
}
