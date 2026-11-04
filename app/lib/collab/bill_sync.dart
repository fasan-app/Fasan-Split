// Fasan Split – a Bill as a replicated document. MPL-2.0
//
// Only inputs are stored (names, cents, shares, payer); sums per person are always recomputed on each device with SplitMath.
// People and items are addressed by uid, not by list position, so a person added on one phone does not shift shares on another.
// Local-only things stay local: photo, scan data, recognition log.
import '../model/bill.dart';
import 'lww.dart';

abstract final class BillSync {
  /// Writes the differences between [b] and [doc] into [doc] (nothing if equal). Returns true if anything changed.
  static bool write(LwwDoc doc, Bill b) {
    var changed = false;
    bool set(String k, Object? v) {
      final c = doc.set(k, v);
      changed = changed || c;
      return c;
    }

    set('meta/purpose', b.purpose);
    set('meta/total', b.total);
    set('meta/payer', b.payer != null && b.payer! < b.ps.length ? b.ps[b.payer!].uid : null);
    set('meta/done', b.done);
    set('meta/settled', b.settled ? true : null);
    set('meta/refund', b.refund);
    set('meta/category', b.category); // shared like the other metadata (04.11.)
    set('meta/currency', b.currency);
    set('meta/rate', b.rate);
    set('meta/rateDate', b.rateDate?.millisecondsSinceEpoch);
    set('meta/advance', b.advance);
    set('meta/date', b.receiptDate?.millisecondsSinceEpoch);
    set('meta/place', b.placeAddress);
    set('meta/taxId', b.taxId);

    final puids = {for (final p in b.ps) p.uid};
    for (var i = 0; i < b.ps.length; i++) {
      final p = b.ps[i];
      set('p/${p.uid}', {'name': p.name, 'color': p.color, 'pos': i});
    }
    for (final k in doc.keys('p/').toList()) {
      if (!puids.contains(k.substring(2))) set(k, null); // person removed here
    }

    final iuids = {for (final it in b.its) it.uid};
    for (var n = 0; n < b.its.length; n++) {
      final it = b.its[n];
      set('i/${it.uid}', {'name': it.name, 'amount': it.amount, 'qty': it.qty, 'note': it.note, 'pos': n, if (it.proportional) 'prop': true});
      for (var i = 0; i < b.ps.length; i++) {
        final w = it.shares[i];
        set('s/${it.uid}/${b.ps[i].uid}', w != null && w > 0 ? w : null);
      }
      // shares of people that no longer exist
      for (final k in doc.keys('s/${it.uid}/').toList()) {
        if (!puids.contains(k.split('/').last)) set(k, null);
      }
    }
    for (final k in doc.keys('i/').toList()) {
      if (!iuids.contains(k.substring(2))) {
        set(k, null); // item removed here
        for (final s in doc.keys('s/${k.substring(2)}/').toList()) {
          set(s, null);
        }
      }
    }
    return changed;
  }

  /// True if the document holds a bill (at least one fact about it).
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
        ..proportional = v['prop'] == true;
      final shares = <int, double>{};
      for (final sk in doc.keys('s/$uid/')) {
        final pi = index[sk.split('/').last];
        final w = doc.get(sk);
        if (pi != null && w is num && w > 0) shares[pi] = w.toDouble();
      }
      it.shares = shares;
      its.add(((v['pos'] as num?)?.toInt() ?? 0, it));
    }
    its.sort((a, c) => a.$1 != c.$1 ? a.$1.compareTo(c.$1) : a.$2.uid.compareTo(c.$2.uid));
    b.items = [for (final (_, it) in its) it];

    final purpose = doc.get('meta/purpose');
    if (purpose is String) b.purpose = purpose;
    b.total = (doc.get('meta/total') as num?)?.toInt();
    final payer = doc.get('meta/payer');
    b.payer = payer is String ? index[payer] : null;
    b.done = doc.get('meta/done') == true;
    b.settled = doc.get('meta/settled') == true;
    b.refund = doc.get('meta/refund') == true;
    b.category = doc.get('meta/category') as String?;
    b.currency = doc.get('meta/currency') as String?;
    b.rate = (doc.get('meta/rate') as num?)?.toDouble();
    b.rateDate = switch (doc.get('meta/rateDate')) { final num t => DateTime.fromMillisecondsSinceEpoch(t.toInt()), _ => null };
    b.advance = (doc.get('meta/advance') as num?)?.toInt() ?? 0;
    final date = doc.get('meta/date');
    b.receiptDate = date is num ? DateTime.fromMillisecondsSinceEpoch(date.toInt()) : null;
    b.placeAddress = doc.get('meta/place') as String?;
    b.taxId = doc.get('meta/taxId') as String?;
    b.updated = DateTime.now();
    return b;
  }
}
