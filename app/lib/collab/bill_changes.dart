// SPDX-License-Identifier: MPL-2.0
// Fasan Split – what exactly changed in a shared bill (Nutzer 07.11.: „Ich bekomme nur die Benachrichtigung, dass jemand etwas
// geändert hat, aber nicht was“). The bill documents keep only the newest value per key, so the change log is built while
// entries arrive: each applied entry comes with the entry it replaced (LwwDoc.onApplied). Here such pairs become sentences,
// and a burst (many entries of one edit) becomes one record. MPL-2.0
import 'dart:convert';

import 'package:fasan_core/bill.dart' show money;

import 'lww.dart';

/// One line of a record, German and English.
class ChangeLine {
  const ChangeLine(this.de, this.en, {this.item});
  final String de, en;

  /// uid of the item the line is about (the history opens the bill at that item), null otherwise.
  final String? item;
  String text(bool german) => german ? de : en;
}

/// One value of a bill document that a change replaced: with it the change can be taken back (Nutzer 12.11.: Saldo-Verlauf,
/// „rückgängig machbar“). [old] is what the key held before (null = it was new), [now] what the change wrote.
class UndoOp {
  const UndoOp(this.key, this.old, this.now);
  final String key;
  final Object? old, now;

  List<Object?> toJson() => [key, old, now];
  static UndoOp fromJson(Object? j) => UndoOp((j as List)[0] as String, j[1], j[2]);
}

/// Keys that are never kept for taking back: big blobs (photo, thumbnail) – the change is listed, but not revertible through them.
bool undoable(String key) => !(key == 'meta/thumb' || key == 'meta/photo' || key == 'meta/orig' || key.startsWith('meta/schema'));

/// Puts the old values of [ops] back into [doc] (as new changes of this device). A key that was changed again since is left
/// alone: it is returned in the list of skipped keys, so the caller can say „seitdem weiter geändert“. [allow] is the padlock rule.
List<String> applyUndo(LwwDoc doc, List<UndoOp> ops, {bool Function(String key)? allow}) {
  final skipped = <String>[];
  for (final o in ops) {
    if (jsonEncode(doc.get(o.key)) != jsonEncode(o.now)) {
      skipped.add(o.key);
      continue;
    }
    if (allow != null && !allow(o.key)) {
      skipped.add(o.key);
      continue;
    }
    doc.set(o.key, o.old);
  }
  return skipped;
}

/// What one person changed in one bill in one go.
class ChangeRecord {
  ChangeRecord({required this.at, required this.group, required this.billId, required this.title, required this.who, required this.whoKey, required this.lines, this.app, DateTime? rcvAt, this.undo = const []}) : rcvAt = rcvAt ?? DateTime.now();

  /// When the change reached this phone (the writer's [at] can be hours older when they were offline): the balance history
  /// matches a change of my balance to the records that arrived since it last looked.
  final DateTime rcvAt;

  /// The replaced values, empty if the change cannot be taken back (too big, or nothing recorded).
  final List<UndoOp> undo;

  final DateTime at;
  final String group; // group tag
  final String billId;
  final String title; // bill name when it happened
  final String who; // display name when it happened
  final String whoKey; // public key of the author
  final List<ChangeLine> lines;

  /// Version of the device that made the change (Entry.app), null if unknown.
  final String? app;

  Map<String, Object?> toJson() => {
        if (app != null) 'a': app,
        't': at.millisecondsSinceEpoch,
        'g': group,
        'b': billId,
        'n': title,
        'w': who,
        'k': whoKey,
        'rv': rcvAt.millisecondsSinceEpoch,
        if (undo.isNotEmpty) 'u': [for (final o in undo) o.toJson()],
        'l': [for (final l in lines) [l.de, l.en, if (l.item != null) l.item]],
      };

