// SPDX-License-Identifier: MPL-2.0
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

import 'package:fasan_core/bill.dart' show Bill;

import 'bill_sync.dart';
import 'crypto.dart';
import 'lww.dart';
import 'nostr.dart';

const int kindData = 30078;

/// Secrets and settings of one group on this device.
class GroupSecret {
  GroupSecret({required this.key, required this.adminPub, required this.name, required this.relays, DateTime? created, this.direct = false}) : created = created ?? DateTime.now();

  /// Direct connection of two friends (Nutzer 04.11.: invite friends without a group or bill, to chat and try the app).
  /// Same machinery as a group; shown under Freunde, never in the group or bill lists. [name] is the inviter's name.
  final bool direct;

  final Uint8List key; // 32 bytes
  final String adminPub;
  String name;
  List<String> relays;
  final DateTime created;

  String get tag => toHex(sha256([...utf8.encode('fasan-split/group/v1'), ...key]).sublist(0, 16));

  Map<String, Object?> toJson() => {'key': toHex(key), 'admin': adminPub, 'name': name, 'relays': relays, 'created': created.toIso8601String(), if (direct) 'direct': true};
  static GroupSecret fromJson(Map<String, dynamic> j) => GroupSecret(
        key: fromHex(j['key'] as String),
        adminPub: j['admin'] as String,
        name: j['name'] as String,
        relays: [for (final r in j['relays'] as List) '$r'],
        created: DateTime.tryParse(j['created'] as String? ?? ''),
        direct: j['direct'] == true,
      );
}

/// The invitation a new member opens. Carries no group key.
class Invite {
  Invite({required this.tag, required this.secret, required this.adminPub, required this.relays, required this.expires, required this.name, this.person, this.auto = false, this.groupKey, this.direct = false});

  /// Friend link (GroupSecret.direct): joining connects two people, no group.
  final bool direct;

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

  /// Compact binary form (v2, 05.11.): the JSON form was ~490 characters (hex keys, the tag twice, relay URLs spelled out) and a link of
  /// 534 characters got cut when friends copied it from messengers – the key behind „#“ was missing and they landed in an empty app.
  /// v2 is ~160 characters: version, flags, one-time secret, admin key, group key (the tag follows from it), expiry, names, relays
  /// only when they are not the default ones, and a 3-byte check so that a cut link is recognised as such. Old v1 links still open.
  String encode() {
    // not real hex keys (hand-made test data, damaged state): the old text form can carry anything
    final hex = RegExp(r'^[0-9a-f]+$');
    if (!hex.hasMatch(adminPub) || adminPub.length != 64 || secret.length != 32 || (groupKey == null && !(hex.hasMatch(tag) && tag.length == 32)) || (groupKey != null && groupKey!.length != 32)) return _encodeV1();
    final b = BytesBuilder();
    final defaults = _sameRelays(relays, defaultRelays);
    final flags = (auto ? 1 : 0) | (groupKey != null ? 2 : 0) | (direct ? 4 : 0) | (person != null ? 8 : 0) | (defaults ? 16 : 0);
    b.addByte(2);
    b.addByte(flags);
    b.add(secret);
    b.add(fromHex(adminPub));
    b.add(groupKey ?? fromHex(tag)); // with the key the tag is derived (GroupSecret.tag); without it, the 16 bytes of the tag
    final x = expires.millisecondsSinceEpoch ~/ 1000;
    b.add([(x >> 24) & 255, (x >> 16) & 255, (x >> 8) & 255, x & 255]);
    _putString(b, name);
    if (person != null) _putString(b, person!);
    if (!defaults) {
      b.addByte(relays.length.clamp(0, 255));
      for (final r in relays.take(255)) {
        _putString(b, r);
      }
    }
    final body = b.toBytes();
    return base64Url.encode([...body, ...sha256(body).sublist(0, 3)]).replaceAll('=', '');
  }

  String _encodeV1() => base64Url.encode(utf8.encode(jsonEncode({
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
        if (direct) 'd': 1,
      }))).replaceAll('=', '');

  static bool _sameRelays(List<String> a, List<String> b) => a.length == b.length && List.generate(a.length, (i) => a[i] == b[i]).every((e) => e);

