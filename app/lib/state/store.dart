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
    try {
      final raw = p.getString(_key);
      if (raw != null) {
        for (final j in jsonDecode(raw) as List) {
          s.bills.add(Bill.fromJson((j as Map).cast<String, dynamic>()));
        }
      }
    } catch (_) {/* damaged data: start empty, never crash */}
    return s;
  }

  /// In-memory store for tests and screenshots.
  static BillStore memory([List<Bill> bills = const []]) => BillStore(null)..bills.addAll(bills);

  String? get settingsJson => _prefs?.getString('fasan_ui.settings');
  void saveSettings(String s) => _prefs?.setString('fasan_ui.settings', s);

  /// Names of people from earlier bills (most recent first).
  List<String> get recentNames {
    final out = <String>[];
    for (final b in bills.reversed) {
      for (final p in b.ps) {
        if (!out.contains(p.name)) out.add(p.name);
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

  List<Bill> get drafts => [for (final b in bills) if (!b.done && (b.its.isNotEmpty || b.total != null || b.ps.isNotEmpty)) b]
    ..sort((a, b) => b.updated.compareTo(a.updated));
  List<Bill> get finished => [for (final b in bills) if (b.done) b]..sort((a, b) => b.created.compareTo(a.created));

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
