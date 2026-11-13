// SPDX-License-Identifier: MPL-2.0
// Fasan Split – the amount history of a person, shared on request (Paket 7, 13.11.; docs/KONZEPT-VERLAUF.md). MPL-2.0
part of 'service.dart';

/// One line of somebody's shared history: when, which bill, how much their balance moved.
typedef SharedHistoryLine = ({DateTime at, String title, int delta});

extension CollabServiceHistory on CollabService {
  /// Whether I show my balance history to the members of my groups (default off, an agreement between the people, no technical lock).
  bool get shareHistory => prefs?.getBool(CollabService._kShareHistory) ?? false;

  set shareHistory(bool v) {
    prefs?.setBool(CollabService._kShareHistory, v);
    for (final g in groups.values) {
      _publishHistory(g);
    }
    _notify();
  }

  /// Writes (or withdraws) my history into my profile of [g]: only bookings of this group, never of hidden bills, newest 50.
  void _publishHistory(CollabGroup g) {
    final me = identity;
    if (me == null || g.secret.direct) return;
    final id = GroupSession.profile(me.pub);
    final hiddenIds = {for (final b in store.bills) if (b.hidden) b.id};
    final lines = shareHistory
        ? [
            for (final e in ledger.entries.reversed)
              if (e.group == g.localName && !hiddenIds.contains(e.billId)) {'t': e.at.millisecondsSinceEpoch, 'n': e.title, 'd': e.delta},
          ].take(50).toList()
        : null;
    if (jsonEncode(g.session.doc(id).get('hist')) == jsonEncode(lines)) return;
    g.session.doc(id).set('hist', lines);
    g.session.touch(id);
  }

  void _publishHistoryAll() {
    if (!shareHistory) return;
    for (final g in groups.values) {
      _publishHistory(g);
    }
  }

  /// What [pub] shows of their history in [g], or null when they do not share it.
  List<SharedHistoryLine>? historyOf(CollabGroup g, String pub) {
    final v = g.session.doc(GroupSession.profile(pub)).get('hist');
    if (v is! List) return null;
    return [
      for (final m in v)
        if (m is Map) (at: DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()), title: '${m['n']}', delta: (m['d'] as num).toInt()),
    ];
  }
}
