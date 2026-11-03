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
  final Invitations? invitations; // only the admin
  bool get isAdmin => invitations != null;
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
    final admin = me.pub == secret.adminPub;
    final inv = admin ? Invitations(secret: secret, me: me.key, relay: relay) : null;
    final g = CollabGroup(secret, local, session, inv);
    groups[secret.tag] = g;
    if (restoreDocs) _restoreDocs(g);
    _subs[secret.tag] = session.changes.listen((id) => _onDocChanged(g, id));
    session.start();
    if (inv != null) {
      inv.listen();
      inv.changes.stream.listen((_) => notifyListeners());
    }
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

  void removeMember(CollabGroup g, String pub) {
    g.session.removeMember(pub);
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
