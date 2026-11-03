// Fasan Split – replicated document: last-writer-wins map with a Lamport clock. MPL-2.0
//
// Why this and not a text CRDT for everything: a shared bill is a set of small facts (item name, amount, who has how much).
// Two people changing different facts merge without loss; two people changing the SAME fact: the later change (higher clock, then
// the larger author key) wins on every device the same way. The result depends only on the set of changes, not on the order they
// arrive (commutative, associative, idempotent) – the CRDT property, tested in test/lww_test.dart.
// Money is never added up inside the CRDT: it stores inputs; each device recomputes with the exact SplitMath (see split_math.dart).
import 'dart:convert';

class Entry {
  const Entry(this.key, this.value, this.ts, this.author);

  final String key;
  final Object? value; // JSON value; null = deleted (tombstone)
  final int ts; // Lamport clock
  final String author; // public key (hex) of whoever made the change

  /// True if this change beats [o] (higher clock; equal clock: larger author; equal both: larger value text, for determinism).
  bool beats(Entry o) {
    if (ts != o.ts) return ts > o.ts;
    final c = author.compareTo(o.author);
    if (c != 0) return c > 0;
    return jsonEncode(value).compareTo(jsonEncode(o.value)) > 0;
  }

  List<Object?> toJson() => [key, value, ts, author];
  static Entry fromJson(Object? j) {
    final l = j as List;
    return Entry(l[0] as String, l[1], (l[2] as num).toInt(), l[3] as String);
  }
}

class LwwDoc {
  LwwDoc(this.author);

  /// Who we are (public key hex); stamped on our changes.
  final String author;
  final Map<String, Entry> _m = {};
  int _clock = 0;

  int get clock => _clock;
  Iterable<Entry> get entries => _m.values;
  Object? get(String key) => _m[key]?.value;
  bool has(String key) => _m[key]?.value != null;
  Entry? entry(String key) => _m[key];

  /// Keys with [prefix], live (not deleted).
  Iterable<String> keys(String prefix) => _m.entries.where((e) => e.key.startsWith(prefix) && e.value.value != null).map((e) => e.key);

  /// Our change. Returns false (and writes nothing) if the value is already what we want – keeps the history small and
  /// avoids pointless conflicts.
  bool set(String key, Object? value) {
    if (jsonEncode(_m[key]?.value) == jsonEncode(value)) return false;
    _m[key] = Entry(key, value, ++_clock, author);
    return true;
  }

  bool remove(String key) => _m.containsKey(key) && _m[key]!.value != null ? set(key, null) : false;

  /// A change from somewhere else. Returns true if it changed our state.
  bool apply(Entry e) {
    if (e.ts > _clock) _clock = e.ts;
    final cur = _m[e.key];
    if (cur != null && !e.beats(cur)) return false;
    _m[e.key] = e;
    return true;
  }

  /// Merges a whole snapshot; returns how many entries changed.
  int merge(Iterable<Entry> es) {
    var n = 0;
    for (final e in es) {
      if (apply(e)) n++;
    }
    return n;
  }

  String encode() => jsonEncode([for (final e in _m.values) e.toJson()]);

  static List<Entry> decode(String s) => [for (final x in jsonDecode(s) as List) Entry.fromJson(x)];

  /// Order-independent fingerprint of the live state (tests and „in sync“ checks).
  String get fingerprint {
    final keys = _m.keys.toList()..sort();
    return keys.map((k) => '$k=${jsonEncode(_m[k]!.value)}@${_m[k]!.ts}:${_m[k]!.author}').join('|');
  }
}
