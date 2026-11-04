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
  ChatMessage(this.id, this.from, this.text, this.at, {this.bill});
  final String id, from, text;

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
    for (final k in doc.keys('c/')) {
      final v = doc.get(k);
      if (v is Map) out.add(ChatMessage(k.substring(2), v['f'] as String? ?? '', v['x'] as String? ?? '', DateTime.fromMillisecondsSinceEpoch((v['t'] as num?)?.toInt() ?? 0), bill: v['b'] as String?));
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

  static void send(LwwDoc doc, String from, String text, {String? bill}) => doc.set('c/${newUid()}', {'f': from, 'x': text, 't': _stamp(), 'b': ?bill});
}
