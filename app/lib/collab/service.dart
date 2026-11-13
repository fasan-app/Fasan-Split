// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the collaboration service: identity, groups, invitations, and the bridge to the local bills. MPL-2.0
//
// Local bills in a group that is shared (live) are written into that group's documents after every change; changes from the
// others are read back into the same bills. Nothing is sent for groups that are not shared. Public relays are contacted only by
// this service, only for groups the user created or joined, never by tests (they use MemoryRelay).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fasan_core/bill.dart';
import 'package:fasan_core/pay.dart';
import '../state/images.dart';
import '../state/snippets.dart';
import '../state/store.dart';
import 'activity.dart';
import 'bill_changes.dart';
import 'bill_sync.dart';
import 'ledger.dart';
import 'crypto.dart';
import 'group.dart';
import 'lock_rules.dart';
import 'lww.dart';
import 'keys.dart';
import 'nostr.dart';
import 'notes.dart';
import 'pairing.dart';
import 'photo_sync.dart';

export 'nostr.dart' show defaultRelays; // defined next to the relays (the invitation format needs it too)

/// An invitation sent to a friend from a bill: kept for a moment so it can be taken back ([CollabService.undoFriendInvite]).
class FriendInvite {
  FriendInvite(this.group, this.direct, this.invite, this.messageId, this.friend, this.name);

  final CollabGroup group, direct;
  final Invite invite;
  final String? messageId;
  final String friend, name;
}

class CollabGroup {
  CollabGroup(this.secret, this.localName, this.session, this.invitations);

  final GroupSecret secret;
  String localName; // name of the group in the bill list
  final GroupSession session;
  Invitations? invitations; // admins only; made when someone becomes admin (CollabService._ensureInvitations)
  bool get isAdmin => session.isAdmin;
  StreamSubscription<NostrEvent>? rekeySub;
}

/// A change by someone else that concerns me and waits for my confirmation (trust settings).
/// How far another member may enter things that concern me (stand-in levels, Nutzer 09.11.).
enum TrustLevel { full, confirm, block }

class HeldChange {
  HeldChange(this.group, this.docId, this.entry);
  final CollabGroup group;
  final String docId;
  final Entry entry;
}

/// An invitation we opened and wait for the admin's answer.
class PendingJoin {
  PendingJoin(this.invite, this.name, this.since);
  final Invite invite;
  final String name;
  final DateTime since;
  String? error;
}

class CollabService extends ChangeNotifier {
  CollabService({required this.store, required this.vault, this.prefs, Relay Function(List<String> urls)? relayFactory})
      : _relayFactory = relayFactory ?? ((urls) => RelayPool([for (final u in urls) WsRelay(u)]));

  final BillStore store;
  final Vault vault;
  final SharedPreferences? prefs;
  final Relay Function(List<String> urls) _relayFactory;

  Identity? identity;
  final Map<String, CollabGroup> groups = {}; // by tag
  final List<PendingJoin> joins = [];
  bool _storeListening = false;
  final Map<String, StreamSubscription<String>> _subs = {};
  Timer? _saveTimer;

  static const _kGroups = 'fasan.groups', _kDocs = 'collab.doc.', _kJoins = 'collab.joins';

  bool get hasGroups => groups.isNotEmpty;

  CollabGroup? groupByLocalName(String name) {
    for (final g in groups.values) {
      if (g.localName == name) return g;
    }
    return null;
  }

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
    for (final k in [...Identity.vaultKeys, _kGroups]) {
      final x = await vault.read(k);
      if (x != null) v[k] = x;
    }
    return {
      'vault': v,
      // documents are strings, the id lists string lists (saveDocs): keep the type (04.11.: getString on a list failed)
      'prefs': {for (final k in prefs?.getKeys() ?? const <String>{}) if (k.startsWith(_kDocs) || k == _kJoins) k: prefs!.get(k)},
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
    final raw = await vault.read(_kGroups);
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
      for (final j in jsonDecode(prefs?.getString(_kJoins) ?? '[]') as List) {
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
    notifyListeners();
  }

  /// True for a moment after „Abmelden“ / „Konto löschen“: screens that save a typed name when they close must not
  /// create a new account then.
  bool get justLeft => _leftAt != null && DateTime.now().difference(_leftAt!) < const Duration(seconds: 3);
  DateTime? _leftAt;

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
    notifyListeners();
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
    notifyListeners();
    final n = await recoverGroups();
    _adoptPending = (name ?? '').trim().isEmpty; // the profiles may arrive a moment later: adopt then
    await _adoptNameFromGroups(typed: name ?? '');
    return n;
  }

  /// After a sign-in with the words (Nutzer 11.11.: the browser had no name afterwards): the name the groups know me by comes
  /// back as my name, unless the person typed another one – then the group's name is remembered as an old name of mine (the
  /// bills keep using it, see [ownNames]). A „gelöscht“ mark on my profile from an earlier deletion is taken away.
  bool _adoptPending = false;
  bool _adopting = false;
  String? _adoptedGuess; // the name taken from the groups; while it is still my name, a newer one from my profile replaces it

  bool _adoptBusy = false, _adoptAgain = false;

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

  // ---- my names (Nutzer 11.11.: „Chris“ stayed behind as a friend after renaming to „Chris2“) ----
  //
  // The bills know me by a name (a person on the bill). Renaming the account must not turn that person into a stranger:
  // the names I used before are kept (this phone only) and, with the persons an admin linked to my key in the groups, they
  // all count as me.

  static const _kOldNames = 'collab.ownNames';