  /// Length byte and UTF-8 bytes (at most 100 bytes, cut at a character boundary).
  static void _putString(BytesBuilder b, String s) {
    var bytes = utf8.encode(s);
    if (bytes.length > 100) {
      var end = 100;
      while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
        end--;
      }
      bytes = bytes.sublist(0, end);
    }
    b.addByte(bytes.length);
    b.add(bytes);
  }

  /// Link for sharing. The part after „#“ is never sent to a server: GitHub Pages only sees /Fasan-Split/join/.
  /// Opens the app (Android App Link, needs assetlinks.json on the host) or the web app (docs/WEB.md).
  String get link => '$inviteBase#${encode()}';

  /// Web address of invitations. Older links „fasansplit://join#…“ still work (parse reads the part after „#“).
  static const inviteBase = 'https://fasan-app.github.io/Fasan-Split/join/';

  static Invite? parse(String input) => parseDetailed(input).invite;

  /// Like [parse], but says what is wrong with text that holds no usable invitation: `empty` (nothing there), `incomplete` (it ends
  /// too early or fails its check: the link was cut when it was copied), `invalid` (not one of ours), `expired` is the caller's job.
  static ({Invite? invite, String problem}) parseDetailed(String input) {
    final candidates = _candidates(input);
    if (candidates.isEmpty) return (invite: null, problem: 'empty');
    var problem = 'invalid';
    for (final c in candidates) {
      final r = _decode(c);
      if (r.invite != null) return (invite: r.invite, problem: '');
      if (r.problem == 'incomplete') problem = 'incomplete';
    }
    return (invite: null, problem: problem);
  }

  static final _b64 = RegExp(r'^[A-Za-z0-9_\-=]+$');

  /// Possible payloads in a pasted text: the part behind „#“, then the same joined with the following words (a link that was wrapped
  /// by a messenger), then a bare code on its own.
  static List<String> _candidates(String input) {
    var s = input.replaceAll('%23', '#').replaceAll(RegExp(r'[<>"\u201c\u201d\u00ab\u00bb]'), ' ').trim();
    s = s.replaceAll(RegExp(r'#+\s*$'), '').trim(); // a stray „#“ after the link
    if (s.isEmpty) return [];
    final out = <String>[];
    final hash = s.lastIndexOf('#');
    final tail = hash >= 0 ? s.substring(hash + 1) : s;
    final words = tail.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var cur = '';
    for (var i = 0; i < words.length && i < 6; i++) {
      var w = words[i];
      // a link at the end of a sentence: drop the punctuation after it
      w = w.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
      if (!_b64.hasMatch(w) && !w.contains('/')) break;
      if (w.contains('/')) w = w.substring(w.lastIndexOf('/') + 1);
      if (w.isEmpty) break;
      cur += w;
      out.add(cur);
    }
    final joined = out.reversed.toList(); // the longest first: a wrapped link is the whole
    if (hash < 0) {
      // a code without any link around it („Code: …“): every long word of its own
      for (final m in RegExp(r'[A-Za-z0-9_\-]{40,}').allMatches(s)) {
        if (!joined.contains(m[0]!)) joined.add(m[0]!);
      }
    }
    return joined;
  }

  static ({Invite? invite, String problem}) _decode(String payload) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(payload));
      if (bytes.isEmpty) return (invite: null, problem: 'invalid');
      if (bytes[0] == 2) return _decodeV2(bytes);
      // v1: JSON (links made before 05.11.)
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (j['v'] != 1) return (invite: null, problem: 'invalid');
      return (
        invite: Invite(
          tag: j['t'] as String,
          secret: fromHex(j['s'] as String),
          adminPub: j['a'] as String,
          relays: [for (final r in j['r'] as List) '$r'],
          expires: DateTime.fromMillisecondsSinceEpoch((j['x'] as num).toInt() * 1000),
          name: j['n'] as String? ?? '',
          person: j['p'] as String?,
          auto: j['o'] == 1,
          groupKey: j['k'] is String ? fromHex(j['k'] as String) : null,
          direct: j['d'] == 1,
        ),
        problem: ''
      );
    } on FormatException {
      // base64 that stops in the middle, or JSON that stops in the middle: a cut link
      return (invite: null, problem: payload.length > 20 ? 'incomplete' : 'invalid');
    } catch (_) {
      return (invite: null, problem: 'invalid');
    }
  }

  static ({Invite? invite, String problem}) _decodeV2(List<int> all) {
    if (all.length < 4 + 3) return (invite: null, problem: 'incomplete');
    final body = all.sublist(0, all.length - 3), check = all.sublist(all.length - 3);
    final want = sha256(body).sublist(0, 3);
    if (check[0] != want[0] || check[1] != want[1] || check[2] != want[2]) return (invite: null, problem: 'incomplete');
    var p = 1;
    int u8() => body[p++];
    List<int> take(int n) {
      if (p + n > body.length) throw const FormatException('short');
      final r = body.sublist(p, p + n);
      p += n;
      return r;
    }

    String str() => utf8.decode(take(u8()), allowMalformed: true);
    try {
      final flags = u8();
      final secret = Uint8List.fromList(take(32));
      final admin = toHex(Uint8List.fromList(take(32)));
      final hasKey = flags & 2 != 0;
      final keyOrTag = Uint8List.fromList(take(hasKey ? 32 : 16));
      final x = take(4);
      final exp = (x[0] << 24) | (x[1] << 16) | (x[2] << 8) | x[3];
      final name = str();
      final person = flags & 8 != 0 ? str() : null;
      var relays = defaultRelays;
      if (flags & 16 == 0) {
        final n = u8();
        relays = [for (var i = 0; i < n; i++) str()];
      }
      final direct = flags & 4 != 0;
      final tag = hasKey ? GroupSecret(key: keyOrTag, adminPub: admin, name: name, relays: relays, direct: direct).tag : toHex(keyOrTag);
      return (
        invite: Invite(
          tag: tag,
          secret: secret,
          adminPub: admin,
          relays: relays,
          expires: DateTime.fromMillisecondsSinceEpoch(exp * 1000),
          name: name,
          person: person,
          auto: flags & 1 != 0,
          groupKey: hasKey ? keyOrTag : null,
          direct: direct,
        ),
        problem: ''
      );
    } catch (_) {
      return (invite: null, problem: 'invalid');
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

  /// Tells the listeners; harmless after [close] (an approval that was under way when the group was closed used to throw
  /// „Cannot add new events after calling close“).
  void _changed() {
    if (!changes.isClosed) changes.add(null);
  }

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
        groupKey: auto ? secret.key : null,
        direct: secret.direct);
    _issued[toHex(inv.secret)] = inv;
    onIssued?.call(open);
    return inv;
  }

  /// Withdraws one invitation (Nutzer 04.11.: choose which one).
  void revoke(Invite i) {
    _issued.remove(toHex(i.secret));
    onIssued?.call(open);
    _changed();
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
        _changed();
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
    final body = nip44Encrypt(jsonEncode({'key': toHex(secret.key), 'name': secret.name, 'admin': secret.adminPub, 'relays': secret.relays, if (secret.direct) 'direct': true}), conv);
    final ev = NostrEvent.create(me, kind: kindData, tags: [['d', 'fs:${secret.tag}:welcome:$pub'], ['t', '${secret.tag}:welcome'], ['p', pub]], content: body);
    pending.remove(pub);
    _changed();
    return relay.publish(ev);
  }

  void decline(String pub) {
    pending.remove(pub);
    _changed();
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
        final g = GroupSecret(key: fromHex(j['key'] as String), adminPub: j['admin'] as String? ?? invite.adminPub, name: j['name'] as String? ?? invite.name, relays: [for (final r in j['relays'] as List) '$r'], direct: j['direct'] == true || invite.direct);
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

  /// Every applied entry of a bill document (docId, replaced entry, new entry) – the service builds the change log from it.
  void Function(String docId, Entry? old, Entry now)? onEntry;

  LwwDoc doc(String id) => _docs.putIfAbsent(id, () {
        final d = LwwDoc(me.pub);
        if (id.startsWith('bill:')) d.onApplied = (o, n) => onEntry?.call(id, o, n);
        return d;
      });

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
      if (id.startsWith('profile:')) {
        // a profile (name, later picture and status) is written by its owner only, from the owner's own event
        final owner = id.substring('profile:'.length);
        if (e.pubkey != owner) return;
        accepted = entries.where((x) => x.author == owner);
      } else if (!isMembersDoc) {
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
      if (doc(id).merge(accepted) > 0 && !_changes.isClosed) _changes.add(id);
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
    // the person the link was made for, or – a general link – the own name
    return persons is List && persons.length == 1 && persons.single == (t['p'] ?? v['name']);
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
    // every member is a person of the group right away (Nutzer 04.11.: joined, but not listed as a person)
    final person = inv.person != null && inv.person!.isNotEmpty ? inv.person! : name;
    doc(members).set('m/${me.pub}', {'name': name, 'i': inv.ticketId, if (person.isNotEmpty) 'persons': [person]});
    touch(members);
  }

  /// Marks a document as changed locally; the snapshot goes out after a short pause (many edits, one message).
  void touch(String id) {
    if (!_changes.isClosed) _changes.add(id);
    _dirty.add(id);
    _timer?.cancel();
    _timer = Timer(publishDelay, flush);
  }

  /// The last state of a bill each member published (a relay keeps one event per author and document). Read-only: nothing is
  /// written. Used to bring a damaged bill back (Nutzer 08.11.: Kassenzettel zerschossen). Newest first. [wait]: relays have no
  /// "end of stored events" signal in this layer, so the fetch listens for that long.
  Future<List<BillSnapshot>> snapshotsOf(String billId, {Duration wait = const Duration(seconds: 4)}) async {
    final d = _d(bill(billId));
    final newest = <String, NostrEvent>{};
    final sub = relay.subscribe(Filter(kinds: const [kindData], tags: {'d': [d]})).listen((e) {
      if (!e.valid || e.tag('d') != d || !memberKeys.contains(e.pubkey)) return;
      final old = newest[e.pubkey];
      if (old == null || e.createdAt > old.createdAt) newest[e.pubkey] = e;
    });
    await Future<void>.delayed(wait);
    await sub.cancel();
    final out = <BillSnapshot>[];
    for (final e in newest.values) {
      try {
        final doc = LwwDoc(me.pub)..merge(LwwDoc.decode(aeadOpen(e.content, secret.key, d)));
        out.add(BillSnapshot(author: e.pubkey, at: DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000), doc: doc));
      } catch (_) {/* not readable: skip */}
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  /// Publishes every changed document now.
  Future<void> flush() async {
    _timer?.cancel();
    final ids = _dirty.toList();
    _dirty.clear();
    var failed = false;
    for (final (i, id) in ids.indexed) {
      // a short pause between documents: public relays limit bursts („rate-limited“), and a refused document used to wait
      // for the next change – the other phones then showed an old state (Nutzer 04.11.)
      if (i > 0 && publishPace > Duration.zero) await Future<void>.delayed(publishPace);
      final d = _d(id);
      final ev = NostrEvent.create(me, kind: kindData, tags: [['d', d], ['t', secret.tag]], content: aeadSeal(doc(id).encode(), secret.key, d));
      final ok = await relay.publish(ev);
      if (ok) {
        published++;
      } else {
        failedPublishes++;
        _dirty.add(id);
        failed = true;
      }
    }
    if (failed && !_closed) {
      // try again by itself: 3 s, 6 s, 12 s … up to 2 minutes
      _retry = _retry == Duration.zero ? const Duration(seconds: 3) : (_retry * 2 > const Duration(minutes: 2) ? const Duration(minutes: 2) : _retry * 2);
      _timer = Timer(_retry, flush);
    } else if (!failed) {
      _retry = Duration.zero;
    }
  }

  Duration _retry = Duration.zero;
  bool _closed = false;

  /// Pause between two documents of one flush (tests: zero).
  Duration publishPace = const Duration(milliseconds: 120);

  /// After the start: every document of this phone goes out once more, so relays that missed one (or a member who
  /// joined later) get the newest state without waiting for a change.
  void republishAll() {
    _dirty.addAll(_docs.keys);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), flush);
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

  /// Member linked to [person], or null. Without an explicit link a member whose own name is the same (ignoring case)
  /// counts as that person (Nutzer 04.11.: linking by hand was confusing; „Lena“ in a bill is Lena who joined).
  String? memberOfPerson(String person) {
    for (final k in memberKeys) {
      if (personsOf(k).contains(person)) return k;
    }
    final p = person.trim().toLowerCase();
    if (p.isEmpty) return null;
    for (final k in memberKeys) {
      if (personsOf(k).isEmpty && nameOf(k).trim().toLowerCase() == p) return k;
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

  /// Profile document of a member (`profile:<pub>`, written only by that member): the name the person gave themselves.
  static String profile(String pub) => 'profile:$pub';

  /// Sets my name in this group (my profile; as admin also my entry in the members list, for older app versions).
  void setMyName(String name) {
    if (name.isEmpty) return;
    doc(profile(me.pub)).set('name', name);
    touch(profile(me.pub));
    if (!isAdmin) return;
    if (doc(members).get('m/${me.pub}') case final Map m when m['name'] != name) {
      doc(members).set('m/${me.pub}', {...m.cast<String, Object?>(), 'name': name});
      touch(members);
    }
  }

  /// Name of a member for display: the own profile first (Nutzer 04.11.: a renamed person stayed „—“), then the members list.
  String nameOf(String pub) {
    if (doc(profile(pub)).get('name') case final String n when n.trim().isNotEmpty) return n;
    final m = doc(members).get('m/$pub');
    if (m is Map && m['name'] is String && (m['name'] as String).trim().isNotEmpty) return m['name'] as String;
    return pub.substring(0, 8);
  }

  /// The real name of a member, or null while neither profile nor members list has one yet (a new member's name arrives
  /// a moment after the key; Nutzer 07.11.: „Name war leer, wer beigetreten ist“).
  String? knownName(String pub) {
    final n = nameOf(pub);
    return n == pub.substring(0, 8) ? null : n;
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await flush();
    await _sub?.cancel();
    await _changes.close();
  }
}

/// One member's last published state of a bill (see [GroupSession.snapshotsOf]).
class BillSnapshot {
  BillSnapshot({required this.author, required this.at, required this.doc});
  final String author;
  final DateTime at;
  final LwwDoc doc;

  /// The bill as this snapshot holds it (for a preview and for restoring).
  Bill bill(String id, {Bill? into}) => BillSync.read(doc, id: id, into: into);
}
