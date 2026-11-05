// Fasan Split – saved bills and settings (shared_preferences; images and logs as files in the app folder). MPL-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/category.dart';
import '../model/settle.dart';
import '../model/bill.dart';
import 'images.dart';

class BillStore extends ChangeNotifier {
  BillStore(this._prefs);

  final SharedPreferences? _prefs;
  final List<Bill> bills = [];

  static const _key = 'bills.v1';

  static Future<BillStore> load() async {
    final p = await SharedPreferences.getInstance();
    await initImages();
    final s = BillStore(p);
    s._loadApp();
    try {
      final raw = p.getString(_key);
      if (raw != null) {
        for (final j in jsonDecode(raw) as List) {
          final b = Bill.fromJson((j as Map).cast<String, dynamic>());
          // a photo still waiting or being read when the app was closed: it has to be read again (nothing is lost, the photo is saved)
          if (b.read == BillRead.queued || b.read == BillRead.reading) b.read = BillRead.failed;
          s.bills.add(b);
        }
      }
    } catch (_) {/* damaged data: start empty, never crash */}
    s.purgeTrash();
    s.migrateCategories();
    return s;
  }

  /// In-memory store for tests and screenshots.
  static BillStore memory([List<Bill> bills = const []]) => BillStore(null)..bills.addAll(bills);

  String? get settingsJson => _prefs?.getString('fasan_ui.settings');

  // ---- Split settings (docs/recherche/2026-11-02-einstellungen.md): few, with defaults for most people ----
  Map<String, Object?> _app = {};
  void _loadApp() {
    try {
      _app = (jsonDecode(_prefs?.getString('split.settings') ?? '{}') as Map).cast<String, Object?>();
    } catch (_) {
      _app = {};
    }
    BillItem.plainNames = plainNames;
  }

  void _setApp(String k, Object? v) {
    _app[k] = v;
    _prefs?.setString('split.settings', jsonEncode(_app));
    BillItem.plainNames = plainNames;
    notifyListeners();
  }

  /// Who uses this phone (shown first in „Wer war dabei?“); empty = not set.
  String get me => _app['me'] as String? ?? '';
  set me(String v) => _setApp('me', v.trim());

  /// Plain German names with symbol for items (Karte 3.8). Default on.
  bool get plainNames => _app['plainNames'] as bool? ?? true;
  set plainNames(bool v) => _setApp('plainNames', v);

  /// Receipt layer shown first: 'scan' or 'original'.
  String get receiptLayer => _app['receiptLayer'] as String? ?? 'scan';
  set receiptLayer(String v) => _setApp('receiptLayer', v);

  /// Look for a new version once a day (talks to api.github.com). Default on (Nutzer 02.11.: Updates in der App).
  bool get autoUpdate => _app['autoUpdate'] as bool? ?? true;
  set autoUpdate(bool v) => _setApp('autoUpdate', v);

  DateTime? get lastUpdateCheck => DateTime.tryParse(_app['lastUpdateCheck'] as String? ?? '');
  set lastUpdateCheck(DateTime? v) => _setApp('lastUpdateCheck', v?.toIso8601String());

  /// The introduction was seen or skipped.
  /// Hints that were closed (ids). „Hinweise wieder zeigen“ in the settings clears them.
  List<String> get _hints => ((_app['hints'] as List?) ?? const []).cast<String>();
  bool hintDone(String id) => _hints.contains(id);
  void hintDismiss(String id) {
    if (!hintDone(id)) _setApp('hints', [..._hints, id]);
  }

  void resetHints() => _setApp('hints', <String>[]);

  bool get onboarded => _app['onboarded'] as bool? ?? false;
  set onboarded(bool v) => _setApp('onboarded', v);

  /// Names the user removed from the suggestions.
  Set<String> get forgotten => {...?(_app['forgotten'] as List?)?.cast<String>()};
  void forget(String name) => _setApp('forgotten', [...forgotten, name]);

  /// Everything as one JSON document (bills, settings; photos stay files) for „Alles exportieren“.
  String exportJson() => const JsonEncoder.withIndent(' ').convert({
        'app': 'app.fasan.split',
        'version': 1,
        'exportiert': DateTime.now().toIso8601String(),
        'einstellungen': _app,
        'rechnungen': [for (final b in bills) b.toJson()],
      });