  void _rememberOwnName(String old) {
    final o = old.trim();
    if (o.isEmpty || o == '—' || (identity != null && o == identity!.pub.substring(0, 8))) return;
    final had = prefs?.getStringList(_kOldNames) ?? const <String>[];
    if (had.contains(o)) return;
    prefs?.setStringList(_kOldNames, [...had, o]);
    if (identity != null) unawaited(syncAccount());
  }

  /// Every name that means me (lower case): the account name, „Ich bin“ in the bills, earlier names and linked persons.
  Set<String> get ownNames {
    final me = identity;
    return {
      (me?.name ?? '').trim().toLowerCase(),
      store.me.trim().toLowerCase(),
      for (final n in prefs?.getStringList(_kOldNames) ?? const <String>[]) n.trim().toLowerCase(),
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

  // ---- account across devices (Nutzer 04.11.: reinstall, several devices; no server and no login beyond the 12 words) ----
  //
  // The list of my groups (group key, local name) is published as one addressable event (kind 30078, d „fs:account:v1“),
  // encrypted with NIP-44 to my own key: only the holder of the 12 words can read it. Every device with the same words
  // publishes and reads it; lists are merged (union), so a group joined on one device appears on the other.

  static const _accountD = 'fs:account:v1';
  StreamSubscription<NostrEvent>? _accountWatch;

  /// One account event from another device: groups missing here are joined.
  Future<void> _mergeAccountEvent(NostrEvent e) async {
    final me = identity;
    if (me == null || !e.valid || e.pubkey != me.pub || e.tag('d') != _accountD) return;
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
        await vault.write(_kGroups, jsonEncode([for (final g in groups.values) {'secret': g.secret.toJson(), 'local': g.localName}]));
        notifyListeners();
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
      'names': prefs?.getStringList(_kOldNames) ?? const <String>[],
      'uids': ownUids.toList(),
    });
    final ev = NostrEvent.create(me.key, kind: kindData, tags: [['d', _accountD], ['t', 'fs:account']], content: nip44Encrypt(body, nip44ConversationKey(me.key.priv, me.pub)));
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
      if (!e.valid || e.pubkey != me.pub || e.tag('d') != _accountD) return;
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
    if (uids.isNotEmpty) prefs?.setStringList(_kUids, {...ownUids, ...uids}.toList());
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
      notifyListeners();
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
    notifyListeners();
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

  // ---- friends: direct connections (Nutzer 04.11.: invite friends without a group, chat, try the app) ----

  /// Internal local name of a direct connection; never shown (the UI shows the other person's name).
  static String directLocalName(GroupSecret s) => '@friend:${s.tag}';

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
    final g = await _activate(secret, directLocalName(secret));
    g.session.addMember(me.pub, me.name.isEmpty ? '—' : me.name);
    g.session.addMember(pub, name);
    await g.session.flush();
    final ev = NostrEvent.create(me.key,
        kind: kindData,
        tags: [['d', 'fs:direct:${secret.tag}'], ['t', 'fs:direct'], ['p', pub]],
        content: nip44Encrypt(jsonEncode(secret.toJson()), nip44ConversationKey(me.key.priv, pub)));
    await _relayFactory(_accountRelays).publish(ev);
    await _persistGroups();
    notifyListeners();
    return g;
  }

  StreamSubscription<NostrEvent>? _directWatch;

  void _watchDirectOffers() {
    final me = identity;
    if (me == null || _directWatch != null) return;
    _directWatch = _relayFactory(_accountRelays).subscribe(Filter(kinds: const [kindData], tags: {'t': ['fs:direct'], 'p': [me.pub]})).listen(_onDirectOffer);
  }