  static ChangeRecord? fromJson(Object? j) {
    try {
      final m = (j as Map).cast<String, Object?>();
      return ChangeRecord(
        at: DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()),
        group: m['g'] as String,
        billId: m['b'] as String,
        title: m['n'] as String,
        who: m['w'] as String,
        whoKey: m['k'] as String,
        lines: [for (final l in m['l'] as List) ChangeLine((l as List)[0] as String, l[1] as String, item: l.length > 2 ? l[2] as String? : null)],
        app: m['a'] as String?,
        rcvAt: m['rv'] == null ? null : DateTime.fromMillisecondsSinceEpoch((m['rv'] as num).toInt()),
        undo: [for (final u in (m['u'] as List?) ?? const []) UndoOp.fromJson(u)],
      );
    } catch (_) {
      return null;
    }
  }

  static String encode(List<ChangeRecord> l) => jsonEncode([for (final r in l) r.toJson()]);
  static List<ChangeRecord> decode(String? s) {
    try {
      return [for (final j in jsonDecode(s ?? '[]') as List) ?ChangeRecord.fromJson(j)];
    } catch (_) {
      return [];
    }
  }
}

/// An entry that took effect: [old] is what it replaced (null = the key was new).
typedef EntryChange = (Entry? old, Entry now);

String _num(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

/// Sentences for [changes] of the bill document [doc] (state after the changes).
List<ChangeLine> describeChanges(LwwDoc doc, List<EntryChange> changes) {
  String person(String puid) => (doc.get('p/$puid') as Map?)?['name'] as String? ?? '?';
  Map? itemOf(String uid) => doc.get('i/$uid') as Map?;
  String itemName(String uid, [Map? old]) => (itemOf(uid)?['name'] ?? old?['name'] ?? '?') as String;
  String m(int c) => money(c);
  final out = <ChangeLine>[];
  final seen = <String>{};
  String? ref; // item uid of the entry being described
  void add(String de, String en) {
    if (seen.add(de)) out.add(ChangeLine(de, en, item: ref));
  }

  // item rows first, so that „new item“ comes before who put themselves on it
  final sorted = [...changes]..sort((a, b) => _rank(a.$2.key).compareTo(_rank(b.$2.key)));
  for (final (old, now) in sorted) {
    final k = now.key;
    final parts = k.split('/');
    final nv = now.value, ov = old?.value;
    // no change, no line (Nutzer 11.11.: „Summe 86,90 → 86,90“, „Datum geändert“ without a difference)
    if (jsonEncode(ov) == jsonEncode(nv)) continue;
    ref = (parts.first == 'i' || parts.first == 's' || parts.first == 'f') && parts.length > 1 ? parts[1] : null;
    switch (parts.first) {
      case 'i':
        final o = ov is Map ? ov : null, n = nv is Map ? nv : null;
        if (n != null && o == null) {
          final q = (n['qty'] as num?)?.toInt() ?? 1;
          add('Posten „${n['name']}“ hinzugefügt (${q > 1 ? '$q × ' : ''}${m((n['amount'] as num).toInt())})', 'Item “${n['name']}” added (${q > 1 ? '$q × ' : ''}${money((n['amount'] as num).toInt(), de: false)})');
        } else if (n == null && o != null) {
          add('Posten „${o['name']}“ entfernt', 'Item “${o['name']}” removed');
        } else if (n != null && o != null) {
          final name = n['name'] as String;
          if (o['name'] != n['name']) add('Posten „${o['name']}“ heißt jetzt „$name“', 'Item “${o['name']}” is now called “$name”');
          if (o['qty'] != n['qty']) add('$name: Menge ${o['qty'] ?? 1} → ${n['qty'] ?? 1}', '$name: quantity ${o['qty'] ?? 1} → ${n['qty'] ?? 1}');
          if (o['amount'] != n['amount']) {
            add('$name: Betrag ${m((o['amount'] as num).toInt())} → ${m((n['amount'] as num).toInt())}', '$name: amount ${money((o['amount'] as num).toInt(), de: false)} → ${money((n['amount'] as num).toInt(), de: false)}');
          }
        }
      case 's':
        if (parts.length < 3) break;
        final it = itemOf(parts[1]);
        if (it == null) break; // item gone: its shares go with it
        final item = it['name'] as String, who = person(parts[2]);
        final per = it['pu'] == true;
        final ow = ov is num && ov > 0 ? ov : null, nw = nv is num && nv > 0 ? nv : null;
        if (nw != null && ow == null) {
          add('$who bei „$item“ eingetragen${per ? ' (${_num(nw)} Stück)' : ''}', '$who added to “$item”${per ? ' (${_num(nw)} pcs)' : ''}');
        } else if (nw == null && ow != null) {
          add('$who bei „$item“ ausgetragen', '$who removed from “$item”');
        } else if (nw != null && ow != null && nw != ow) {
          add(per ? '$who bei „$item“: ${_num(ow)} → ${_num(nw)} Stück' : 'Anteil von $who bei „$item“ geändert', per ? '$who on “$item”: ${_num(ow)} → ${_num(nw)} pcs' : '$who’s share of “$item” changed');
        }
      case 'f':
        if (parts.length < 3 || itemOf(parts[1]) == null) break;
        final item = itemName(parts[1]), who = person(parts[2]);
        if (nv is num) {
          add('$who zahlt bei „$item“ fest ${m(nv.toInt())}', '$who pays a fixed ${money(nv.toInt(), de: false)} on “$item”');
        } else if (ov is num) {
          add('Festbetrag von $who bei „$item“ entfernt', 'Fixed amount of $who on “$item” removed');
        }
      case 'p':
        final o = ov is Map ? ov : null, n = nv is Map ? nv : null;
        if (n != null && o == null) {
          add('Person „${n['name']}“ hinzugefügt', 'Person “${n['name']}” added');
        } else if (n == null && o != null) {
          add('Person „${o['name']}“ entfernt', 'Person “${o['name']}” removed');
        } else if (n != null && o != null && o['name'] != n['name']) {
          add('Person „${o['name']}“ heißt jetzt „${n['name']}“', 'Person “${o['name']}” is now called “${n['name']}”');
        }
      case 'n':
        if (nv != null && ov == null) add('Notiz hinzugefügt', 'Note added');
      case 'meta':
        final f = parts.length > 1 ? parts[1] : '';
        switch (f) {
          case 'total':
            if (nv is num) add(ov is num ? 'Summe ${m(ov.toInt())} → ${m(nv.toInt())}' : 'Summe ${m(nv.toInt())} festgelegt', ov is num ? 'Total ${money(ov.toInt(), de: false)} → ${money(nv.toInt(), de: false)}' : 'Total set to ${money(nv.toInt(), de: false)}');
          case 'payer':
            if (nv is String) add('Bezahlt hat ${person(nv)}', 'Paid by ${person(nv)}');
            if (nv == null && ov != null) add('Zahler entfernt', 'Payer removed');
          case 'paid':
            add('Gezahlte Beträge geändert', 'Paid amounts changed');
          case 'done':
            if (nv == true) add('als fertig markiert', 'marked as done');
            if (nv != true && ov == true) add('wieder geöffnet', 'reopened');
          case 'settled':
            if (nv == true) add('als beglichen markiert', 'marked as settled');
            if (nv != true && ov == true) add('Begleichen zurückgenommen', 'settlement undone');
          case 'trashed':
            add(nv != null ? 'in den Papierkorb gelegt' : 'aus dem Papierkorb geholt', nv != null ? 'moved to the trash' : 'restored from the trash');
          case 'purpose':
            if (nv is String && nv.isNotEmpty) add(ov is String && ov.isNotEmpty ? 'Name „$ov“ → „$nv“' : 'Name „$nv“ vergeben', ov is String && ov.isNotEmpty ? 'Name “$ov” → “$nv”' : 'Named “$nv”');
          case 'refund':
            if ((ov == true) == (nv == true)) break;
            add(nv == true ? 'als Rückerstattung markiert' : 'Rückerstattung zurückgenommen', nv == true ? 'marked as refund' : 'refund undone');
          case 'currency':
            if (nv is String) add('Währung $nv', 'Currency $nv');
          case 'category':
            add('Kategorie geändert', 'Category changed');
          case 'date':
            add('Datum geändert', 'Date changed');
        }
    }
  }
  return out;
}

int _rank(String k) => k.startsWith('i/') ? 0 : k.startsWith('p/') ? 1 : 2;
