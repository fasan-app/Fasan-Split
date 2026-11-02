// Fasan Split – saved bills and settings (shared_preferences; images and logs as files in the app folder). MPL-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/bill.dart';

class BillStore extends ChangeNotifier {
  BillStore(this._prefs);

  final SharedPreferences? _prefs;
  final List<Bill> bills = [];

  static const _key = 'bills.v1';

  static Future<BillStore> load() async {
    final p = await SharedPreferences.getInstance();
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
            File(f).deleteSync();
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

  /// Names of people from earlier bills (most recent first).
  List<String> get recentNames {
    final out = <String>[];
    final gone = forgotten;
    if (me.isNotEmpty) out.add(me);
    for (final b in bills.reversed) {
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

  /// Bills hidden for a moment while „Rückgängig“ is on offer after a delete; removed for good when it runs out.
  final Set<String> _hidden = {};

  bool _show(Bill b) => !_hidden.contains(b.id);

  List<Bill> get drafts => [
        for (final b in bills)
          if (_show(b) && !b.done && (b.read != BillRead.ok || b.its.isNotEmpty || b.total != null || b.ps.isNotEmpty)) b
      ]..sort((a, b) => b.updated.compareTo(a.updated));
  List<Bill> get finished => [for (final b in bills) if (_show(b) && b.done) b]..sort((a, b) => b.created.compareTo(a.created));

  /// All visible bills of one group, newest first; `null` = bills without a group.
  List<Bill> inGroup(String? g) => [
        for (final b in bills)
          if (_show(b) && b.group == g && (b.done || b.read != BillRead.ok || b.its.isNotEmpty || b.total != null || b.ps.isNotEmpty)) b
      ]..sort((a, b) => b.updated.compareTo(a.updated));

  /// Group names in use, alphabetical.
  List<String> get groups => ({for (final b in bills) if (_show(b) && b.group != null && b.group!.isNotEmpty) b.group!}.toList()..sort());

  /// Puts bills into a group (null or empty = take out of the group).
  void setGroup(Iterable<Bill> list, String? group) {
    final g = group == null || group.trim().isEmpty ? null : group.trim();
    for (final b in list) {
      b.group = g;
      b.updated = DateTime.now();
    }
    _persist();
  }

  /// Marks bills as finished or open again (status on the overview).
  void setDone(Iterable<Bill> list, bool done) {
    for (final b in list) {
      b.done = done;
      b.updated = DateTime.now();
    }
    _persist();
  }

  /// Hides bills at once; [commit] removes them for good (call when „Rückgängig“ ran out), [restore] shows them again.
  void hide(Iterable<Bill> list) {
    _hidden.addAll(list.map((b) => b.id));
    notifyListeners();
  }

  void restore(Iterable<Bill> list) {
    _hidden.removeAll(list.map((b) => b.id));
    notifyListeners();
  }

  void commit(Iterable<Bill> list) {
    for (final b in list.toList()) {
      _hidden.remove(b.id);
      remove(b);
    }
  }

  void upsert(Bill b) {
    b.updated = DateTime.now();
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
          File(f).deleteSync();
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

  static Future<String?> saveFile(String name, Uint8List bytes) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}
