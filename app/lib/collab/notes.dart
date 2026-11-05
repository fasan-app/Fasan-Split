// Fasan Split – shared notes and chat on top of LwwDoc. MPL-2.0
//
// A note is a list of lines; every line has its own id and position. Editing the text of a note changes only the lines that
// differ, so two people typing in different places of the same note both keep their words. If two people change the SAME line at
// the same time, both versions stay (as two lines) – nothing a person typed silently disappears.
import 'lww.dart';
import '../model/bill.dart' show newUid;

class NoteInfo {
  NoteInfo(this.id, this.title, this.text);
  final String id, title, text;
}

class ChatMessage {
  ChatMessage(this.id, this.from, this.text, this.at, {this.bill, this.reply, this.edited = false, this.deleted = false, this.reactions = const {}, this.mentions = const [], this.pinned = false});
  final String id, from, text;

  /// Id of the message this one answers (quote), or null.
  final String? reply;

  /// Text was changed after sending / message was deleted (the entry stays so quotes still resolve; text is empty).
  final bool edited, deleted;

  /// People (public keys) the author mentioned with @; they are told in their „Neuigkeiten“ (Nutzer 04.11.).
  final List<String> mentions;

  /// Pinned for the whole group (anyone can pin and unpin, like in other group chats); shown on top of the chat.
  final bool pinned;

  /// Reactions: person (public key) → emoji. One per person and message; the same emoji again takes it back.
  final Map<String, String> reactions;

  /// A bill mentioned in the message (Nutzer 04.11.: bills tagged in the chat); shown as a card.
  final String? bill;
  final DateTime at;
}

abstract final class Notes {
  static List<NoteInfo> list(LwwDoc doc) {
    final ids = <String>{};
    for (final k in doc.keys('n/')) {
      final parts = k.split('/');
      if (parts.length >= 3) ids.add(parts[1]);
    }
    final out = [
      for (final id in ids)
        if (doc.get('n/$id/del') != true && doc.get('n/$id/title') != null) NoteInfo(id, doc.get('n/$id/title') as String, text(doc, id))
    ];
    out.sort((a, b) => (doc.entry('n/${b.id}/title')?.ts ?? 0).compareTo(doc.entry('n/${a.id}/title')?.ts ?? 0));
    return out;
  }

  static List<(String, String, double)> _lines(LwwDoc doc, String id) {
    final out = <(String, String, double)>[];
    for (final k in doc.keys('n/$id/l/')) {
      final v = doc.get(k);
      if (v is Map) out.add((k.split('/').last, v['t'] as String? ?? '', (v['p'] as num?)?.toDouble() ?? 0));
    }
    out.sort((a, b) => a.$3 != b.$3 ? a.$3.compareTo(b.$3) : a.$1.compareTo(b.$1));
    return out;
  }

  static String text(LwwDoc doc, String id) => _lines(doc, id).map((l) => l.$2).join('\n');

  static String create(LwwDoc doc, String title) {
    final id = newUid();
    doc.set('n/$id/title', title.isEmpty ? '—' : title);
    return id;
  }

  static void rename(LwwDoc doc, String id, String title) => doc.set('n/$id/title', title);

  static void delete(LwwDoc doc, String id) => doc.set('n/$id/del', true);

  /// Makes the note's text equal [newText] by changing only the lines that differ.
  static void setText(LwwDoc doc, String id, String newText) {
    final old = _lines(doc, id);
    final neu = newText.isEmpty ? <String>[] : newText.split('\n');
    final a = [for (final l in old) l.$2];
    // longest common subsequence of lines: these keep their ids
    final n = a.length, m = neu.length;
    final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = a[i] == neu[j] ? dp[i + 1][j + 1] + 1 : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }
    final keepOld = <int, int>{}; // old index → new index
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (a[i] == neu[j]) {
        keepOld[i] = j;
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    for (var k = 0; k < n; k++) {
      if (!keepOld.containsKey(k)) doc.set('n/$id/l/${old[k].$1}', null);
    }
    final kept = {for (final e in keepOld.entries) e.value: old[e.key]}; // new index → old line
    // positions: new lines go between the nearest kept neighbours
    var reindex = false;
    final pos = List<double>.filled(m, 0);
    for (var q = 0; q < m; q++) {
      if (kept.containsKey(q)) pos[q] = kept[q]!.$3;
    }
    for (var q = 0; q < m; q++) {
      if (kept.containsKey(q)) continue;
      var lo = q - 1, hi = q + 1;
      while (lo >= 0 && !kept.containsKey(lo) && pos[lo] == 0) {
        lo--;
      }
      double before = lo >= 0 ? pos[lo] : (old.isEmpty ? 0 : old.first.$3 - 2);
      if (q > 0) before = pos[q - 1];
      while (hi < m && !kept.containsKey(hi)) {
        hi++;
      }
      final after = hi < m ? pos[hi] : before + 2;
      pos[q] = (before + after) / 2;
      if ((after - before).abs() < 1e-9) reindex = true;
    }
    if (reindex) {
      for (var q = 0; q < m; q++) {
        pos[q] = q.toDouble();
      }
    }
    for (var q = 0; q < m; q++) {
      final line = kept[q];
      final lid = line?.$1 ?? newUid();
      doc.set('n/$id/l/$lid', {'t': neu[q], 'p': pos[q]});
    }
  }

