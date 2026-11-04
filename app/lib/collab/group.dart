// Fasan Split – groups: secrets, invitation, approval, live sync of documents. MPL-2.0
//
// Protocol (all events are Nostr kind 30078 „application data“, addressable by author + d tag; content always encrypted):
// 1. Admin creates a group: random 256-bit group key K, id tag = SHA-256("fasan-split/group/v1" ‖ K)[0..16] (relays cannot link tag and key).
// 2. Invitation (link or code) carries: id tag, one-time invite secret IV, admin public key, relays, expiry. It does NOT carry K.
// 3. Joiner publishes a join request, sealed with a key from IV (ChaCha20-Poly1305). Only the admin (who made IV) can read it.
// 4. Admin sees the request and approves: writes the person into the members document and sends a welcome (K, NIP-44 from the
//    admin key to the joiner key). Before approval a person with the link cannot read the group.
// 4b. Open link (Invite.groupKey, default since 04.11.: „people have little patience“): the link also carries K, and the
//    admin wrote a ticket `i/<id>` into the members document. The joiner adds itself as `m/<own pub>` with that ticket
//    id and is in at once, even when no admin is online (like a messenger group link: whoever has the link gets in).
//    Every phone checks: a self entry counts only from its own author's event, names a ticket an admin wrote and that is
//    not withdrawn, and never carries „admin“. The admin adopts the member on the next start (join request, step 4).
//    Withdrawing links = deleting the tickets and a new K (CollabService.revokeInvites).
// 5. Everyone publishes their copy of each document as an encrypted snapshot (ChaCha20-Poly1305 with K, bound to the d tag);
//    everyone merges what the others publish (LwwDoc). Missed updates arrive with the next snapshot, no extra sync step.
// Members trust each other: anyone who holds K can write. The member list is changed by admins only: the founder (adminPub
// in the secret, always admin) and members marked admin by an admin (m/<pub>.admin, 04.11.: the group survives when the
// founder leaves). Removing a member: an admin rotates K (CollabService.rotateKey: new K, sent with NIP-44 to everyone
// else as a „rekey“ event; the removed one cannot read anything new). Changes that concern me from people I do not trust
// can be held back as suggestions (GroupSession.acceptEntry, CollabService trust settings).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'crypto.dart';
import 'lww.dart';
import 'nostr.dart';

const int kindData = 30078;

/// Secrets and settings of one group on this device.
class GroupSecret {
  GroupSecret({required this.key, required this.adminPub, required this.name, required this.relays, DateTime? created}) : created = created ?? DateTime.now();

  final Uint8List key; // 32 bytes
  final String adminPub;
  String name;
  List<String> relays;
  final DateTime created;

  String get tag => toHex(sha256([...utf8.encode('fasan-split/group/v1'), ...key]).sublist(0, 16));

  Map<String, Object?> toJson() => {'key': toHex(key), 'admin': adminPub, 'name': name, 'relays': relays, 'created': created.toIso8601String()};
  static GroupSecret fromJson(Map<String, dynamic> j) => GroupSecret(
        key: fromHex(j['key'] as String),
        adminPub: j['admin'] as String,
        name: j['name'] as String,
        relays: [for (final r in j['relays'] as List) '$r'],
        created: DateTime.tryParse(j['created'] as String? ?? ''),
      );
}

/// The invitation a new member opens. Carries no group key.
class Invite {
  Invite({required this.tag, required this.secret, required this.adminPub, required this.relays, required this.expires, required this.name, this.person, this.auto = false, this.groupKey});

  final String tag, adminPub, name;

  /// Person in the group's bills this invitation is for (Nutzer 03.11.: people from a bill are invited and linked).
  /// The admin's phone links the new member to this name on approval; null = no person yet.
  final String? person;

  /// Let in without asking (Nutzer 04.11.: people have little patience): the inviting phone approves at once.
  final bool auto;
  final Uint8List secret; // 32 bytes, one-time

  /// Open link: the group key itself (step 4b above); null = the admin's phone has to let the person in.
  final Uint8List? groupKey;

  /// Id of the ticket in the members document (`i/<id>`); does not reveal [secret].
  String get ticketId => toHex(sha256([...utf8.encode('fasan-split/ticket/v1'), ...secret]).sublist(0, 16));
  final List<String> relays;
  final DateTime expires;

  bool get expired => DateTime.now().isAfter(expires);

