// SPDX-License-Identifier: MPL-2.0
// Fasan Split – CollabService, part: Chat and notes, mute, unread, presence. Split out of service.dart (13.11., Umbau U3, behaviour unchanged): the fields
// and constants stay in the class, these are its methods as an extension in the same library. MPL-2.0
part of 'service.dart';

extension CollabServiceChat on CollabService {

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

  Set<String> get _muted => _mutedCache ??= {for (final t in ((jsonDecode(prefs?.getString(CollabService._kMuted) ?? '[]') as List))) '$t'};

  bool isMuted(CollabGroup g) => _muted.contains(g.secret.tag);

  void setMuted(CollabGroup g, bool muted) {
    if (muted) {
      _muted.add(g.secret.tag);
    } else {
      _muted.remove(g.secret.tag);
    }
    prefs?.setString(CollabService._kMuted, jsonEncode(_muted.toList()));
    _notify();
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

  Map<String, int> get _read => _readCache ??= {
        for (final e in ((jsonDecode(prefs?.getString(CollabService._kRead) ?? '{}') as Map).entries)) '${e.key}': (e.value as num).toInt(),
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
    prefs?.setString(CollabService._kRead, jsonEncode(_read));
    // „gelesen“ for the others (only with presence on)
    if (presence) {
      g.session.doc(GroupSession.profile(g.session.me.pub)).set('read', v);
      g.session.touch(GroupSession.profile(g.session.me.pub));
    }
    _notify();
  }

  /// Online status and read marks are shared (default). Off: nothing of mine goes out, and others' are not shown either.
  bool get presence => prefs?.getBool(CollabService._kPresence) ?? true;

  set presence(bool v) {
    prefs?.setBool(CollabService._kPresence, v);
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
    _notify();
  }

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
}
