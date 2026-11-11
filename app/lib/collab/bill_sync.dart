// SPDX-License-Identifier: MPL-2.0
// Fasan Split – a Bill as a replicated document. MPL-2.0
//
// Only inputs are stored (names, cents, shares, payer); sums per person are always recomputed on each device with SplitMath.
// People and items are addressed by uid, not by list position, so a person added on one phone does not shift shares on another.
// Local-only things stay local: photo files, scan data, recognition log. The photos travel separately (photo_sync.dart);
// the document only names them (meta/photo, meta/orig) and carries each item's place on the receipt (bx), so every device
// cuts the same line pictures from the shared scan (06.11.: in the browser there were no line pictures and no receipt).
import 'dart:convert' show jsonEncode;

import 'package:fasan_core/bill.dart';
import 'lww.dart';

abstract final class BillSync {
  /// Version of the document layout (Nutzer 08.11.: old phones and tabs wrote whole items without newer fields and spoiled the
  /// bills of everyone). 2 = pieces mode (`pu`), padlocks, boxes. A build that finds a HIGHER number in a document is out of date:
  /// it reads, but never writes. Raise it whenever a change would be lost by an older build; builds before 08.11. know no number.
  static const schema = 2;

  /// Layout version a document was last written with (1 = no number: written by a build before 08.11.).
  static int schemaOf(LwwDoc doc) => (doc.get('meta/schema') as num?)?.toInt() ?? 1;

  /// Writes the differences between [b] and [doc] into [doc] (nothing if equal). Returns true if anything changed.
  ///
  /// [allow] (padlocks, lock_rules.dart): keys it refuses are not written; [onBlocked] then tells the caller, which takes the
  /// locked parts back from the document (`read`), so a locked item or bill never shows a change that nobody else receives.
  static bool write(LwwDoc doc, Bill b, {bool Function(String key)? allow, void Function()? onBlocked}) {
    if (schemaOf(doc) > schema) return false; // this build is older than the document: reading only
    var changed = false;
    if (schemaOf(doc) < schema && doc.set('meta/schema', schema)) changed = true; // bypasses padlocks: it is about the layout, not content
    bool set(String k, Object? v) {
      if (allow != null && !allow(k)) {
        if (jsonEncode(doc.get(k)) != jsonEncode(v)) onBlocked?.call();
        return false;
      }
      final c = doc.set(k, v);
      changed = changed || c;
      return c;
    }

    set('meta/purpose', b.purpose);
    set('meta/total', b.total);
    set('meta/payer', b.payer != null && b.payer! < b.ps.length ? b.ps[b.payer!].uid : null);
    // several payers: person uid → cents (Nutzer 04.11.)
    set('meta/paid', b.paid.isEmpty ? null : {for (final e in b.paid.entries) if (e.key < b.ps.length) b.ps[e.key].uid: e.value});
    set('meta/done', b.done);
    set('meta/settled', b.settled ? true : null);
    set('meta/trashed', b.trashedAt?.millisecondsSinceEpoch);
    set('meta/thumb', b.thumb);
    set('meta/refund', b.refund);
    set('meta/lock', b.lockBy);
    if (b.hidden) set('meta/hidden', true);
    if (b.sums) set('meta/sums', true);
    set('meta/category', b.category); // shared like the other metadata (04.11.)
    set('meta/currency', b.currency);
    set('meta/rate', b.rate);
    set('meta/rateDate', b.rateDate?.millisecondsSinceEpoch);
    set('meta/advance', b.advance);
    set('meta/date', b.receiptDate?.millisecondsSinceEpoch);
    set('meta/place', b.placeAddress);
    set('meta/taxId', b.taxId);
    set('meta/photo', b.photoRef);
    set('meta/orig', b.origRef);

    final puids = {for (final p in b.ps) p.uid};
    for (var i = 0; i < b.ps.length; i++) {
      final p = b.ps[i];
      set('p/${p.uid}', {'name': p.name, 'color': p.color, 'pos': i});
    }
    for (final k in doc.keys('p/').toList()) {
      if (!puids.contains(k.substring(2))) set(k, null); // person removed here
    }

    // notes (Nutzer 04.11.): one entry each, removed ones become empty
    final nids = {for (final n in b.notes) n.id};
    for (final n in b.notes) {
      set('n/${n.id}', n.toJson());
    }
    for (final k in doc.keys('n/').toList()) {
      if (!nids.contains(k.substring(2))) set(k, null);
    }

    final iuids = {for (final it in b.its) it.uid};
    for (var n = 0; n < b.its.length; n++) {
      final it = b.its[n];
      set('i/${it.uid}', {
        'name': it.name,
        'amount': it.amount,
        'qty': it.qty,
        'note': it.note,
        'pos': n,
        if (it.proportional) 'prop': true,
        if (it.perUnit) 'pu': true,
        if (it.lockBy != null) 'lock': it.lockBy,
        // place on the receipt, rounded (4 decimals ≈ 0.1 px on a 1300 px scan)
        if (it.boxes.isNotEmpty) 'bx': [for (final x in it.boxes) [for (final v in x.toJson()) (v * 10000).round() / 10000]],
      });
      for (var i = 0; i < b.ps.length; i++) {
        final w = it.shares[i];
        set('s/${it.uid}/${b.ps[i].uid}', w != null && w > 0 ? w : null);
        set('f/${it.uid}/${b.ps[i].uid}', it.fixed[i]);
        set('sv/${it.uid}/${b.ps[i].uid}', it.maybe[i]);
      }
      // shares of people that no longer exist
      for (final k in doc.keys('s/${it.uid}/').toList()) {
        if (!puids.contains(k.split('/').last)) set(k, null);
      }
      for (final k in doc.keys('f/${it.uid}/').toList()) {
        if (!puids.contains(k.split('/').last)) set(k, null);
      }
      for (final k in doc.keys('sv/${it.uid}/').toList()) {
        if (!puids.contains(k.split('/').last)) set(k, null);
      }
    }
    for (final k in doc.keys('i/').toList()) {
      if (!iuids.contains(k.substring(2))) {
        set(k, null); // item removed here
        for (final s in [...doc.keys('s/${k.substring(2)}/'), ...doc.keys('f/${k.substring(2)}/'), ...doc.keys('sv/${k.substring(2)}/')]) {
          set(s, null);
        }
      }
    }
    return changed;
  }