  /// Key that seals join requests.
  Uint8List get requestKey => sha256([...utf8.encode('fasan-split/invite/v1'), ...secret]);

  String encode() => base64Url.encode(utf8.encode(jsonEncode({
        'v': 1,
        't': tag,
        's': toHex(secret),
        'a': adminPub,
        'r': relays,
        'x': expires.millisecondsSinceEpoch ~/ 1000,
        'n': name,
        if (person != null) 'p': person,
        if (auto) 'o': 1,
        if (groupKey != null) 'k': toHex(groupKey!),
      }))).replaceAll('=', '');

  /// Link for sharing. The part after „#“ is never sent to a server: GitHub Pages only sees /Fasan-Split/join/.
  /// Opens the app (Android App Link, needs assetlinks.json on the host) or the web app (docs/WEB.md).
  String get link => '$inviteBase#${encode()}';

  /// Web address of invitations. Older links „fasansplit://join#…“ still work (parse reads the part after „#“).
  static const inviteBase = 'https://fasan-app.github.io/Fasan-Split/join/';

  static Invite? parse(String input) {
    try {
      var s = input.trim();
      final i = s.indexOf('#');
      if (i >= 0) s = s.substring(i + 1);
      if (s.contains('/')) s = s.substring(s.lastIndexOf('/') + 1);
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(s)))) as Map<String, dynamic>;
      if (j['v'] != 1) return null;
      return Invite(
        tag: j['t'] as String,
        secret: fromHex(j['s'] as String),
        adminPub: j['a'] as String,
        relays: [for (final r in j['r'] as List) '$r'],
        expires: DateTime.fromMillisecondsSinceEpoch((j['x'] as num).toInt() * 1000),
        name: j['n'] as String? ?? '',
        person: j['p'] as String?,
        auto: j['o'] == 1,
        groupKey: j['k'] is String ? fromHex(j['k'] as String) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

class JoinRequest {
  JoinRequest(this.pub, this.name, this.at, {this.person, this.auto = false});
  final String pub, name;
  final DateTime at;

  /// From the invitation that sealed the request (Invite.person, Invite.auto).
  final String? person;
  final bool auto;
}

/// Admin side of invitations: keeps the secrets of invitations it made, reads requests, approves.
class Invitations {
  Invitations({required this.secret, required this.me, required this.relay});

  final GroupSecret secret;
  final KeyPair me;
  final Relay relay;
  final Map<String, Invite> _issued = {}; // by secret hex
  final Map<String, JoinRequest> pending = {};
  StreamSubscription<NostrEvent>? _sub;
  final StreamController<void> changes = StreamController<void>.broadcast();

  /// Called when the issued invitations change: the service stores them (04.11.: they lived in memory only – after an
  /// update or restart of the inviting phone, requests of invited people could not be read any more).
  void Function(List<Invite>)? onIssued;

  /// Invitations made earlier (stored by the service). Requests already on the relays are read again by [listen].
  void restore(Iterable<Invite> l) {
    for (final i in l) {
      if (!i.expired && i.tag == secret.tag) _issued[toHex(i.secret)] = i;
    }
  }

  /// A new invitation valid for [valid]; [auto] lets the person in without asking.
  Invite create({Duration valid = const Duration(days: 7), String? person, bool auto = true}) {
    final inv = Invite(
        tag: secret.tag, secret: randomBytes(32), adminPub: me.pub, relays: secret.relays, expires: DateTime.now().add(valid), name: secret.name, person: person, auto: auto,
        groupKey: auto ? secret.key : null);
    _issued[toHex(inv.secret)] = inv;
    onIssued?.call(open);
    return inv;
  }

  /// Revokes all open invitations.
  void revokeAll() {
    _issued.clear();
    onIssued?.call(open);
  }

  List<Invite> get open => _issued.values.where((i) => !i.expired).toList();

  void listen() {
    _sub ??= relay.subscribe(Filter(kinds: const [kindData], tags: {'t': ['${secret.tag}:join']})).listen(_onEvent);
  }

  void _onEvent(NostrEvent e) {
    if (!e.valid) return;
    final d = e.tag('d');
    if (d == null || d != 'fs:${secret.tag}:join:${e.pubkey}') return;
    for (final inv in _issued.values) {
      if (inv.expired) continue;
      try {
        final j = jsonDecode(aeadOpen(e.content, inv.requestKey, d)) as Map<String, dynamic>;
        pending[e.pubkey] = JoinRequest(e.pubkey, (j['name'] as String? ?? '').trim(), DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000), person: inv.person, auto: inv.auto);
        changes.add(null);
        return;
      } on FormatException {
        continue; // sealed with another invitation's key (or garbage)
      }
    }
  }

  /// Sends the welcome (group key) to an approved person. The caller also adds them to the members document.
  Future<bool> welcome(String pub) {
    final conv = nip44ConversationKey(me.priv, pub);
    // 'admin' is the founder (the group's adminPub), also when another admin sends the welcome
    final body = nip44Encrypt(jsonEncode({'key': toHex(secret.key), 'name': secret.name, 'admin': secret.adminPub, 'relays': secret.relays}), conv);
    final ev = NostrEvent.create(me, kind: kindData, tags: [['d', 'fs:${secret.tag}:welcome:$pub'], ['t', '${secret.tag}:welcome'], ['p', pub]], content: body);
    pending.remove(pub);
    changes.add(null);
    return relay.publish(ev);
  }

  void decline(String pub) {
    pending.remove(pub);
    changes.add(null);
  }

  Future<void> close() async {
    await _sub?.cancel();
    await changes.close();
  }
}