  /// Deletes all bills and their files (after confirmation in the UI).
  void removeAll() {
    for (final b in [...bills]) {
      remove(b);
    }
  }

  /// Deletes only the photos, bills stay (Bon-Ansicht then shows the digital receipt).
  int removePhotos() {
    var n = 0;
    for (final b in bills) {
      for (final f in [b.imagePath, b.originalPath]) {
        if (f != null) {
          try {
            deleteImage(f);
            n++;
          } catch (_) {}
        }
      }
      b.imagePath = null;
      b.originalPath = null;
    }
    _persist();
    return n;
  }
  void saveSettings(String s) => _prefs?.setString('fasan_ui.settings', s);

  /// Language of the app: 'system' (follows the phone or browser), 'de' or 'en' (Nutzer 05.11.: a switch in the settings).
  String get language => const ['de', 'en'].contains(_app['language']) ? _app['language'] as String : 'system';
  set language(String v) => _setApp('language', const ['de', 'en'].contains(v) ? v : 'system');

  /// Home currency (ISO code): balances across bills are in it; a bill in another currency has its own rate.
  String get homeCurrency => _app['currency'] as String? ?? 'EUR';
  set homeCurrency(String c) => _setApp('currency', c);

  /// Read exchange rates from the ECB (state/rates.dart); off = enter rates by hand.
  bool get ratesOnline => _app['ratesOnline'] as bool? ?? true;
  set ratesOnline(bool v) => _setApp('ratesOnline', v);

  // ---- backup reminder (Nutzer 04.11.: weekly or after many changes) ----

  DateTime? get lastBackup => DateTime.tryParse(_app['lastBackup'] as String? ?? '');
  int get changesSinceBackup => (_app['changes'] as num?)?.toInt() ?? 0;
  DateTime? get backupHintSnoozed => DateTime.tryParse(_app['backupSnooze'] as String? ?? '');

  /// Counted without notifying (upsert notifies anyway); written with the next settings write or bill write.
  void _changed() => _app['changes'] = changesSinceBackup + 1;

  void backupDone() {
    _app['changes'] = 0;
    _setApp('lastBackup', DateTime.now().toIso8601String());
  }

  void snoozeBackupHint() => _setApp('backupSnooze', DateTime.now().toIso8601String());

  /// True when it is time to suggest a backup: a few receipts and either never saved after 10 changes, a week since the
  /// last backup with changes, or 40 changes. Not again within 3 days after „Später“.
  bool get backupDue {
    final real = bills.where((b) => b.trashedAt == null).length;
    if (real < 3) return false;
    final now = DateTime.now(), s = backupHintSnoozed;
    if (s != null && now.difference(s).inDays < 3) return false;
    final c = changesSinceBackup, last = lastBackup;
    if (last == null) return c >= 10;
    return c >= 40 || (c > 0 && now.difference(last).inDays >= 7);
  }

  /// Bills from before categories (0.1.41 and older) get the guess once, like new scans (Nutzer 04.11.: new features
  /// must reach existing bills). Never overwrites a category the user chose or cleared later.
  void migrateCategories() {
    if (_app['catMigrated'] == true) return;
    for (final b in bills) {
      b.category ??= guessCategory(b);
    }
    _app['catMigrated'] = true;
    _write();
    _setApp('catMigrated', true);
  }

  /// „Fokus“ and „Karten“ in Zuordnen (off by default, Nutzer 04.11.).
  bool get assignExtraModes => _app['assignExtra'] == true;
  set assignExtraModes(bool v) => _setApp('assignExtra', v);

  /// Bills in the trash that still carry [name] (shown when removing a name).
  int trashedWith(String name) => bills.where((b) => b.trashedAt != null && b.ps.any((p) => p.name == name)).length;

  /// Own categories (names), model/category.dart.
  List<String> get customCategories => [...?(_app['categories'] as List?)?.cast<String>()];
  void addCategory(String name) {
    if (name.isEmpty || customCategories.contains(name)) return;
    _setApp('categories', [...customCategories, name]);
  }

