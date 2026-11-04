// Fasan Split – the collaboration service: identity, groups, invitations, and the bridge to the local bills. MPL-2.0
//
// Local bills in a group that is shared (live) are written into that group's documents after every change; changes from the
// others are read back into the same bills. Nothing is sent for groups that are not shared. Public relays are contacted only by
// this service, only for groups the user created or joined, never by tests (they use MemoryRelay).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/bill.dart';
import '../state/store.dart';
import 'bill_sync.dart';
import 'crypto.dart';
import 'group.dart';
import 'lww.dart';
import 'keys.dart';
import 'nostr.dart';
import 'notes.dart';

/// Relays used for new groups. Not checked for availability here – the user can change them per group later.
const List<String> defaultRelays = ['wss://relay.damus.io', 'wss://nos.lol', 'wss://relay.primal.net'];

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
    if (groups.isNotEmpty || await vault.read(Identity.vaultKeys.first) != null && identity?.pub != _pubOf(m)) return false;
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
    return true;
  }

  static String? _pubOf(Map<String, Object?> m) {
    final priv = (m['vault'] as Map?)?[Identity.vaultKeys.first] as String?;
    return priv == null ? null : KeyPair.fromPrivate(priv).pub;
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
    try {
      for (final j in jsonDecode(prefs?.getString(_kJoins) ?? '[]') as List) {
        final m = (j as Map).cast<String, dynamic>();
        final inv = Invite.parse(m['code'] as String);
        if (inv != null && !inv.expired) _waitForWelcome(PendingJoin(inv, m['name'] as String, DateTime.tryParse(m['since'] as String? ?? '') ?? DateTime.now()));
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<Identity> ensureIdentity({String name = ''}) async {
    identity ??= await Identity.loadOrCreate(vault, defaultName: name);
    return identity!;
  }

  Future<void> setName(String name) async {
    final id = await ensureIdentity();
    id.name = name.trim();
    await id.save(vault);
    notifyListeners();
  }

  Future<void> restoreIdentity(String words, {String? name}) async {
    identity = await Identity.restore(vault, words, name: name ?? identity?.name ?? '');
    // the groups on this phone belong to the old key: a restored key re-joins nothing by itself, the admin can invite again
    notifyListeners();
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
    final relay = _relayFactory(secret.relays);
    final session = GroupSession(secret: secret, me: me.key, relay: relay);
    final g = CollabGroup(secret, local, session, null);
    session.acceptEntry = (docId, e) => _accept(g, docId, e);
    groups[secret.tag] = g;
    if (restoreDocs) _restoreDocs(g);
    _subs[secret.tag] = session.changes.listen((id) => _onDocChanged(g, id));
    session.start();
    _ensureInvitations(g);
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

  void _waitForWelcome(PendingJoin p, {JoinFlow? flow}) {
    final me = identity;
    () async {
      final id = me ?? await ensureIdentity();
      final f = flow ?? JoinFlow(invite: p.invite, me: id.key, relay: _relayFactory(p.invite.relays), name: p.name);
      try {
        final secret = await f.waitForWelcome(timeout: p.invite.expires.add(const Duration(days: 1)).difference(DateTime.now()));
        joins.remove(p);
        _saveJoins();
        final local = uniqueLocalName(secret.name);
        store.addGroup(local);
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
    g.session.addMember(r.pub, r.name.isEmpty ? r.pub.substring(0, 8) : r.name, person: r.person);
    await g.session.flush(); // members first, then the key
    await inv.welcome(r.pub);
    notifyListeners();
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
    final ns = GroupSecret(key: randomBytes(32), adminPub: s.adminPub, name: s.name, relays: s.relays);
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
      final ns = GroupSecret(key: fromHex(j['key'] as String), adminPub: j['admin'] as String? ?? g.secret.adminPub, name: j['name'] as String? ?? g.secret.name, relays: [for (final r in j['relays'] as List) '$r']);
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
    inv.listen();
    inv.changes.stream.listen((_) => notifyListeners());
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

  void sendMessage(CollabGroup g, String text) {
    final me = identity;
    final t = text.trim();
    if (me == null || t.isEmpty) return;
    Notes.send(g.session.doc(GroupSession.chat), me.pub, t);
    g.session.touch(GroupSession.chat);
  }

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

  void _pushAll() {
    for (final g in groups.values) {
      for (final b in store.bills) {
        if (b.group != g.localName || b.trashedAt != null || b.read != BillRead.ok) continue;
        final id = GroupSession.bill(b.id);
        if (BillSync.write(g.session.doc(id), b)) g.session.touch(id);
      }
    }
  }

  void _onDocChanged(CollabGroup g, String id) {
    _scheduleSave();
    if (id == GroupSession.members || id == GroupSession.chat || id == GroupSession.notes) {
      if (id == GroupSession.members) _ensureInvitations(g); // someone made me admin
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

  Future<void> _persistGroups() => vault.write(_kGroups, jsonEncode([for (final g in groups.values) {'secret': g.secret.toJson(), 'local': g.localName}]));

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

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_storeListening) store.removeListener(_onStoreChanged);
    for (final s in _subs.values) {
      s.cancel();
    }
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