/// Joiner side: publish the request, wait for the welcome.
class JoinFlow {
  JoinFlow({required this.invite, required this.me, required this.relay, required this.name});

  final Invite invite;
  final KeyPair me;
  final Relay relay;
  final String name;

  Future<bool> sendRequest() {
    final d = 'fs:${invite.tag}:join:${me.pub}';
    final ev = NostrEvent.create(me, kind: kindData, tags: [['d', d], ['t', '${invite.tag}:join']], content: aeadSeal(jsonEncode({'name': name}), invite.requestKey, d));
    return relay.publish(ev);
  }

  /// Completes with the group once the admin approves. Only a welcome signed by the admin named in the invitation counts.
  Future<GroupSecret> waitForWelcome({Duration timeout = const Duration(days: 2)}) {
    final c = Completer<GroupSecret>();
    late StreamSubscription<NostrEvent> sub;
    sub = relay.subscribe(Filter(kinds: const [kindData], authors: [invite.adminPub], tags: {'t': ['${invite.tag}:welcome'], 'p': [me.pub]})).listen((e) {
      if (!e.valid || e.pubkey != invite.adminPub || e.tag('d') != 'fs:${invite.tag}:welcome:${me.pub}') return;
      try {
        final j = jsonDecode(nip44Decrypt(e.content, nip44ConversationKey(me.priv, invite.adminPub))) as Map<String, dynamic>;
        final g = GroupSecret(key: fromHex(j['key'] as String), adminPub: j['admin'] as String? ?? invite.adminPub, name: j['name'] as String? ?? invite.name, relays: [for (final r in j['relays'] as List) '$r']);
        if (g.tag != invite.tag) return; // not the group we asked for
        if (!c.isCompleted) c.complete(g);
        sub.cancel();
      } catch (_) {
        // not for us or damaged: ignore
      }
    });
    return c.future.timeout(timeout, onTimeout: () {
      sub.cancel();
      throw TimeoutException('no welcome');
    });
  }
}

/// One group in use: documents are merged from everyone's snapshots and published again after local changes.
class GroupSession {
  GroupSession({required this.secret, required this.me, required this.relay, this.publishDelay = const Duration(milliseconds: 350)});

  final GroupSecret secret;
  final KeyPair me;
  final Relay relay;
  final Duration publishDelay;

  final Map<String, LwwDoc> _docs = {};
  final Set<String> _dirty = {};
  final List<NostrEvent> _waiting = []; // events from not-yet-known authors
  Timer? _timer;
  StreamSubscription<NostrEvent>? _sub;
  final StreamController<String> _changes = StreamController<String>.broadcast();

  /// Document ids that changed (by someone else or by us).
  Stream<String> get changes => _changes.stream;

  /// Counters for the log and tests.
  int received = 0, rejected = 0, published = 0, failedPublishes = 0;

  bool get isAdmin => admins.contains(me.pub);

  /// The founder and every member an admin marked as admin.
  Set<String> get admins => {
        secret.adminPub,
        for (final k in doc(members).keys('m/'))
          if (doc(members).get(k) case final Map m when m['admin'] == true) k.substring(2),
      };

  /// Filter for entries of others in the bill documents (trust, CollabService). Null = take all.
  bool Function(String docId, Entry e)? acceptEntry;