  /// App settings as stored (backup.dart).
  Map<String, Object?> get appSettings => Map.of(_app);
  set appSettings(Map<String, Object?> m) {
    _app = Map.of(m);
    _prefs?.setString('split.settings', jsonEncode(_app));
    BillItem.plainNames = plainNames;
    notifyListeners();
  }

  /// Saves and shows bills that were added to [bills] directly (backup.dart).
  void upsertAll() => _persist();

  /// Names of people from earlier bills (most recent first).
  List<String> get recentNames {
    final out = <String>[];
    final gone = forgotten;
    if (me.isNotEmpty) out.add(me);
    for (final b in bills.reversed) {
      if (b.trashedAt != null) continue; // trash does not suggest names
      for (final p in b.ps) {
        if (!out.contains(p.name) && !gone.contains(p.name)) out.add(p.name);
      }
    }
    return out.take(12).toList();
  }

  Timer? _debounce;

  /// Saves after every change, debounced (Beschluss Karte 3.9: angefangene Rechnungen nach jeder Änderung speichern).
  void touch(Bill b) {
    b.updated = DateTime.now();
    final i = bills.indexWhere((x) => x.id == b.id);
    if (i < 0) bills.add(b);
    // no notifyListeners here: screens that read the store would rebuild and save again, forever.
    // Listeners hear about it on upsert (leaving a step, „Speichern“, „Fertig“).
    _debounce?.cancel();
    if (_prefs != null) _debounce = Timer(const Duration(milliseconds: 400), () => _write());
  }

  /// Visible = not in the trash.
  bool _show(Bill b) => b.trashedAt == null;

  bool _real(Bill b) => b.done || b.read != BillRead.ok || b.its.isNotEmpty || b.total != null || b.ps.isNotEmpty;

  /// Offen: in progress and entered but not settled yet (Nutzer 04.11.: the archive is only for paid-back bills).
  List<Bill> get drafts => [for (final b in bills) if (_show(b) && !b.settled && _real(b)) b]..sort((a, b) => b.updated.compareTo(a.updated));

  /// Archive: bills settled (paid back), Nutzer 04.11.
  List<Bill> get finished => [for (final b in bills) if (_show(b) && b.settled) b]..sort((a, b) => b.created.compareTo(a.created));