  final List<NostrEvent> _laterOffers = []; // offers from people whose membership has not arrived yet

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
        await _activate(s, directLocalName(s));
        await _persistGroups();
        notifyListeners();
      } catch (_) {}
  }

  /// A new friend link: a direct connection with only me in it; the link lets the friend in at once (open link).
  Future<CollabGroup> createDirect({List<String>? relays}) async {
    final me = await ensureIdentity();
    final secret = GroupSecret(key: randomBytes(32), adminPub: me.pub, name: me.name.isEmpty ? '—' : me.name, relays: relays ?? defaultRelays, direct: true);
    final g = await _activate(secret, directLocalName(secret));
    g.session.addMember(me.pub, me.name.isEmpty ? '—' : me.name);
    await _persistGroups();
    notifyListeners();
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
    notifyListeners();
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
    final pay = myPay;
    if (!pay.isEmpty && session.doc(GroupSession.profile(me.pub)).get('pay') == null) _publishPay(g, pay);
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
      notifyListeners();
    }
    _waitForWelcome(p, flow: flow);
    notifyListeners();
    return ok ? null : 'send';
  }

  /// Open link (group.dart step 4b): in at once with the key from the link, no admin needed. The join request still
  /// goes out, so an admin adopts the member when its phone runs.
  Future<String?> _joinOpen(Invite inv, String name, Identity me) async {
    final secret = GroupSecret(key: inv.groupKey!, adminPub: inv.adminPub, name: inv.name, relays: inv.relays, direct: inv.direct);
    if (secret.tag != inv.tag) return 'invalid'; // damaged link
    final local = secret.direct ? directLocalName(secret) : uniqueLocalName(secret.name);
    if (!secret.direct) store.addGroup(local);
    final g = await _activate(secret, local);
    g.session.joinWithTicket(inv, name);
    // saved at once, not 600 ms later: closing the browser or the app right after joining (iPhone: switching to the messenger)
    // must not lose the entry – it is sent when the app is opened again (_activate → republishAll)
    saveDocs();
    await _persistGroups();
    await g.session.flush();
    unawaited(JoinFlow(invite: inv, me: me.key, relay: _relayFactory(inv.relays), name: name).sendRequest());
    notifyListeners();
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
        final local = secret.direct ? directLocalName(secret) : uniqueLocalName(secret.name);
        if (!secret.direct) store.addGroup(local);
        await _activate(secret, local);
        await _persistGroups();
      } catch (_) {
        p.error = 'timeout';
      }
      notifyListeners();
    }();
  }

  void cancelJoin(PendingJoin p) {
    joins.remove(p);
    _saveJoins();
    notifyListeners();
  }

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
    notifyListeners();
  }

  /// Withdraws one link: nobody new gets in with it (its ticket is deleted). Whoever already joined stays. The group key
  /// stays too – for „nobody who ever had a link can read on“ there is [revokeInvites].
  void revokeInvite(CollabGroup g, Invite i) {
    if (i.groupKey != null && g.session.isAdmin) g.session.setTicket(i, open: false);
    g.invitations?.revoke(i);
    notifyListeners();
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
    notifyListeners();
    return ng;
  }

  void decline(CollabGroup g, JoinRequest r) {
    g.invitations?.decline(r.pub);
    notifyListeners();
  }

  /// Admin: links a member to a person of the group's bills, or unlinks (person null).
  void linkPerson(CollabGroup g, String pub, String? person) {
    g.session.linkPerson(pub, person);
    notifyListeners();
  }

  void unlinkPerson(CollabGroup g, String pub, String person) {
    g.session.unlinkPerson(pub, person);
    notifyListeners();
  }

  /// Removes a member and gives everyone else a new group key, so the removed one cannot read anything new (04.11.).
  Future<CollabGroup> removeMember(CollabGroup g, String pub) async {
    g.session.removeMember(pub);
    await g.session.flush();
    final ng = await rotateKey(g);
    notifyListeners();
    return ng;
  }

  /// Admin: makes a member admin too (or takes it back). Then the group keeps an admin when the founder leaves.
  void setAdmin(CollabGroup g, String pub, bool admin) {
    g.session.setAdmin(pub, admin);
    notifyListeners();
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
    notifyListeners();
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
      notifyListeners();
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

  // ---- trust (Nutzer 04.11.: block changes of others that concern me; default: trust everyone) ----

  static const _kTrust = 'collab.trust';

  Map<String, Object?> get _trust => (jsonDecode(prefs?.getString(_kTrust) ?? '{}') as Map).cast<String, Object?>();

  /// Changes by anyone else that touch my shares, my person or the payer wait for me.
  bool get confirmAll => _trust['all'] == true;
  set confirmAll(bool v) {
    prefs?.setString(_kTrust, jsonEncode({..._trust, 'all': v}));
    notifyListeners();
  }

  /// Members whose changes about me wait for me.
  Set<String> get distrusted => {...?(_trust['people'] as List?)?.cast<String>()};
  void setTrusted(String pub, bool trusted) {
    final p = distrusted;
    trusted ? p.remove(pub) : p.add(pub);
    prefs?.setString(_kTrust, jsonEncode({..._trust, 'people': p.toList()}));
    notifyListeners();
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
    prefs?.setString(_kTrust, jsonEncode({..._trust, 'people': d.toList(), 'block': b.toList()}));
    notifyListeners();
  }

  /// Changes held back for my confirmation.
  final List<HeldChange> held = [];

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
          notifyListeners();
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
    notifyListeners();
  }

  // ---- how others can pay me back (model/pay.dart; Nutzer 04.11.) ----

  static const _kPay = 'collab.pay';

  /// My payment details, on this device; shared only in my groups' profiles (encrypted, members only).
  PayInfo get myPay => PayInfo.fromJson((jsonDecode(prefs?.getString(_kPay) ?? '{}') as Map).cast<String, Object?>());
  set myPay(PayInfo p) {
    prefs?.setString(_kPay, jsonEncode(p.toJson()));
    for (final g in groups.values) {
      _publishPay(g, p);
    }
    notifyListeners();
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
    final refs = <String>{'$kindData:${me.pub}:$_accountD'};
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
      final empty = NostrEvent.create(me.key, kind: kindData, tags: [['d', _accountD], ['t', 'fs:account']], content: nip44Encrypt(jsonEncode({'groups': []}), nip44ConversationKey(me.key.priv, me.pub)));
      final del = NostrEvent.create(me.key, kind: 5, tags: [for (final a in refs) ['a', a], ['k', '$kindData']], content: 'Fasan Split: Konto gelöscht');
      final relay = _relayFactory(_accountRelays);
      await relay.publish(empty);
      await relay.publish(del);
    } catch (_) {}
    for (final g in groups.values.toList()) {
      await leave(g);
    }
    for (final k in ['fasan.identity.priv', 'fasan.identity.name', 'fasan.identity.words', _kGroups]) {
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
    notifyListeners();
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

  static const _kHidden = 'collab.hiddenFriends';

  /// Friends removed from the list (e.g. after they deleted their account).
  Set<String> get hiddenFriends => {...?prefs?.getStringList(_kHidden)};

  /// Removes [pub] from my friends: hidden in the list, our direct chat is left.
  Future<void> forgetFriendPub(String pub) async {
    await prefs?.setStringList(_kHidden, {...hiddenFriends, pub}.toList());
    final d = directWithPub(pub);
    if (d != null) await leave(d);
    notifyListeners();
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
    for (final k in prefs?.getKeys().where((k) => k.startsWith('$_kDocs${g.secret.tag}.')).toList() ?? <String>[]) {
      await prefs?.remove(k);
    }
    await _persistGroups();
    notifyListeners();
  }

  /// Signs out of this device (Nutzer 11.11.): the account stays as it is – for the groups nothing changes, nothing is
  /// written to the relays, no deletion mark. Key, words, group list and collaboration data leave this device; the 12 words
  /// (or a backup, or a second device) bring everything back. [alsoBills] also empties the bills here (shared computer).
  Future<void> signOut({bool alsoBills = false}) async {
    _markLeft();
    for (final g in groups.values.toList()) {
      await leave(g);
    }
    for (final k in ['fasan.identity.priv', 'fasan.identity.name', 'fasan.identity.words', _kGroups]) {
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
    notifyListeners();
  }

  // ---- chat and notes ----

  List<ChatMessage> messages(CollabGroup g) => Notes.messages(g.session.doc(GroupSession.chat));

  /// Sends a chat message; returns its id, or null when nothing was sent.
  String? sendMessage(CollabGroup g, String text, {String? bill, List<int> items = const [], String? reply, List<String> mentions = const []}) {
    final me = identity;
    final t = text.trim();
    if (me == null || t.isEmpty && bill == null) return null;
    // a mention counts while its @name is still in the text, and only for members of the group
    final ms = [for (final k in mentions.toSet()) if (k != me.pub && g.session.memberKeys.contains(k) && t.contains('@${g.session.nameOf(k)}')) k];
    final id = Notes.send(g.session.doc(GroupSession.chat), me.pub, t, bill: bill, items: items, reply: reply, mentions: ms);
    g.session.touch(GroupSession.chat);
    return id;
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
    notifyListeners();
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

  // ---- mute per group (Nutzer 04.11.: stumm): no notifications from this chat, except when someone mentions me; unread numbers stay ----

  static const _kMuted = 'collab.muted';
  Set<String>? _mutedCache;
  Set<String> get _muted => _mutedCache ??= {for (final t in ((jsonDecode(prefs?.getString(_kMuted) ?? '[]') as List))) '$t'};

  bool isMuted(CollabGroup g) => _muted.contains(g.secret.tag);

  void setMuted(CollabGroup g, bool muted) {
    if (muted) {
      _muted.add(g.secret.tag);
    } else {
      _muted.remove(g.secret.tag);
    }
    prefs?.setString(_kMuted, jsonEncode(_muted.toList()));
    notifyListeners();
  }

  /// Own message: change its text (Nutzer 04.11.: edit and delete in the chat).
  void editMessage(CollabGroup g, String id, String text) {
    final me = identity;
    if (me != null && Notes.editMessage(g.session.doc(GroupSession.chat), id, me.pub, text)) g.session.touch(GroupSession.chat);
  }

  /// Own message: delete for everyone (a marker stays).
  void deleteMessage(CollabGroup g, String id) {
    final me = identity;
    if (me != null && Notes.deleteMessage(g.session.doc(GroupSession.chat), id, me.pub)) g.session.touch(GroupSession.chat);
  }

  /// React with an emoji; the same emoji again takes the reaction back.
  void reactToMessage(CollabGroup g, String id, String emoji) {
    final me = identity;
    if (me == null) return;
    Notes.reactMessage(g.session.doc(GroupSession.chat), id, me.pub, emoji);
    g.session.touch(GroupSession.chat);
  }

  // ---- unread (Nutzer 04.11.: last message in the friends list, unread made clear, numbers on the tabs) ----

  static const _kRead = 'collab.read';
  Map<String, int>? _readCache;
  Map<String, int> get _read => _readCache ??= {
        for (final e in ((jsonDecode(prefs?.getString(_kRead) ?? '{}') as Map).entries)) '${e.key}': (e.value as num).toInt(),
      };

  /// Last message of a chat, or null.
  ChatMessage? lastMessage(CollabGroup g) => messages(g).lastOrNull;

  /// Messages of others since I last opened this chat. Before the first opening only the last day counts (joining an
  /// old group does not show hundreds).
  int unread(CollabGroup g) {
    final me = identity?.pub;
    final since = _read[g.secret.tag] ?? DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    return messages(g).where((m) => m.from != me && m.at.millisecondsSinceEpoch > since).length;
  }

  /// The chat is open: everything up to now is read.
  void markRead(CollabGroup g) {
    // up to the newest message (not „now“: every rebuild of the chat would send a new read mark)
    final v = messages(g).lastOrNull?.at.millisecondsSinceEpoch ?? 0;
    if (v == 0 || (_read[g.secret.tag] ?? 0) >= v) return;
    _read[g.secret.tag] = v;
    prefs?.setString(_kRead, jsonEncode(_read));
    // „gelesen“ for the others (only with presence on)
    if (presence) {
      g.session.doc(GroupSession.profile(g.session.me.pub)).set('read', v);
      g.session.touch(GroupSession.profile(g.session.me.pub));
    }
    notifyListeners();
  }

  // ---- presence and read receipts (Nutzer 04.11.: online / zuletzt online, abschaltbar; gelesen) ----

  static const _kPresence = 'collab.presence';

  /// Online status and read marks are shared (default). Off: nothing of mine goes out, and others' are not shown either.
  bool get presence => prefs?.getBool(_kPresence) ?? true;
  set presence(bool v) {
    prefs?.setBool(_kPresence, v);
    if (!v) {
      for (final g in groups.values) {
        final d = g.session.doc(GroupSession.profile(g.session.me.pub));
        d.set('seen', null);
        d.set('read', null);
        g.session.touch(GroupSession.profile(g.session.me.pub));
      }
    } else {
      _beat();
    }
    notifyListeners();
  }

  Timer? _heart;
  bool _front = false;

  /// The app came to the front or left it (main.dart): while in front „seen“ is renewed every 3 minutes.
  /// The app is in front again after it was away (the browser or the phone may have frozen the connections): connect again at once
  /// and send what is still waiting – a join that did not get through, a change from the bus.
  void wake() {
    if (_disposed) return;
    for (final g in groups.values) {
      g.session.relay.wake();
      unawaited(g.session.flush());
    }
    for (final p in joins) {
      p.error = null;
    }
  }

  void setForeground(bool front) {
    final wasAway = !_front && front;
    _front = front;
    _heart?.cancel();
    if (wasAway) wake();
    if (front) {
      _beat();
      _heart = Timer.periodic(const Duration(minutes: 3), (_) => _beat());
    }
  }

  void _beat() {
    if (!presence || !_front) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final g in groups.values) {
      g.session.doc(GroupSession.profile(g.session.me.pub)).set('seen', now);
      g.session.touch(GroupSession.profile(g.session.me.pub));
    }
  }

  /// When [pub] was last in the app (newest over all shared groups); null if unknown or presence is off.
  DateTime? lastSeen(String pub) {
    if (!presence) return null;
    int? best;
    for (final g in groups.values) {
      final v = g.session.doc(GroupSession.profile(pub)).get('seen');
      if (v is num && (best == null || v > best)) best = v.toInt();
    }
    return best == null ? null : DateTime.fromMillisecondsSinceEpoch(best);
  }

  /// Seen within the last 4 minutes (one heartbeat plus slack).
  bool isOnline(String pub) => lastSeen(pub)?.isAfter(DateTime.now().subtract(const Duration(minutes: 4))) ?? false;

  /// Until when [pub] has read this chat; null if unknown or presence is off.
  DateTime? readUntil(CollabGroup g, String pub) {
    if (!presence) return null;
    final v = g.session.doc(GroupSession.profile(pub)).get('read');
    return v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
  }

  int get unreadDirects => directs.fold(0, (a, g) => a + unread(g));
  int get unreadGroups => groups.values.where((g) => !g.secret.direct).fold(0, (a, g) => a + unread(g));

  List<NoteInfo> notes(CollabGroup g) => Notes.list(g.session.doc(GroupSession.notes));

  String newNote(CollabGroup g, String title) {
    final id = Notes.create(g.session.doc(GroupSession.notes), title);
    g.session.touch(GroupSession.notes);
    return id;
  }

  void saveNote(CollabGroup g, String id, {String? title, String? text}) {
    final d = g.session.doc(GroupSession.notes);
    if (title != null) Notes.rename(d, id, title);
    if (text != null) Notes.setText(d, id, text);
    g.session.touch(GroupSession.notes);
  }

  void deleteNote(CollabGroup g, String id) {
    Notes.delete(g.session.doc(GroupSession.notes), id);
    g.session.touch(GroupSession.notes);
  }

  // ---- bridge to the bills ----

  void _onStoreChanged() => _pushAll();

  final Set<String> _thumbing = {};

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

  /// True while this build is known to be stale (browser: a newer build is on the server but a bill is being read, so the page
  /// cannot reload yet): nothing is written into shared bills then (Nutzer 08.11.).
  bool writesPaused = false;

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

  static const _kHideNew = 'collab.hideNew';

  /// Group tags in which new bills I start are hidden at once (Standardstufe je Gruppe, Anforderung 18). Local to this phone.
  Set<String> get _hideNew => {...?prefs?.getStringList(_kHideNew)};

  bool hidesNewBills(CollabGroup g) => _hideNew.contains(g.secret.tag);

  void setHideNewBills(CollabGroup g, bool on) {
    final s = _hideNew;
    on ? s.add(g.secret.tag) : s.remove(g.secret.tag);
    prefs?.setStringList(_kHideNew, s.toList());
    if (on) _pushAll();
    notifyListeners();
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
    notifyListeners();
    return true;
  }

  // ---- receipt photos for the group (Beschluss 06.11., photo_sync.dart) ----
  //
  // The phone with the photo makes a downscaled JPEG of the scan and of the original, names them in the bill document
  // (meta/photo, meta/orig) and sends the encrypted pieces once per group. Everyone else fetches them one after another,
  // stores them like their own photos and cuts the line pictures from the scan (state/snippets.dart). Without this the
  // browser and the other phones had no receipt, no line pictures, no Original/Digital switch (Nutzer 06.11.).

  static const _kPhotoSent = 'collab.photoSent', _kPhotoFiles = 'collab.photoFiles';
  final Set<String> _photoPreparing = {}, _photoSending = {};
  final List<(String tag, String billId, bool orig)> _photoQueue = [];
  final Map<String, DateTime> _photoFailed = {}; // hash → last failed fetch (retry after a minute)
  bool _photoRunning = false;

  /// Local files of shared photos, by hash (to send them again, e.g. to a member who joins later).
  Map<String, String> get _photoFiles => {for (final e in (jsonDecode(prefs?.getString(_kPhotoFiles) ?? '{}') as Map).entries) '${e.key}': '${e.value}'};
  void _rememberPhoto(String hash, String path) => prefs?.setString(_kPhotoFiles, jsonEncode({..._photoFiles, hash: path}));

  /// Downscaled JPEG: longest side ≤ [side], [quality]; smaller again if it would not fit the relay limit.
  static Uint8List? _shrink(Uint8List bytes, int side, int quality) {
    final src = img.decodeImage(bytes);
    if (src == null) return null;
    var out = src;
    for (var s = side, q = quality; ; s = (s * 0.8).round(), q = math.max(40, q - 10)) {
      if (src.width > s || src.height > s) out = src.width >= src.height ? img.copyResize(src, width: s) : img.copyResize(src, height: s);
      final jpg = Uint8List.fromList(img.encodeJpg(out, quality: q));
      if (PhotoSync.refOf(jpg).pieces <= PhotoSync.maxPieces ~/ 2 || s < 400) return jpg;
    }
  }

  void _preparePhotos(Bill b) {
    for (final orig in const [false, true]) {
      final path = orig ? b.originalPath : b.imagePath;
      if ((orig ? b.origRef : b.photoRef) != null || path == null || !imageExists(path)) continue;
      final key = '${b.id}:$orig';
      if (!_photoPreparing.add(key)) continue;
      unawaited(() async {
        try {
          final bytes = await readImage(path);
          if (bytes == null) return;
          // scan: 1000 px is sharp enough for the line pictures and the receipt view; original: 1200 px (Blossom will carry the
          // full resolution); about 100–250 KB each, 4–9 pieces
          final small = _shrink(bytes, orig ? 1200 : 1000, orig ? 60 : 70);
          if (small == null) return;
          final ref = PhotoSync.refOf(small);
          final file = await saveImage('ph_${ref.hash}.jpg', small);
          if (file != null) _rememberPhoto(ref.hash, file);
          if (orig) {
            b.origRef = ref.toJson();
          } else {
            b.photoRef = ref.toJson();
          }
          store.upsert(b, record: false); // goes out with the bill; the pieces follow in _sendPhotos
        } catch (_) {
          // no shared photo for this bill; the others keep the digital receipt
        } finally {
          _photoPreparing.remove(key);
        }
      }());
    }
  }

  /// Sends the pieces of every shared photo that this group has not had from this phone yet.
  void _sendPhotos() {
    final sent = {...?prefs?.getStringList(_kPhotoSent)};
    final files = _photoFiles;
    for (final g in groups.values) {
      for (final b in store.bills) {
        if (b.group != g.localName || b.read != BillRead.ok) continue;
        for (final r in [b.photoRef, b.origRef]) {
          final ref = PhotoRef.fromJson(r);
          final file = ref == null ? null : files[ref.hash];
          // a hidden bill's photo goes out under the bill's own key (again, even if it was sent before it was hidden: the new
          // event replaces the old one); without the key nothing is sent
          if (b.hidden && !g.session.hasBillKey(b.id)) continue;
          final billKey = b.hidden ? g.session.keyFor(GroupSession.bill(b.id)) : null;
          final key = '${g.secret.tag}:${ref?.hash}${b.hidden ? ':h' : ''}';
          if (ref == null || file == null || sent.contains(key) || !_photoSending.add(key)) continue;
          unawaited(() async {
            try {
              final bytes = await readImage(file);
              if (bytes == null || PhotoSync.hashOf(bytes) != ref.hash) return;
              if (await PhotoSync.send(g.session.relay, g.session.me, g.secret, bytes, key: billKey)) {
                prefs?.setStringList(_kPhotoSent, [...{...?prefs?.getStringList(_kPhotoSent), key}]);
              }
            } catch (_) {
              // tried again with the next change or start
            } finally {
              _photoSending.remove(key);
            }
          }());
        }
      }
    }
  }

  /// A shared bill names photos this device does not have: fetch them (one after another, scan first).
  void _wantPhotos(CollabGroup g, Bill b) {
    if (b.photosRemoved) return;
    for (final orig in const [false, true]) {
      final ref = PhotoRef.fromJson(orig ? b.origRef : b.photoRef);
      if (ref == null || imageExists(orig ? b.originalPath : b.imagePath)) continue;
      final failed = _photoFailed[ref.hash];
      if (failed != null && DateTime.now().difference(failed) < const Duration(minutes: 1)) continue;
      final job = (g.secret.tag, b.id, orig);
      if (!_photoQueue.contains(job)) orig ? _photoQueue.add(job) : _photoQueue.insert(0, job);
    }
    unawaited(_runPhotoQueue());
  }

  /// Photo of [b] is on its way from the group (the receipt view shows „kommt …“ instead of nothing).
  bool photoComing(Bill b) => !b.photosRemoved && b.photoRef != null && !imageExists(b.imagePath) && b.group != null && groupByLocalName(b.group!) != null;

  final Map<String, int> _photoRetries = {};
  final List<Timer> _photoRetryTimers = [];

  Future<void> _runPhotoQueue() async {
    if (_photoRunning) return;
    _photoRunning = true;
    try {
      while (_photoQueue.isNotEmpty && !_disposed) {
        final (tag, billId, orig) = _photoQueue.removeAt(0);
        final g = groups[tag];
        final b = store.bills.where((x) => x.id == billId).firstOrNull;
        final ref = PhotoRef.fromJson(orig ? b?.origRef : b?.photoRef);
        if (g == null || b == null || ref == null || imageExists(orig ? b.originalPath : b.imagePath)) continue;
        final bytes = await PhotoSync.fetch(g.session.relay, g.secret, ref, isMember: (pub) => g.session.memberKeys.contains(pub), key: b.hidden ? g.session.keyFor(GroupSession.bill(b.id)) : null);
        if (bytes == null) {
          _photoFailed[ref.hash] = DateTime.now();
          // nobody asks again by itself: try again after the pause, a few times (a new member may learn the members late)
          final tries = _photoRetries[ref.hash] = (_photoRetries[ref.hash] ?? 0) + 1;
          if (tries <= 5 && !_disposed) {
            _photoRetryTimers.add(Timer(const Duration(minutes: 1, seconds: 5), () {
              final gg = groups[tag], bb = store.bills.where((x) => x.id == billId).firstOrNull;
              if (!_disposed && gg != null && bb != null) _wantPhotos(gg, bb);
            }));
          }
          continue;
        }
        final path = await saveImage('ph_${ref.hash}.jpg', bytes);
        if (path == null) continue;
        _rememberPhoto(ref.hash, path);
        if (orig) {
          b.originalPath = path;
        } else {
          b.imagePath = path;
          try {
            b.imageAspect = await fillSnippets(b, bytes) ?? b.imageAspect;
          } catch (_) {}
        }
        store.upsert(b, record: false);
        notifyListeners();
      }
    } finally {
      _photoRunning = false;
    }
  }

  // ---- activity (bell) and changed bills (Nutzer 04.11.) ----

  static const _kActivity = 'collab.activity', _kSeen = 'collab.activitySeen', _kChanged = 'collab.changedBills';
  List<Activity>? _act;
  List<Activity> get activity => _act ??= Activity.decode(prefs?.getString(_kActivity));
  final Map<String, DateTime> _activeSince = {}; // group tag → when it started on this phone (first sync is not news)
  final Map<String, Set<String>> _knownMembers = {};
  final Map<String, Set<String>> _knownMessages = {};
  final Map<String, Set<String>> _knownNotes = {}; // bill doc → note ids seen
  final Map<String, Set<String>> _knownMaybe = {}; // bill doc → proposal keys (sv/…) seen
  final Map<String, Map<String, String>> _knownItemNotes = {}; // bill doc → item uid → note text seen

  /// New since the bell was opened.
  int get unseenActivity {
    final seen = prefs?.getInt(_kSeen) ?? 0;
    return activity.where((a) => a.at.millisecondsSinceEpoch > seen).length;
  }

  void markActivitySeen() {
    prefs?.setInt(_kSeen, DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  /// Bills someone else changed that I have not opened since (marked in the list).
  Set<String> get changedBills => {...?prefs?.getStringList(_kChanged)};
  // When I opened a bill the last time (Nutzer 08.11.: beim Öffnen sieht man nicht, was von wem geändert wurde). The change log has
  // the changes with their time (writer's clock, never later than now); what is newer than my last opening is „new“. The previous
  // opening time stays in memory while the bill is open, so the banner can list the changes after the opening was recorded.
  static const _kOpened = 'collab.opened.';
  final Map<String, int> _sinceOpen = {};
  int _openedAt(String id) => prefs?.getInt('$_kOpened$id') ?? 0;

  /// Changes by others to [billId] since I opened it the time before (newest first).
  List<ChangeRecord> unseenChanges(String billId) {
    final since = _sinceOpen[billId] ?? _openedAt(billId);
    return [for (final r in changesOfBill(billId)) if (r.whoKey != identity?.pub && r.at.millisecondsSinceEpoch > since) r];
  }

  /// Number of single changes (lines) in [unseenChanges] – the counter on the bill's thumbnail in the list.
  int unseenCount(String billId) => unseenChanges(billId).fold(0, (a, r) => a + r.lines.length);

  void billSeen(String id) {
    _sinceOpen[id] = _openedAt(id);
    prefs?.setInt('$_kOpened$id', DateTime.now().millisecondsSinceEpoch);
    final c = changedBills;
    if (c.remove(id)) {
      prefs?.setStringList(_kChanged, c.toList());
      notifyListeners();
    }
  }

  /// Called for every new activity (system notification in the app, Benachrichtigungen settings).
  void Function(Activity)? onActivity;

  /// Which news count (Einstellungen → Benachrichtigungen, one place; Nutzer 04.11.). Default: all on.
  static const _kNotify = 'collab.notifyOff';
  bool notifies(ActivityKind k) => !(prefs?.getStringList(_kNotify) ?? const []).contains(k.name);
  void setNotifies(ActivityKind k, bool on) {
    final off = {...?prefs?.getStringList(_kNotify)};
    on ? off.remove(k.name) : off.add(k.name);
    prefs?.setStringList(_kNotify, off.toList());
    notifyListeners();
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
    prefs?.setString(_kActivity, Activity.encode(l));
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
      prefs?.setStringList(_kChanged, c.toList());
    }
  }

  // ── cost history of my balance (Nutzer 07.11.) ──
  static const _kLedger = 'collab.ledger';
  BalanceLedger? _ledger;
  Timer? _ledgerTimer;

  BalanceLedger get ledger => _ledger ??= BalanceLedger.decode(prefs?.getString(_kLedger));

  /// Who counts as me on a bill (Nutzer 11.11.: „Alles muss überall mit dem echten User verknüpft sein“). Names alone
  /// were the weak point: a renamed person or a second „Chris“ broke the link. A person is me when its stable uid is
  /// known as mine ([_ownUids], learned from every person that carries one of my names, see [learnOwnUids]); the names
  /// ([ownNames]) stay only as the way in for bills that no uid was learned from yet.
  bool Function(String) get isMeName {
    final names = ownNames;
    return (n) => names.contains(n.trim().toLowerCase());
  }

  static const _kUids = 'collab.ownUids';

  Set<String> get ownUids => {...?prefs?.getStringList(_kUids)};

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
    prefs?.setStringList(_kUids, uids.toList());
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

  static const _kLedgerAt = 'collab.ledgerAt';
  // when the ledger last looked; kept across restarts so a change that arrived while the app was closed still finds its record
  late DateTime _lastBooked = DateTime.fromMillisecondsSinceEpoch(prefs?.getInt(_kLedgerAt) ?? DateTime.now().millisecondsSinceEpoch);

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
    prefs?.setInt(_kLedgerAt, _lastBooked.millisecondsSinceEpoch);
    if (changed) {
      prefs?.setString(_kLedger, l.encode());
      notifyListeners();
    }
  }

  // ── change log: what exactly changed in a bill, by whom (Nutzer 07.11.) ──
  static const _kChangeLog = 'collab.changelog';
  List<ChangeRecord>? _changeLog;
  final Map<String, _Burst> _bursts = {};

  /// Newest first; every change of every bill in every group, from this phone's point of view (own changes too).
  List<ChangeRecord> get changeLog => _changeLog ??= ChangeRecord.decode(prefs?.getString(_kChangeLog));
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
      prefs?.setString(_kChangeLog, ChangeRecord.encode(l));
      if (e.key != me && !_quiet(g)) {
        final more = lines.length > 3 ? ' (+${lines.length - 3})' : '';
        final de = '$who hat „$title“ geändert: ${lines.take(3).map((x) => x.de).join('; ')}$more';
        final en = '$who changed “${title == 'Bon' ? 'Receipt' : title}”: ${lines.take(3).map((x) => x.en).join('; ')}$more';
        _note(Activity(ActivityKind.billChanged, rec.at, g.secret.tag, de, ref: billId, en: en));
      }
    }
    notifyListeners();
  }

  void _onDocChanged(CollabGroup g, String id) {
    _scheduleSave();
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
      notifyListeners();
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

  // ---- persistence ----

  Future<void> _persistGroups() async {
    await vault.write(_kGroups, jsonEncode([for (final g in groups.values) {'secret': g.secret.toJson(), 'local': g.localName}]));
    unawaited(syncAccount()); // the same list, encrypted to myself, for other devices and reinstalls
  }

  void _saveJoins() => prefs?.setString(_kJoins, jsonEncode([for (final p in joins) {'code': p.invite.encode(), 'name': p.name, 'since': p.since.toIso8601String()}]));

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), saveDocs);
  }

  /// Writes every document of every group to the phone (so the app starts with everything, offline).
  void saveDocs() {
    for (final g in groups.values) {
      for (final id in g.session.docIds) {
        prefs?.setString('$_kDocs${g.secret.tag}.$id', g.session.doc(id).encode());
      }
      prefs?.setStringList('$_kDocs${g.secret.tag}.ids', g.session.docIds.toList());
    }
  }

  /// Writes one document to the phone now.
  void _saveDoc(CollabGroup g, String id) => prefs?.setString('$_kDocs${g.secret.tag}.$id', g.session.doc(id).encode());

  /// After the documents of a group came back from the disk: the DOCUMENT is the shared truth, the bill in the store is only its
  /// copy. Without this the first change in the store made the phone compare its (possibly older) bills with the documents and
  /// write every difference as „its own change“ with a newer clock – posts back to raw names, quantities to 1, people gone, for
  /// everybody (Nutzer 08.11. 10:56 and 11:58; test/stale_store_test.dart). Bills whose document is empty stay as they are:
  /// nothing was ever shared for them, so the local bill is the source.
  void _adoptDocs(CollabGroup g) {
    for (final b in store.bills) {
      if (b.group != g.localName) continue;
      final doc = g.session.doc(GroupSession.bill(b.id));
      if (!BillSync.hasBill(doc)) continue;
      BillSync.read(doc, id: b.id, into: b);
      b.group = g.localName;
    }
    store.upsertAll();
  }

  void _restoreDocs(CollabGroup g) {
    for (final id in prefs?.getStringList('$_kDocs${g.secret.tag}.ids') ?? const <String>[]) {
      final raw = prefs?.getString('$_kDocs${g.secret.tag}.$id');
      if (raw == null) continue;
      try {
        g.session.doc(id).merge(LwwDocDecode.decode(raw));
      } catch (_) {}
    }
    g.session.absorbKeys(); // keys of hidden bills
  }

  bool _disposed = false;

  /// Async work that was under way when the service was closed (an approval, a send) must not touch the listeners any more:
  /// „A CollabService was used after being disposed“ would be an unhandled error.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // a change that was waiting for its 600 ms save must not be lost when the app is closed: save it now
    if (_saveTimer?.isActive ?? false) saveDocs();
    _saveTimer?.cancel();
    if (_storeListening) store.removeListener(_onStoreChanged);
    store.removeListener(_ledgerSoon);
    _ledgerTimer?.cancel();
    for (final t in _photoRetryTimers) {
      t.cancel();
    }
    for (final s in _subs.values) {
      s.cancel();
    }
    _accountWatch?.cancel();
    _directWatch?.cancel();
    _heart?.cancel();
    for (final g in groups.values) {
      g.rekeySub?.cancel();
      g.session.close();
      g.invitations?.close();
    }
    super.dispose();
  }
}

/// Small alias so service.dart does not import lww.dart twice by name.
abstract final class LwwDocDecode {
  static List<Entry> decode(String s) => LwwDoc.decode(s);
}

/// Entries of one document that arrived close together (one edit, one snapshot).
/// Outcome of [CollabService.undoChange].
enum UndoResult { done, partly, nothing }

class _Burst {
  _Burst(this.g, this.docId, this.liveBefore);
  final CollabGroup g;
  final String docId;
  final int liveBefore;
  final List<EntryChange> pairs = [];
  Timer? timer;
}