  /// Fixed document ids.
  static const members = 'members', chat = 'chat', notes = 'notes';
  static String bill(String id) => 'bill:$id';

  LwwDoc doc(String id) => _docs.putIfAbsent(id, () => LwwDoc(me.pub));

  Iterable<String> get docIds => _docs.keys;

  /// Public keys allowed to write: the admin and everyone in the members document.
  Set<String> get memberKeys => {secret.adminPub, ...doc(members).keys('m/').map((k) => k.substring(2))};

  String _d(String id) => 'fs:${secret.tag}:$id';

  void start() {
    _sub ??= relay.subscribe(Filter(kinds: const [kindData], tags: {'t': [secret.tag]})).listen(_onEvent);
  }

  void _onEvent(NostrEvent e) {
    received++;
    if (!e.valid) {
      rejected++;
      return;
    }
    final d = e.tag('d');
    final prefix = 'fs:${secret.tag}:';
    if (d == null || !d.startsWith(prefix)) return;
    final id = d.substring(prefix.length);
    final isMembersDoc = id == members;
    // only members write; the members document from an admin, or a self entry with a ticket (open link, step 4b)
    final fromAdmin = admins.contains(e.pubkey);
    if (!isMembersDoc && !memberKeys.contains(e.pubkey)) {
      // maybe the members document has not arrived yet: keep the event and look again when it has
      if (_waiting.length < 300) _waiting.add(e);
      rejected++;
      return;
    }
    try {
      final entries = LwwDoc.decode(aeadOpen(e.content, secret.key, d));
      // the members document: only entries written by admins count (an admin's snapshot also carries the other admins'
      // entries); m/<pub> = member, l/admin = the founder's own person link (linkPerson)
      final adm = admins;
      final Iterable<Entry> accepted;
      if (!isMembersDoc) {
        accepted = acceptEntry == null ? entries : entries.where((x) => x.author == me.pub || acceptEntry!(id, x));
      } else if (fromAdmin) {
        accepted = entries.where((x) => (x.key.startsWith('m/') || x.key == 'l/admin' || x.key.startsWith('i/')) && adm.contains(x.author));
      } else {
        final self = entries.where((x) => x.key == 'm/${e.pubkey}' && x.author == e.pubkey).toList();
        if (self.isEmpty) return; // nothing a non-admin may write here
        if (!self.every(_validSelfEntry)) {
          // the ticket may not have arrived yet: look again when the admin's members document has
          if (_waiting.length < 300 && !_waiting.contains(e)) _waiting.add(e);
          rejected++;
          return;
        }
        accepted = self;
      }
      if (doc(id).merge(accepted) > 0) _changes.add(id);
      if (isMembersDoc && _waiting.isNotEmpty) {
        final again = _waiting.toList();
        _waiting.clear();
        rejected -= again.length; // they were counted when they first arrived
        again.forEach(_onEvent);
      }
    } on FormatException {
      rejected++;
    } catch (_) {
      rejected++;
    }
  }

  /// A member who added itself with an open link: names a ticket an admin wrote (and did not withdraw), no admin flag,
  /// at most the person name the ticket was made for.
  bool _validSelfEntry(Entry x) {
    final v = x.value;
    if (v == null) return true; // leaving: one may always take oneself out
    if (v is! Map || v['i'] is! String || v.containsKey('admin')) return false;
    final t = doc(members).get('i/${v['i']}');
    if (t is! Map) return false;
    final persons = v['persons'];
    if (persons == null) return true;
    return persons is List && persons.length == 1 && persons.single == t['p'];
  }

  /// In through an open link and not yet adopted by an admin.
  bool isSelfJoined(String pub) => switch (doc(members).get('m/$pub')) { final Map m => m['i'] is String, _ => false };

  /// Admin: writes the ticket of an open link (step 4b) or withdraws it ([open] false).
  void setTicket(Invite inv, {bool open = true}) {
    if (!isAdmin) throw StateError('only the admin changes members');
    doc(members).set('i/${inv.ticketId}', open ? {'x': inv.expires.millisecondsSinceEpoch ~/ 1000, if (inv.person != null) 'p': inv.person} : null);
    touch(members);
  }

  /// Joiner with an open link: adds itself to the members document (checked by everyone, see _validSelfEntry).
  void joinWithTicket(Invite inv, String name) {
    doc(members).set('m/${me.pub}', {'name': name, 'i': inv.ticketId, if (inv.person != null && inv.person!.isNotEmpty) 'persons': [inv.person]});
    touch(members);
  }