  /// Trash, most recently deleted first.
  List<Bill> get trashed => [for (final b in bills) if (b.trashedAt != null) b]..sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!));

  /// Visible bills of one group (null = without group), newest first; [done] picks entered (true) or unfinished (false)
  /// bills, [archived] the archive (settled, true) or the Offen list (false); null = both.
  List<Bill> inGroup(String? g, {bool? done, bool? archived}) => [
        for (final b in bills)
          if (_show(b) && b.group == g && _real(b) && (done == null || b.done == done) && (archived == null || b.settled == archived)) b
      ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));

  /// Groups created by hand (they exist without bills) and friends added by hand.
  List<String> get _extraGroups => [...?(_app['groupsExtra'] as List?)?.cast<String>()];
  List<String> get _extraFriends => [...?(_app['friendsExtra'] as List?)?.cast<String>()];

  /// Groups with and without bills, alphabetical.
  List<String> get allGroups => ({...groups, ..._extraGroups}.toList()..sort());

  void addGroup(String name) {
    final n = name.trim();
    if (n.isEmpty || allGroups.contains(n)) return;
    _setApp('groupsExtra', [..._extraGroups, n]);
  }

  /// Members added by hand per group (a group can exist before its first bill). Stored as {group: [names]}.
  Map<String, List<String>> get _groupMembers => {
        for (final e in ((_app['groupMembers'] as Map?) ?? const {}).entries) e.key as String: [...(e.value as List).cast<String>()]
      };

  /// People of a group: the ones added by hand first, then everyone from its bills. Forgotten people are left out.
  List<String> groupMembers(String group) {
    final gone = forgotten;
    final out = <String>[...?_groupMembers[group]];
    for (final b in inGroup(group)) {
      for (final p in b.ps) {
        if (!out.contains(p.name)) out.add(p.name);
      }
    }
    return out.where((n) => !gone.contains(n)).toList();
  }

  /// True when [person] was added to [group] by hand (only those can be taken out again; people from bills stay).
  bool isHandMember(String group, String person) => _groupMembers[group]?.contains(person) ?? false;

  void addGroupMember(String group, String person) {
    final n = person.trim();
    if (n.isEmpty || groupMembers(group).contains(n)) return;
    final m = _groupMembers;
    m[group] = [...?m[group], n];
    _setApp('groupMembers', m);
  }

  void removeGroupMember(String group, String person) {
    final m = _groupMembers;
    m[group] = [...?m[group]]..remove(person);
    if (m[group]!.isEmpty) m.remove(group);
    _setApp('groupMembers', m);
  }

  /// Balance per member over the finished bills of the group (positive = gets money). See model/settle.dart.
  Map<String, int> groupBalance(String group, {String Function(String name)? key}) => balances(inGroup(group, done: true), key: key);

  /// Removes the group; its bills stay, without group.
  void deleteGroup(String name) {
    for (final b in bills) {
      if (b.group == name) b.group = null;
    }
    final m = _groupMembers..remove(name);
    _app['groupMembers'] = m;
    _setApp('groupsExtra', _extraGroups.where((g) => g != name).toList());
    _persist();
  }

  void addFriend(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    _setApp('forgotten', forgotten.where((x) => x != n).toList());
    if (!_extraFriends.contains(n)) _setApp('friendsExtra', [..._extraFriends, n]);
  }

  void forgetFriend(String name) {
    _setApp('friendsExtra', _extraFriends.where((x) => x != name).toList());
    forget(name);
  }

  /// People with their number of bills, what they consumed in total (cents) and their colour: from the bills (not in the
  /// trash) and the ones added by hand, minus the ones removed.
  List<({String name, int bills, int sum, int color})> get friends {
    final gone = forgotten;
    final map = <String, ({int bills, int sum, int color})>{};
    for (final b in bills) {
      if (!_show(b)) continue;
      final pp = b.perPerson();
      for (var i = 0; i < b.ps.length; i++) {
        final p = b.ps[i];
        if (gone.contains(p.name)) continue;
        final old = map[p.name];
        map[p.name] = (bills: (old?.bills ?? 0) + 1, sum: (old?.sum ?? 0) + (b.refund ? -1 : 1) * (pp[i] ?? 0), color: old?.color ?? p.color);
      }
    }
    for (final n in _extraFriends) {
      if (!gone.contains(n)) map.putIfAbsent(n, () => (bills: 0, sum: 0, color: map.length));
    }
    final out = [for (final e in map.entries) (name: e.key, bills: e.value.bills, sum: e.value.sum, color: e.value.color)]
      ..sort((a, b) => b.bills != a.bills ? b.bills.compareTo(a.bills) : a.name.compareTo(b.name));
    return out;
  }

  /// Group names in use, alphabetical.
  List<String> get groups => ({for (final b in bills) if (_show(b) && b.group != null && b.group!.isNotEmpty) b.group!}.toList()..sort());

  /// Moves [moved] (in their current order) right before [target] in its list, into the target's group (Nutzer 03.11.:
  /// pick several bills and sort them by drag and drop). New places lie between the target and the bill above it, so no
  /// other bill changes.
  void moveBefore(List<Bill> moved, Bill target) {
    final ids = {for (final b in moved) b.id};
    if (ids.contains(target.id)) return;
    final list = inGroup(target.group, archived: target.settled).where((b) => !ids.contains(b.id)).toList();
    final i = list.indexWhere((b) => b.id == target.id);
    final hi = target.sortKey, lo = i > 0 ? list[i - 1].sortKey : hi - moved.length - 1;
    final ordered = [...moved]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    for (final (k, b) in ordered.indexed) {
      b.order = lo + (hi - lo) * (k + 1) / (ordered.length + 1);
      if (b.group != target.group) {
        b.group = target.group;
        b.updated = DateTime.now(); // the group changed: shared like setGroup
      }
    }
    _persist();
  }

  /// Puts bills into a group (null or empty = take out of the group).
  void setGroup(Iterable<Bill> list, String? group) {
    final g = group == null || group.trim().isEmpty ? null : group.trim();
    for (final b in list) {
      b.group = g;
      b.updated = DateTime.now();
    }
    _persist();
  }

  /// Marks bills as finished (archive) or open again.
  void setDone(Iterable<Bill> list, bool done) {
    for (final b in list) {
      b.done = done;
      if (!done) b.settled = false;
      b.updated = DateTime.now();
    }
    _persist();
  }

  /// Settled = paid back: to the archive, out of the balances. Only entered bills ([Bill.done]) can be settled; returns
  /// the bills that changed (for „Rückgängig“).
  List<Bill> setSettled(Iterable<Bill> list, bool settled) {
    final changed = <Bill>[];
    for (final b in list) {
      if (settled && !b.done) continue;
      if (b.settled == settled) continue;
      b.settled = settled;
      b.updated = DateTime.now();
      changed.add(b);
    }
    if (changed.isNotEmpty) _persist();
    return changed;
  }

  // ---- Papierkorb (Nutzer 02.11.: Löschen landet im Papierkorb; Fristen 7 / 30 Tage / nur manuell) ----

  /// Days until the trash empties itself: 7, 30 or 0 = only by hand. Default 30 (Apple „Zuletzt gelöscht“, Google Drive/Gmail).
  int get trashDays => const [7, 30, 0].contains(_app['trashDays']) ? _app['trashDays'] as int : 30;
  set trashDays(int v) => _setApp('trashDays', v);

  /// After „Alle“ in Zuordnen: 0 = never jump on (default, Beschluss 03.11.), 1 = after a short, cancellable wait, 2 = at once.
  int get autoNext => const [0, 1, 2].contains(_app['autoNext']) ? _app['autoNext'] as int : 0;
  set autoNext(int v) => _setApp('autoNext', v);

  /// Moves bills to the trash.
  void trash(Iterable<Bill> list) {
    final now = DateTime.now();
    for (final b in list) {
      b.trashedAt = now;
    }
    _persist();
  }

  /// Takes bills out of the trash again („Rückgängig“, „Wiederherstellen“).
  void untrash(Iterable<Bill> list) {
    for (final b in list) {
      b.trashedAt = null;
      b.updated = DateTime.now();
    }
    _persist();
  }

  /// Removes bills for good (files included).
  void deleteForever(Iterable<Bill> list) {
    for (final b in list.toList()) {
      remove(b);
    }
  }

  /// Empties the trash.
  void emptyTrash() => deleteForever(trashed);

  /// Removes what has been in the trash longer than [trashDays]; returns how many bills went. Does nothing in „nur manuell“.
  int purgeTrash({DateTime? now}) {
    final days = trashDays;
    if (days == 0) return 0;
    final limit = (now ?? DateTime.now()).subtract(Duration(days: days));
    final old = [for (final b in bills) if (b.trashedAt != null && b.trashedAt!.isBefore(limit)) b];
    deleteForever(old);
    return old.length;
  }

  /// Days left before a bill in the trash is removed; null in „nur manuell“.
  int? daysLeft(Bill b, {DateTime? now}) {
    final days = trashDays;
    if (days == 0 || b.trashedAt == null) return null;
    final end = b.trashedAt!.add(Duration(days: days));
    return math.max(0, (end.difference(now ?? DateTime.now()).inHours + 23) ~/ 24); // rounded up: 27½ days left = 28
  }

  void upsert(Bill b) {
    b.updated = DateTime.now();
    _changed();
    final i = bills.indexWhere((x) => x.id == b.id);
    if (i >= 0) {
      bills[i] = b;
    } else {
      bills.add(b);
    }
    _persist();
  }

  void remove(Bill b) {
    bills.removeWhere((x) => x.id == b.id);
    for (final f in [b.imagePath, b.logPath, b.originalPath]) {
      if (f != null) {
        try {
          deleteImage(f);
        } catch (_) {}
      }
    }
    _persist();
  }

  void _persist() {
    notifyListeners();
    _write();
  }

  void _write() => _prefs?.setString(_key, jsonEncode(bills.map((b) => b.toJson()).toList()));

  /// Photo or scan of a receipt: a file on the phone, IndexedDB in the browser (state/images.dart).
  static Future<String?> saveFile(String name, Uint8List bytes) => saveImage(name, bytes);
}
