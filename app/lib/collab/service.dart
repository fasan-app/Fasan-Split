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

export 'nostr.dart' show defaultRelays;
part 'service_account.dart';
part 'service_activity.dart';
part 'service_admin.dart';
part 'service_bridge.dart';
part 'service_chat.dart';
part 'service_friends.dart';
part 'service_history.dart';
part 'service_locks.dart';
part 'service_persistence.dart';
part 'service_photos.dart'; // defined next to the relays (the invitation format needs it too)

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

  /// Called for every new activity (system notification in the app, Benachrichtigungen settings).
  void Function(Activity)? onActivity;
  final List<(String tag, String billId, bool orig)> _photoQueue = [];

  bool get hasGroups => groups.isNotEmpty;

  CollabGroup? groupByLocalName(String name) {
    for (final g in groups.values) {
      if (g.localName == name) return g;
    }
    return null;
  }
  // ---- (methods: service_locks.dart) padlocks on bills and items (lock_rules.dart; Nutzer 07.11.) ----
  DateTime? _leftAt;

  /// After a sign-in with the words (Nutzer 11.11.: the browser had no name afterwards): the name the groups know me by comes
  /// back as my name, unless the person typed another one – then the group's name is remembered as an old name of mine (the
  /// bills keep using it, see [ownNames]). A „gelöscht“ mark on my profile from an earlier deletion is taken away.
  bool _adoptPending = false;
  bool _adopting = false;
  String? _adoptedGuess; // the name taken from the groups; while it is still my name, a newer one from my profile replaces it

  bool _adoptBusy = false, _adoptAgain = false;

  // ---- my names (Nutzer 11.11.: „Chris“ stayed behind as a friend after renaming to „Chris2“) ----
  //
  // The bills know me by a name (a person on the bill). Renaming the account must not turn that person into a stranger:
  // the names I used before are kept (this phone only) and, with the persons an admin linked to my key in the groups, they
  // all count as me.

  static const _kOldNames = 'collab.ownNames';
  // ---- (methods: service_account.dart) linking a second device (pairing.dart) ----

  // ---- account across devices (Nutzer 04.11.: reinstall, several devices; no server and no login beyond the 12 words) ----
  //
  // The list of my groups (group key, local name) is published as one addressable event (kind 30078, d „fs:account:v1“),
  // encrypted with NIP-44 to my own key: only the holder of the 12 words can read it. Every device with the same words
  // publishes and reads it; lists are merged (union), so a group joined on one device appears on the other.

  static const _accountD = 'fs:account:v1';
  StreamSubscription<NostrEvent>? _accountWatch;

  // ---- friends: direct connections (Nutzer 04.11.: invite friends without a group, chat, try the app) ----

  /// Internal local name of a direct connection; never shown (the UI shows the other person's name).
  static String directLocalName(GroupSecret s) => '@friend:${s.tag}';

  StreamSubscription<NostrEvent>? _directWatch;

  final List<NostrEvent> _laterOffers = [];
  // ---- (methods: service_friends.dart) joining ----
  // ---- (methods: service_admin.dart) admin ----

  // ---- trust (Nutzer 04.11.: block changes of others that concern me; default: trust everyone) ----

  static const _kTrust = 'collab.trust';

  /// Changes held back for my confirmation.
  final List<HeldChange> held = [];

  // ---- how others can pay me back (model/pay.dart; Nutzer 04.11.) ----

  static const _kPay = 'collab.pay';
  static const _kShareHistory = 'collab.shareHistory';
  // ---- (methods: service_admin.dart) deleting the account (Nutzer 04.11.) ----

  static const _kHidden = 'collab.hiddenFriends';
  // ---- (methods: service_chat.dart) chat and notes ----
  // ---- (methods: service_friends.dart) invite a friend to a group straight from a bill (Nutzer 05.11.) ----

  // ---- mute per group (Nutzer 04.11.: stumm): no notifications from this chat, except when someone mentions me; unread numbers stay ----

  static const _kMuted = 'collab.muted';
  Set<String>? _mutedCache;

  // ---- unread (Nutzer 04.11.: last message in the friends list, unread made clear, numbers on the tabs) ----

  static const _kRead = 'collab.read';
  Map<String, int>? _readCache;

  // ---- presence and read receipts (Nutzer 04.11.: online / zuletzt online, abschaltbar; gelesen) ----

  static const _kPresence = 'collab.presence';

  Timer? _heart;
  bool _front = false;
  // ---- (methods: service_bridge.dart) bridge to the bills ----

  final Set<String> _thumbing = {};

  /// True while this build is known to be stale (browser: a newer build is on the server but a bill is being read, so the page
  /// cannot reload yet): nothing is written into shared bills then (Nutzer 08.11.).
  bool writesPaused = false;
  // ---- (methods: service_bridge.dart) hidden bills (Sichtbarkeit je Rechnung, docs/KONZEPT-SICHTBARKEIT.md) ----

  static const _kHideNew = 'collab.hideNew';

  // ---- receipt photos for the group (Beschluss 06.11., photo_sync.dart) ----
  //
  // The phone with the photo makes a downscaled JPEG of the scan and of the original, names them in the bill document
  // (meta/photo, meta/orig) and sends the encrypted pieces once per group. Everyone else fetches them one after another,
  // stores them like their own photos and cuts the line pictures from the scan (state/snippets.dart). Without this the
  // browser and the other phones had no receipt, no line pictures, no Original/Digital switch (Nutzer 06.11.).

  static const _kPhotoSent = 'collab.photoSent', _kPhotoFiles = 'collab.photoFiles';
  final Set<String> _photoPreparing = {}, _photoSending = {};
  final Map<String, DateTime> _photoFailed = {}; // hash → last failed fetch (retry after a minute)
  bool _photoRunning = false;

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

  final Map<String, int> _photoRetries = {};
  final List<Timer> _photoRetryTimers = [];

  // ---- activity (bell) and changed bills (Nutzer 04.11.) ----

  static const _kActivity = 'collab.activity', _kSeen = 'collab.activitySeen', _kChanged = 'collab.changedBills';
  List<Activity>? _act;
  final Map<String, DateTime> _activeSince = {}; // group tag → when it started on this phone (first sync is not news)
  final Map<String, Set<String>> _knownMembers = {};
  final Map<String, Set<String>> _knownMessages = {};
  final Map<String, Set<String>> _knownNotes = {}; // bill doc → note ids seen
  final Map<String, Set<String>> _knownMaybe = {}; // bill doc → proposal keys (sv/…) seen
  final Map<String, Map<String, String>> _knownItemNotes = {};
  // When I opened a bill the last time (Nutzer 08.11.: beim Öffnen sieht man nicht, was von wem geändert wurde). The change log has
  // the changes with their time (writer's clock, never later than now); what is newer than my last opening is „new“. The previous
  // opening time stays in memory while the bill is open, so the banner can list the changes after the opening was recorded.
  static const _kOpened = 'collab.opened.';
  final Map<String, int> _sinceOpen = {};

  /// Which news count (Einstellungen → Benachrichtigungen, one place; Nutzer 04.11.). Default: all on.
  static const _kNotify = 'collab.notifyOff';

  // ── cost history of my balance (Nutzer 07.11.) ──
  static const _kLedger = 'collab.ledger';
  BalanceLedger? _ledger;
  Timer? _ledgerTimer;

  static const _kUids = 'collab.ownUids';

  static const _kLedgerAt = 'collab.ledgerAt';
  // when the ledger last looked; kept across restarts so a change that arrived while the app was closed still finds its record
  late DateTime _lastBooked = DateTime.fromMillisecondsSinceEpoch(prefs?.getInt(_kLedgerAt) ?? DateTime.now().millisecondsSinceEpoch);

  // ── change log: what exactly changed in a bill, by whom (Nutzer 07.11.) ──
  static const _kChangeLog = 'collab.changelog';
  List<ChangeRecord>? _changeLog;
  final Map<String, _Burst> _bursts = {};
  // ---- (methods: service_persistence.dart) persistence ----

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

  void _notify() => notifyListeners(); // for the extensions in the part files (notifyListeners is protected)

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
