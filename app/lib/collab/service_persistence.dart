// SPDX-License-Identifier: MPL-2.0
// Fasan Split – CollabService, part: Persistence. Split out of service.dart (13.11., Umbau U3, behaviour unchanged): the fields
// and constants stay in the class, these are its methods as an extension in the same library. MPL-2.0
part of 'service.dart';

extension CollabServicePersistence on CollabService {

  // ---- persistence ----

  Future<void> _persistGroups() async {
    await vault.write(CollabService._kGroups, jsonEncode([for (final g in groups.values) {'secret': g.secret.toJson(), 'local': g.localName}]));
    unawaited(syncAccount()); // the same list, encrypted to myself, for other devices and reinstalls
  }

  void _saveJoins() => prefs?.setString(CollabService._kJoins, jsonEncode([for (final p in joins) {'code': p.invite.encode(), 'name': p.name, 'since': p.since.toIso8601String()}]));

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), saveDocs);
  }

  /// Writes every document of every group to the phone (so the app starts with everything, offline).
  void saveDocs() {
    for (final g in groups.values) {
      for (final id in g.session.docIds) {
        prefs?.setString('${CollabService._kDocs}${g.secret.tag}.$id', g.session.doc(id).encode());
      }
      prefs?.setStringList('${CollabService._kDocs}${g.secret.tag}.ids', g.session.docIds.toList());
    }
  }

  /// Writes one document to the phone now.
  void _saveDoc(CollabGroup g, String id) => prefs?.setString('${CollabService._kDocs}${g.secret.tag}.$id', g.session.doc(id).encode());

  /// After the documents of a group came back from the disk: the DOCUMENT is the shared truth, the bill in the store is only its
  /// copy. Without this the first change in the store made the phone compare its (possibly older) bills with the documents and
  /// write every difference as „its own change“ with a newer clock – posts back to raw names, quantities to 1, people gone, for
  /// everybody (Nutzer 08.11. 10:56 and 11:58; test/stale_store_test.dart). Bills whose document is empty stay as they are:
  /// nothing was ever shared for them, so the local bill is the source.
  void _adoptDocs(CollabGroup g) {
    for (final b in store.bills) {
      if (b.group != g.localName) continue;
      final doc = g.session.doc(GroupSession.bill(b.id));
      if (!BillSync.hasBill(doc)) continue;
      BillSync.read(doc, id: b.id, into: b);
      b.group = g.localName;
    }
    store.upsertAll();
  }

  void _restoreDocs(CollabGroup g) {
    for (final id in prefs?.getStringList('${CollabService._kDocs}${g.secret.tag}.ids') ?? const <String>[]) {
      final raw = prefs?.getString('${CollabService._kDocs}${g.secret.tag}.$id');
      if (raw == null) continue;
      try {
        g.session.doc(id).merge(LwwDocDecode.decode(raw));
      } catch (_) {}
    }
    g.session.absorbKeys(); // keys of hidden bills
  }
}