  /// True if the document holds a bill (at least one fact about it).
  /// The summary of a hidden bill with visible amounts (`sum:<id>`): people, what each owes, who paid, total, state. No item
  /// names, no photo, no notes. Returns true if anything changed.
  static bool writeSummary(LwwDoc doc, Bill b) {
    final pp = b.perPerson();
    final v = <String, Object?>{
      'people': [for (final p in b.ps) {'u': p.uid, 'n': p.name, 'c': p.color}],
      'amounts': {for (final e in pp.entries) if (e.key < b.ps.length && e.value != 0) b.ps[e.key].uid: e.value},
      'total': b.effectiveTotal,
      'payer': b.payer != null && b.payer! < b.ps.length ? b.ps[b.payer!].uid : null,
      'paid': {for (final e in b.paid.entries) if (e.key < b.ps.length) b.ps[e.key].uid: e.value},
      'done': b.done,
      'settled': b.settled,
      'trashed': b.trashedAt?.millisecondsSinceEpoch,
      'date': b.receiptDate?.millisecondsSinceEpoch,
      'currency': b.currency,
      'rate': b.rate,
    };
    return doc.set('s', v);
  }

  static bool hasSummary(LwwDoc doc) => doc.get('s') is Map;

  /// A bill without items made from [writeSummary]: one item per person with what they owe, so balances work as usual.
  static Bill readSummary(LwwDoc doc, {required String id, Bill? into}) {
    final m = (doc.get('s') as Map).cast<String, Object?>();
    final b = into ?? Bill(id: id, created: DateTime.now(), items: [], people: []);
    final ps = [for (final j in (m['people'] as List? ?? const [])) Person((j as Map)['n'] as String, (j['c'] as num).toInt(), uid: j['u'] as String)];
    final idx = {for (final (i, p) in ps.indexed) p.uid: i};
    final amounts = (m['amounts'] as Map? ?? const {}).cast<String, Object?>();
    b.people = ps;
    b.items = [
      for (final e in amounts.entries)
        if (idx[e.key] != null) BillItem(uid: 'sum-${e.key}', name: '', amount: (e.value as num).toInt(), shares: {idx[e.key]!: 1}),
    ];
    b.purpose = '';
    b.total = (m['total'] as num?)?.toInt();
    b.payer = m['payer'] is String ? idx[m['payer']] : null;
    final paid = (m['paid'] as Map? ?? const {});
    b.paid = {for (final e in paid.entries) if (idx['${e.key}'] != null) idx['${e.key}']!: (e.value as num).toInt()};
    b.done = m['done'] == true;
    b.settled = m['settled'] == true;
    b.trashedAt = m['trashed'] is num ? DateTime.fromMillisecondsSinceEpoch((m['trashed'] as num).toInt()) : null;
    b.receiptDate = m['date'] is num ? DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()) : null;
    b.currency = m['currency'] as String?;
    b.rate = (m['rate'] as num?)?.toDouble();
    b.hidden = true;
    b.sums = true;
    b.sumOnly = true;
    return b;
  }

  static bool hasBill(LwwDoc doc) => doc.entries.any((e) => e.value != null);

  /// Applies the document to [into] (or a new bill with [id]). Local-only fields of [into] stay as they are.
  static Bill read(LwwDoc doc, {required String id, Bill? into}) {
    final b = into ?? Bill(id: id, created: DateTime.now(), items: [], people: []);
    final ps = <(int, Person)>[];
    for (final k in doc.keys('p/')) {
      final v = doc.get(k) as Map;
      ps.add(((v['pos'] as num?)?.toInt() ?? 0, Person(v['name'] as String, (v['color'] as num).toInt(), uid: k.substring(2))));
    }
    ps.sort((a, c) => a.$1 != c.$1 ? a.$1.compareTo(c.$1) : a.$2.uid.compareTo(c.$2.uid));
    // keep Person objects we already have (names can change)
    final old = {for (final p in b.ps) p.uid: p};
    b.people = [
      for (final (_, p) in ps)
        if (old[p.uid] != null) (old[p.uid]!..name = p.name) else p
    ];
    final index = {for (var i = 0; i < b.people!.length; i++) b.people![i].uid: i};

    final its = <(int, BillItem)>[];
    final oldItems = {for (final it in b.its) it.uid: it};
    for (final k in doc.keys('i/')) {
      final uid = k.substring(2);
      final v = doc.get(k) as Map;
      final it = oldItems[uid] ?? BillItem(uid: uid, name: '', amount: 0);
      it
        ..name = v['name'] as String? ?? ''
        ..amount = (v['amount'] as num?)?.toInt() ?? 0
        ..qty = (v['qty'] as num?)?.toInt() ?? 1
        ..note = v['note'] as String?
        ..proportional = v['prop'] == true
        ..perUnit = v['pu'] == true
        ..lockBy = v['lock'] as String?;
      if (v['bx'] case final List bx when it.boxes.isEmpty) it.boxes = bx.map(NBox.fromJson).whereType<NBox>().toList();
      final shares = <int, double>{};
      for (final sk in doc.keys('s/$uid/')) {
        final pi = index[sk.split('/').last];
        final w = doc.get(sk);
        if (pi != null && w is num && w > 0) shares[pi] = w.toDouble();
      }
      it.shares = shares;
      final fixed = <int, int>{};
      for (final fk in doc.keys('f/$uid/')) {
        final pi = index[fk.split('/').last];
        final c = doc.get(fk);
        if (pi != null && c is num) fixed[pi] = c.toInt();
      }
      it.fixed = fixed;
      final maybe = <int, String>{};
      for (final mk in doc.keys('sv/$uid/')) {
        final pi = index[mk.split('/').last];
        final who = doc.get(mk);
        if (pi != null && who is String) maybe[pi] = who;
      }
      it.maybe = maybe;
      its.add(((v['pos'] as num?)?.toInt() ?? 0, it));
    }
    its.sort((a, c) => a.$1 != c.$1 ? a.$1.compareTo(c.$1) : a.$2.uid.compareTo(c.$2.uid));
    b.items = [for (final (_, it) in its) it];

    final purpose = doc.get('meta/purpose');
    if (purpose is String) b.purpose = purpose;
    b.total = (doc.get('meta/total') as num?)?.toInt();
    final payer = doc.get('meta/payer');
    b.payer = payer is String ? index[payer] : null;
    final paid = doc.get('meta/paid');
    b.paid = paid is Map ? {for (final e in paid.entries) if (index['${e.key}'] != null) index['${e.key}']!: (e.value as num).toInt()} : {};
    b.done = doc.get('meta/done') == true;
    b.settled = doc.get('meta/settled') == true;
    if (doc.get('meta/thumb') case final String th) b.thumb = th;
    b.notes = [
      for (final k in doc.keys('n/'))
        if (doc.get(k) case final Map m) BillNote.fromJson(m.cast<String, Object?>()),
    ]..sort((x, y) => x.at.compareTo(y.at));
    final tr = doc.get('meta/trashed');
    b.trashedAt = tr is num ? DateTime.fromMillisecondsSinceEpoch(tr.toInt()) : null;
    b.refund = doc.get('meta/refund') == true;
    b.category = doc.get('meta/category') as String?;
    b.lockBy = doc.get('meta/lock') as String?;
    if (doc.get('meta/hidden') == true) b.hidden = true;
    if (doc.get('meta/sums') == true) b.sums = true;
    b.sumOnly = false; // a full document replaces a summary copy
    b.currency = doc.get('meta/currency') as String?;
    b.rate = (doc.get('meta/rate') as num?)?.toDouble();
    b.rateDate = switch (doc.get('meta/rateDate')) { final num t => DateTime.fromMillisecondsSinceEpoch(t.toInt()), _ => null };
    b.advance = (doc.get('meta/advance') as num?)?.toInt() ?? 0;
    final date = doc.get('meta/date');
    b.receiptDate = date is num ? DateTime.fromMillisecondsSinceEpoch(date.toInt()) : null;
    b.placeAddress = doc.get('meta/place') as String?;
    b.taxId = doc.get('meta/taxId') as String?;
    if (doc.get('meta/photo') case final Map m) b.photoRef = m.cast<String, Object?>();
    if (doc.get('meta/orig') case final Map m) b.origRef = m.cast<String, Object?>();
    b.updated = DateTime.now();
    return b;
  }
}
