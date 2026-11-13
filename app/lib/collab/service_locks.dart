// SPDX-License-Identifier: MPL-2.0
// Fasan Split – CollabService, part: Padlocks on bills and items. Split out of service.dart (13.11., Umbau U3, behaviour unchanged): the fields
// and constants stay in the class, these are its methods as an extension in the same library. MPL-2.0
part of 'service.dart';

extension CollabServiceLocks on CollabService {

  // ---- padlocks on bills and items (lock_rules.dart; Nutzer 07.11.) ----

  /// A padlock needs a shared group: only there are there others to lock against.
  bool canLock(Bill b) => identity != null && b.group != null && groupByLocalName(b.group!) != null;

  /// True if [lockBy] (a public key) keeps me from changing: locked by somebody else, and I am not the group's admin.
  bool lockedAgainstMe(Bill b, String? lockBy) {
    if (lockBy == null || lockBy.isEmpty) return false;
    final me = identity?.pub;
    if (me == null || me == lockBy) return false;
    final g = b.group == null ? null : groupByLocalName(b.group!);
    return g == null || g.secret.adminPub != me;
  }

  /// Display name of whoever holds the lock.
  String lockerName(Bill b, String lockBy) {
    final g = b.group == null ? null : groupByLocalName(b.group!);
    return g?.session.nameOf(lockBy) ?? '';
  }

  /// Locks or unlocks the whole bill for me; refused (false) when somebody else holds the lock.
  bool toggleBillLock(Bill b) {
    final me = identity?.pub;
    if (me == null || !canLock(b) || lockedAgainstMe(b, b.lockBy)) return false;
    b.lockBy = b.lockBy == null ? me : null;
    b.updated = DateTime.now();
    store.upsert(b);
    return true;
  }

  /// Locks or unlocks one item.
  bool toggleItemLock(Bill b, BillItem it) {
    final me = identity?.pub;
    if (me == null || !canLock(b) || lockedAgainstMe(b, it.lockBy) || lockedAgainstMe(b, b.lockBy)) return false;
    it.lockBy = it.lockBy == null ? me : null;
    b.updated = DateTime.now();
    store.upsert(b);
    return true;
  }

  /// Account and shared groups for the backup file (state/backup.dart): identity from the vault, group keys, the stored
  /// documents. The result is secret like the 12 words.
  Future<Map<String, Object?>> exportSecrets() async {
    saveDocs();
    final v = <String, String>{};
    for (final k in [...Identity.vaultKeys, CollabService._kGroups]) {
      final x = await vault.read(k);
      if (x != null) v[k] = x;
    }
    return {
      'vault': v,
      // documents are strings, the id lists string lists (saveDocs): keep the type (04.11.: getString on a list failed)
      'prefs': {for (final k in prefs?.getKeys() ?? const <String>{}) if (k.startsWith(CollabService._kDocs) || k == CollabService._kJoins) k: prefs!.get(k)},
    };
  }

  /// Puts account and groups from a backup back, only if this device has no account and no groups yet (never mixes two
  /// accounts). Takes effect after a restart of the app. Returns whether something was restored.
  Future<bool> importSecrets(Map<String, Object?> m) async {
    // never mix two accounts that have groups; a fresh account without groups (e.g. made by opening „Konto“ before the
    // restore, 04.11.: the group was gone after reinstall + restore) is replaced
    if (groups.isNotEmpty) return false;
    final v = (m['vault'] as Map? ?? const {}).cast<String, String>();
    if (v.isEmpty) return false;
    for (final e in v.entries) {
      await vault.write(e.key, e.value);
    }
    for (final e in (m['prefs'] as Map? ?? const {}).cast<String, Object?>().entries) {
      final v = e.value;
      if (v is String) await prefs?.setString(e.key, v);
      if (v is List) await prefs?.setStringList(e.key, [for (final x in v) '$x']);
    }
    // at once, no restart: load the account and its groups again
    identity = null;
    await ensureIdentity();
    await init();
    return true;
  }

  /// Loads identity and groups and starts the sessions (connects only if there is a group).
  Future<void> init() async {
    store.addListener(_ledgerSoon);
    _ledgerSoon();
    final raw = await vault.read(CollabService._kGroups);
    if (raw != null) {
      try {
        for (final j in jsonDecode(raw) as List) {
          final m = (j as Map).cast<String, dynamic>();
          await _activate(GroupSecret.fromJson((m['secret'] as Map).cast<String, dynamic>()), m['local'] as String, restoreDocs: true);
        }
      } catch (_) {
        // damaged group list: start without, never crash
      }
    }
    // other devices with the same 12 words: their new groups arrive while the app runs (only with groups = after consent)
    if (groups.isNotEmpty && _accountWatch == null) {
      final me = await ensureIdentity();
      _accountWatch = _relayFactory(_accountRelays)
          .subscribe(Filter(kinds: const [kindData], authors: [me.pub], tags: {'t': ['fs:account']}))
          .listen((e) => unawaited(_mergeAccountEvent(e)));
      unawaited(syncAccount()); // groups from before 0.1.49 reach the account list without waiting for a change
    }
    if (groups.isNotEmpty) _watchDirectOffers();
    try {
      for (final j in jsonDecode(prefs?.getString(CollabService._kJoins) ?? '[]') as List) {
        final m = (j as Map).cast<String, dynamic>();
        final inv = Invite.parse(m['code'] as String);
        if (inv != null && !inv.expired) _waitForWelcome(PendingJoin(inv, m['name'] as String, DateTime.tryParse(m['since'] as String? ?? '') ?? DateTime.now()));
      }
    } catch (_) {}
    if (groups.isNotEmpty) {
      await ensureIdentity();
      await _syncName();
    }
    _beat(); // online now (when the app is in front)
    _notify();
  }

