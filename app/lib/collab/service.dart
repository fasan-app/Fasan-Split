// Fasan Split – the collaboration service: identity, groups, invitations, and the bridge to the local bills. MPL-2.0
//
// Local bills in a group that is shared (live) are written into that group's documents after every change; changes from the
// others are read back into the same bills. Nothing is sent for groups that are not shared. Public relays are contacted only by
// this service, only for groups the user created or joined, never by tests (they use MemoryRelay).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../model/bill.dart';
import '../model/pay.dart';
import '../state/images.dart';
import '../state/store.dart';
import 'activity.dart';
import 'bill_sync.dart';
import 'crypto.dart';
import 'group.dart';
import 'lww.dart';
import 'keys.dart';
import 'nostr.dart';
import 'notes.dart';
import 'pairing.dart';

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
    if (store.me.trim().isEmpty || store.me.trim() == old.trim()) store.me = n;
    for (final g in groups.values) {
      g.session.setMyName(n);
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
    return recoverGroups();
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
    final sub = relay.subscribe(Filter(kinds: const [kindData], authors: [me.pub], tags: {'t': ['fs:account']})).listen((e) {
      if (!e.valid || e.pubkey != me.pub || e.tag('d') != _accountD) return;
      try {
        final j = jsonDecode(nip44Decrypt(e.content, nip44ConversationKey(me.key.priv, me.pub))) as Map<String, dynamic>;
        for (final g in (j['groups'] as List? ?? const [])) {
          final m = (g as Map).cast<String, dynamic>();
          final s = GroupSecret.fromJson((m['secret'] as Map).cast<String, dynamic>());
          seen[s.tag] = m;
        }
      } catch (_) {}
    });
    await Future<void>.delayed(wait);
    await sub.cancel();
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
      session.republishAll(); // relays that missed something get it now (04.11.)
    }
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

  /// Changes held back for my confirmation.
  final List<HeldChange> held = [];

  bool _accept(CollabGroup g, String docId, Entry e) {
    final me = identity;
    if (me == null || e.author == me.pub || !docId.startsWith('bill:')) return true;
    if (!confirmAll && !distrusted.contains(e.author)) return true;
    // which persons of this bill are me: my name or names linked to my key
    final names = {store.me.trim().toLowerCase(), ...g.session.personsOf(me.pub).map((n) => n.toLowerCase())}..remove('');
    final doc = g.session.doc(docId);
    final mine = <String>{
      for (final k in doc.keys('p/'))
        if (doc.get(k) case final Map p when names.contains('${p['name']}'.trim().toLowerCase())) k.substring(2),
    };
    if (mine.isEmpty) return true;
    final concerns = e.key == 'meta/payer' || mine.any((u) => e.key == 'p/$u' || (e.key.startsWith('s/') && e.key.endsWith('/$u')));
    if (!concerns) return true;
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
    final me = identity;
    if (me == null) return;
    final refs = <String>{'$kindData:${me.pub}:$_accountD'};
    for (final g in groups.values.toList()) {
      final s = g.session;
      s.doc(GroupSession.profile(me.pub))
        ..set('deleted', true)
        ..set('seen', null);
      s.touch(GroupSession.profile(me.pub));
      if (s.doc(GroupSession.members).get('m/${me.pub}') != null && !s.isAdmin) {
        s.doc(GroupSession.members).set('m/${me.pub}', null); // own entry: allowed (group.dart _validSelfEntry)
        s.touch(GroupSession.members);
      }
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

  /// Leaves a group on this phone (the others keep it). Bills stay, without the shared link.
  Future<void> leave(CollabGroup g) async {
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

  // ---- chat and notes ----

  List<ChatMessage> messages(CollabGroup g) => Notes.messages(g.session.doc(GroupSession.chat));

  /// Sends a chat message; returns its id, or null when nothing was sent.
  String? sendMessage(CollabGroup g, String text, {String? bill, String? reply, List<String> mentions = const []}) {
    final me = identity;
    final t = text.trim();
    if (me == null || t.isEmpty && bill == null) return null;
    // a mention counts while its @name is still in the text, and only for members of the group
    final ms = [for (final k in mentions.toSet()) if (k != me.pub && g.session.memberKeys.contains(k) && t.contains('@${g.session.nameOf(k)}')) k];
    final id = Notes.send(g.session.doc(GroupSession.chat), me.pub, t, bill: bill, reply: reply, mentions: ms);
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
      store.upsert(b);
    } catch (_) {
      // no preview: the bill is shared without it
    }
  }

  void _pushAll() {
    for (final b in store.bills) {
      if (b.thumb == null && b.imagePath != null && b.group != null && groupByLocalName(b.group!) != null) unawaited(_makeThumb(b));
    }
    for (final g in groups.values) {
      for (final b in store.bills) {
        // trashed bills go out too: the others move them to their trash (04.11.: they stayed there)
        if (b.group != g.localName || b.read != BillRead.ok) continue;
        final id = GroupSession.bill(b.id);
        if (BillSync.write(g.session.doc(id), b)) g.session.touch(id);
      }
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
  void billSeen(String id) {
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
        if (k != me) _note(Activity(ActivityKind.joined, DateTime.now(), g.secret.tag, '${s.nameOf(k)} ist „${g.localName}“ beigetreten', en: '${s.nameOf(k)} joined “${g.localName}”'));
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
      if (last == null || last.author == me || _quiet(g)) return;
      final isNew = !store.bills.any((b) => b.id == billId);
      final purpose = doc.get('meta/purpose');
      final title = purpose is String && purpose.isNotEmpty ? purpose : 'Bon';
      final who = s.nameOf(last.author);
      _note(Activity(isNew ? ActivityKind.billNew : ActivityKind.billChanged, DateTime.now(), g.secret.tag,
          isNew ? '$who hat „$title“ in „${g.localName}“ eingetragen' : '$who hat „$title“ geändert', ref: billId,
          en: isNew ? '$who added “${title == 'Bon' ? 'Receipt' : title}” to “${g.localName}”' : '$who changed “${title == 'Bon' ? 'Receipt' : title}”'));
      final c = changedBills..add(billId);
      prefs?.setStringList(_kChanged, c.toList());
    }
  }

  void _onDocChanged(CollabGroup g, String id) {
    _scheduleSave();
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
    store.upsert(bill); // notifies; the write back finds nothing to change
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

  void _restoreDocs(CollabGroup g) {
    for (final id in prefs?.getStringList('$_kDocs${g.secret.tag}.ids') ?? const <String>[]) {
      final raw = prefs?.getString('$_kDocs${g.secret.tag}.$id');
      if (raw == null) continue;
      try {
        g.session.doc(id).merge(LwwDocDecode.decode(raw));
      } catch (_) {}
    }
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