  /// Marks a document as changed locally; the snapshot goes out after a short pause (many edits, one message).
  void touch(String id) {
    _changes.add(id);
    _dirty.add(id);
    _timer?.cancel();
    _timer = Timer(publishDelay, flush);
  }

  /// Publishes every changed document now.
  Future<void> flush() async {
    _timer?.cancel();
    final ids = _dirty.toList();
    _dirty.clear();
    for (final id in ids) {
      final d = _d(id);
      final ev = NostrEvent.create(me, kind: kindData, tags: [['d', d], ['t', secret.tag]], content: aeadSeal(doc(id).encode(), secret.key, d));
      final ok = await relay.publish(ev);
      if (ok) {
        published++;
      } else {
        failedPublishes++;
        _dirty.add(id); // try again with the next change or flush
      }
    }
  }

  /// Admin: puts a person into the members document (call before the welcome).
  void addMember(String pub, String name, {String? person}) {
    if (!isAdmin) throw StateError('only the admin changes members');
    doc(members).set('m/$pub', {'name': name, if (person != null && person.isNotEmpty) 'persons': [person]});
    touch(members);
  }

  /// Admin: links a member to a person name of the group's bills (Nutzer 03.11.). A member can have several names (the
  /// same person written differently in two bills), a name belongs to one member: linking takes it away elsewhere.
  /// [person] null unlinks all names of [pub]. Stored as `m/<pub>.persons` (older entries: .person); the admin itself has
  /// no m/ entry and uses l/admin.
  void linkPerson(String pub, String? person) {
    if (!isAdmin) throw StateError('only the admin changes members');
    if (person != null) {
      final other = memberOfPerson(person);
      if (other == pub) return;
      if (other != null) unlinkPerson(other, person);
    }
    _setPersons(pub, person == null ? const [] : [...personsOf(pub), person]);
  }

  /// Admin: takes one name away from a member.
  void unlinkPerson(String pub, String person) {
    if (!isAdmin) throw StateError('only the admin changes members');
    _setPersons(pub, personsOf(pub).where((p) => p != person).toList());
  }

  void _setPersons(String pub, List<String> persons) {
    if (pub == secret.adminPub) {
      doc(members).set('l/admin', persons.isEmpty ? null : persons);
    } else {
      final m = doc(members).get('m/$pub');
      final v = m is Map ? Map<String, Object?>.of(m.cast<String, Object?>()) : <String, Object?>{'name': nameOf(pub)};
      v.remove('person');
      if (persons.isEmpty) {
        v.remove('persons');
      } else {
        v['persons'] = persons;
      }
      doc(members).set('m/$pub', v);
    }
    touch(members);
  }

  /// All person names a member is linked to (first = the one shown).
  List<String> personsOf(String pub) {
    final Object? v = pub == secret.adminPub ? doc(members).get('l/admin') : doc(members).get('m/$pub');
    if (v is List) return [for (final x in v) '$x'];
    if (v is Map) {
      if (v['persons'] is List) return [for (final x in v['persons'] as List) '$x'];
      if (v['person'] is String) return [v['person'] as String];
    }
    return const [];
  }

  /// First person name of a member, or null.
  String? personOf(String pub) => personsOf(pub).firstOrNull;

  /// Member linked to [person], or null.
  String? memberOfPerson(String person) {
    for (final k in memberKeys) {
      if (personsOf(k).contains(person)) return k;
    }
    return null;
  }

  /// Admin: makes a member admin too, or takes it back. The founder stays admin always.
  void setAdmin(String pub, bool admin) {
    if (!isAdmin) throw StateError('only the admin changes members');
    if (pub == secret.adminPub) return;
    final m = doc(members).get('m/$pub');
    if (m is! Map) return;
    final v = Map<String, Object?>.of(m.cast<String, Object?>());
    admin ? v['admin'] = true : v.remove('admin');
    doc(members).set('m/$pub', v);
    touch(members);
  }

  void removeMember(String pub) {
    if (!isAdmin) throw StateError('only the admin changes members');
    doc(members).remove('m/$pub');
    touch(members);
  }

  /// Name of a member for display.
  String nameOf(String pub) {
    final m = doc(members).get('m/$pub');
    if (m is Map && m['name'] is String) return m['name'] as String;
    return pub.substring(0, 8);
  }

  Future<void> close() async {
    _timer?.cancel();
    await flush();
    await _sub?.cancel();
    await _changes.close();
  }
}