  // ---- chat ----

  static List<ChatMessage> messages(LwwDoc doc) {
    final out = <ChatMessage>[];
    final reactions = <String, Map<String, String>>{}; // message id → person → emoji (keys `c/<id>/e/<pub>`)
    final pinned = <String>{};
    for (final k in doc.keys('c/')) {
      final parts = k.split('/');
      if (parts.length == 4 && parts[2] == 'e' && doc.get(k) is String) (reactions[parts[1]] ??= {})[parts[3]] = doc.get(k) as String;
      if (parts.length == 3 && parts[2] == 'p' && doc.get(k) == true) pinned.add(parts[1]);
    }
    for (final k in doc.keys('c/')) {
      if (k.indexOf('/', 2) >= 0) continue; // only `c/<id>` entries are messages
      final v = doc.get(k);
      if (v is Map) {
        final id = k.substring(2);
        out.add(ChatMessage(id, v['f'] as String? ?? '', v['x'] as String? ?? '', DateTime.fromMillisecondsSinceEpoch((v['t'] as num?)?.toInt() ?? 0),
            bill: v['b'] as String?, reply: v['r'] as String?, edited: v['ed'] == 1, deleted: v['d'] == 1, reactions: reactions[id] ?? const {}, mentions: [for (final m in (v['m'] as List?) ?? const []) '$m'], pinned: pinned.contains(id)));
      }
    }
    out.sort((a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.id.compareTo(b.id));
    return out;
  }

  static int _lastSentMs = 0;

  /// Time stamp for a new message: never lower or equal to the last one sent in this process, so messages sent one after
  /// another keep their order even within the same millisecond (the ID alone would order them at random).
  static int _stamp() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastSentMs = now > _lastSentMs ? now : _lastSentMs + 1;
    return _lastSentMs;
  }

  /// Sends a message; returns its id (to delete or quote it later).
  static String send(LwwDoc doc, String from, String text, {String? bill, String? reply, List<String> mentions = const []}) {
    final id = newUid();
    doc.set('c/$id', {'f': from, 'x': text, 't': _stamp(), 'b': ?bill, 'r': ?reply, if (mentions.isNotEmpty) 'm': mentions});
    return id;
  }

  /// Pins or unpins a message for the whole group.
  static void pinMessage(LwwDoc doc, String id, bool pin) {
    if (_raw(doc, id) == null) return;
    doc.set('c/$id/p', pin ? true : null);
  }

  static Map<String, Object?>? _raw(LwwDoc doc, String id) {
    final v = doc.get('c/$id');
    return v is Map ? Map<String, Object?>.from(v) : null;
  }

  /// Changes the text of a message of [from]. Only the author edits (checked here, not cryptographically – group members are
  /// trusted like everywhere in this document). Returns false if there is nothing to edit.
  static bool editMessage(LwwDoc doc, String id, String from, String text) {
    final m = _raw(doc, id);
    if (m == null || m['f'] != from || m['d'] == 1 || m['b'] != null || text.trim().isEmpty) return false;
    doc.set('c/$id', {...m, 'x': text.trim(), 'ed': 1});
    return true;
  }

  /// „Delete for everyone“: the entry stays as a marker without text (quotes and reactions still resolve).
  static bool deleteMessage(LwwDoc doc, String id, String from) {
    final m = _raw(doc, id);
    if (m == null || m['f'] != from || m['d'] == 1) return false;
    doc.set('c/$id', {'f': m['f'], 'x': '', 't': m['t'], 'd': 1, 'r': ?m['r']});
    return true;
  }

  /// Sets, changes or (same emoji again) removes the reaction of [pub] to a message.
  static void reactMessage(LwwDoc doc, String id, String pub, String emoji) {
    if (_raw(doc, id) == null) return;
    final key = 'c/$id/e/$pub';
    doc.set(key, doc.get(key) == emoji ? null : emoji);
  }
}
