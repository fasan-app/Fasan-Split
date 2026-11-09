// SPDX-License-Identifier: MPL-2.0
// Fasan Split – padlocks on items and bills (Nutzer 07.11.: „Posten, Rechnungen und Gruppen mit einem Vorhängeschloss vor Änderungen
// sperren“). Everyone in a group may enter for everyone unless somebody locks. A lock holds the public key of whoever set it
// (`meta/lock` on the bill, `lock` inside the item entry `i/<uid>`); only that person or the group admin may change what is locked.
// Notes (`n/`) stay open on a locked bill. The rule is checked on every phone for incoming entries (service `_accept`) and for the
// own writes (BillSync.write); a modified app can ignore it – it protects against slips and well-meaning edits, not against attackers
// (members share one group key). MPL-2.0
import 'lww.dart';

/// Key of the item an entry belongs to (`i/<uid>`, `s/<uid>/<person>`, `f/<uid>/<person>`), else null.
String? itemOfKey(String key) {
  if (key.startsWith('i/')) return key.substring(2);
  if ((key.startsWith('s/') || key.startsWith('f/'))) {
    final parts = key.split('/');
    if (parts.length >= 3) return parts[1];
  }
  return null;
}

/// May [author] write [key] into the bill document [doc]? [adminPub] (the founder of the group) may always.
bool lockAllows(LwwDoc doc, String key, String author, {String? adminPub}) {
  if (adminPub != null && author == adminPub) return true;
  final bill = doc.get('meta/lock');
  if (bill is String && bill.isNotEmpty && bill != author && !key.startsWith('n/')) return false;
  final uid = itemOfKey(key);
  if (uid != null) {
    final item = doc.get('i/$uid');
    final l = item is Map ? item['lock'] : null;
    if (l is String && l.isNotEmpty && l != author) return false;
  }
  return true;
}
