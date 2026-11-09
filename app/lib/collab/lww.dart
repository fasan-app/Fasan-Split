// SPDX-License-Identifier: MPL-2.0
// Fasan Split – replicated document: last-writer-wins map with a Lamport clock. MPL-2.0
//
// Why this and not a text CRDT for everything: a shared bill is a set of small facts (item name, amount, who has how much).
// Two people changing different facts merge without loss; two people changing the SAME fact: the later change (higher clock, then
// the larger author key) wins on every device the same way. The result depends only on the set of changes, not on the order they
// arrive (commutative, associative, idempotent) – the CRDT property, tested in test/lww_test.dart.
// Money is never added up inside the CRDT: it stores inputs; each device recomputes with the exact SplitMath (see split_math.dart).
import 'dart:convert';

class Entry {
  const Entry(this.key, this.value, this.ts, this.author, {this.wall, this.app});

  /// Version of this build (e.g. „0.1.77“ or „web a1b2c3d“), stamped on our changes (Nutzer 08.11.: which device wrote what, with
  /// which version). Set once at the start (main.dart); empty in tests.
  static String appTag = '';

  /// Clock time of the writer's device in ms (only for showing „when“: the Lamport clock decides, a wrong device clock changes
  /// nothing about who wins). Null for entries of builds before 08.11. Older builds read only the first four list entries.
  final int? wall;

  /// [appTag] of the writer; null for older builds.
  final String? app;

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

  List<Object?> toJson() => [key, value, ts, author, if (wall != null) wall, if (wall != null) app ?? ''];
  static Entry fromJson(Object? j) {
    final l = j as List;
    return Entry(l[0] as String, l[1], (l[2] as num).toInt(), l[3] as String,
        wall: l.length > 4 ? (l[4] as num?)?.toInt() : null, app: l.length > 5 && (l[5] as String?)?.isNotEmpty == true ? l[5] as String : null);
  }
}

class LwwDoc {
  LwwDoc(this.author);

  /// Who we are (public key hex); stamped on our changes.
  final String author;

  /// Called after every change that took effect (ours or from somewhere else) with the entry it replaced (null = new key).
  /// The change log (bill_changes.dart) is built from this: an entry alone only holds the newest value.
  void Function(Entry? old, Entry now)? onApplied;
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
    final old = _m[key];
    final e = _m[key] = Entry(key, value, ++_clock, author, wall: DateTime.now().millisecondsSinceEpoch, app: Entry.appTag);
    onApplied?.call(old, e);
    return true;
  }

  bool remove(String key) => _m.containsKey(key) && _m[key]!.value != null ? set(key, null) : false;

  /// A change from somewhere else. Returns true if it changed our state.
  bool apply(Entry e) {
    if (e.ts > _clock) _clock = e.ts;
    final cur = _m[e.key];
    if (cur != null && !e.beats(cur)) return false;
    _m[e.key] = e;
    onApplied?.call(cur, e);
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