  /// True for a moment after „Abmelden“ / „Konto löschen“: screens that save a typed name when they close must not
  /// create a new account then.
  bool get justLeft => _leftAt != null && DateTime.now().difference(_leftAt!) < const Duration(seconds: 3);

  void _markLeft() => _leftAt = DateTime.now();

  Future<Identity> ensureIdentity({String name = ''}) async {
    identity ??= await Identity.loadOrCreate(vault, defaultName: name);
    return identity!;
  }

  /// One name everywhere (Nutzer 04.11.): the account name is also „Ich bin“ in the bills and my name in every group
  /// (my profile document there). Before 04.11. the two were separate and the account name often stayed empty („—“).
  Future<void> setName(String name) async {
    final n = name.trim();
    final id = await ensureIdentity();
    if (n.isEmpty) return;
    final old = id.name;
    id.name = n;
    await id.save(vault);
    _rememberOwnName(old);
    if (!_adopting) {
      _adoptPending = false; // typed by the person: no group name replaces it any more
      _adoptedGuess = null;
    }
    if (store.me.trim().isEmpty || store.me.trim() == old.trim()) store.me = n;
    // adopting a name from the groups must never write it back: an older name would overwrite a newer rename (LWW)
    if (!_adopting) {
      for (final g in groups.values) {
        g.session.setMyName(n);
      }
    }
    _notify();
  }

  /// Start: an account without a name takes „Ich bin“; groups get my name if they do not have it yet.
  Future<void> _syncName() async {
    final id = identity;
    if (id == null) return;
    if (id.name.trim().isEmpty && store.me.trim().isNotEmpty) {
      id.name = store.me.trim();
      await id.save(vault);
    } else if (store.me.trim().isEmpty && id.name.trim().isNotEmpty) {
      store.me = id.name.trim();
    }
    publishOwnUids();
    if (id.name.trim().isEmpty) return;
    for (final g in groups.values) {
      if (g.session.doc(GroupSession.profile(id.pub)).get('name') != id.name.trim()) g.session.setMyName(id.name.trim());
    }
  }

  /// Restores the account from the 12 words and fetches its groups from the relays (account list, [syncAccount]).
  /// Returns how many groups came back. Groups of another key on this phone stay as they are.
  Future<int> restoreIdentity(String words, {String? name}) async {
    identity = await Identity.restore(vault, words, name: name ?? identity?.name ?? '');
    _notify();
    final n = await recoverGroups();
    _adoptPending = (name ?? '').trim().isEmpty; // the profiles may arrive a moment later: adopt then
    await _adoptNameFromGroups(typed: name ?? '');
    return n;
  }

  Future<void> _adoptNameFromGroups({String typed = ''}) async {
    if (_adoptBusy) {
      _adoptAgain = true; // one run at a time; a change that arrives meanwhile is looked at afterwards
      return;
    }
    _adoptBusy = true;
    try {
      do {
        _adoptAgain = false;
        await _adoptNameOnce(typed: typed);
      } while (_adoptAgain);
    } finally {
      _adoptBusy = false;
    }
  }

  Future<void> _adoptNameOnce({String typed = ''}) async {
    final id = identity;
    if (id == null) return;
    String? known, fromProfile;
    for (final g in groups.values) {
      final d = g.session.doc(GroupSession.profile(id.pub));
      if (d.get('deleted') == true) {
        d.set('deleted', null);
        g.session.touch(GroupSession.profile(id.pub));
      }
      if (d.get('name') case final String pn when pn.trim().isNotEmpty && fromProfile == null) fromProfile = pn.trim();
      final n = g.session.knownName(id.pub);
      if (known == null && n != null && n.trim().isNotEmpty && n != '—') known = n.trim();
    }
    // my own profile is the newest word on my name (a rename writes it first); the members list can lag behind, and
    // older versions of the profile can arrive before newer ones – so adopting goes on until I type a name myself
    known = fromProfile ?? known;
    if (known == null) return;
    // A fresh restore without a typed name carries the placeholder (first 8 characters of the key), not a real name.
    final placeholder = id.name.trim().isEmpty || id.name.trim() == id.pub.substring(0, 8) || (_adoptPending && id.name == _adoptedGuess);
    if (typed.trim().isEmpty && placeholder) {
      if (id.name != known) {
        _adopting = true;
        try {
          await setName(known);
        } finally {
          _adopting = false;
        }
      }
      _adoptedGuess = known;
    } else if (typed.trim().isNotEmpty && typed.trim() != known) {
      _rememberOwnName(known);
      _adoptPending = false;
    }
  }
}
